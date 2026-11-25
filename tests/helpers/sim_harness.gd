class_name SimHarness
extends RefCounted
## Повтор python tools/validate_case.py --simulate.
## Один проход: открыть улики, показать каждую открытую каждому агенту,
## пересчитать факты, записать доступные утверждения, затем противоречия.
## Ложь пишется с самого начала. Оговорка can_lie не считается правдой.


static func run(case_data: CaseData, tone: int) -> Dictionary:
	var state := GameState.new()
	var engine := RulesEngine.new(case_data, state)
	engine._seed_agents()
	for agent in case_data.agents:
		state.pressure[agent.id] = Balance.clamp_pressure(agent.starting_pressure + tone)
		state.talked_to.append(agent.id)
	_assume_mentions(case_data, state)
	var guard := 0
	while guard < 80:
		guard += 1
		var before := engine.simulation_signature()
		engine.pass_unlock()
		for evidence in case_data.evidence:
			if not state.unlocked_evidence.has(evidence.id):
				continue
			for agent in case_data.agents:
				engine.present_quiet(agent.id, evidence.id)
		engine.assume_simulation_retells()
		engine.pass_facts()
		engine.record_simulation_statements()
		engine.pass_contradictions()
		if engine.simulation_signature() == before:
			break
	return snapshot(case_data, state, tone)


static func _assume_mentions(case_data: CaseData, state: GameState) -> void:
	for evidence in case_data.evidence:
		if _mentions(evidence.unlock_condition, evidence.id):
			state.evidence_mentions.append(evidence.id)


static func _mentions(cond: Variant, evidence_id: String) -> bool:
	if cond is not Dictionary:
		return false
	var body := cond as Dictionary
	for op in ["AND", "OR"]:
		if body.has(op) and body[op] is Array:
			for sub in body[op]:
				if _mentions(sub, evidence_id):
					return true
			return false
	return str(body.get("type", "")) == "evidence_mentioned" and str(body.get("evidence_id", "")) == evidence_id


static func snapshot(case_data: CaseData, state: GameState, tone: int) -> Dictionary:
	var levels := {}
	for agent in case_data.agents:
		for fact in agent.facts:
			if fact.is_lie and not state.broken_lies.has(fact.id):
				levels[fact.id] = "lie"
			else:
				levels[fact.id] = str(state.fact_levels.get(fact.id, "closed"))
	var unlocked := state.unlocked_evidence.duplicate()
	unlocked.sort()
	var broken := state.broken_lies.duplicate()
	broken.sort()
	var registered := state.contradictions.duplicate()
	registered.sort()
	var pressure := {}
	for agent in case_data.agents:
		pressure[agent.id] = int(state.pressure.get(agent.id, 0))
	return {
		"tone": tone,
		"fact_levels": levels,
		"pressure": pressure,
		"unlocked_evidence": unlocked,
		"contradictions": registered,
		"broken_lies": broken,
	}
