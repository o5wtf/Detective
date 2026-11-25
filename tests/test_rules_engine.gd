extends TestCase

const REAL_CASE := "res://cases/rain_over_shadow.json"


func test_basic_and_full_thresholds() -> void:
	var data := _case()
	_fact(data, "a", "f", 20, 40)
	var engine := _engine(data)
	engine.start_new()
	assert_eq(_level(engine, "f"), "full")
	assert_eq(engine.get_packet("a")[0]["mode"], "full")
	assert_eq(engine.get_packet("a")[0]["content"], "полно")
	engine.apply_tone("a", 40)
	assert_eq(_level(engine, "f"), "full")


func test_requires_evidence() -> void:
	var data := _case()
	var fact := _fact(data, "a", "f", 0, 0)
	fact.requires_evidence = true
	fact.related_evidence_ids = ["e"]
	_evidence(data, "e", ["a"], false)
	var engine := _engine(data)
	engine.start_new()
	assert_eq(_level(engine, "f"), "closed")
	engine.present_evidence("b", "e")
	assert_eq(_level(engine, "f"), "closed")
	engine.present_evidence("a", "e")
	assert_eq(_level(engine, "f"), "full")


func test_must_lie_hides_truth_until_break() -> void:
	var data := _case()
	var fact := _fact(data, "a", "f", 10, 10)
	_as_lie(fact, "must_lie", "ложь", "pressure")
	fact.related_evidence_ids = ["e"]
	_evidence(data, "e", ["a"], false)
	var engine := _engine(data)
	engine.start_new()
	engine.apply_tone("a", 100)
	var packet: Array = engine.get_packet("a")
	assert_eq(packet.size(), 1)
	assert_eq(packet[0]["mode"], "lie")
	assert_eq(packet[0]["content"], "ложь")
	assert_false(engine.state.broken_lies.has("f"))
	fact.breaks_lie_on = "evidence"
	engine.present_evidence("a", "e")
	assert_true(engine.state.broken_lies.has("f"))
	assert_eq(_level(engine, "f"), "full")
	assert_eq(engine.get_packet("a")[0]["mode"], "full")
	assert_eq(engine.get_packet("a")[0]["content"], "полно")


func test_can_lie_offers_slip_without_pressure() -> void:
	var data := _case()
	var fact := _fact(data, "a", "f", 15, 40)
	_as_lie(fact, "can_lie", "ложь", "pressure")
	var engine := _engine(data)
	engine.start_new()
	var entry: Dictionary = engine.get_packet("a")[0]
	assert_eq(entry["mode"], "lie_or_basic")
	assert_eq(entry["lie_text"], "ложь")
	assert_eq(entry["content"], "кратко")
	engine.apply_tone("a", 100)
	assert_false(engine.state.broken_lies.has("f"))
	assert_eq(engine.get_packet("a")[0]["mode"], "lie_or_basic")


func test_breaks_lie_on_any_of_list() -> void:
	var by_evidence := _case()
	var fact := _fact(by_evidence, "a", "f", 100, 100)
	_as_lie(fact, "must_lie", "ложь", ["evidence", "pressure"])
	fact.related_evidence_ids = ["e"]
	_evidence(by_evidence, "e", [], false)
	var engine := _engine(by_evidence)
	engine.start_new()
	engine.present_evidence("a", "e")
	assert_true(engine.state.broken_lies.has("f"))
	assert_eq(_level(engine, "f"), "full")
	var by_pressure := _case()
	var other := _fact(by_pressure, "a", "f", 100, 30)
	_as_lie(other, "must_lie", "ложь", ["evidence", "pressure"])
	var pressure_engine := _engine(by_pressure)
	pressure_engine.start_new()
	pressure_engine.apply_tone("a", 100)
	assert_false(pressure_engine.state.broken_lies.has("f"))


