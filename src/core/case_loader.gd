class_name CaseLoader
extends RefCounted
## Читает JSON дела и, если валидатор молчит, собирает CaseData.


class Result:
	extends RefCounted
	var ok: bool = false
	## null, если файл не прочитан или валидатор нашёл ошибки.
	var case_data: CaseData = null
	## Словари {code, message}. Тот же набор, что у CaseValidator.
	var errors: Array[Dictionary] = []


static func load_case(path: String) -> Result:
	var result := Result.new()
	if not FileAccess.file_exists(path):
		result.errors.append(CaseValidator.error("file_not_found", "не удалось прочитать файл: %s" % path))
		return result
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	var parse_code := parser.parse(text)
	if parse_code != OK:
		result.errors.append(CaseValidator.error(
			"json_parse",
			"не удалось разобрать JSON (%s, строка %d)" % [parser.get_error_message(), parser.get_error_line()]
		))
		return result
	if typeof(parser.data) != TYPE_DICTIONARY:
		result.errors.append(CaseValidator.error("json_not_object", "JSON дела должен быть объектом, а не %s" % type_string(typeof(parser.data))))
		return result
	var raw := parser.data as Dictionary
	result.errors = CaseValidator.validate(raw)
	if not result.errors.is_empty():
		return result
	result.ok = true
	result.case_data = _parse(raw)
	return result


static func _parse(raw: Dictionary) -> CaseData:
	var data := CaseData.new()
	data.id = _string(raw.get("id"))
	data.title = _string(raw.get("title"))
	data.briefing = _string(raw.get("briefing"))
	data.intro_atmosphere = _string(raw.get("intro_atmosphere"))
	data.killer_id = _string(raw.get("killer_id"))
	data.true_motive_id = _string(raw.get("true_motive_id"))
	data.true_method_id = _string(raw.get("true_method_id"))
	data.truth_timeline = _string(raw.get("truth_timeline"))
	data.victory_condition = _string(raw.get("victory_condition", "correct_accusation"))
	data.starting_agent_id = _string(raw.get("starting_agent_id"))
	data.motive_options = _options(raw.get("motive_options"))
	data.method_options = _options(raw.get("method_options"))
	for agent_raw in _array(raw.get("agents")):
		if agent_raw is not Dictionary:
			continue
		var agent := _agent(agent_raw as Dictionary)
		data.agents.append(agent)
		data.agent_by_id[agent.id] = agent
		for fact in agent.facts:
			data.fact_by_id[fact.id] = fact
			data.fact_owner[fact.id] = agent.id
	for evidence_raw in _array(raw.get("evidence")):
		if evidence_raw is not Dictionary:
			continue
		var evidence := _evidence(evidence_raw as Dictionary)
		data.evidence.append(evidence)
		data.evidence_by_id[evidence.id] = evidence
	for contradiction_raw in _array(raw.get("contradictions")):
		if contradiction_raw is not Dictionary:
			continue
		var contradiction := _contradiction(contradiction_raw as Dictionary)
		data.contradictions.append(contradiction)
		data.contradiction_by_id[contradiction.id] = contradiction
	return data


static func _agent(raw: Dictionary) -> CaseData.Agent:
	var agent := CaseData.Agent.new()
	agent.id = _string(raw.get("id"))
	agent.name = _string(raw.get("name"))
	agent.role = _string(raw.get("role"))
	agent.personality = _string(raw.get("personality"))
	agent.prompt_background = _string(raw.get("prompt_background"))
	agent.background = _string(raw.get("background"))
	agent.starting_pressure = _int(raw.get("starting_pressure", 0))
	agent.starting_emotion = _string(raw.get("starting_emotion", "neutral"))
	agent.gender = _string(raw.get("gender"))
	agent.tts_voice = _string(raw.get("tts_voice"))
	agent.voice_style = _string(raw.get("voice_style"))
	agent.greeting = _string(raw.get("greeting"))
	var profanity := _string(raw.get("profanity"))
	agent.profanity = profanity if profanity != "" else "never"
	agent.wants = _string(raw.get("wants"))
	agent.fears = _string(raw.get("fears"))
	agent.own_version = _string(raw.get("own_version"))
	agent.life_details = _string(raw.get("life_details"))
	agent.sample_lines = _strings(raw.get("sample_lines"))
	if raw.get("relationships") is Dictionary:
		agent.relationships = (raw.get("relationships") as Dictionary).duplicate(true)
	for fact_raw in _array(raw.get("facts")):
		if fact_raw is Dictionary:
			agent.facts.append(_fact(fact_raw as Dictionary))
	return agent


