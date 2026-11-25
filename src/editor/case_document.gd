class_name CaseDocument
extends RefCounted
## Черновик редактора. Снимок — исходный словарь, не CaseData.


signal changed

const UNDO_LIMIT := 20

var raw: Dictionary = {}
var _undo: Array[String] = []
var _redo_lock := false


static func open(source: Dictionary) -> CaseDocument:
	var doc := CaseDocument.new()
	doc.raw = _copy(source)
	doc._bring_starting_forward()
	return doc


func export_raw() -> Dictionary:
	var body := _copy(raw)
	body["victory_condition"] = "correct_accusation"
	var agents: Array = body.get("agents", [])
	if not agents.is_empty() and agents[0] is Dictionary:
		body["starting_agent_id"] = str((agents[0] as Dictionary).get("id", ""))
	for agent in agents:
		if agent is not Dictionary:
			continue
		var who := agent as Dictionary
		if str(who.get("profanity", "")) == "":
			who["profanity"] = "never"
		var fillers: Array = []
		var listed: Variant = who.get("filler_lines", [])
		if listed is Array:
			for line in listed:
				var text := str(line).strip_edges()
				if text == "":
					continue
				fillers.append(text)
				if fillers.size() == 3:
					break
		if fillers.is_empty():
			who.erase("filler_lines")
		else:
			who["filler_lines"] = fillers
		var links: Dictionary = who.get("relationships", {})
		var kept := {}
		for other in links:
			var phrase := str(links[other]).strip_edges()
			if phrase != "":
				kept[other] = phrase
		who["relationships"] = kept
	return SaveState.without_secrets(body)


func set_field(key: String, value: Variant) -> void:
	_snapshot()
	raw[key] = value
	changed.emit()


func set_editor_note(text: String) -> void:
	_snapshot()
	var note: Dictionary = raw.get("editor", {})
	note["timeline_text"] = text
	raw["editor"] = note
	changed.emit()


func set_agent_field(index: int, key: String, value: Variant) -> void:
	var agents: Array = raw.get("agents", [])
	if index < 0 or index >= agents.size() or agents[index] is not Dictionary:
		return
	_snapshot()
	(agents[index] as Dictionary)[key] = value
	changed.emit()


func move_agent(index: int, delta: int) -> void:
	var agents: Array = raw.get("agents", [])
	var next := index + delta
	if index < 0 or next < 0 or index >= agents.size() or next >= agents.size():
		return
	_snapshot()
	var item: Variant = agents[index]
	agents.remove_at(index)
	agents.insert(next, item)
	raw["agents"] = agents
	changed.emit()


func add_agent() -> void:
	_snapshot()
	var agents: Array = raw.get("agents", [])
	var ids := {}
	for agent in agents:
		if agent is Dictionary:
			ids[str((agent as Dictionary).get("id", ""))] = true
	var n := agents.size() + 1
	var agent_id := "agent_%d" % n
	while ids.has(agent_id):
		n += 1
		agent_id = "agent_%d" % n
	agents.append(CaseLibrary._blank_agent(agent_id))
	raw["agents"] = agents
	changed.emit()


func undo() -> bool:
	if _undo.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(_undo.pop_back())
	if parsed is not Dictionary:
		return false
	raw = parsed
	changed.emit()
	return true


func _snapshot() -> void:
	if _redo_lock:
		return
	_undo.append(JSON.stringify(raw))
	while _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func _bring_starting_forward() -> void:
	var start := str(raw.get("starting_agent_id", ""))
	var agents: Array = raw.get("agents", [])
	if start == "" or agents.is_empty():
		return
	var index := -1
	for i in agents.size():
		if agents[i] is Dictionary and str((agents[i] as Dictionary).get("id", "")) == start:
			index = i
			break
	if index <= 0:
		return
	var agent: Variant = agents[index]
	agents.remove_at(index)
	agents.insert(0, agent)
	raw["agents"] = agents


static func _copy(source: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(source))
	if parsed is Dictionary:
		return parsed
	return {}