func test_evidence_pair_pressures_once() -> void:
	var data := _case()
	_evidence(data, "key", ["a"], true)
	_evidence(data, "note", ["a", "b"], false)
	_evidence(data, "loose", [], false)
	var engine := _engine(data)
	engine.start_new()
	engine.present_evidence("a", "key")
	engine.present_evidence("a", "key")
	assert_eq(int(engine.state.pressure["a"]), Balance.EVIDENCE_KEY)
	engine.present_evidence("b", "key")
	assert_eq(int(engine.state.pressure["b"]), 0)
	engine.present_evidence("a", "note")
	engine.present_evidence("b", "note")
	engine.present_evidence("a", "note")
	assert_eq(int(engine.state.pressure["a"]), Balance.EVIDENCE_KEY + Balance.EVIDENCE_NORMAL)
	assert_eq(int(engine.state.pressure["b"]), Balance.EVIDENCE_NORMAL)
	engine.present_evidence("a", "loose")
	assert_eq(int(engine.state.pressure["a"]), Balance.EVIDENCE_KEY + Balance.EVIDENCE_NORMAL)


func test_broken_lie_contradiction_adds_no_pressure() -> void:
	var data := _case()
	var lie := _fact(data, "a", "lie", 0, 0)
	_as_lie(lie, "must_lie", "ложь", "evidence")
	lie.related_evidence_ids = ["e"]
	_evidence(data, "e", ["a"], false)
	_fact(data, "b", "truth", 0, 0)
	_contradiction(data, "c", "lie", "lie", "truth", "truth")
	var engine := _engine(data)
	engine.start_new()
	engine.present_evidence("a", "e")
	assert_true(engine.state.broken_lies.has("lie"))
	var before_a := int(engine.state.pressure["a"])
	var before_b := int(engine.state.pressure["b"])
	engine.register_statements("a", [{"fact_id": "lie", "form": "lie"}])
	engine.register_statements("b", [{"fact_id": "truth", "form": "basic"}])
	assert_true(engine.state.contradictions.has("c"))
	assert_eq(int(engine.state.pressure["a"]), before_a)
	assert_eq(int(engine.state.pressure["b"]), before_b)


func test_plain_contradiction_adds_five_to_both() -> void:
	var data := _case()
	_fact(data, "a", "fa", 0, 0)
	_fact(data, "b", "fb", 0, 0)
	_contradiction(data, "c", "fa", "truth", "fb", "truth")
	var engine := _engine(data)
	engine.start_new()
	engine.register_statements("a", [{"fact_id": "fa", "form": "basic"}])
	engine.register_statements("b", [{"fact_id": "fb", "form": "full"}])
	assert_true(engine.state.contradictions.has("c"))
	assert_eq(int(engine.state.pressure["a"]), Balance.CONTRADICTION_PLAIN)
	assert_eq(int(engine.state.pressure["b"]), Balance.CONTRADICTION_PLAIN)


func test_pressure_is_clamped() -> void:
	var data := _case()
	_evidence(data, "key", ["a"], true)
	var engine := _engine(data)
	engine.start_new()
	engine.state.pressure["a"] = 95
	engine.present_evidence("a", "key")
	assert_eq(int(engine.state.pressure["a"]), 100)
	engine.apply_tone("a", 50)
	assert_eq(int(engine.state.pressure["a"]), 100)
	engine.apply_tone("b", -10)
	assert_eq(int(engine.state.pressure["b"]), 0)
	assert_eq(engine.pressure_band("b"), "calm")
	engine.apply_tone("b", 24)
	assert_eq(engine.pressure_band("b"), "calm")
	engine.apply_tone("b", 1)
	assert_eq(engine.pressure_band("b"), "tense")
	engine.apply_tone("b", 25)
	assert_eq(engine.pressure_band("b"), "nervous")
	engine.apply_tone("b", 25)
	assert_eq(engine.pressure_band("b"), "breaking")


