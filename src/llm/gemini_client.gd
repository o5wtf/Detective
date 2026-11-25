class_name GeminiClient
extends LLMClient
## REST generateContent. Транспорт подменяется в тестах. Ключ в логи не попадает.

const BASE_URL := "https://generativelanguage.googleapis.com/v1beta/models"
const SERVER_PAUSE_S := 2.0
const SERVER_ATTEMPTS := 2
const TRANSIENT_RETRIES := 2
const NET_RETRIES := 2
const ATTEMPT_TIMEOUT_S := 10.0
const TURN_DEADLINE_S := 30.0
const MIN_ATTEMPT_S := 3.0

var api_key: String = ""
var dialogue_model: String = LLMConfig.DEFAULT_DIALOGUE_MODEL
var summary_model: String = LLMConfig.DEFAULT_DIALOGUE_MODEL
var thinking_level: String = LLMConfig.DEFAULT_THINKING
var timeout_s: float = 45.0
var ping_timeout_s: float = 32.0
var min_interval_s: float = 0.0
var base_url: String = BASE_URL
## Принятый thinkingLevel по модели: MINIMAL, LOW или off.
var accepted_thinking: Dictionary = {}
var turn_deadline_ms: int = int(TURN_DEADLINE_S * 1000.0)
var _turn_deadline: int = 0

var _transport: Object = null
var _busy: bool = false
var _instant_wait: bool = false
var _clock_s: float = 0.0
var _last_request_s: float = -1.0
var waits: Array[float] = []

signal _released


func apply_config(config: LLMConfig) -> void:
	api_key = config.api_key
	dialogue_model = config.dialogue_model
	summary_model = config.dialogue_model
	thinking_level = config.thinking_level
	timeout_s = config.timeout_s
	ping_timeout_s = config.ping_timeout_s
	min_interval_s = 0.0
	accepted_thinking = SettingsStore.load_thinking()


func set_transport(transport: Object) -> void:
	_transport = transport


func _ready() -> void:
	if _transport != null:
		return
	var http := Transport.new()
	add_child(http)
	_transport = http


func generate(request: Dictionary) -> Dictionary:
	while _busy:
		await _released
	_busy = true
	var result := await _generate_body(request)
	_busy = false
	_released.emit()
	finished.emit(result)
	return result


