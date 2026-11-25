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
	CaseDerive.materialize_breaks(doc.raw)
	return doc


func export_raw() -> Dictionary:
	var body := _copy(raw)
	CaseDerive.apply(body)
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


func add_fact(agent_index: int) -> String:
	var agents: Array = raw.get("agents", [])
	if agent_index < 0 or agent_index >= agents.size() or agents[agent_index] is not Dictionary:
		return ""
	_snapshot()
	var who := agents[agent_index] as Dictionary
	var facts: Array = who.get("facts", [])
	var fact_id := _fresh_id("fact", _fact_ids())
	facts.append({
		"id": fact_id,
		"content_full": "",
		"content_basic": "",
		"is_lie": false,
		"lie_type": "cannot_lie",
		"lie_text": "",
		"related_evidence_ids": [],
		"requires_evidence": false,
		"requires_broken_lies": [],
		"breaks_lie_on": null,
	})
	who["facts"] = facts
	changed.emit()
	return fact_id


func set_fact_field(agent_index: int, fact_index: int, key: String, value: Variant) -> void:
	var fact := _fact(agent_index, fact_index)
	if fact.is_empty():
		return
	_snapshot()
	fact[key] = value
	changed.emit()


func set_fact_kind(agent_index: int, fact_index: int, kind: String) -> void:
	var fact := _fact(agent_index, fact_index)
	if fact.is_empty():
		return
	_snapshot()
	var fact_id := str(fact.get("id", ""))
	if kind == "must_lie" or kind == "can_lie":
		fact["is_lie"] = true
		fact["lie_type"] = kind
		if not fact.has("breaks_with"):
			fact["breaks_with"] = []
	else:
		fact["is_lie"] = false
		fact["lie_type"] = "cannot_lie"
		fact["lie_text"] = ""
		fact.erase("breaks_with")
		fact["breaks_lie_on"] = null
		_drop_lie_contradictions(fact_id)
	changed.emit()


func move_fact(agent_index: int, fact_index: int, delta: int) -> void:
	var who := _agent(agent_index)
	if who.is_empty():
		return
	var facts: Array = who.get("facts", [])
	var next := fact_index + delta
	if fact_index < 0 or next < 0 or fact_index >= facts.size() or next >= facts.size():
		return
	_snapshot()
	var item: Variant = facts[fact_index]
	facts.remove_at(fact_index)
	facts.insert(next, item)
	who["facts"] = facts
	changed.emit()


func add_evidence() -> String:
	_snapshot()
	var evidence: Array = raw.get("evidence", [])
	var evidence_id := _fresh_id("ev", _evidence_ids())
	evidence.append({
		"id": evidence_id,
		"title": "",
		"type": "object",
		"short_description": "",
		"full_text": "",
		"related_fact_ids": [],
		"related_agent_ids": [],
		"is_key": false,
		"unlock_condition": null,
	})
	raw["evidence"] = evidence
	changed.emit()
	return evidence_id


func set_evidence_field(index: int, key: String, value: Variant) -> void:
	var evidence: Array = raw.get("evidence", [])
	if index < 0 or index >= evidence.size() or evidence[index] is not Dictionary:
		return
	_snapshot()
	(evidence[index] as Dictionary)[key] = value
	changed.emit()


func move_evidence(index: int, delta: int) -> void:
	var evidence: Array = raw.get("evidence", [])
	var next := index + delta
	if index < 0 or next < 0 or index >= evidence.size() or next >= evidence.size():
		return
	_snapshot()
	var item: Variant = evidence[index]
	evidence.remove_at(index)
	evidence.insert(next, item)
	raw["evidence"] = evidence
	changed.emit()


func set_unlock(index: int, condition: Variant) -> void:
	set_evidence_field(index, "unlock_condition", condition)


func add_break_set(agent_index: int, fact_index: int) -> void:
	var fact := _fact(agent_index, fact_index)
	if fact.is_empty():
		return
	_snapshot()
	var sets: Array = fact.get("breaks_with", []) if fact.get("breaks_with") is Array else []
	sets.append([{"type": "evidence_shown", "evidence_id": ""}])
	fact["breaks_with"] = sets
	changed.emit()