func test_unlock_conditions() -> void:
	var pressure_case := _locked("pressure", {"type": "pressure_on_agent", "agent_id": "a", "gte": 30})
	var pressure_engine := _engine(pressure_case)
	pressure_engine.start_new()
	assert_false(pressure_engine.state.unlocked_evidence.has("pressure"))
	pressure_engine.apply_tone("a", 100)
	assert_false(pressure_engine.state.unlocked_evidence.has("pressure"))
	var talk_case := _locked("talk", {"type": "dialogue_with", "agent_id": "b"})
	var talk_engine := _engine(talk_case)
	talk_engine.start_new()
	assert_false(talk_engine.state.unlocked_evidence.has("talk"))
	talk_engine.note_question("b")
	assert_true(talk_engine.state.unlocked_evidence.has("talk"))
	var shown_case := _case()
	_evidence(shown_case, "open", [], false)
	_evidence(shown_case, "any", [], false, {"type": "evidence_shown", "evidence_id": "open"})
	_evidence(shown_case, "only_b", [], false, {"type": "evidence_shown", "evidence_id": "open", "agent_id": "b"})
	var shown_engine := _engine(shown_case)
	shown_engine.start_new()
	shown_engine.present_evidence("a", "open")
	assert_true(shown_engine.state.unlocked_evidence.has("any"))
	assert_false(shown_engine.state.unlocked_evidence.has("only_b"))
	shown_engine.present_evidence("b", "open")
	assert_true(shown_engine.state.unlocked_evidence.has("only_b"))
	var logic := _case()
	_evidence(logic, "and", [], false, {
		"AND": [
			{"type": "dialogue_with", "agent_id": "a"},
			{"type": "pressure_on_agent", "agent_id": "a", "gte": 10},
		],
	})
	_evidence(logic, "or", [], false, {
		"OR": [
			{"type": "dialogue_with", "agent_id": "b"},
			{"type": "pressure_on_agent", "agent_id": "a", "gte": 10},
		],
	})
	var logic_engine := _engine(logic)
	logic_engine.start_new()
	logic_engine.apply_tone("a", 100)
	assert_false(logic_engine.state.unlocked_evidence.has("and"))
	assert_false(logic_engine.state.unlocked_evidence.has("or"))
	logic_engine.note_question("b")
	assert_false(logic_engine.state.unlocked_evidence.has("and"))
	assert_true(logic_engine.state.unlocked_evidence.has("or"))
	logic_engine.note_question("a")
	assert_false(logic_engine.state.unlocked_evidence.has("and"))
	var contradiction_case := _case()
	_fact(contradiction_case, "a", "fa", 0, 0)
	_fact(contradiction_case, "b", "fb", 0, 0)
	_contradiction(contradiction_case, "c1", "fa", "truth", "fb", "truth")
	_evidence(contradiction_case, "named", [], false, {"type": "inconsistency_created", "contradiction_id": "c1"})
	_evidence(contradiction_case, "any_c", [], false, {"type": "inconsistency_created"})
	var contradiction_engine := _engine(contradiction_case)
	contradiction_engine.start_new()
	contradiction_engine.register_statements("a", [{"fact_id": "fa", "form": "basic"}])
	assert_false(contradiction_engine.state.unlocked_evidence.has("named"))
	contradiction_engine.register_statements("b", [{"fact_id": "fb", "form": "basic"}])
	assert_true(contradiction_engine.state.contradictions.has("c1"))
	assert_false(contradiction_engine.state.unlocked_evidence.has("named"))
	assert_false(contradiction_engine.state.unlocked_evidence.has("any_c"))


func test_commit_plan_does_not_break_a_lie_before_its_requirements() -> void:
	var loaded := CaseLoader.load_case(REAL_CASE)
	assert_true(loaded.ok)
	var engine := RulesEngine.new(loaded.case_data, GameState.new())
	engine.start_new()
	engine.commit_plan("arkady_volkov", {"break_lies": ["fact_arkady_panic"], "present": [], "unlock": [], "touch": []})
	assert_false(engine.state.broken_lies.has("fact_arkady_panic"))
	engine.state.broken_lies.append("fact_arkady_meeting")
	engine.state.broken_lies.append("fact_arkady_knife")
	engine.commit_plan("arkady_volkov", {"break_lies": ["fact_arkady_panic"], "present": [], "unlock": [], "touch": []})
	assert_true(engine.state.broken_lies.has("fact_arkady_panic"))


