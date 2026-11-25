class_name CaseValidator
extends RefCounted
## Те же правила, что tools/validate_case.py. У каждой ошибки есть код.
## Предупреждения о невзаимных связях не блокируют загрузку.

const EMOTIONS: PackedStringArray = [
	"angry", "calm", "contemptuous", "controlled", "nervous", "neutral", "sad", "scared",
]
const LIE_TYPES: PackedStringArray = ["can_lie", "cannot_lie", "must_lie"]
const BREAKS: PackedStringArray = ["contradiction", "evidence", "pressure"]
const FORMS: PackedStringArray = ["lie", "truth", "truth_full"]
const CASE_FIELDS: PackedStringArray = [
	"id", "title", "briefing", "killer_id", "true_motive_id", "true_method_id",
	"motive_options", "method_options", "agents", "evidence",
]
const AGENT_FIELDS: PackedStringArray = [
	"name", "role", "personality", "prompt_background", "background", "facts",
]


static func error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}


static func validate(raw: Dictionary) -> Array[Dictionary]:
	return _inspect(raw)["errors"]


static func warning_messages(raw: Dictionary) -> PackedStringArray:
	return _inspect(raw)["warnings"]


static func _inspect(raw: Dictionary) -> Dictionary:
	var errors: Array[Dictionary] = []
	var warnings: PackedStringArray = PackedStringArray()
	for key in CASE_FIELDS:
		if not raw.has(key):
			errors.append(error("missing_field", "нет обязательного поля дела: %s" % key))
	var agents := _as_array(raw.get("agents", []))
	var evidence := _as_array(raw.get("evidence", []))
	var contradictions := _as_array(raw.get("contradictions", []))
	var agent_ids := _unique_ids(agents, "агента", errors)
	var evidence_ids := _unique_ids(evidence, "улики", errors)
	var contradiction_ids := _unique_ids(contradictions, "противоречия", errors)
	var facts := {}
	for agent in agents:
		if agent is not Dictionary:
			continue
		var agent_body := agent as Dictionary
		for fact in _as_array(agent_body.get("facts", [])):
			if fact is not Dictionary:
				continue
			var fact_body := fact as Dictionary
			var fact_id: Variant = fact_body.get("id")
			if _falsy(fact_id):
				errors.append(error("fact_id_missing", "факт без id у агента %s" % _show(agent_body.get("id"))))
				continue
			if facts.has(fact_id):
				errors.append(error("fact_id_duplicate", "повторяющийся id факта: %s" % _show(fact_id)))
			facts[fact_id] = fact_body
	if not agent_ids.has(raw.get("killer_id")):
		errors.append(error(
			"killer_missing",
			"убийца %s не найден среди агентов" % _show(raw.get("killer_id"))
		))
	if not _option_ids(raw.get("motive_options", [])).has(raw.get("true_motive_id")):
		errors.append(error(
			"true_motive_missing",
			"true_motive_id %s нет в motive_options" % _show(raw.get("true_motive_id"))
		))
	if not _option_ids(raw.get("method_options", [])).has(raw.get("true_method_id")):
		errors.append(error(
			"true_method_missing",
			"true_method_id %s нет в method_options" % _show(raw.get("true_method_id"))
		))
	var victory: Variant = raw.get("victory_condition", "correct_accusation")
	if victory != "correct_accusation":
		errors.append(error(
			"victory_condition",
			"victory_condition '%s' не поддерживается (только correct_accusation)" % _show(victory)
		))
	var starting_agent: Variant = raw.get("starting_agent_id")
	if not _falsy(starting_agent) and not agent_ids.has(starting_agent):
		errors.append(error(
			"starting_agent_missing",
			"starting_agent_id %s не найден" % _show(starting_agent)
		))
	for agent in agents:
		if agent is not Dictionary:
			continue
		_validate_agent(agent as Dictionary, agent_ids, errors)
	var lie_facts := {}
	for contradiction in contradictions:
		if contradiction is not Dictionary:
			continue
		var contradiction_body := contradiction as Dictionary
		for side in ["a", "b"]:
			if contradiction_body.get("fact_%s_form" % side) == "lie":
				lie_facts[contradiction_body.get("fact_%s_id" % side)] = true
	for fact_id in facts:
		_validate_fact(str(fact_id), facts[fact_id], facts, evidence_ids, lie_facts, errors)
	for contradiction_id in contradiction_ids:
		_validate_contradiction(contradiction_id, contradiction_ids[contradiction_id], facts, errors)
	for evidence_id in evidence_ids:
		_validate_evidence(
			evidence_id,
			evidence_ids[evidence_id],
			facts,
			agent_ids,
			evidence_ids,
			contradiction_ids,
			errors
		)
	for evidence_id in evidence_ids:
		var evidence_body: Dictionary = evidence_ids[evidence_id]
		for fact_id in _as_array(evidence_body.get("related_fact_ids", [])):
			if not facts.has(fact_id):
				continue
			var related: Variant = (facts[fact_id] as Dictionary).get("related_evidence_ids", [])
			var linked := related is Array and (related as Array).has(evidence_id)
			if not linked:
				warnings.append("улика %s ссылается на факт %s, но факт не ссылается на улику" % [
					_show(evidence_id), _show(fact_id),
				])
	return {"errors": errors, "warnings": warnings}