func _generate_body(request: Dictionary) -> Dictionary:
	if api_key.strip_edges() == "":
		return _failure("auth", "Не задан ключ API. Укажите его в настройках или в переменной GEMINI_API_KEY.")
	var model := _model_for(request)
	var schema_field := "responseJsonSchema"
	var started := Time.get_ticks_msec()
	var probe := bool(request.get("probe", false))
	var deadline := started + turn_deadline_ms
	_turn_deadline = deadline
	var thinking_sent := _thinking_for(model, request)
	var raise_tokens := false
	var token_retried := false
	var transient_retries := 0
	var net_retries := 0
	var server_retries := 0
	var last := _failure("bad_response", "Запрос к Gemini не завершился.")
	while true:
		if not probe and _remaining_s(deadline, false) < MIN_ATTEMPT_S:
			return _with_meta(_failure("timeout", UiStrings.NO_LINK), model, started)
		if _past_deadline(deadline, probe):
			return _with_meta(_failure("timeout", "Модель «%s» не ответила за %d с." % [model, int(turn_deadline_ms / 1000.0)]), model, started)
		var call_started := Time.get_ticks_msec()
		var outcome: Dictionary = await _post(model, request, schema_field, thinking_sent, raise_tokens)
		var response_ms := Time.get_ticks_msec() - call_started
		var total_ms := Time.get_ticks_msec() - started
		var transport_error := str(outcome.get("error", ""))
		if transport_error == "offline" or transport_error == "timeout":
			_emit_request(model, thinking_sent, 0, response_ms, total_ms, "", transport_error)
			last = _failure(transport_error, UiStrings.NO_LINK)
			if probe or net_retries >= NET_RETRIES:
				return _with_meta(last, model, started)
			var pause := 1.0 if net_retries == 0 else 3.0
			if _remaining_s(deadline, false) < pause + MIN_ATTEMPT_S:
				return _with_meta(last, model, started)
			net_retries += 1
			await _wait(pause)
			continue
		var status := int(outcome.get("status", 0))
		var body := _redact(str(outcome.get("body", "")))
		var google := _google_status(body)
		var reason := _google_reason(body)
		if status == 200:
			var parsed := _parse_success(body)
			var finish := str(parsed.get("finish", ""))
			var truncated := str(parsed.get("error", "")) == "truncated"
			if (finish == "MAX_TOKENS" or truncated) and not token_retried:
				_emit_request(model, thinking_sent, status, response_ms, total_ms, body, "truncated" if truncated else "max_tokens")
				token_retried = true
				raise_tokens = true
				continue
			_emit_request(model, thinking_sent, status, response_ms, total_ms, body, str(parsed.get("error", "")) if not parsed.get("ok", false) else "none")
			return _with_meta(parsed, model, call_started)
		if status == 400 and schema_field == "responseJsonSchema" and _is_schema_rejection(body):
			_emit_request(model, thinking_sent, status, response_ms, total_ms, body, "schema")
			schema_field = "responseSchema"
			continue
		if _is_auth(status, google, reason):
			_emit_request(model, thinking_sent, status, response_ms, total_ms, body, "auth")
			return _with_meta(_failure("auth", _with_reason("Ключ API отклонён.", reason)), model, call_started)
		if status == 404 or google == "NOT_FOUND":
			_emit_request(model, thinking_sent, status, response_ms, total_ms, body, "unavailable")
			return _with_meta(_failure("unavailable", _with_reason("Модель «%s» недоступна." % model, reason)), model, call_started)
		if status == 429 or status == 503 or status == 502 or status == 504:
			var code := "rate_limited" if status == 429 else "overloaded"
			_emit_request(model, thinking_sent, status, response_ms, total_ms, body, code)
			last = _failure(code, _with_reason("Слишком много запросов к «%s»." % model if status == 429 else "Модель «%s» перегружена." % model, reason))
			var transient_delay := _transient_delay(transient_retries, outcome, deadline, probe)
			if transient_delay >= 0.0:
				transient_retries += 1
				await _wait(transient_delay)
				continue
			return _with_meta(last, model, started)
		if status >= 500:
			server_retries += 1
			_emit_request(model, thinking_sent, status, response_ms, total_ms, body, "server")
			if server_retries < SERVER_ATTEMPTS and not _past_deadline(deadline, probe):
				await _wait(SERVER_PAUSE_S)
				continue
			return _with_meta(_failure("server", _with_reason("Сервис Gemini временно недоступен.", reason)), model, call_started)
		if status == 400 and _mentions_thinking(reason) and thinking_sent != "off":
			_emit_request(model, thinking_sent, status, response_ms, total_ms, body, "thinking")
			var role := str(request.get("model_role", "dialogue"))
			if role == "dialogue" and thinking_sent.to_upper() == "LOW":
				return _with_meta(_failure("rejected", _with_reason("Запрос отклонён.", reason)), model, call_started)
			thinking_sent = _downgrade_thinking(model, role, thinking_sent)
			continue
		if status == 400:
			_emit_request(model, thinking_sent, status, response_ms, total_ms, body, "rejected")
			return _with_meta(_failure("rejected", _with_reason("Запрос отклонён.", reason)), model, call_started)
		_emit_request(model, thinking_sent, status, response_ms, total_ms, body, "bad_response")
		return _with_meta(_failure("bad_response", _with_reason("Неожиданный ответ сервиса.", reason)), model, call_started)
	return last


func _transient_delay(used: int, outcome: Dictionary, deadline: int, probe: bool) -> float:
	if used >= TRANSIENT_RETRIES or _past_deadline(deadline, probe):
		return -1.0
	var delay := _retry_delay(outcome, used + 1)
	if delay > _remaining_s(deadline, probe):
		return -1.0
	return delay


func _past_deadline(deadline: int, probe: bool) -> bool:
	return not probe and Time.get_ticks_msec() >= deadline


func _remaining_s(deadline: int, probe: bool) -> float:
	if probe:
		return 60.0
	return maxf(0.0, float(deadline - Time.get_ticks_msec()) / 1000.0)