static func _fact(raw: Dictionary) -> CaseData.Fact:
	var fact := CaseData.Fact.new()
	fact.id = _string(raw.get("id"))
	fact.content_basic = _string(raw.get("content_basic"))
	fact.content_full = _string(raw.get("content_full"))
	fact.is_lie = raw.get("is_lie") == true
	fact.lie_type = _string(raw.get("lie_type"))
	fact.lie_text = _string(raw.get("lie_text"))
	fact.tags = _strings(raw.get("tags"))
	fact.related_evidence_ids = _strings(raw.get("related_evidence_ids"))
	fact.pressure_for_basic = _int(raw.get("pressure_for_basic", 0))
	fact.pressure_for_full = _int(raw.get("pressure_for_full", 0))
	fact.requires_evidence = raw.get("requires_evidence") == true
	fact.requires_broken_lies = _strings(raw.get("requires_broken_lies"))
	fact.breaks_lie_on = _breaks(raw.get("breaks_lie_on"))
	fact.breaks_with_explicit = raw.has("breaks_with")
	if fact.breaks_with_explicit:
		fact.breaks_with = _break_sets(raw.get("breaks_with"))
	return fact


static func _break_sets(value: Variant) -> Array:
	var sets: Array = []
	if value is not Array:
		return sets
	for raw_set in value:
		var items: Array = []
		if raw_set is Array:
			for item in raw_set:
				if item is Dictionary:
					items.append((item as Dictionary).duplicate(true))
		sets.append(items)
	return sets


static func _evidence(raw: Dictionary) -> CaseData.EvidenceItem:
	var evidence := CaseData.EvidenceItem.new()
	evidence.id = _string(raw.get("id"))
	evidence.title = _string(raw.get("title"))
	evidence.short_description = _string(raw.get("short_description"))
	evidence.full_text = _string(raw.get("full_text"))
	evidence.type = _string(raw.get("type"))
	evidence.related_fact_ids = _strings(raw.get("related_fact_ids"))
	evidence.related_agent_ids = _strings(raw.get("related_agent_ids"))
	evidence.is_key = raw.get("is_key") == true
	var condition: Variant = raw.get("unlock_condition")
	if condition is Dictionary:
		evidence.unlock_condition = (condition as Dictionary).duplicate(true)
	return evidence


static func _contradiction(raw: Dictionary) -> CaseData.Contradiction:
	var contradiction := CaseData.Contradiction.new()
	contradiction.id = _string(raw.get("id"))
	contradiction.fact_a_id = _string(raw.get("fact_a_id"))
	contradiction.fact_a_form = _string(raw.get("fact_a_form"))
	contradiction.fact_b_id = _string(raw.get("fact_b_id"))
	contradiction.fact_b_form = _string(raw.get("fact_b_form"))
	contradiction.description = _string(raw.get("description"))
	return contradiction


static func _options(value: Variant) -> Array[CaseData.Option]:
	var options: Array[CaseData.Option] = []
	for item in _array(value):
		if item is not Dictionary:
			continue
		var option := CaseData.Option.new()
		option.id = _string((item as Dictionary).get("id"))
		option.text = _string((item as Dictionary).get("text"))
		options.append(option)
	return options


static func _breaks(value: Variant) -> Variant:
	if value == null:
		return null
	if value is Array:
		return _strings(value)
	return _string(value)


static func _strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in _array(value):
		result.append(_string(item))
	return result


static func _array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


static func _string(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)


static func _int(value: Variant) -> int:
	if value is bool:
		return 1 if value else 0
	if value is int:
		return value
	if value is float:
		return int(value)
	return 0