static func _validate_agent(agent: Dictionary, agent_ids: Dictionary, errors: Array[Dictionary]) -> void:
	var agent_id := _show(agent.get("id"))
	for key in AGENT_FIELDS:
		if not agent.has(key) or _is_blank_text(agent[key]):
			errors.append(error("agent_field_missing", "агент %s: нет поля %s" % [agent_id, key]))
	var emotion: Variant = agent.get("starting_emotion", "neutral")
	if not EMOTIONS.has(emotion):
		errors.append(error(
			"emotion_unknown",
			"агент %s: эмоция '%s' не из списка %s" % [agent_id, _show(emotion), _py_list(EMOTIONS)]
		))
	for key in ["starting_pressure"]:
		var value: Variant = agent.get(key, 0)
		if not _is_number(value) or not _in_unit_interval(value):
			errors.append(error(
				"agent_stat_range",
				"агент %s: %s=%s вне 0–100" % [agent_id, key, _show(value)]
			))
	var relationships: Variant = agent.get("relationships")
	if relationships is Dictionary and not (relationships as Dictionary).is_empty():
		for other in relationships:
			if not agent_ids.has(other) or other == agent.get("id"):
				errors.append(error(
					"relationship_unknown",
					"агент %s: relationships ссылается на неверного агента %s" % [agent_id, _show(other)]
				))
	var gender := _string_or_empty(agent.get("gender"))
	if gender != "" and gender != "male" and gender != "female":
		errors.append(error("agent_gender", "агент %s: gender '%s' не male/female" % [agent_id, gender]))
	var tts_voice := _string_or_empty(agent.get("tts_voice"))
	if tts_voice != "" and not _voice_name_ok(tts_voice):
		errors.append(error("agent_tts_voice", "агент %s: tts_voice '%s' не имя голоса" % [agent_id, tts_voice]))