func _thinking_for(model: String, request: Dictionary) -> String:
	if bool(request.get("probe", false)):
		return "off"
	var role := str(request.get("model_role", "dialogue"))
	var key := _thinking_key(model, role)
	if accepted_thinking.has(key):
		var saved := str(accepted_thinking[key])
		if role == "dialogue" and (saved == "off" or saved == ""):
			return "MINIMAL"
		return saved
	if role == "dialogue":
		return "MINIMAL"
	var level := thinking_level.strip_edges().to_upper()
	if level == "":
		return LLMConfig.DEFAULT_THINKING
	return level


func _downgrade_thinking(model: String, role: String, sent: String) -> String:
	var next := "LOW"
	if role != "dialogue" and sent.to_upper() != "MINIMAL":
		next = "off"
	accepted_thinking[_thinking_key(model, role)] = next
	SettingsStore.remember_thinking(model, next, role)
	return next


func _thinking_key(model: String, role: String) -> String:
	return "%s|%s" % [model, role]


func _mentions_thinking(reason: String) -> bool:
	return reason.to_lower().contains("thinking")


func _post(model: String, request: Dictionary, schema_field: String, thinking_sent: String, raise_tokens: bool) -> Dictionary:
	var url := "%s/%s:generateContent" % [base_url.trim_suffix("/"), model]
	var headers := {
		"Content-Type": "application/json",
		"x-goog-api-key": api_key,
	}
	var payload := JSON.stringify(_body(request, schema_field, thinking_sent, raise_tokens))
	var mark := "dialogue_first_byte" if str(request.get("model_role", "")) == "dialogue" else ""
	var pending: Variant = _transport.call("request", url, headers, payload, _timeout_for(request), mark)
	if pending is Dictionary:
		return pending
	return await pending


func _timeout_for(request: Dictionary) -> float:
	var limit := timeout_s
	if request.has("timeout_s"):
		limit = float(request["timeout_s"])
	elif bool(request.get("probe", false)):
		limit = ping_timeout_s
	if bool(request.get("probe", false)):
		return limit
	var remaining := _remaining_s(_turn_deadline, false)
	return minf(ATTEMPT_TIMEOUT_S, minf(limit, maxf(remaining, 0.0)))


func _body(request: Dictionary, schema_field: String, thinking_sent: String, raise_tokens: bool) -> Dictionary:
	var schema: Dictionary = request.get("schema", {})
	var tokens := int(request.get("max_output_tokens", LLMConfig.REPLY_MAX_OUTPUT_TOKENS))
	if raise_tokens:
		tokens = maxi(tokens, LLMConfig.REPLY_MAX_OUTPUT_TOKENS)
	var generation := {
		"responseMimeType": "application/json",
		schema_field: schema,
		"temperature": float(request.get("temperature", 0.9)),
		"maxOutputTokens": tokens,
	}
	if thinking_sent != "" and thinking_sent != "off":
		generation["thinkingConfig"] = {"thinkingLevel": thinking_sent}
	var parts: Array = []
	var wav: Variant = request.get("wav", PackedByteArray())
	if wav is PackedByteArray and not (wav as PackedByteArray).is_empty():
		parts.append({
			"inlineData": {"mimeType": "audio/wav", "data": Marshalls.raw_to_base64(wav)},
		})
	parts.append({"text": str(request.get("user", ""))})
	return {
		"systemInstruction": {"parts": [{"text": str(request.get("system", ""))}]},
		"contents": [{"role": "user", "parts": parts}],
		"generationConfig": generation,
		"safetySettings": _safety_settings(),
	}