func test_button_and_voice_break_the_same_lies() -> void:
	var loaded := CaseLoader.load_case(REAL_CASE)
	assert_true(loaded.ok)
	var data := loaded.case_data
	var knife: CaseData.EvidenceItem = data.evidence_by_id["ev_kitchen_knife"]
	assert_true(knife.related_fact_ids.has("fact_arkady_panic"))
	for evidence in data.evidence:
		for agent in data.agents:
			var button := RulesEngine.new(data, GameState.new())
			button.start_new()
			var voice := RulesEngine.new(data, GameState.new())
			voice.start_new()
			if not button.state.unlocked_evidence.has(evidence.id):
				button.state.unlocked_evidence.append(evidence.id)
				voice.state.unlocked_evidence.append(evidence.id)
			button.present_evidence(agent.id, evidence.id)
			var options := TurnOptions.build(data, voice.state, agent.id)
			var number := -1
			for option in options:
				if str(option.get("kind", "")) == "present" and str(option.get("evidence_id", "")) == evidence.id:
					number = int(option.get("n", -1))
			assert_true(number >= 0, evidence.id)
			var plan := TurnOptions.plan(data, voice.state, agent.id, options, [number])
			voice.commit_plan(agent.id, plan)
			_assert_same_list(button.state.broken_lies, voice.state.broken_lies, evidence.id)
			assert_eq(JSON.stringify(button.get_packet(agent.id)), JSON.stringify(voice.get_packet(agent.id)), evidence.id)


func test_voice_knife_does_not_admit_the_confession_early() -> void:
	var loaded := CaseLoader.load_case(REAL_CASE)
	var data := loaded.case_data
	var engine := RulesEngine.new(data, GameState.new())
	engine.start_new()
	var options := TurnOptions.build(data, engine.state, "arkady_volkov")
	var number := -1
	for option in options:
		if str(option.get("evidence_id", "")) == "ev_kitchen_knife":
			number = int(option.get("n", -1))
	var plan := TurnOptions.plan(data, engine.state, "arkady_volkov", options, [number])
	assert_false((plan["break_lies"] as Array).has("fact_arkady_panic"))
	assert_true((plan["break_lies"] as Array).has("fact_arkady_knife"))
	var admitted := " ".join(plan["admit"])
	assert_false(admitted.contains("ударил"))
	if not engine.state.unlocked_evidence.has("ev_financial_docs"):
		engine.state.unlocked_evidence.append("ev_financial_docs")
	options = TurnOptions.build(data, engine.state, "arkady_volkov")
	var docs := -1
	for option in options:
		if str(option.get("evidence_id", "")) == "ev_financial_docs":
			docs = int(option.get("n", -1))
	assert_true(docs >= 0)
	var money := TurnOptions.plan(data, engine.state, "arkady_volkov", options, [docs])
	assert_true(" ".join(money["admit"]).contains("Должен Виктору около 2,5 млн."))


func test_confession_opens_in_the_simulation() -> void:
	var loaded := CaseLoader.load_case(REAL_CASE)
	for tone in [0, 15]:
		var snapshot := SimHarness.run(loaded.case_data, tone)
		assert_eq(str(snapshot["fact_levels"]["fact_arkady_panic"]), "full", "признание")
		assert_eq(str(snapshot["fact_levels"]["fact_mira_knife"]), "full", "нож ломает показание Миры")
		for evidence_id in ["ev_crime_scene", "ev_financial_docs", "ev_security_log", "ev_kitchen_knife"]:
			assert_true((snapshot["unlocked_evidence"] as Array).has(evidence_id), evidence_id)


