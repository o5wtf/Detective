class_name LlmTiming
extends RefCounted
## Строки журнала хода. Без ключа и без текста промпта.


static func request_line(fields: Dictionary) -> String:
	return "llm request model=%s thinking=%s http=%d response_ms=%d total_ms=%d prompt_tokens=%d thought_tokens=%d output_tokens=%d finish=%s retry=%s" % [
		str(fields.get("model", "")),
		str(fields.get("thinking", "off")),
		int(fields.get("http", 0)),
		int(fields.get("response_ms", 0)),
		int(fields.get("total_ms", 0)),
		int(fields.get("prompt_tokens", 0)),
		int(fields.get("thought_tokens", 0)),
		int(fields.get("output_tokens", 0)),
		str(fields.get("finish", "")),
		str(fields.get("retry", "none")),
	]


static func turn_line(ms: int, model: String, tally: Dictionary) -> String:
	return "llm timing ask_to_text_ms=%d model=%s requests=%d summary=%d regen=%d reasons=%s merged=%s fallback=%s" % [
		ms,
		model,
		int(tally.get("requests", 0)),
		int(tally.get("summary", 0)),
		int(tally.get("regen", 0)),
		reasons_text(tally),
		str(tally.get("merged", "no")),
		str(tally.get("fallback", "keyboard")),
	]


static func screen_line(ms: int, requests: int, model: String) -> String:
	var tenths := int(round(float(maxi(ms, 0)) / 100.0))
	var whole := int(tenths / 10)
	var frac := tenths % 10
	return "ход %d,%d с · %d запр. · %s" % [whole, frac, requests, model]


static func empty_tally() -> Dictionary:
	return {"requests": 0, "summary": 0, "regen": 0, "reasons": PackedStringArray()}


static func note_request(tally: Dictionary, kind: String, reason: String) -> void:
	tally["requests"] = int(tally.get("requests", 0)) + 1
	if kind == "summary":
		tally["summary"] = int(tally.get("summary", 0)) + 1
	elif kind == "regen":
		tally["regen"] = int(tally.get("regen", 0)) + 1
		var reasons: PackedStringArray = tally.get("reasons", PackedStringArray())
		reasons.append(reason)
		tally["reasons"] = reasons


static func reasons_text(tally: Dictionary) -> String:
	var reasons: PackedStringArray = tally.get("reasons", PackedStringArray())
	if reasons.is_empty():
		return "none"
	return ",".join(reasons)


static func median_int(values: Array) -> int:
	if values.is_empty():
		return 0
	var copy: Array = values.duplicate()
	copy.sort()
	var mid := int(copy.size() / 2)
	if copy.size() % 2 == 1:
		return int(copy[mid])
	return int((int(copy[mid - 1]) + int(copy[mid])) / 2.0)


static func usage_from_body(body: String) -> Dictionary:
	var usage := {"prompt_tokens": 0, "thought_tokens": 0, "output_tokens": 0, "finish": ""}
	var trimmed := body.strip_edges()
	if not trimmed.begins_with("{"):
		return usage
	var parsed: Variant = JSON.parse_string(trimmed)
	if parsed is not Dictionary:
		return usage
	var root := parsed as Dictionary
	var meta: Variant = root.get("usageMetadata", {})
	if meta is Dictionary:
		var counts := meta as Dictionary
		usage["prompt_tokens"] = int(counts.get("promptTokenCount", 0))
		usage["thought_tokens"] = int(counts.get("thoughtsTokenCount", 0))
		usage["output_tokens"] = int(counts.get("candidatesTokenCount", 0))
	var candidates: Variant = root.get("candidates", [])
	if candidates is Array and not (candidates as Array).is_empty() and (candidates as Array)[0] is Dictionary:
		usage["finish"] = str(((candidates as Array)[0] as Dictionary).get("finishReason", ""))
	return usage