func _parse_success(body: String) -> Dictionary:
	var root = _parse_json(body)
	if root == null or root is not Dictionary:
		return _failure("bad_response", "Ответ Gemini не разобрался как JSON.")
	var data := root as Dictionary
	var feedback: Dictionary = data.get("promptFeedback", {})
	if str(feedback.get("blockReason", "")) != "":
		return _failure("blocked", "Запрос заблокирован фильтром.")
	var candidates: Array = data.get("candidates", [])
	if candidates.is_empty() or candidates[0] is not Dictionary:
		return _failure("bad_response", "В ответе Gemini нет кандидата.")
	var candidate := candidates[0] as Dictionary
	var finish := str(candidate.get("finishReason", "STOP"))
	if finish == "SAFETY" or finish == "PROHIBITED_CONTENT" or finish == "BLOCKLIST":
		return _failure("blocked", "Ответ заблокирован фильтром.")
	var text := _join_visible_text(candidate)
	var parsed: Variant = _parse_model_json(text)
	if finish == "MAX_TOKENS" and (parsed == null or parsed is not Dictionary):
		var truncated := _failure("truncated", "Ответ модели оборвался: не хватило места на текст.")
		truncated["finish"] = finish
		return truncated
	if finish != "" and finish != "STOP" and finish != "MAX_TOKENS":
		var incomplete := _failure("bad_response", "Ответ модели оборван или неполон.")
		incomplete["finish"] = finish
		return incomplete
	if parsed == null or parsed is not Dictionary:
		var broken := _failure("bad_response", "Текст ответа не является JSON-объектом.")
		broken["finish"] = finish
		return broken
	return {
		"ok": true,
		"json": _normalize_reply(parsed),
		"raw_text": _redact(text),
		"error": "",
		"retry_after_s": 0.0,
		"message": "",
		"finish": finish,
	}


func _join_visible_text(candidate: Dictionary) -> String:
	var content: Dictionary = candidate.get("content", {})
	var parts: Array = content.get("parts", [])
	var chunks: PackedStringArray = PackedStringArray()
	for part in parts:
		if part is not Dictionary:
			continue
		var body := part as Dictionary
		if body.get("thought", false) == true:
			continue
		var text := str(body.get("text", ""))
		if text == "":
			continue
		chunks.append(text)
	return "".join(chunks)


func _parse_model_json(text: String) -> Variant:
	var stripped := _strip_fences(text)
	var parsed: Variant = _parse_json(stripped)
	if parsed is Dictionary:
		return parsed
	return _parse_json(_extract_object(stripped))


func _strip_fences(text: String) -> String:
	var trimmed := text.strip_edges()
	if not trimmed.begins_with("```"):
		return trimmed
	var lines := trimmed.split("\n")
	if lines.size() >= 2 and lines[0].begins_with("```"):
		lines.remove_at(0)
	if lines.size() >= 1 and lines[lines.size() - 1].strip_edges() == "```":
		lines.remove_at(lines.size() - 1)
	return "\n".join(lines).strip_edges()


func _extract_object(text: String) -> String:
	var start := text.find("{")
	var finish := text.rfind("}")
	if start < 0 or finish <= start:
		return text
	return text.substr(start, finish - start + 1)


func _normalize_reply(data: Dictionary) -> Dictionary:
	if not data.has("reply"):
		return data
	return ResponseValidator._normalize(data)


func _retry_delay(outcome: Dictionary, _attempt: int) -> float:
	var from_body := _retry_info_seconds(str(outcome.get("body", "")))
	if from_body > 0.0:
		return from_body
	var headers: Dictionary = outcome.get("headers", {})
	for key in headers:
		if str(key).to_lower() == "retry-after":
			var seconds := float(headers[key])
			if seconds > 0.0:
				return seconds
	return 1.0


func _retry_info_seconds(body: String) -> float:
	var parsed: Variant = _parse_json(body)
	if parsed is not Dictionary:
		return 0.0
	var err: Variant = (parsed as Dictionary).get("error", {})
	if err is not Dictionary:
		return 0.0
	var details: Variant = (err as Dictionary).get("details", [])
	if details is not Array:
		return 0.0
	for item in details:
		if item is not Dictionary:
			continue
		var info := item as Dictionary
		var kind := str(info.get("@type", ""))
		if not kind.contains("RetryInfo"):
			continue
		return _duration_seconds(str(info.get("retryDelay", "")))
	return 0.0


func _duration_seconds(raw: String) -> float:
	var text := raw.strip_edges()
	if text == "":
		return 0.0
	if text.ends_with("ms"):
		return float(text.trim_suffix("ms")) / 1000.0
	if text.ends_with("s"):
		return float(text.trim_suffix("s"))
	return float(text)


