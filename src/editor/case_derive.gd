class_name CaseDerive
extends RefCounted
## Поля, которые редактор пересчитывает при сохранении (раздел 6).


static func materialize_breaks(raw: Dictionary) -> void:
	var contradictions: Array = raw.get("contradictions", [])
	for agent in raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is not Dictionary:
				continue
			var body := fact as Dictionary
			if not body.get("is_lie", false) or body.has("breaks_with"):
				continue
			body["breaks_with"] = CaseValidator.effective_sets(body, contradictions)


static func apply(raw: Dictionary) -> void:
	raw["victory_condition"] = "correct_accusation"
	var agents: Array = raw.get("agents", [])
	if not agents.is_empty() and agents[0] is Dictionary:
		raw["starting_agent_id"] = str((agents[0] as Dictionary).get("id", ""))
	for agent in agents:
		if agent is not Dictionary:
			continue
		_agent(agent as Dictionary)
	materialize_breaks(raw)
	var owners := _owners(raw)
	for agent in agents:
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is Dictionary:
				_fact(fact as Dictionary)
	_evidence(raw, owners)
	_contradictions(raw)


static func _agent(who: Dictionary) -> void:
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
	var links: Variant = who.get("relationships", {})
	var kept := {}
	if links is Dictionary:
		for other in links:
			var phrase := str(links[other]).strip_edges()
			if phrase != "":
				kept[other] = phrase
	who["relationships"] = kept


static func _fact(fact: Dictionary) -> void:
	var lie: bool = fact.get("is_lie", false) == true
	var kind := str(fact.get("lie_type", ""))
	if not lie or kind == "cannot_lie":
		fact["is_lie"] = false
		fact["lie_type"] = "cannot_lie"
		fact["lie_text"] = ""
		fact.erase("breaks_with")
		fact["breaks_lie_on"] = null
		if str(fact.get("content_basic", "")).strip_edges() == "":
			fact["content_basic"] = str(fact.get("content_full", ""))
		return
	if kind != "must_lie" and kind != "can_lie":
		fact["lie_type"] = "must_lie"
		kind = "must_lie"
	var sets: Array = fact.get("breaks_with", []) if fact.get("breaks_with") is Array else []
	var kept: Array = []
	for raw_set in sets:
		if raw_set is Array and not (raw_set as Array).is_empty():
			kept.append(raw_set)
	fact["breaks_with"] = kept
	fact["breaks_lie_on"] = _breaks_lie_on(fact.get("breaks_lie_on"), kept)
	if kind != "can_lie" and str(fact.get("content_basic", "")).strip_edges() == "":
		fact["content_basic"] = str(fact.get("content_full", ""))


static func _breaks_lie_on(previous: Variant, sets: Array) -> Variant:
	var had_pressure := false
	var listed: Array = previous if previous is Array else ([] if previous == null or str(previous) == "" else [previous])
	for item in listed:
		if str(item) == "pressure":
			had_pressure = true
	var evidence := false
	var retold := false
	for raw_set in sets:
		if raw_set is not Array:
			continue
		for item in raw_set:
			if item is not Dictionary:
				continue
			var kind := str((item as Dictionary).get("type", ""))
			if kind == "evidence_shown":
				evidence = true
			elif kind == "testimony_retold":
				retold = true
	var modes: Array = []
	if retold:
		modes.append("contradiction")
	if evidence:
		modes.append("evidence")
	if had_pressure:
		modes.append("pressure")
	if modes.is_empty():
		return null
	if modes.size() == 1:
		return modes[0]
	return modes


static func _owners(raw: Dictionary) -> Dictionary:
	var owners := {}
	for agent in raw.get("agents", []):
		if agent is not Dictionary:
			continue
		var agent_id := str((agent as Dictionary).get("id", ""))
		for fact in (agent as Dictionary).get("facts", []):
			if fact is not Dictionary:
				continue
			var fact_id := str((fact as Dictionary).get("id", ""))
			for evidence_id in (fact as Dictionary).get("related_evidence_ids", []):
				var key := str(evidence_id)
				if not owners.has(key):
					owners[key] = []
				var row: Array = owners[key]
				if not row.has(agent_id) and agent_id != "":
					row.append(agent_id)
	return owners


static func _evidence(raw: Dictionary, owners: Dictionary) -> void:
	var linked := {}
	for agent in raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is not Dictionary:
				continue
			var fact_id := str((fact as Dictionary).get("id", ""))
			for evidence_id in (fact as Dictionary).get("related_evidence_ids", []):
				var key := str(evidence_id)
				if not linked.has(key):
					linked[key] = []
				var row: Array = linked[key]
				if fact_id != "" and not row.has(fact_id):
					row.append(fact_id)
	var agent_ids := {}
	for agent in raw.get("agents", []):
		if agent is Dictionary:
			agent_ids[str((agent as Dictionary).get("id", ""))] = true
	for evidence in raw.get("evidence", []):
		if evidence is not Dictionary:
			continue
		var body := evidence as Dictionary
		var kind := str(body.get("type", ""))
		if kind == "scene" or kind == "location":
			body["type"] = "place"
		elif kind == "item":
			body["type"] = "object"
		var evidence_id := str(body.get("id", ""))
		var facts: Array = linked.get(evidence_id, [])
		var previous: Array = body.get("related_fact_ids", []) if body.get("related_fact_ids") is Array else []
		var next: Array = []
		for fact_id in previous:
			if facts.has(str(fact_id)) and not next.has(str(fact_id)):
				next.append(str(fact_id))
		for fact_id in facts:
			if not next.has(fact_id):
				next.append(fact_id)
		body["related_fact_ids"] = next
		var people: Array = owners.get(evidence_id, [])
		var had: Array = body.get("related_agent_ids", []) if body.get("related_agent_ids") is Array else []
		var agents: Array = []
		for agent_id in had:
			var who := str(agent_id)
			if agent_ids.has(who) and not agents.has(who):
				agents.append(who)
		for agent_id in people:
			if not agents.has(agent_id):
				agents.append(agent_id)
		body["related_agent_ids"] = agents
		if not body.has("is_key"):
			body["is_key"] = false


static func _contradictions(raw: Dictionary) -> void:
	for item in raw.get("contradictions", []):
		if item is not Dictionary:
			continue
		var body := item as Dictionary
		var form := str(body.get("fact_b_form", ""))
		if form == "lie":
			continue
		if form != "truth" and form != "truth_full":
			body["fact_b_form"] = "truth"
		if str(body.get("fact_a_form", "")) == "":
			body["fact_a_form"] = "lie"
