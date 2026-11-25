class_name TurnOptions
extends RefCounted
## Закрытый список для поля chosen. Код решает, модель только выбирает номер.


static func build(case_data: CaseData, state: GameState, agent_id: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if case_data == null or state == null or agent_id == "":
		return options
	var number := 1
	for evidence in case_data.evidence:
		if state.unlocked_evidence.has(evidence.id):
			continue
		var topic := _topic(evidence.unlock_condition, agent_id, evidence.id)
		if topic == "":
			continue
		options.append({
			"n": number,
			"kind": "topic",
			"evidence_id": evidence.id,
			"fact_id": "",
			"lie_id": "",
			"title": evidence.title,
			"topic": topic,
			"text": "разговор по смыслу уже о теме «%s» (улика «%s»)" % [topic, evidence.title],
		})
		number += 1
		options.append({
			"n": number,
			"kind": "ask",
			"evidence_id": evidence.id,
			"fact_id": "",
			"lie_id": "",
			"title": evidence.title,
			"topic": topic,
			"text": "игрок прямо спрашивает про улику «%s»" % evidence.title,
		})
		number += 1
	for evidence in case_data.evidence:
		if not state.unlocked_evidence.has(evidence.id):
			continue
		var substance := evidence.full_text.strip_edges()
		if substance == "":
			continue
		if substance.length() > 180:
			substance = substance.substr(0, 180)
		options.append({
			"n": number,
			"kind": "present",
			"evidence_id": evidence.id,
			"fact_id": "",
			"lie_id": "",
			"title": evidence.title,
			"topic": "",
			"text": "игрок называет содержание улики «%s»: %s" % [evidence.title, substance],
		})
		number += 1
	var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
	var seen_cite := {}
	if agent != null:
		for fact in agent.facts:
			if not fact.is_lie or state.broken_lies.has(fact.id):
				continue
			for items in BreakSets.sets_of(case_data, fact):
				if items is not Array:
					continue
				for item in items:
					if item is not Dictionary:
						continue
					var body := item as Dictionary
					if str(body.get("type", "")) != "testimony_retold":
						continue
					var fact_id := str(body.get("fact_id", ""))
					var forms := PackedStringArray()
					if str(body.get("form", "")) == "truth_full":
						forms.append("full")
					else:
						forms.append("basic")
						forms.append("full")
					for form in forms:
						var pair := "%s|%s" % [fact_id, form]
						if seen_cite.has(pair) or state.retold.has(BreakSets.retell_key(agent_id, fact_id, form)):
							continue
						if not _heard(state, fact_id, form):
							continue
						seen_cite[pair] = true
						var speaker := _speaker(case_data, str(case_data.fact_owner.get(fact_id, "")))
						var quote := Notebook.text_for(case_data.fact_by_id.get(fact_id) as CaseData.Fact, form)
						options.append({
							"n": number,
							"kind": "cite",
							"evidence_id": "",
							"fact_id": fact_id,
							"lie_id": "",
							"form": form,
							"title": "",
							"topic": "",
							"text": "игрок прямо говорит, что %s сказал: «%s»" % [speaker, quote],
						})
						number += 1
	if options.is_empty():
		return options
	options.append({
		"n": number,
		"kind": "none",
		"evidence_id": "",
		"fact_id": "",
		"lie_id": "",
		"title": "",
		"topic": "",
		"text": "ничего из списка последняя реплика прямо не касается",
	})
	return options


static func prompt_block(case_data: CaseData, state: GameState, agent_id: String, options: Array) -> String:
	if options.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("ВЫБОР. Первый ключ ответа — chosen, массив номеров. Бери только то, что последняя реплика следователя говорит прямо и по смыслу. Сомневаешься — только номер «ничего».")
	for option in options:
		var body: Dictionary = option
		var line := "%d. %s" % [int(body.get("n", 0)), str(body.get("text", ""))]
		if str(body.get("kind", "")) == "topic":
			var count := touch_count(state, agent_id, str(body.get("evidence_id", "")))
			if count >= 1:
				line += ". В этой реплике скажи, что существует «%s»." % str(body.get("title", ""))
		elif str(body.get("kind", "")) == "ask":
			line += ". В этой реплике скажи, что существует «%s»." % str(body.get("title", ""))
		elif str(body.get("kind", "")) == "present":
			line += ". Только если названа суть, не одно название улики."
		lines.append(line)
	return "\n".join(lines)


static func numbers(options: Array) -> Array:
	var values: Array = []
	for option in options:
		values.append(int((option as Dictionary).get("n", 0)))
	return values


static func plan(case_data: CaseData, state: GameState, agent_id: String, options: Array, picked: Array) -> Dictionary:
	var result := {
		"decision": "none",
		"unlock": [] as Array[String],
		"touch": [] as Array[String],
		"break_lies": [] as Array[String],
		"present": [] as Array[String],
		"retold": [] as Array[String],
		"admit": [] as Array,
		"restart": false,
		"picked": picked,
	}
	var saw := false
	for number in picked:
		var option := _option(options, int(number))
		if option.is_empty() or str(option.get("kind", "")) == "none":
			continue
		saw = true
		var kind := str(option.get("kind", ""))
		if kind == "topic" or kind == "ask":
			var evidence_id := str(option.get("evidence_id", ""))
			var key := touch_key(agent_id, evidence_id)
			if not (result["touch"] as Array).has(key):
				(result["touch"] as Array).append(key)
			var count := touch_count(state, agent_id, evidence_id)
			if kind == "ask" or count + 1 >= 2:
				if not (result["unlock"] as Array).has(evidence_id):
					(result["unlock"] as Array).append(evidence_id)
			result["decision"] = "ask" if kind == "ask" else "topic"
		elif kind == "present":
			var evidence_id := str(option.get("evidence_id", ""))
			if evidence_id != "" and not (result["present"] as Array).has(evidence_id):
				(result["present"] as Array).append(evidence_id)
			_present_grants(case_data, state, agent_id, evidence_id, result)
			result["restart"] = true
			result["decision"] = "present"
		elif kind == "cite" and _cite_ok(case_data, state, agent_id, option):
			var fact_id := str(option.get("fact_id", ""))
			var form := str(option.get("form", ""))
			var key := BreakSets.retell_key(agent_id, fact_id, form)
			if not (result["retold"] as Array).has(key):
				(result["retold"] as Array).append(key)
			_retell_grants(case_data, state, agent_id, key, result)
			result["decision"] = "cite"
			if not (result["break_lies"] as Array).is_empty():
				result["restart"] = true
	if not saw:
		result["decision"] = "none"
	return result


static func touch_key(agent_id: String, evidence_id: String) -> String:
	return "%s|%s" % [agent_id, evidence_id]


static func touch_count(state: GameState, agent_id: String, evidence_id: String) -> int:
	if state == null:
		return 0
	return int(state.topic_touches.get(touch_key(agent_id, evidence_id), 0))


static func _present_grants(case_data: CaseData, state: GameState, agent_id: String, evidence_id: String, result: Dictionary) -> void:
	var preview := GameState.from_dict(state.to_dict())
	_mark(preview, evidence_id, agent_id)
	_grants(case_data, preview, agent_id, result, evidence_id)


static func _retell_grants(case_data: CaseData, state: GameState, agent_id: String, key: String, result: Dictionary) -> void:
	var preview := GameState.from_dict(state.to_dict())
	for previous in result.get("retold", []):
		var name := str(previous)
		if name != "" and not preview.retold.has(name):
			preview.retold.append(name)
	if not preview.retold.has(key):
		preview.retold.append(key)
	for evidence_id in result.get("present", []):
		_mark(preview, str(evidence_id), agent_id)
	_grants(case_data, preview, agent_id, result, "")


static func _grants(case_data: CaseData, preview: GameState, agent_id: String, result: Dictionary, shown_evidence_id: String) -> void:
	var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
	if agent == null:
		return
	for fact in agent.facts:
		if not fact.is_lie or preview.broken_lies.has(fact.id) or not _requirements_open(preview, fact):
			continue
		if not BreakSets.holds(case_data, preview, fact):
			continue
		if (result["break_lies"] as Array).has(fact.id):
			continue
		(result["break_lies"] as Array).append(fact.id)
		(result["admit"] as Array).append(_truth(case_data, preview, fact.id, shown_evidence_id))


static func _mark(preview: GameState, evidence_id: String, agent_id: String) -> void:
	if evidence_id == "":
		return
	if not preview.shown.has(evidence_id):
		preview.shown[evidence_id] = [] as Array[String]
	var agents: Array = preview.shown[evidence_id]
	if not agents.has(agent_id):
		agents.append(agent_id)
		preview.shown[evidence_id] = agents


static func _requirements_open(state: GameState, fact: CaseData.Fact) -> bool:
	for fact_id in fact.requires_broken_lies:
		if not state.broken_lies.has(fact_id):
			return false
	return true


static func _option(options: Array, number: int) -> Dictionary:
	for option in options:
		if int((option as Dictionary).get("n", 0)) == number:
			return option
	return {}


static func _cite_ok(case_data: CaseData, state: GameState, agent_id: String, option: Dictionary) -> bool:
	var fact_id := str(option.get("fact_id", ""))
	var form := str(option.get("form", ""))
	if fact_id == "" or form == "" or case_data.fact_by_id.get(fact_id) == null:
		return false
	if state.retold.has(BreakSets.retell_key(agent_id, fact_id, form)):
		return false
	return _heard(state, fact_id, form)


static func _heard(state: GameState, fact_id: String, form: String) -> bool:
	for entry in state.heard:
		if str(entry.get("fact_id", "")) == fact_id and str(entry.get("form", "")) == form:
			return true
	return false


static func _heard_form(state: GameState, agent_id: String, fact_id: String) -> String:
	for entry in state.heard:
		if str(entry.get("agent_id", "")) == agent_id:
			continue
		if str(entry.get("fact_id", "")) == fact_id:
			return str(entry.get("form", ""))
	return ""


static func _paired_lie(case_data: CaseData, state: GameState, agent_id: String, fact_id: String, form: String, contradiction: CaseData.Contradiction) -> String:
	var pairs := [
		[contradiction.fact_a_id, contradiction.fact_a_form, contradiction.fact_b_id, contradiction.fact_b_form],
		[contradiction.fact_b_id, contradiction.fact_b_form, contradiction.fact_a_id, contradiction.fact_a_form],
	]
	for pair in pairs:
		if str(pair[0]) != fact_id or not _form_ok(form, str(pair[1])):
			continue
		if str(pair[3]) != "lie":
			continue
		var lie_id := str(pair[2])
		if str(case_data.fact_owner.get(lie_id, "")) != agent_id:
			continue
		if state.broken_lies.has(lie_id):
			continue
		var fact: CaseData.Fact = case_data.fact_by_id.get(lie_id) as CaseData.Fact
		if fact != null and fact.is_lie and _requirements_open(state, fact):
			return lie_id
	return ""


static func _form_ok(journal_form: String, contradiction_form: String) -> bool:
	if contradiction_form == "lie":
		return journal_form == "lie"
	if contradiction_form == "truth_full":
		return journal_form == "full"
	if contradiction_form == "truth":
		return journal_form == "basic" or journal_form == "full"
	return false


static func _topic(cond: Variant, agent_id: String, evidence_id: String) -> String:
	if cond is not Dictionary:
		return ""
	var body := cond as Dictionary
	for op in ["AND", "OR"]:
		if body.has(op) and body[op] is Array:
			for sub in body[op]:
				var topic := _topic(sub, agent_id, evidence_id)
				if topic != "":
					return topic
			return ""
	if str(body.get("type", "")) != "evidence_mentioned":
		return ""
	if str(body.get("agent_id", "")) != agent_id or str(body.get("evidence_id", "")) != evidence_id:
		return ""
	var topic := str(body.get("topic", "")).strip_edges()
	return topic if topic != "" else evidence_id


static func _speaker(case_data: CaseData, agent_id: String) -> String:
	var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
	if agent == null:
		return agent_id
	if agent.role == "":
		return agent.name
	return "%s, %s" % [agent.name, agent.role]


static func _truth(case_data: CaseData, state: GameState, lie_id: String, shown_evidence_id: String = "") -> String:
	var fact: CaseData.Fact = case_data.fact_by_id.get(lie_id) as CaseData.Fact
	if fact == null:
		return ""
	var shown := shown_evidence_id != "" and fact.related_evidence_ids.has(shown_evidence_id)
	var owner := str(case_data.fact_owner.get(lie_id, ""))
	if not shown:
		for evidence_id in fact.related_evidence_ids:
			var agents: Array = state.shown.get(evidence_id, [])
			if agents.has(owner):
				shown = true
	if fact.requires_evidence and not shown:
		return fact.content_basic
	return fact.content_full if fact.content_full != "" else fact.content_basic
