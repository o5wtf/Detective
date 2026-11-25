class_name RulesEngine
extends RefCounted
## Раскрытие фактов, ложь, давление, противоречия, улики, обвинение.
## Каскад — в порядке файла дела, как в А§3.2 и validate_case.py --simulate.

var case_data: CaseData
var state: GameState


func _init(case_data: CaseData, state: GameState) -> void:
	self.case_data = case_data
	self.state = state


func start_new() -> Array:
	_seed_agents()
	return _resolve()


func get_packet(agent_id: String) -> Array[Dictionary]:
	var agent: CaseData.Agent = case_data.agent_by_id[agent_id]
	var packet: Array[Dictionary] = []
	var index := 1
	for fact in agent.facts:
		var entry := _packet_entry(fact)
		if entry.is_empty():
			continue
		entry["key"] = "k%d" % index
		index += 1
		packet.append(entry)
	return packet


func note_question(agent_id: String) -> Array:
	if not state.talked_to.has(agent_id):
		state.talked_to.append(agent_id)
	return _resolve()


func commit_plan(agent_id: String, plan: Dictionary) -> Array:
	var events: Array = []
	for key in plan.get("touch", []):
		state.topic_touches[str(key)] = int(state.topic_touches.get(str(key), 0)) + 1
	for evidence_id in plan.get("unlock", []):
		var name := str(evidence_id)
		if name != "" and not state.evidence_mentions.has(name):
			state.evidence_mentions.append(name)
	for lie_id in plan.get("break_lies", []):
		var name := str(lie_id)
		if name == "" or state.broken_lies.has(name):
			continue
		var fact: CaseData.Fact = case_data.fact_by_id.get(name) as CaseData.Fact
		if fact == null or not _required_lies_broken(fact):
			continue
		state.broken_lies.append(name)
		events.append({"type": "lie_broken", "fact_id": name, "agent_id": agent_id})
	for evidence_id in plan.get("present", []):
		_present(agent_id, str(evidence_id), events)
	events.append_array(_resolve())
	return events


func register_statements(agent_id: String, statements: Array) -> Array:
	var events: Array = []
	for statement in statements:
		if statement is not Dictionary:
			continue
		var body := statement as Dictionary
		if _add_heard(agent_id, str(body.get("fact_id", "")), str(body.get("form", ""))):
			events.append({
				"type": "heard",
				"agent_id": agent_id,
				"fact_id": str(body.get("fact_id", "")),
				"form": str(body.get("form", "")),
			})
	events.append_array(_resolve())
	return events


func present_evidence(agent_id: String, evidence_id: String) -> Array:
	var events: Array = []
	if not _present(agent_id, evidence_id, events):
		return events
	events.append_array(_resolve())
	return events


func apply_tone(agent_id: String, tone: int) -> Array:
	var events: Array = []
	_add_pressure(agent_id, tone, events)
	events.append_array(_resolve())
	return events


func set_emotion(agent_id: String, emotion: String) -> void:
	if Balance.emotion_allowed(emotion):
		state.emotion[agent_id] = emotion


func check_accusation(killer_id: String, motive_id: String, method_id: String) -> Dictionary:
	return Accusation.check(case_data, state, killer_id, motive_id, method_id)


func pressure_band(agent_id: String) -> String:
	return Balance.band(int(state.pressure.get(agent_id, 0)))


func pass_unlock() -> bool:
	var events: Array = []
	_pass_unlock(events)
	return not events.is_empty()


func present_quiet(agent_id: String, evidence_id: String) -> bool:
	var events: Array = []
	return _present(agent_id, evidence_id, events)


func pass_facts() -> bool:
	var events: Array = []
	_pass_facts(events)
	return not events.is_empty()


func pass_contradictions() -> bool:
	var events: Array = []
	_pass_contradictions(events)
	return not events.is_empty()


## Журнал для симуляции: ложь с самого начала, правда — по уровню.
## Оговорка can_lie (уровень ещё не выставлен) в журнал не пишется.
func record_simulation_statements() -> bool:
	var added := false
	for agent in case_data.agents:
		for fact in agent.facts:
			if fact.is_lie and _add_heard(agent.id, fact.id, "lie"):
				added = true
			if fact.is_lie and not state.broken_lies.has(fact.id):
				continue
			var level := str(state.fact_levels.get(fact.id, "closed"))
			if level == "basic" or level == "full":
				if _add_heard(agent.id, fact.id, "basic"):
					added = true
			if level == "full":
				if _add_heard(agent.id, fact.id, "full"):
					added = true
	return added