func _is_schema_rejection(body: String) -> bool:
	var lower := body.to_lower()
	if lower.contains("api_key") or lower.contains("api key"):
		return false
	return lower.contains("responsejsonschema") or lower.contains("unknown name") or lower.contains("invalid json payload")


func _google_status(body: String) -> String:
	var parsed: Variant = _parse_json(body)
	if parsed is not Dictionary:
		return ""
	var err: Variant = (parsed as Dictionary).get("error", {})
	if err is not Dictionary:
		return ""
	return str((err as Dictionary).get("status", ""))


func _google_reason(body: String) -> String:
	var parsed: Variant = _parse_json(body)
	if parsed is not Dictionary:
		return ""
	var err: Variant = (parsed as Dictionary).get("error", {})
	if err is not Dictionary:
		return ""
	var message := _redact(str((err as Dictionary).get("message", ""))).strip_edges()
	var newline := message.find("\n")
	if newline > 0:
		message = message.substr(0, newline).strip_edges()
	if message.length() > 180:
		message = message.substr(0, 180).strip_edges()
	return message


func _is_auth(status: int, google: String, reason: String) -> bool:
	if status == 401 or status == 403:
		return true
	var blob := ("%s %s" % [google, reason]).to_lower()
	return blob.contains("api_key_invalid") or blob.contains("api key not valid") or blob.contains("permission_denied")


func _with_reason(lead: String, reason: String) -> String:
	if reason == "":
		return lead
	return "%s %s" % [lead, reason]


func _emit_request(model: String, thinking_sent: String, status: int, response_ms: int, total_ms: int, body: String, retry: String) -> void:
	var usage := LlmTiming.usage_from_body(body)
	print(LlmTiming.request_line({
		"model": model,
		"thinking": thinking_sent,
		"http": status,
		"response_ms": response_ms,
		"total_ms": total_ms,
		"prompt_tokens": usage["prompt_tokens"],
		"thought_tokens": usage["thought_tokens"],
		"output_tokens": usage["output_tokens"],
		"finish": usage["finish"],
		"retry": retry if retry != "" else "none",
	}))
	SpendMeter.note(model, int(usage["prompt_tokens"]), int(usage["thought_tokens"]), int(usage["output_tokens"]))


func _with_meta(result: Dictionary, model: String, started_ms: int) -> Dictionary:
	result["model"] = model
	result["elapsed_s"] = (Time.get_ticks_msec() - started_ms) / 1000.0
	result["message"] = _redact(str(result.get("message", "")))
	return result


func _model_for(_request: Dictionary) -> String:
	return dialogue_model


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	waits.append(seconds)
	if _instant_wait:
		_clock_s += seconds
		return
	await get_tree().create_timer(seconds).timeout


func _now() -> float:
	if _instant_wait:
		return _clock_s
	return Time.get_ticks_msec() / 1000.0


func _parse_json(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if trimmed.begins_with("{") and not trimmed.ends_with("}"):
		return null
	if trimmed.begins_with("[") and not trimmed.ends_with("]"):
		return null
	if not trimmed.begins_with("{") and not trimmed.begins_with("["):
		return null
	return JSON.parse_string(trimmed)


func _redact(text: String) -> String:
	var secret := api_key.strip_edges()
	if secret == "":
		return text
	return text.replace(secret, "[redacted]")


func _failure(error_code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"json": {},
		"raw_text": "",
		"error": error_code,
		"retry_after_s": 0.0,
		"message": message,
	}


func _safety_settings() -> Array:
	var settings: Array = []
	for category in [
		"HARM_CATEGORY_HARASSMENT",
		"HARM_CATEGORY_HATE_SPEECH",
		"HARM_CATEGORY_SEXUALLY_EXPLICIT",
		"HARM_CATEGORY_DANGEROUS_CONTENT",
	]:
		settings.append({"category": category, "threshold": "BLOCK_ONLY_HIGH"})
	return settings


class Transport:
	extends Node

	func request(url: String, headers: Dictionary, body: String, timeout_s: float, byte_mark: String = "") -> Dictionary:
		var lines: PackedStringArray = PackedStringArray()
		for key in headers:
			lines.append("%s: %s" % [str(key), str(headers[key])])
		return await HttpSession.exchange(self, url, lines, body, timeout_s, byte_mark)