static func _validate_fact(
	fact_id: String,
	fact: Dictionary,
	facts: Dictionary,
	evidence_ids: Dictionary,
	lie_facts: Dictionary,
	errors: Array[Dictionary]
) -> void:
	var where := "факт %s" % fact_id
	for key in ["content_basic", "content_full"]:
		if _falsy(fact.get(key)):
			errors.append(error("fact_content_empty", "%s: пустое %s" % [where, key]))
	var basic: Variant = fact.get("pressure_for_basic")
	var full: Variant = fact.get("pressure_for_full")
	if basic != null or full != null:
		if not _is_number(basic) or not _is_number(full):
			errors.append(error("pressure_not_number", "%s: пороги давления не числа" % where))
		elif _as_float(full) < _as_float(basic):
			errors.append(error(
				"pressure_order",
				"%s: pressure_for_full (%s) < pressure_for_basic (%s)" % [where, _show(full), _show(basic)]
			))
	var related := _as_array(fact.get("related_evidence_ids", []))
	for evidence_id in related:
		if not evidence_ids.has(evidence_id):
			errors.append(error(
				"fact_unknown_evidence",
				"%s: улика %s не существует" % [where, _show(evidence_id)]
			))
	if not _falsy(fact.get("requires_evidence")) and related.is_empty():
		errors.append(error(
			"requires_evidence_empty",
			"%s: requires_evidence=true, но related_evidence_ids пуст" % where
		))
	var lie_type: Variant = fact.get("lie_type")
	if not LIE_TYPES.has(lie_type):
		errors.append(error(
			"lie_type_unknown",
			"%s: lie_type '%s' не из %s" % [where, _show(lie_type), _py_list(LIE_TYPES)]
		))
	var breaks_value: Variant = fact.get("breaks_lie_on")
	if breaks_value is Array:
		var seen := {}
		var duplicate := false
		for item in breaks_value:
			if seen.has(item):
				duplicate = true
			seen[item] = true
		if (breaks_value as Array).is_empty() or duplicate:
			errors.append(error(
				"breaks_lie_on_invalid_list",
				"%s: breaks_lie_on — пустой список или повторы" % where
			))
	var breaks := _breaks_list(breaks_value)
	for item in breaks:
		if not BREAKS.has(item):
			errors.append(error(
				"breaks_lie_on_unknown",
				"%s: breaks_lie_on '%s' недопустим" % [where, _show(item)]
			))
	var is_lie: Variant = fact.get("is_lie")
	if lie_type == "must_lie" or lie_type == "can_lie":
		if not (is_lie is bool and is_lie == true):
			errors.append(error(
				"lie_flag_mismatch",
				"%s: lie_type=%s, но is_lie не true" % [where, _show(lie_type)]
			))
		if _falsy(fact.get("lie_text")):
			errors.append(error(
				"lie_text_missing",
				"%s: lie_type=%s, но lie_text пуст" % [where, _show(lie_type)]
			))
	if lie_type == "cannot_lie":
		if not _falsy(is_lie):
			errors.append(error("cannot_lie_flag", "%s: cannot_lie, но is_lie=true" % where))
		if not _falsy(fact.get("lie_text")):
			errors.append(error("lie_text_forbidden", "%s: cannot_lie, но lie_text заполнен" % where))
	if _falsy(is_lie) and not breaks.is_empty():
		errors.append(error("breaks_lie_on_unexpected", "%s: у факта без лжи задан breaks_lie_on" % where))
	if breaks.has("evidence") and related.is_empty():
		errors.append(error(
			"breaks_lie_evidence_unlinked",
			"%s: breaks_lie_on=evidence, но нет related_evidence_ids" % where
		))
	if breaks.has("contradiction") and not lie_facts.has(fact_id):
		errors.append(error(
			"breaks_lie_no_contradiction",
			"%s: breaks_lie_on=contradiction, но нет противоречия с этим фактом в форме lie" % where
		))
	for prior_id in _as_array(fact.get("requires_broken_lies", [])):
		if not facts.has(prior_id):
			errors.append(error(
				"requires_broken_unknown",
			"%s: requires_broken_lies ссылается на неизвестный факт %s" % [where, _show(prior_id)]
		))


static func _validate_contradiction(
	contradiction_id: Variant,
	contradiction: Dictionary,
	facts: Dictionary,
	errors: Array[Dictionary]
) -> void:
	var where := "противоречие %s" % _show(contradiction_id)
	var pair: Array[Array] = []
	for side in ["a", "b"]:
		var fact_id: Variant = contradiction.get("fact_%s_id" % side)
		var form: Variant = contradiction.get("fact_%s_form" % side)
		if not facts.has(fact_id):
			errors.append(error(
				"contradiction_unknown_fact",
				"%s: факт %s не существует" % [where, _show(fact_id)]
			))
		elif form == "lie" and _falsy((facts[fact_id] as Dictionary).get("is_lie")):
			errors.append(error(
				"contradiction_lie_without_lie",
				"%s: форма lie у факта %s без лжи" % [where, _show(fact_id)]
			))
		if not FORMS.has(form):
			errors.append(error(
				"contradiction_form_unknown",
				"%s: форма '%s' не из %s" % [where, _show(form), _py_list(FORMS)]
			))
		pair.append([fact_id, form])
	if pair[0][0] == pair[1][0] and pair[0][1] == pair[1][1]:
		errors.append(error("contradiction_same_statement", "%s: оба утверждения одинаковы" % where))
	if _falsy(contradiction.get("description")):
		errors.append(error("contradiction_no_description", "%s: нет description" % where))