func test_contradiction_turn_and_filter() -> void:
	var data := _case()
	_fact(data, "a", "fa", 0, 0)
	_fact(data, "b", "fb", 0, 0)
	_contradiction(data, "c", "fa", "truth", "fb", "truth")
	var engine := _engine(data)
	engine.start_new()
	engine.state.turn = 4
	engine.register_statements("a", [{"fact_id": "fa", "form": "basic"}])
	assert_false(engine.state.contradictions.has("c"))
	engine.register_statements("b", [{"fact_id": "fb", "form": "basic"}])
	assert_true(engine.state.contradictions.has("c"))
	assert_eq(int(engine.state.contradiction_turns["c"]), 4)
	assert_eq(int(engine.state.pressure["a"]), Balance.CONTRADICTION_PLAIN)
	var book := Notebook.new(data, engine.state)
	var all_rows := book.found_contradictions("")
	assert_eq(all_rows.size(), 1)
	assert_eq(str(all_rows[0]["description"]), "пара")
	assert_eq(int(all_rows[0]["turn"]), 4)
	assert_eq(book.found_contradictions("a").size(), 1)
	assert_eq(book.found_contradictions("b").size(), 1)
	assert_eq(book.found_contradictions("other").size(), 0)
	var old := GameState.from_dict({"contradictions": ["c"], "pressure": {"a": 3}})
	assert_true(old.contradictions.has("c"))
	assert_eq(int(old.pressure["a"]), 3)
	assert_false(old.contradiction_turns.has("c"))
	var restored := Notebook.new(data, old)
	var legacy := restored.found_contradictions("a")
	assert_eq(legacy.size(), 1)
	assert_eq(int(legacy[0]["turn"]), -1)


func test_accusation_keeps_ticks() -> void:
	var data := _case()
	data.killer_id = "a"
	data.true_motive_id = "m"
	data.true_method_id = "w"
	var engine := _engine(data)
	engine.start_new()
	var wrong: Dictionary = engine.check_accusation("b", "m", "w")
	assert_false(wrong["killer_ok"])
	assert_false(wrong["motive_evaluated"])
	assert_false(wrong["method_evaluated"])
	assert_false(engine.state.accusation["motive_ok"])
	assert_false(engine.state.accusation["method_ok"])
	var partial: Dictionary = engine.check_accusation("a", "nope", "w")
	assert_true(partial["killer_ok"])
	assert_false(partial["motive_ok"])
	assert_true(partial["method_ok"])
	assert_true(partial["motive_evaluated"])
	var ignored: Dictionary = engine.check_accusation("b", "m", "nope")
	assert_true(ignored["killer_ok"])
	assert_false(ignored["motive_ok"])
	assert_true(ignored["method_ok"])
	assert_false(ignored["motive_evaluated"])
	var solved: Dictionary = engine.check_accusation("a", "m", "w")
	assert_true(solved["solved"])
	assert_eq(int(engine.state.accusation["attempts"]), 4)


func test_state_round_trip() -> void:
	var data := _case()
	_fact(data, "a", "f", 0, 10)
	var engine := _engine(data)
	engine.start_new()
	engine.apply_tone("a", 4)
	engine.state.heard.append({"agent_id": "a", "fact_id": "f", "form": "basic", "turn": 3})
	engine.state.turn = 3
	engine.state.case_version_hash = "abc"
	engine.state.dialogues["a"] = {"summary": "кратко", "messages": [{"role": "player", "text": "вопрос"}]}
	engine.state.accusation["attempts"] = 2
	engine.state.accusation["killer_ok"] = true
	var restored := GameState.from_dict(engine.state.to_dict())
	assert_eq(restored.to_dict(), engine.state.to_dict())


func test_emotion_is_ignored_outside_the_list() -> void:
	var engine := _engine(_case())
	engine.start_new()
	engine.set_emotion("a", "joyful")
	assert_eq(str(engine.state.emotion["a"]), "neutral")
	engine.set_emotion("a", "angry")
	assert_eq(str(engine.state.emotion["a"]), "angry")


func test_golden_simulations_match() -> void:
	var loaded := CaseLoader.load_case(REAL_CASE)
	assert_true(loaded.ok)
	_assert_golden(SimHarness.run(loaded.case_data, 0), "res://tests/golden/rain_over_shadow_sim_0.json")
	_assert_golden(SimHarness.run(loaded.case_data, 15), "res://tests/golden/rain_over_shadow_sim_15.json")


