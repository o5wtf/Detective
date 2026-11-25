class_name Conditions
extends RefCounted
## Синтаксис и вычисление unlock_condition (Д§15).


static func evaluate(cond: Variant, state: GameState, ctx: Dictionary = {}) -> bool:
	if cond == null:
		return true
	if cond is not Dictionary:
		return false
	var body := cond as Dictionary
	if body.has("AND"):
		for sub in body["AND"] as Array:
			if not evaluate(sub, state, ctx):
				return false
		return true
	if body.has("OR"):
		for sub in body["OR"] as Array:
			if evaluate(sub, state, ctx):
				return true
		return false
	var kind: Variant = body.get("type")
	if kind == "dialogue_with":
		return state.talked_to.has(str(body.get("agent_id", "")))
	if kind == "evidence_shown":
		var evidence_id := str(body.get("evidence_id", ""))
		var shown_to: Array = state.shown.get(evidence_id, [])
		if body.has("agent_id"):
			return shown_to.has(str(body["agent_id"]))
		if ctx.has("agent_id"):
			return shown_to.has(str(ctx["agent_id"]))
		return not shown_to.is_empty()
	if kind == "evidence_mentioned":
		return state.evidence_mentions.has(str(body.get("evidence_id", "")))
	if kind == "lie_broken":
		return state.broken_lies.has(str(body.get("fact_id", "")))
	if kind == "testimony_retold":
		return _retold(body, ctx)
	if kind == "inconsistency_created":
		var contradiction_id := str(body.get("contradiction_id", ""))
		if contradiction_id == "":
			return false
		return state.contradictions.has(contradiction_id)
	return false


static func check(
	cond: Variant,
	where: String,
	evidence_self: String,
	agent_ids: Dictionary,
	evidence_ids: Dictionary,
	contradiction_ids: Dictionary,
	fact_ids: Dictionary
) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	_check(cond, where, evidence_self, agent_ids, evidence_ids, contradiction_ids, fact_ids, errors)
	return errors


static func _check(
	cond: Variant,
	where: String,
	evidence_self: String,
	agent_ids: Dictionary,
	evidence_ids: Dictionary,
	contradiction_ids: Dictionary,
	fact_ids: Dictionary,
	errors: Array[Dictionary]
) -> void:
	if cond == null:
		return
	if cond is not Dictionary:
		errors.append(_err("cond_not_object", "%s: условие не объект: %s" % [where, _show(cond)]))
		return
	var body := cond as Dictionary
	for op in ["AND", "OR"]:
		if not body.has(op):
			continue
		var items: Variant = body[op]
		var empty := items is not Array or (items as Array).is_empty()
		if body.size() != 1 or empty:
			errors.append(_err(
				"cond_group_invalid",
				"%s: %s должен быть единственным ключом с непустым списком" % [where, op]
			))
			return
		for sub in items as Array:
			_check(sub, where, evidence_self, agent_ids, evidence_ids, contradiction_ids, fact_ids, errors)
		return
	var kind: Variant = body.get("type")
	if kind == "pressure_on_agent":
		return
	elif kind == "dialogue_with":
		_require_agent(body, where, agent_ids, errors)
	elif kind == "evidence_shown":
		var evidence_id: Variant = body.get("evidence_id")
		if not evidence_ids.has(evidence_id):
			errors.append(_err(
				"cond_unknown_evidence",
				"%s: улика %s не найдена" % [where, _show(evidence_id)]
			))
		if evidence_id == evidence_self:
			errors.append(_err("cond_self_evidence", "%s: улика требует предъявления самой себя" % where))
		if body.has("agent_id") and not agent_ids.has(body["agent_id"]):
			errors.append(_err(
				"cond_unknown_agent",
				"%s: агент %s не найден" % [where, _show(body["agent_id"])]
			))
	elif kind == "evidence_mentioned":
		_require_agent(body, where, agent_ids, errors)
		var evidence_id: Variant = body.get("evidence_id")
		if not evidence_ids.has(evidence_id):
			errors.append(_err(
				"cond_unknown_evidence",
				"%s: улика %s не найдена" % [where, _show(evidence_id)]
			))
	elif kind == "lie_broken":
		var fact_id: Variant = body.get("fact_id")
		if not fact_ids.has(fact_id):
			errors.append(_err(
				"cond_unknown_fact",
				"%s: факт %s не найден" % [where, _show(fact_id)]
			))
	elif kind == "inconsistency_created":
		if body.has("contradiction_id") and not contradiction_ids.has(body["contradiction_id"]):
			errors.append(_err(
				"cond_unknown_contradiction",
				"%s: противоречие %s не найдено" % [where, _show(body["contradiction_id"])]
			))
	else:
		errors.append(_err(
			"cond_unknown_type",
			"%s: неизвестный тип условия '%s'" % [where, _show(kind)]
		))


static func _retold(body: Dictionary, ctx: Dictionary) -> bool:
	var fact_id := str(body.get("fact_id", ""))
	var full_only := str(body.get("form", "")) == "truth_full"
	var rows: Array = ctx.get("retold", [])
	for row in rows:
		if row is not Dictionary:
			continue
		if str((row as Dictionary).get("fact_id", "")) != fact_id:
			continue
		var form := str((row as Dictionary).get("form", ""))
		if full_only:
			if form == "full":
				return true
		elif form == "basic" or form == "full":
			return true
	return false


static func _require_agent(body: Dictionary, where: String, agent_ids: Dictionary, errors: Array[Dictionary]) -> void:
	var agent_id: Variant = body.get("agent_id")
	if not agent_ids.has(agent_id):
		errors.append(_err("cond_unknown_agent", "%s: агент %s не найден" % [where, _show(agent_id)]))


static func _err(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}


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
