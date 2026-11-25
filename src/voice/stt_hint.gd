class_name SttHint
extends RefCounted
## Слова, которые игрок уже видел. Закрытые улики и скрытые тексты сюда не входят.
## Локальный Parakeet подсказку не получает.


const BRIEFING_LIMIT := 400
const LINE_LIMIT := 200
const LIST_LIMIT := 900


static func for_turn(backend: String, case_data: CaseData, state: GameState, agent_id: String, last_line: String) -> String:
	if backend == "parakeet":
		return ""
	return build(case_data, state, agent_id, last_line)


static func build(case_data: CaseData, state: GameState, _agent_id: String, last_line: String) -> String:
	if case_data == null:
		return ""
	var words: PackedStringArray = PackedStringArray()
	var seen := {}
	for agent in case_data.agents:
		_add(words, seen, agent.name)
	_add(words, seen, case_data.title)
	_add(words, seen, _clip(case_data.briefing, BRIEFING_LIMIT))
	if state != null:
		for evidence in case_data.evidence:
			if not state.unlocked_evidence.has(evidence.id):
				continue
			_add(words, seen, evidence.title)
			_add(words, seen, _kind(evidence.type))
	_add(words, seen, _clip(last_line, LINE_LIMIT))
	if words.is_empty():
		return ""
	var listed := ", ".join(words)
	if listed.length() > LIST_LIMIT:
		listed = listed.substr(0, LIST_LIMIT)
		var comma := listed.rfind(", ")
		if comma > 0:
			listed = listed.substr(0, comma)
	return GameLanguage.text("stt_hint") + listed


static func _add(words: PackedStringArray, seen: Dictionary, raw: String) -> void:
	var text := raw.strip_edges()
	if text == "":
		return
	var key := text.to_lower()
	if seen.has(key):
		return
	seen[key] = true
	words.append(text)


static func _clip(raw: String, limit: int) -> String:
	var text := raw.strip_edges()
	if text.length() <= limit:
		return text
	return text.substr(0, limit).strip_edges()


static func _kind(type_name: String) -> String:
	match type_name:
		"place", "scene", "location":
			return "место"
		"object", "item":
			return "предмет"
		"document":
			return "документ"
		_:
			return ""