func simulation_signature() -> String:
	var shown_pairs: Array[String] = []
	for evidence_id in state.shown:
		var agents: Array = state.shown[evidence_id]
		for agent_id in agents:
			shown_pairs.append("%s>%s" % [str(evidence_id), str(agent_id)])
	shown_pairs.sort()
	var heard_keys: Array[String] = []
	for entry in state.heard:
		heard_keys.append("%s|%s" % [str(entry["fact_id"]), str(entry["form"])])
	heard_keys.sort()
	var levels: Array[String] = []
	for fact_id in state.fact_levels:
		levels.append("%s=%s" % [str(fact_id), str(state.fact_levels[fact_id])])
	levels.sort()
	var pressures: Array[String] = []
	for agent_id in state.pressure:
		pressures.append("%s=%d" % [str(agent_id), int(state.pressure[agent_id])])
	pressures.sort()
	var unlocked := state.unlocked_evidence.duplicate()
	unlocked.sort()
	var broken := state.broken_lies.duplicate()
	broken.sort()
	var contras := state.contradictions.duplicate()
	contras.sort()
	return "%s#%s#%s#%s#%s#%s#%s" % [
		"|".join(pressures), "|".join(levels), "|".join(unlocked),
		"|".join(broken), "|".join(contras), "|".join(shown_pairs), "|".join(heard_keys),
	]


func _seed_agents() -> void:
	state.case_id = case_data.id
	for agent in case_data.agents:
		state.pressure[agent.id] = agent.starting_pressure
		state.emotion[agent.id] = agent.starting_emotion
		if not state.dialogues.has(agent.id):
			state.dialogues[agent.id] = {}
		for fact in agent.facts:
			if not state.fact_levels.has(fact.id):
				state.fact_levels[fact.id] = "closed"


func _resolve() -> Array:
	var events: Array = []
	var guard := 0
	while guard < 80:
		guard += 1
		var size_before := events.size()
		_pass_unlock(events)
		_pass_facts(events)
		_pass_contradictions(events)
		if events.size() == size_before:
			break
	return events


func _pass_unlock(events: Array) -> void:
	for evidence in case_data.evidence:
		if state.unlocked_evidence.has(evidence.id):
			continue
		if not Conditions.evaluate(evidence.unlock_condition, state):
			continue
		state.unlocked_evidence.append(evidence.id)
		events.append({"type": "evidence_unlocked", "evidence_id": evidence.id})


func _pass_facts(events: Array) -> void:
	for agent in case_data.agents:
		for fact in agent.facts:
			if fact.is_lie and not state.broken_lies.has(fact.id):
				if _lie_breaks(fact):
					state.broken_lies.append(fact.id)
					events.append({
						"type": "lie_broken",
						"fact_id": fact.id,
						"agent_id": agent.id,
					})
				continue
			var current := str(state.fact_levels.get(fact.id, "closed"))
			var desired := _desired_level(fact)
			if _rank(desired) > _rank(current):
				state.fact_levels[fact.id] = desired
				events.append({
					"type": "fact_level_changed",
					"fact_id": fact.id,
					"level": desired,
				})


func _pass_contradictions(events: Array) -> void:
	for contradiction in case_data.contradictions:
		if state.contradictions.has(contradiction.id):
			continue
		if not _contradiction_side_heard(contradiction.fact_a_id, contradiction.fact_a_form):
			continue
		if not _contradiction_side_heard(contradiction.fact_b_id, contradiction.fact_b_form):
			continue
		state.contradictions.append(contradiction.id)
		state.contradiction_turns[contradiction.id] = state.turn
		events.append({
			"type": "contradiction_registered",
			"contradiction_id": contradiction.id,
		})
		_apply_contradiction_pressure(contradiction, events)


func _present(agent_id: String, evidence_id: String, events: Array) -> bool:
	if not state.unlocked_evidence.has(evidence_id):
		return false
	if _shown_to(evidence_id, agent_id):
		return false
	_mark_shown(evidence_id, agent_id)
	var evidence: CaseData.EvidenceItem = case_data.evidence_by_id[evidence_id]
	if evidence.related_agent_ids.has(agent_id):
		var amount := Balance.EVIDENCE_KEY if evidence.is_key else Balance.EVIDENCE_NORMAL
		_add_pressure(agent_id, amount, events)
	return true


func _lie_breaks(fact: CaseData.Fact) -> bool:
	if not _required_lies_broken(fact):
		return false
	var breaks := _breaks_of(fact)
	var agent_id := str(case_data.fact_owner[fact.id])
	if breaks.has("evidence"):
		for evidence_id in fact.related_evidence_ids:
			if _shown_to(evidence_id, agent_id):
				return true
	return false


