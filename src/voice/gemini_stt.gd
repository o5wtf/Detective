class_name GeminiStt
extends SttBackend
## Один generateContent с WAV. Модель не переключается. Ключ в тело и логи не пишется.


const MODEL := "gemini-3.5-flash-lite"
const PROMPT := "Дословно расшифруй русскую речь. Верни только текст. Если речи нет, верни пустую строку."
const TIMEOUT_S := 8.0
const DEADLINE_S := 25.0
const NET_RETRIES := 2
const TRANSIENT_RETRIES := 2
const MIN_ATTEMPT_S := 3.0

var model: String = MODEL
var api_key: String = ""
var transport: Object = null
var _instant: bool = false
var _clock_s: float = 0.0


func _ready() -> void:
	if api_key == "":
		api_key = LLMConfig.load_settings().api_key
	if transport == null:
		var live := GeminiSttTransport.new()
		transport = live
		add_child(live)


func transcribe(wav: PackedByteArray) -> Dictionary:
	if api_key.strip_edges() == "":
		return _failure("auth", "Нет ключа для распознавания.")
	if wav.is_empty():
		return _failure("empty", "Пустая запись.")
	var thinking := "MINIMAL"
	var net_retries := 0
	var transient_retries := 0
	var started := Time.get_ticks_msec()
	var deadline := started + int(DEADLINE_S * 1000.0)
	while true:
		if _left_s(deadline) < MIN_ATTEMPT_S:
			return _failure("timeout", UiStrings.NO_LINK)
		var body := build_body(wav, thinking)
		var outcome: Dictionary = await _post(body)
		var transport_error := str(outcome.get("error", ""))
		if transport_error == "timeout" or transport_error == "offline":
			if net_retries < NET_RETRIES and _left_s(deadline) >= (3.0 if net_retries > 0 else 1.0) + MIN_ATTEMPT_S:
				var pause := 1.0 if net_retries == 0 else 3.0
				net_retries += 1
				await _pause(pause)
				continue
			return _failure(transport_error, UiStrings.NO_LINK)
		var status := int(outcome.get("status", 0))
		var raw := str(outcome.get("body", ""))
		_log(status, raw)
		if status == 200:
			var parsed := parse_transcript(raw)
			if parsed.get("ok", false):
				var usage: Dictionary = parsed.get("usage", {})
				SpendMeter.note_stt(model, int(usage.get("prompt", 0)), int(usage.get("output", 0)))
			return parsed
		var reason := _reason(raw)
		if status == 400 and reason.to_lower().contains("thinking") and thinking != "off":
			thinking = "LOW" if thinking == "MINIMAL" else "off"
			continue
		if (status == 429 or status == 503 or status == 502 or status == 504) and transient_retries < TRANSIENT_RETRIES:
			transient_retries += 1
			await _pause(_retry_delay(raw))
			continue
		if status == 401 or status == 403:
			return _failure("auth", "Ключ отклонён.")
		return _failure("bad_response", "Распознавание не удалось.")
	return _failure("bad_response", "Распознавание не удалось.")


static func build_body(wav: PackedByteArray, thinking: String) -> Dictionary:
	var generation := {
		"temperature": 0.0,
		"maxOutputTokens": 512,
	}
	if thinking != "off":
		generation["thinkingConfig"] = {"thinkingLevel": thinking}
	return {
		"contents": [{
			"role": "user",
			"parts": [
				{"inlineData": {"mimeType": "audio/wav", "data": Marshalls.raw_to_base64(wav)}},
				{"text": PROMPT},
			],
		}],
		"generationConfig": generation,
	}


static func parse_transcript(body: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(body)
	if parsed is not Dictionary:
		return {"ok": false, "text": "", "error": "bad_response", "usage": {}}
	var root := parsed as Dictionary
	var usage := _usage(root)
	var candidates: Variant = root.get("candidates", [])
	if candidates is not Array or (candidates as Array).is_empty():
		return {"ok": false, "text": "", "error": "bad_response", "usage": usage}
	var first: Variant = (candidates as Array)[0]
	if first is not Dictionary:
		return {"ok": false, "text": "", "error": "bad_response", "usage": usage}
	var content: Variant = (first as Dictionary).get("content", {})
	var parts: Variant = (content as Dictionary).get("parts", []) if content is Dictionary else []
	var text := ""
	if parts is Array:
		for part in parts:
			if part is Dictionary:
				text += str((part as Dictionary).get("text", ""))
	return {"ok": true, "text": text.strip_edges(), "error": "", "usage": usage}


func _post(body: Dictionary) -> Dictionary:
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % model
	var headers := {
		"Content-Type": "application/json",
		"x-goog-api-key": api_key,
	}
	var payload := JSON.stringify(body)
	TurnTiming.mark("stt_sent")
	return await transport.call("request", url, headers, payload, TIMEOUT_S)


func _left_s(deadline: int) -> float:
	return maxf(0.0, float(deadline - Time.get_ticks_msec()) / 1000.0)


func _log(status: int, body: String) -> void:
	var usage := {}
	var parsed: Variant = JSON.parse_string(body)
	if parsed is Dictionary:
		usage = _usage(parsed)
	print("stt model=%s http=%d prompt_tokens=%d output_tokens=%d" % [
		model,
		status,
		int(usage.get("prompt", 0)),
		int(usage.get("output", 0)),
	])


func _pause(seconds: float) -> void:
	if _instant:
		_clock_s += seconds
		return
	await get_tree().create_timer(maxf(seconds, 0.0)).timeout


func _failure(kind: String, message: String) -> Dictionary:
	return {"ok": false, "text": "", "error": kind, "message": message, "usage": {}}


static func _usage(root: Dictionary) -> Dictionary:
	var raw: Variant = root.get("usageMetadata", {})
	if raw is not Dictionary:
		return {"prompt": 0, "output": 0}
	var meta := raw as Dictionary
	return {
		"prompt": int(meta.get("promptTokenCount", 0)),
		"output": int(meta.get("candidatesTokenCount", 0)),
	}


static func _reason(body: String) -> String:
	var parsed: Variant = JSON.parse_string(body)
	if parsed is not Dictionary:
		return ""
	var err: Variant = (parsed as Dictionary).get("error", {})
	if err is not Dictionary:
		return ""
	return str((err as Dictionary).get("message", ""))


static func _retry_delay(body: String) -> float:
	var parsed: Variant = JSON.parse_string(body)
	if parsed is not Dictionary:
		return 1.0
	var err: Variant = (parsed as Dictionary).get("error", {})
	if err is not Dictionary:
		return 1.0
	var details: Variant = (err as Dictionary).get("details", [])
	if details is not Array:
		return 1.0
	for item in details:
		if item is not Dictionary:
			continue
		if not str((item as Dictionary).get("@type", "")).contains("RetryInfo"):
			continue
		var raw := str((item as Dictionary).get("retryDelay", "")).strip_edges()
		if raw.ends_with("s"):
			return float(raw.trim_suffix("s"))
	return 1.0


class GeminiSttTransport:
	extends Node

	func request(url: String, headers: Dictionary, payload: String, timeout_s: float) -> Dictionary:
		var header_list: PackedStringArray = PackedStringArray()
		for key in headers.keys():
			header_list.append("%s: %s" % [str(key), str(headers[key])])
		var outcome: Dictionary = await HttpSession.exchange(self, url, header_list, payload, timeout_s)
		if not bool(outcome.get("ok", false)):
			return {"error": str(outcome.get("error", "offline")), "status": 0, "body": ""}
		return {"error": "", "status": int(outcome.get("status", 0)), "body": str(outcome.get("body", ""))}