func add_contradiction(fact_id: String, other_fact_id: String, full_only: bool, description: String) -> String:
	_snapshot()
	var rows: Array = raw.get("contradictions", [])
	var contradiction_id := _fresh_id("con", _contradiction_ids())
	rows.append({
		"id": contradiction_id,
		"fact_a_id": fact_id,
		"fact_a_form": "lie",
		"fact_b_id": other_fact_id,
		"fact_b_form": "truth_full" if full_only else "truth",
		"description": description,
	})
	raw["contradictions"] = rows
	changed.emit()
	return contradiction_id


func usage_lines(kind: String, item_id: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if kind == "agent" and str(raw.get("killer_id", "")) == item_id:
		lines.append("убийца")
	for agent in raw.get("agents", []):
		if agent is not Dictionary:
			continue
		var who := agent as Dictionary
		if kind == "agent" and (who.get("relationships", {}) as Dictionary).has(item_id):
			lines.append("отношения «%s»" % str(who.get("name", who.get("id", ""))))
		for fact in who.get("facts", []):
			if fact is not Dictionary:
				continue
			var fact_body := fact as Dictionary
			var label := str(fact_body.get("content_full", fact_body.get("id", "")))
			if kind == "fact" and (fact_body.get("requires_broken_lies", []) as Array).has(item_id):
				lines.append("после сломанной лжи: %s" % label)
			if kind == "evidence" and (fact_body.get("related_evidence_ids", []) as Array).has(item_id):
				lines.append("связанные улики: %s" % label)
			for raw_set in fact_body.get("breaks_with", []):
				if raw_set is not Array:
					continue
				for item in raw_set:
					if item is not Dictionary:
						continue
					var point := item as Dictionary
					if kind == "evidence" and str(point.get("evidence_id", "")) == item_id:
						lines.append("чем можно сломать: %s" % label)
					if kind == "fact" and str(point.get("fact_id", "")) == item_id:
						lines.append("пересказ в наборе: %s" % label)
	for row in raw.get("contradictions", []):
		if row is not Dictionary:
			continue
		var body := row as Dictionary
		if kind == "fact" and (str(body.get("fact_a_id", "")) == item_id or str(body.get("fact_b_id", "")) == item_id):
			lines.append("противоречие %s" % str(body.get("id", "")))
	for evidence in raw.get("evidence", []):
		if evidence is not Dictionary:
			continue
		var title := str((evidence as Dictionary).get("title", (evidence as Dictionary).get("id", "")))
		if _cond_mentions((evidence as Dictionary).get("unlock_condition"), kind, item_id):
			lines.append("условие улики «%s»" % title)
	return lines


func remove_item(kind: String, item_id: String) -> void:
	_snapshot()
	if kind == "agent":
		_remove_agent(item_id)
	elif kind == "fact":
		_remove_fact(item_id)
	elif kind == "evidence":
		_remove_evidence(item_id)
	changed.emit()


func _remove_agent(agent_id: String) -> void:
	var facts: Array = []
	var agents: Array = raw.get("agents", [])
	var kept: Array = []
	for agent in agents:
		if agent is not Dictionary:
			continue
		if str((agent as Dictionary).get("id", "")) == agent_id:
			for fact in (agent as Dictionary).get("facts", []):
				if fact is Dictionary:
					facts.append(str((fact as Dictionary).get("id", "")))
			continue
		var links: Dictionary = (agent as Dictionary).get("relationships", {})
		links.erase(agent_id)
		(agent as Dictionary)["relationships"] = links
		kept.append(agent)
	raw["agents"] = kept
	if str(raw.get("killer_id", "")) == agent_id:
		raw["killer_id"] = ""
	for fact_id in facts:
		_remove_fact(str(fact_id))
	_strip_agent_conditions(agent_id)


func _remove_fact(fact_id: String) -> void:
	for agent in raw.get("agents", []):
		if agent is not Dictionary:
			continue
		var facts: Array = (agent as Dictionary).get("facts", [])
		var kept: Array = []
		for fact in facts:
			if fact is Dictionary and str((fact as Dictionary).get("id", "")) == fact_id:
				continue
			if fact is Dictionary:
				_drop_fact_refs(fact as Dictionary, fact_id)
			kept.append(fact)
		(agent as Dictionary)["facts"] = kept
	var rows: Array = raw.get("contradictions", [])
	var left: Array = []
	for row in rows:
		if row is not Dictionary:
			continue
		var body := row as Dictionary
		if str(body.get("fact_a_id", "")) == fact_id or str(body.get("fact_b_id", "")) == fact_id:
			continue
		left.append(row)
	raw["contradictions"] = left
	_strip_conditions_fact(fact_id)


func _remove_evidence(evidence_id: String) -> void:
	var evidence: Array = raw.get("evidence", [])
	var kept: Array = []
	for item in evidence:
		if item is Dictionary and str((item as Dictionary).get("id", "")) == evidence_id:
			continue
		kept.append(item)
	raw["evidence"] = kept
	for agent in raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is Dictionary:
				_drop_evidence_refs(fact as Dictionary, evidence_id)
	_strip_conditions_evidence(evidence_id)


func _drop_fact_refs(fact: Dictionary, fact_id: String) -> void:
	var priors: Array = fact.get("requires_broken_lies", []) if fact.get("requires_broken_lies") is Array else []
	if not priors.is_empty():
		var next: Array = []
		var lost := false
		for prior in priors:
			if str(prior) == fact_id:
				lost = true
				continue
			next.append(prior)
		if lost and next.is_empty():
			fact["requires_broken_lies"] = [""]
		elif lost:
			fact["requires_broken_lies"] = next
	var sets: Array = fact.get("breaks_with", []) if fact.get("breaks_with") is Array else []
	if sets.is_empty():
		return
	var kept_sets: Array = []
	for raw_set in sets:
		if raw_set is not Array:
			continue
		var items: Array = []
		for item in raw_set:
			if item is Dictionary and str((item as Dictionary).get("type", "")) == "testimony_retold" and str((item as Dictionary).get("fact_id", "")) == fact_id:
				continue
			items.append(item)
		if not items.is_empty():
			kept_sets.append(items)
	fact["breaks_with"] = kept_sets


func _drop_evidence_refs(fact: Dictionary, evidence_id: String) -> void:
	var related: Array = fact.get("related_evidence_ids", []) if fact.get("related_evidence_ids") is Array else []
	var next: Array = []
	for item in related:
		if str(item) != evidence_id:
			next.append(item)
	fact["related_evidence_ids"] = next
	var sets: Array = fact.get("breaks_with", []) if fact.get("breaks_with") is Array else []
	if sets.is_empty():
		return
	var kept_sets: Array = []
	for raw_set in sets:
		if raw_set is not Array:
			continue
		var items: Array = []
		for item in raw_set:
			if item is Dictionary and str((item as Dictionary).get("type", "")) == "evidence_shown" and str((item as Dictionary).get("evidence_id", "")) == evidence_id:
				continue
			items.append(item)
		if not items.is_empty():
			kept_sets.append(items)
	fact["breaks_with"] = kept_sets


func _drop_lie_contradictions(fact_id: String) -> void:
	var rows: Array = raw.get("contradictions", [])
	var left: Array = []
	for row in rows:
		if row is not Dictionary:
			continue
		var body := row as Dictionary
		var drop := false
		if str(body.get("fact_a_id", "")) == fact_id and str(body.get("fact_a_form", "")) == "lie":
			drop = true
		if str(body.get("fact_b_id", "")) == fact_id and str(body.get("fact_b_form", "")) == "lie":
			drop = true
		if not drop:
			left.append(row)
	raw["contradictions"] = left


func _strip_agent_conditions(agent_id: String) -> void:
	for evidence in raw.get("evidence", []):
		if evidence is Dictionary:
			(evidence as Dictionary)["unlock_condition"] = _strip_cond((evidence as Dictionary).get("unlock_condition"), "", "", agent_id, "")


func _strip_conditions_fact(fact_id: String) -> void:
	for evidence in raw.get("evidence", []):
		if evidence is Dictionary:
			(evidence as Dictionary)["unlock_condition"] = _strip_cond((evidence as Dictionary).get("unlock_condition"), "", fact_id, "", "")


func _strip_conditions_evidence(evidence_id: String) -> void:
	for evidence in raw.get("evidence", []):
		if evidence is Dictionary:
			(evidence as Dictionary)["unlock_condition"] = _strip_cond((evidence as Dictionary).get("unlock_condition"), evidence_id, "", "", "")


func _strip_cond(cond: Variant, evidence_id: String, fact_id: String, agent_id: String, contradiction_id: String) -> Variant:
	var cleaned: Variant = _strip_node(cond, evidence_id, fact_id, agent_id, contradiction_id)
	if cleaned is Dictionary and (cleaned as Dictionary).has("_drop"):
		return {"AND": []}
	return cleaned


func _strip_node(cond: Variant, evidence_id: String, fact_id: String, agent_id: String, contradiction_id: String) -> Variant:
	if cond == null or cond is not Dictionary:
		return cond
	var body := cond as Dictionary
	for op in ["AND", "OR"]:
		if not body.has(op):
			continue
		var kept: Array = []
		for sub in body[op] if body[op] is Array else []:
			var cleaned: Variant = _strip_node(sub, evidence_id, fact_id, agent_id, contradiction_id)
			if cleaned is Dictionary and (cleaned as Dictionary).has("_drop"):
				continue
			kept.append(cleaned)
		if kept.is_empty():
			return {"_drop": true}
		return {op: kept}
	if _clause_drops(body, evidence_id, fact_id, agent_id, contradiction_id):
		return {"_drop": true}
	return body


func _cond_mentions(cond: Variant, kind: String, item_id: String) -> bool:
	if cond is not Dictionary:
		return false
	var body := cond as Dictionary
	for op in ["AND", "OR"]:
		if body.has(op) and body[op] is Array:
			for sub in body[op]:
				if _cond_mentions(sub, kind, item_id):
					return true
			return false
	if kind == "evidence" and str(body.get("evidence_id", "")) == item_id:
		return true
	if kind == "fact" and str(body.get("fact_id", "")) == item_id:
		return true
	if kind == "agent" and str(body.get("agent_id", "")) == item_id:
		return true
	return false


func _clause_drops(body: Dictionary, evidence_id: String, fact_id: String, agent_id: String, contradiction_id: String) -> bool:
	if evidence_id != "" and str(body.get("evidence_id", "")) == evidence_id and str(body.get("type", "")) != "":
		return true
	if fact_id != "" and str(body.get("fact_id", "")) == fact_id:
		return true
	if agent_id != "" and str(body.get("agent_id", "")) == agent_id:
		return true
	if contradiction_id != "" and str(body.get("contradiction_id", "")) == contradiction_id:
		return true
	return false


func _agent(index: int) -> Dictionary:
	var agents: Array = raw.get("agents", [])
	if index < 0 or index >= agents.size() or agents[index] is not Dictionary:
		return {}
	return agents[index]


func _fact(agent_index: int, fact_index: int) -> Dictionary:
	var who := _agent(agent_index)
	var facts: Array = who.get("facts", [])
	if fact_index < 0 or fact_index >= facts.size() or facts[fact_index] is not Dictionary:
		return {}
	return facts[fact_index]


func _fact_ids() -> Dictionary:
	var ids := {}
	for agent in raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is Dictionary:
				ids[str((fact as Dictionary).get("id", ""))] = true
	return ids


func _evidence_ids() -> Dictionary:
	var ids := {}
	for evidence in raw.get("evidence", []):
		if evidence is Dictionary:
			ids[str((evidence as Dictionary).get("id", ""))] = true
	return ids


func _contradiction_ids() -> Dictionary:
	var ids := {}
	for row in raw.get("contradictions", []):
		if row is Dictionary:
			ids[str((row as Dictionary).get("id", ""))] = true
	return ids


func _fresh_id(prefix: String, used: Dictionary) -> String:
	var number := 1
	var item_id := "%s_%d" % [prefix, number]
	while used.has(item_id):
		number += 1
		item_id = "%s_%d" % [prefix, number]
	return item_id


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