func _desired_level(fact: CaseData.Fact) -> String:
	if not _required_lies_broken(fact):
		return "closed"
	var evidence_ok := _evidence_satisfied(fact)
	var broken := state.broken_lies.has(fact.id)
	if evidence_ok:
		return "full"
	if broken:
		return "basic"
	return "closed"


func _required_lies_broken(fact: CaseData.Fact) -> bool:
	for fact_id in fact.requires_broken_lies:
		if not state.broken_lies.has(fact_id):
			return false
	return true


func _evidence_satisfied(fact: CaseData.Fact) -> bool:
	if not fact.requires_evidence:
		return true
	var agent_id := str(case_data.fact_owner[fact.id])
	for evidence_id in fact.related_evidence_ids:
		if _shown_to(evidence_id, agent_id):
			return true
	return false


func _basic_threshold_met(fact: CaseData.Fact) -> bool:
	return _evidence_satisfied(fact)


func _packet_entry(fact: CaseData.Fact) -> Dictionary:
	var broken := state.broken_lies.has(fact.id)
	if fact.is_lie and not broken:
		if fact.lie_type == "can_lie" and _basic_threshold_met(fact):
			return {
				"fact_id": fact.id,
				"mode": "lie_or_basic",
				"lie_text": fact.lie_text,
				"content": fact.content_basic,
			}
		return {
			"fact_id": fact.id,
			"mode": "lie",
			"lie_text": fact.lie_text,
			"content": fact.lie_text,
		}
	var level := str(state.fact_levels.get(fact.id, "closed"))
	if level == "full":
		return {"fact_id": fact.id, "mode": "full", "lie_text": "", "content": fact.content_full}
	if level == "basic":
		return {"fact_id": fact.id, "mode": "basic", "lie_text": "", "content": fact.content_basic}
	return {}


func _apply_contradiction_pressure(contradiction: CaseData.Contradiction, events: Array) -> void:
	var lie_ids: Array[String] = []
	if contradiction.fact_a_form == "lie":
		lie_ids.append(contradiction.fact_a_id)
	if contradiction.fact_b_form == "lie":
		lie_ids.append(contradiction.fact_b_id)
	if not lie_ids.is_empty():
		for fact_id in lie_ids:
			if state.broken_lies.has(fact_id):
				continue
			_add_pressure(str(case_data.fact_owner[fact_id]), Balance.CONTRADICTION_LIE, events)
		return
	for fact_id in [contradiction.fact_a_id, contradiction.fact_b_id]:
		_add_pressure(str(case_data.fact_owner[fact_id]), Balance.CONTRADICTION_PLAIN, events)


func _add_pressure(agent_id: String, delta: int, events: Array) -> void:
	if delta == 0:
		return
	var before := int(state.pressure.get(agent_id, 0))
	var after := Balance.clamp_pressure(before + delta)
	if after == before:
		return
	state.pressure[agent_id] = after
	events.append({
		"type": "pressure_changed",
		"agent_id": agent_id,
		"delta": after - before,
		"pressure": after,
	})


func _add_heard(agent_id: String, fact_id: String, form: String) -> bool:
	if fact_id.is_empty() or form.is_empty():
		return false
	if _journal_has(fact_id, form):
		return false
	state.heard.append({
		"agent_id": agent_id,
		"fact_id": fact_id,
		"form": form,
		"turn": state.turn,
	})
	return true


func _journal_has(fact_id: String, form: String) -> bool:
	for entry in state.heard:
		if str(entry.get("fact_id", "")) == fact_id and str(entry.get("form", "")) == form:
			return true
	return false


func _contradiction_side_heard(fact_id: String, form: String) -> bool:
	if form == "lie":
		return _journal_has(fact_id, "lie")
	if form == "truth_full":
		return _journal_has(fact_id, "full")
	if form == "truth":
		return _journal_has(fact_id, "basic") or _journal_has(fact_id, "full")
	return false


func _shown_to(evidence_id: String, agent_id: String) -> bool:
	var agents: Array = state.shown.get(evidence_id, [])
	return agents.has(agent_id)


func _mark_shown(evidence_id: String, agent_id: String) -> void:
	if not state.shown.has(evidence_id):
		state.shown[evidence_id] = [] as Array[String]
	var agents: Array = state.shown[evidence_id]
	agents.append(agent_id)
	state.shown[evidence_id] = agents


func _breaks_of(fact: CaseData.Fact) -> Array:
	var value: Variant = fact.breaks_lie_on
	if value == null:
		return []
	if value is String:
		return [value]
	if value is PackedStringArray:
		var packed: Array = []
		for item in value:
			packed.append(str(item))
		return packed
	if value is Array:
		return value
	return []


func _rank(level: String) -> int:
	if level == "full":
		return 2
	if level == "basic":
		return 1
	return 0