static func _validate_evidence(
	evidence_id: Variant,
	evidence: Dictionary,
	facts: Dictionary,
	agent_ids: Dictionary,
	evidence_ids: Dictionary,
	contradiction_ids: Dictionary,
	errors: Array[Dictionary]
) -> void:
	var where := "улика %s" % _show(evidence_id)
	for key in ["title", "short_description", "full_text", "type"]:
		if _falsy(evidence.get(key)):
			errors.append(error("evidence_field_missing", "%s: нет поля %s" % [where, key]))
	var related_facts := _as_array(evidence.get("related_fact_ids", []))
	for fact_id in related_facts:
		if not facts.has(fact_id):
			errors.append(error(
				"evidence_unknown_fact",
				"%s: факт %s не существует" % [where, _show(fact_id)]
			))
	var related_agents := _as_array(evidence.get("related_agent_ids", []))
	for agent_id in related_agents:
		if not agent_ids.has(agent_id):
			errors.append(error(
				"evidence_unknown_agent",
				"%s: агент %s не существует" % [where, _show(agent_id)]
			))
	var no_facts := _falsy(evidence.get("related_fact_ids"))
	var no_agents := _falsy(evidence.get("related_agent_ids"))
	if not _falsy(evidence.get("is_key")) and no_facts and no_agents:
		errors.append(error("key_evidence_unlinked", "ключевая улика %s ни с чем не связана" % _show(evidence_id)))
	if not _falsy(evidence.get("is_key")) and no_facts:
		errors.append(error(
			"key_evidence_no_facts",
			"ключевая улика %s не связана ни с одним фактом" % _show(evidence_id)
		))
	errors.append_array(Conditions.check(
		evidence.get("unlock_condition"),
		where,
		_show(evidence_id),
		agent_ids,
		evidence_ids,
		contradiction_ids,
		facts
	))


static func _unique_ids(items: Array, what: String, errors: Array[Dictionary]) -> Dictionary:
	var ids := {}
	for item in items:
		if item is not Dictionary:
			errors.append(error("field_type", "%s: элемент не объект" % what))
			continue
		var body := item as Dictionary
		var item_id: Variant = body.get("id")
		if _falsy(item_id):
			errors.append(error("id_missing", "%s без id" % what))
		elif ids.has(item_id):
			errors.append(error("id_duplicate", "повторяющийся id %s: %s" % [what, _show(item_id)]))
		ids[item_id] = body
	return ids


static func _option_ids(options: Variant) -> Dictionary:
	var ids := {}
	for option in _as_array(options):
		if option is Dictionary:
			ids[(option as Dictionary).get("id")] = true
	return ids


static func _breaks_list(value: Variant) -> Array:
	if value == null:
		return []
	if value is Array:
		return value
	return [value]


static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


static func _is_blank_text(value: Variant) -> bool:
	return value == null or (value is String and (value as String).is_empty())


static func _falsy(value: Variant) -> bool:
	if value == null:
		return true
	match typeof(value):
		TYPE_BOOL:
			return not value
		TYPE_INT:
			return value == 0
		TYPE_FLOAT:
			return value == 0.0
		TYPE_STRING:
			return (value as String).is_empty()
		TYPE_ARRAY:
			return (value as Array).is_empty()
		TYPE_DICTIONARY:
			return (value as Dictionary).is_empty()
		TYPE_PACKED_STRING_ARRAY:
			return (value as PackedStringArray).is_empty()
		_:
			return false


static func _string_or_empty(value: Variant) -> String:
	if value == null:
		return ""
	return str(value).strip_edges()


static func _voice_name_ok(value: String) -> bool:
	if value.length() < 2 or value.length() > 32:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z][A-Za-z0-9]+$")
	return pattern.search(value) != null


static func _is_number(value: Variant) -> bool:
	return value is int or value is float or value is bool


static func _in_unit_interval(value: Variant) -> bool:
	var number := _as_float(value)
	return number >= 0.0 and number <= 100.0


static func _as_float(value: Variant) -> float:
	if value is bool:
		return 1.0 if value else 0.0
	return float(value)


static func _show(value: Variant) -> String:
	if value == null:
		return "None"
	if value is float and float(value) == int(value):
		return str(int(value))
	if value is String:
		return value
	return str(value)


static func _py_list(items: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item in items:
		parts.append("'%s'" % item)
	return "[%s]" % ", ".join(parts)