func _assert_golden(actual: Dictionary, path: String) -> void:
	var expected: Dictionary = _read_json(path)
	_assert_same_list(actual["broken_lies"], expected["broken_lies"], "broken_lies")
	_assert_same_list(actual["contradictions"], expected["contradictions"], "contradictions")
	_assert_same_list(actual["unlocked_evidence"], expected["unlocked_evidence"], "unlocked_evidence")
	assert_eq(int(actual["tone"]), int(expected["tone"]), "tone")
	var level_mismatches := 0
	for fact_id in expected["fact_levels"]:
		if str(actual["fact_levels"].get(fact_id, "")) != str(expected["fact_levels"][fact_id]):
			level_mismatches += 1
	assert_eq(level_mismatches, 0, "fact_levels")
	assert_eq(actual["fact_levels"].size(), expected["fact_levels"].size(), "fact_levels size")
	var pressure_mismatches := 0
	for agent_id in expected["pressure"]:
		if int(actual["pressure"].get(agent_id, -1)) != int(expected["pressure"][agent_id]):
			pressure_mismatches += 1
	assert_eq(pressure_mismatches, 0, "pressure")
	assert_eq(actual["pressure"].size(), expected["pressure"].size(), "pressure size")


func _assert_same_list(actual: Variant, expected: Variant, label: String) -> void:
	var left: Array = (actual as Array).duplicate()
	var right: Array = (expected as Array).duplicate()
	left.sort()
	right.sort()
	if left != right:
		fail("%s не совпало с эталоном (%d против %d)" % [label, left.size(), right.size()])


func _read_json(path: String) -> Dictionary:
	var parser := JSON.new()
	assert_eq(parser.parse(FileAccess.get_file_as_string(path)), OK, path)
	return parser.data as Dictionary


func _engine(data: CaseData) -> RulesEngine:
	return RulesEngine.new(data, GameState.new())


func _level(engine: RulesEngine, fact_id: String) -> String:
	return str(engine.state.fact_levels.get(fact_id, "closed"))


func _case() -> CaseData:
	var data := CaseData.new()
	data.id = "fixture"
	data.killer_id = "a"
	data.true_motive_id = "m"
	data.true_method_id = "w"
	for agent_id in ["a", "b"]:
		var agent := CaseData.Agent.new()
		agent.id = agent_id
		agent.starting_emotion = "neutral"
		data.agents.append(agent)
		data.agent_by_id[agent_id] = agent
	return data


func _fact(data: CaseData, agent_id: String, fact_id: String, basic: int, full: int) -> CaseData.Fact:
	var fact := CaseData.Fact.new()
	fact.id = fact_id
	fact.content_basic = "кратко"
	fact.content_full = "полно"
	fact.lie_type = "cannot_lie"
	fact.pressure_for_basic = basic
	fact.pressure_for_full = full
	var agent: CaseData.Agent = data.agent_by_id[agent_id]
	agent.facts.append(fact)
	data.fact_by_id[fact_id] = fact
	data.fact_owner[fact_id] = agent_id
	return fact


func _as_lie(fact: CaseData.Fact, lie_type: String, lie_text: String, breaks: Variant) -> void:
	fact.is_lie = true
	fact.lie_type = lie_type
	fact.lie_text = lie_text
	fact.breaks_lie_on = breaks


func _evidence(data: CaseData, evidence_id: String, agents: Array, is_key: bool, condition: Variant = null) -> void:
	var evidence := CaseData.EvidenceItem.new()
	evidence.id = evidence_id
	evidence.is_key = is_key
	evidence.related_agent_ids.assign(agents)
	evidence.unlock_condition = condition
	data.evidence.append(evidence)
	data.evidence_by_id[evidence_id] = evidence


func _contradiction(
	data: CaseData,
	contradiction_id: String,
	fact_a: String,
	form_a: String,
	fact_b: String,
	form_b: String
) -> void:
	var contradiction := CaseData.Contradiction.new()
	contradiction.id = contradiction_id
	contradiction.fact_a_id = fact_a
	contradiction.fact_a_form = form_a
	contradiction.fact_b_id = fact_b
	contradiction.fact_b_form = form_b
	contradiction.description = "пара"
	data.contradictions.append(contradiction)
	data.contradiction_by_id[contradiction_id] = contradiction


func _locked(evidence_id: String, condition: Dictionary) -> CaseData:
	var data := _case()
	_evidence(data, evidence_id, [], false, condition)
	return data
