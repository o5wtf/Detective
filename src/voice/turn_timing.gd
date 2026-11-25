class_name TurnTiming
extends RefCounted
## Последние ходы: от отпускания кнопки до первого звука. Ключ сюда не пишется.


const LIMIT := 10

static var turns: Array = []
static var lines_log: PackedStringArray = PackedStringArray()


static func begin(backend_name: String) -> void:
	turns.append({
		"backend": backend_name,
		"marks": {},
		"reused": false,
		"prefix": "ход %d" % (turns.size() + 1),
	})
	while turns.size() > LIMIT:
		turns.pop_front()


static func mark(key: String) -> void:
	if turns.is_empty():
		return
	var marks: Dictionary = turns.back()["marks"]
	if marks.has(key):
		return
	marks[key] = Time.get_ticks_msec()
	publish()


static func note_reused(value: bool) -> void:
	if turns.is_empty():
		return
	if value:
		turns.back()["reused"] = true
	elif not bool(turns.back().get("reused", false)):
		turns.back()["reused"] = false


static func note_tts_reused(value: bool) -> void:
	if turns.is_empty():
		return
	turns.back()["tts_reused"] = value
	publish()


static func note_tts(model: String, reason: String) -> void:
	if turns.is_empty():
		return
	turns.back()["tts_model"] = model
	turns.back()["tts_reason"] = reason
	publish()


static func lines() -> PackedStringArray:
	return lines_log.duplicate()


static func publish() -> void:
	if turns.is_empty():
		return
	var row: Dictionary = turns.back()
	var text := format_row(row)
	var prefix := str(row.get("prefix", "ход"))
	var replaced := false
	for index in lines_log.size():
		if str(lines_log[index]).begins_with(prefix):
			lines_log[index] = text
			replaced = true
			break
	if not replaced:
		lines_log.append(text)
	while lines_log.size() > LIMIT:
		lines_log.remove_at(0)
	if is_instance_valid(Speaker):
		Speaker.set_turn_log(lines_log)


static func format_row(row: Dictionary) -> String:
	var marks: Dictionary = row.get("marks", {})
	var origin := int(marks.get("release", 0))
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(row.get("prefix", "ход")))
	parts.append("backend=%s" % str(row.get("backend", "")))
	parts.append("reused=%s" % ("yes" if bool(row.get("reused", false)) else "no"))
	parts.append("tts_reused=%s" % ("yes" if bool(row.get("tts_reused", false)) else "no"))
	for key in ["audio_ready", "stt_sent", "stt_done", "line_shown", "dialogue_sent", "dialogue_first_byte", "dialogue_done", "tts_sent", "first_audio", "playback_start"]:
		if marks.has(key) and origin > 0:
			parts.append("%s=%d" % [key, int(marks[key]) - origin])
	if marks.has("first_audio") and origin > 0:
		parts.append("total=%d" % (int(marks["first_audio"]) - origin))
	if str(row.get("tts_model", "")) != "":
		parts.append("tts_model=%s" % str(row.get("tts_model", "")))
		parts.append("tts_reason=%s" % str(row.get("tts_reason", "")))
	return " ".join(parts)


static func reset() -> void:
	turns.clear()
	lines_log = PackedStringArray()
	if is_instance_valid(Speaker):
		Speaker.set_turn_log(lines_log)
