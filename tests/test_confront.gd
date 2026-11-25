extends TestCase

const REAL_CASE := "res://cases/rain_over_shadow.json"


func test_confront_verdicts_on_the_builtin_case() -> void:
	var engine := _engine()
	engine.state.unlocked_evidence.append("ev_security_log")
	var refuted := engine.confront("arkady_volkov", "fact_arkady_meeting|lie", "ev_security_log")
	assert_eq(str(refuted["verdict"]), "refuted")
	assert_true(engine.state.broken_lies.has("fact_arkady_meeting"))
	var again := engine.confront("arkady_volkov", "fact_arkady_meeting|full", "ev_security_log")
	assert_eq(str(again["verdict"]), "repeat")
	var before := engine.state.broken_lies.size()
	assert_eq(engine.state.broken_lies.size(), before)
	engine.state.unlocked_evidence.append("ev_crime_scene")
	var missed := engine.confront("arkady_volkov", "fact_arkady_humiliation|lie", "ev_crime_scene")
	assert_eq(str(missed["verdict"]), "not_refuted")
	var truth := engine.confront("irina_morozova", "fact_irina_money|basic", "ev_divorce_papers")
	assert_eq(str(truth["verdict"]), "not_refuted")
	for verdict in ["holds", "doubt", "not_refuted"]:
		assert_eq(UiStrings.player_verdict(verdict), "Не опровергает")
	var book := Notebook.new(engine.case_data, engine.state)
	for row in book.confrontations():
		if str(row["verdict"]) in ["holds", "doubt", "not_refuted"]:
			assert_eq(str(row["player_verdict"]), "Не опровергает")
	for entry in book.entries():
		assert_false(str(entry["text"]).contains("под сомнением"))


func test_holds_then_the_confession_breaks_itself_and_names_the_other_lie() -> void:
	var engine := _engine()
	engine.state.unlocked_evidence.append("ev_kitchen_knife")
	var held := engine.confront("arkady_volkov", "fact_arkady_panic|lie", "ev_kitchen_knife")
	assert_eq(str(held["verdict"]), "holds")
	assert_false(engine.state.broken_lies.has("fact_arkady_panic"))
	assert_true(engine.state.broken_lies.has("fact_arkady_knife"))
	assert_true((held["also_broken"] as Array).has("fact_arkady_knife"))
	engine.state.unlocked_evidence.append("ev_security_log")
	engine.present_evidence("arkady_volkov", "ev_security_log")
	assert_true(engine.state.broken_lies.has("fact_arkady_meeting"))
	assert_true(engine.state.broken_lies.has("fact_arkady_panic"))
	assert_eq(_count(engine.state.broken_lies, "fact_arkady_panic"), 1)


func test_doubt_divorce_papers_do_not_break_irinas_affair() -> void:
	var engine := _engine()
	engine.state.unlocked_evidence.append("ev_divorce_papers")
	var doubted := engine.confront("irina_morozova", "fact_irina_affair|lie", "ev_divorce_papers")
	assert_eq(str(doubted["verdict"]), "doubt")
	assert_false(engine.state.broken_lies.has("fact_irina_affair"))
	var line := PromptBuilder._packet_block(engine.get_packet("irina_morozova"))
	assert_true(line.contains("ПОД СОМНЕНИЕМ"))
	assert_true(line.contains("Документы на развод"))
	assert_false(line.contains("Знала об измене Виктора с Алиной"))
	assert_true(line.contains("Знала, что у Виктора кто-то есть."))


func test_completed_debt_then_already() -> void:
	var engine := _engine()
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_irina_money", "full"))
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_alina_viktor_threat", "basic"))
	engine.pass_facts()
	engine.pass_facts()
	assert_true(engine.state.broken_lies.has("fact_arkady_debt"))
	assert_eq(str(engine.state.fact_levels["fact_arkady_debt"]), "basic")
	engine.state.unlocked_evidence.append("ev_financial_docs")
	var done := engine.confront("arkady_volkov", "fact_arkady_debt|basic", "ev_financial_docs")
	assert_eq(str(done["verdict"]), "completed")
	assert_eq(str(engine.state.fact_levels["fact_arkady_debt"]), "full")
	engine.state.unlocked_evidence.append("ev_crime_scene")
	var late := engine.confront("arkady_volkov", "fact_arkady_debt|full", "ev_crime_scene")
	assert_eq(str(late["verdict"]), "already")


func test_sets_need_every_item_and_either_branch() -> void:
	var data := _mini()
	var lie := _lie(data, "a", "lie")
	lie.breaks_with_explicit = true
	lie.breaks_with = [[
		{"type": "testimony_retold", "fact_id": "one"},
		{"type": "testimony_retold", "fact_id": "two"},
	], [
		{"type": "evidence_shown", "evidence_id": "note"},
	]]
	var engine := RulesEngine.new(data, GameState.new())
	engine.start_new()
	engine.state.retold.append(BreakSets.retell_key("a", "one", "basic"))
	engine.pass_facts()
	assert_false(engine.state.broken_lies.has("lie"))
	engine.state.retold.append(BreakSets.retell_key("a", "two", "basic"))
	engine.pass_facts()
	assert_true(engine.state.broken_lies.has("lie"))
	var other := RulesEngine.new(data, GameState.new())
	other.start_new()
	other.state.unlocked_evidence.append("note")
	other.present_evidence("a", "note")
	assert_true(other.state.broken_lies.has("lie"))


func test_full_retell_after_a_slip_counts_for_truth_full() -> void:
	var engine := _engine()
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_mira_leaving", "basic"))
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_alina_saw", "full"))
	engine.pass_facts()
	assert_false(engine.state.broken_lies.has("fact_arkady_mira_blame"))
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_mira_leaving", "full"))
	engine.pass_facts()
	assert_true(engine.state.broken_lies.has("fact_arkady_mira_blame"))


func test_retell_waits_for_required_lies_and_then_counts() -> void:
	var engine := _engine()
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_irina_money", "full"))
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_alina_viktor_threat", "basic"))
	engine.state.broken_lies.append("fact_arkady_debt")
	# Признание ждёт нож и встречу: пересказ сам их не заменяет.
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_pavel_closing", "basic"))
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_mira_leaving", "basic"))
	engine.pass_facts()
	assert_false(engine.state.broken_lies.has("fact_arkady_panic"))
	engine.state.broken_lies.append("fact_arkady_meeting")
	engine.state.broken_lies.append("fact_arkady_knife")
	engine.state.unlocked_evidence.append("ev_kitchen_knife")
	engine.present_quiet("arkady_volkov", "ev_kitchen_knife")
	engine.pass_facts()
	assert_true(engine.state.broken_lies.has("fact_arkady_panic"))


func test_pavel_is_not_counted_while_his_own_knife_lie_holds() -> void:
	var engine := _engine()
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_pavel_arkady_kitchen", "basic"))
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_mira_knife", "basic"))
	engine.pass_facts()
	assert_false(engine.state.broken_lies.has("fact_arkady_knife"))
	engine.state.broken_lies.append("fact_pavel_mira_knife")
	engine.pass_facts()
	assert_true(engine.state.broken_lies.has("fact_arkady_knife"))
	var clear := _engine()
	clear.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_alina_viktor_threat", "basic"))
	clear.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_irina_money", "full"))
	clear.pass_facts()
	assert_true(clear.state.broken_lies.has("fact_arkady_humiliation"))


func test_translated_case_lets_one_witness_break_the_meeting() -> void:
	var engine := _engine()
	var meeting: CaseData.Fact = engine.case_data.fact_by_id["fact_arkady_meeting"]
	meeting.breaks_with_explicit = false
	engine.state.retold.append(BreakSets.retell_key("arkady_volkov", "fact_pavel_closing", "basic"))
	engine.pass_facts()
	assert_true(engine.state.broken_lies.has("fact_arkady_meeting"))
	var explicit := _engine()
	var replaced: CaseData.Fact = explicit.case_data.fact_by_id["fact_arkady_meeting"]
	replaced.breaks_with_explicit = true
	replaced.breaks_with = []
	explicit.state.unlocked_evidence.append("ev_security_log")
	explicit.present_evidence("arkady_volkov", "ev_security_log")
	assert_false(explicit.state.broken_lies.has("fact_arkady_meeting"))


func test_old_save_and_turn_rollback_keep_the_new_fields() -> void:
	var legacy := GameState.from_dict({"pressure": {"a": 1}})
	assert_true(legacy.retold.is_empty())
	assert_true(legacy.confrontations.is_empty())
	assert_true(Game.open_case(REAL_CASE).ok)
	var snapshot := Game.state.to_dict()
	Game.state.unlocked_evidence.append("ev_security_log")
	Game._engine.confront("arkady_volkov", "fact_arkady_meeting|lie", "ev_security_log")
	Game.state.retold.append("arkady_volkov|fact_pavel_closing|basic")
	assert_false(Game.state.confrontations.is_empty())
	Game._restore(snapshot)
	assert_true(Game.state.retold.is_empty())
	assert_true(Game.state.confrontations.is_empty())
	assert_false(Game.state.broken_lies.has("fact_arkady_meeting"))


func test_doubt_prompt_hides_closed_truth_from_everyone_else() -> void:
	var engine := _engine()
	engine.state.unlocked_evidence.append("ev_divorce_papers")
	engine.present_evidence("irina_morozova", "ev_divorce_papers")
	var note := BreakSets.event_note("Документы на развод", "Не знала ни о чём.", "doubt")
	var liar := PromptBuilder.build_turn(engine.case_data, engine.state, "irina_morozova", engine.get_packet("irina_morozova"), DialogueState.new(), "Это она?", note)
	var system := str(liar["user"])
	assert_true(system.contains("Итог проверки: doubt"))
	assert_true(system.contains(BreakSets.HOLD))
	var at := system.find("Знала об измене Виктора с Алиной")
	assert_eq(at, -1, system.substr(maxi(0, at - 120), 280))
	assert_true(system.contains("[ЛОЖЬ, МОЖНО ОГОВОРИТЬСЯ, ПОД СОМНЕНИЕМ]"))
	var other := PromptBuilder.build_turn(engine.case_data, engine.state, "arkady_volkov", engine.get_packet("arkady_volkov"), DialogueState.new(), "Где вы были?", "")
	assert_false(str(other["user"]).contains("Итог проверки"), "чужой промпт")
	assert_false(str(other["user"]).contains("ПОД СОМНЕНИЕМ"), "чужое сомнение")
	engine.state.unlocked_evidence.append("ev_kitchen_knife")
	engine.present_evidence("arkady_volkov", "ev_kitchen_knife")
	var context := {"case_data": engine.case_data, "agent_id": "arkady_volkov", "state": engine.state, "leak_max_stems": 0, "player_text": "Нож?"}
	var leaked := ResponseValidator.validate({
		"player_tone": 0, "reply": "Когда всё случилось, я был там.", "remark": "",
		"emotion": "neutral", "stated": [], "mentioned_evidence": [], "requested_evidence": null,
	}, engine.get_packet("arkady_volkov"), context)
	assert_eq(bool(leaked["ok"]), false, str(leaked["violations"]))


func test_choice_list_does_not_grow_by_evidence_times_statement() -> void:
	var engine := _engine()
	engine.state.unlocked_evidence.append("ev_security_log")
	engine.state.heard.append({"agent_id": "pavel_sokolov", "fact_id": "fact_pavel_closing", "form": "basic", "turn": 1})
	var options := TurnOptions.build(engine.case_data, engine.state, "arkady_volkov")
	var cites := 0
	for option in options:
		var kind := str(option.get("kind", ""))
		assert_true(kind in ["topic", "ask", "present", "cite", "none"])
		if kind == "cite":
			cites += 1
			assert_false(str(option.get("text", "")).contains("улик"))
	assert_eq(cites, 1)


func test_builtin_case_is_solvable_and_four_lies_stay() -> void:
	var loaded := CaseLoader.load_case(REAL_CASE)
	assert_eq(CaseValidator.validate(_read(REAL_CASE)).size(), 0)
	assert_eq(CaseValidator.publish_errors(_read(REAL_CASE)).size(), 0)
	for tone in [0, 15]:
		var snap := SimHarness.run(loaded.case_data, tone)
		var broken: Array = snap["broken_lies"]
		assert_eq(broken.size(), 16)
		assert_eq(str(snap["fact_levels"]["fact_arkady_panic"]), "full")
		for fact_id in ["fact_mira_viktor", "fact_pavel_side", "fact_alina_affair", "fact_roman_grudge"]:
			assert_eq(str(snap["fact_levels"][fact_id]), "lie", fact_id)
			assert_false(broken.has(fact_id))
	var settled := SimHarness.settle(loaded.case_data, 0)
	var retell_sets := 0
	for agent in settled.case_data.agents:
		for fact in agent.facts:
			if not fact.is_lie:
				continue
			for items in BreakSets.sets_of(settled.case_data, fact):
				if items is not Array or not _has_retell(items):
					continue
				retell_sets += 1
				assert_true(BreakSets.set_met(settled.case_data, settled.state, fact, items), fact.id)
	assert_true(retell_sets > 0)
	var bare: Dictionary = _read(REAL_CASE)
	bare["agents"][1]["facts"][0]["breaks_with"] = []
	bare["agents"][1]["facts"][0]["lie_type"] = "must_lie"
	bare["agents"][1]["facts"][0]["is_lie"] = true
	var published := CaseValidator.publish_errors(bare)
	assert_true(published.size() >= 1)
	assert_eq(str(published[0]["code"]), "breaks_with_required")
	assert_eq(CaseValidator.validate(bare).size() >= 0, true)


func _engine() -> RulesEngine:
	var loaded := CaseLoader.load_case(REAL_CASE)
	assert_true(loaded.ok)
	var engine := RulesEngine.new(loaded.case_data, GameState.new())
	engine.start_new()
	return engine


func _mini() -> CaseData:
	var data := CaseData.new()
	data.id = "mini"
	for agent_id in ["a", "b"]:
		var agent := CaseData.Agent.new()
		agent.id = agent_id
		agent.name = agent_id
		agent.starting_emotion = "neutral"
		data.agents.append(agent)
		data.agent_by_id[agent_id] = agent
	_truth(data, "b", "one")
	_truth(data, "b", "two")
	var evidence := CaseData.EvidenceItem.new()
	evidence.id = "note"
	evidence.title = "Записка"
	data.evidence = [evidence]
	data.evidence_by_id["note"] = evidence
	return data


func _truth(data: CaseData, agent_id: String, fact_id: String) -> void:
	var fact := CaseData.Fact.new()
	fact.id = fact_id
	fact.content_basic = fact_id
	fact.content_full = fact_id
	fact.lie_type = "cannot_lie"
	var agent: CaseData.Agent = data.agent_by_id[agent_id]
	agent.facts.append(fact)
	data.fact_by_id[fact_id] = fact
	data.fact_owner[fact_id] = agent_id


func _lie(data: CaseData, agent_id: String, fact_id: String) -> CaseData.Fact:
	var fact := CaseData.Fact.new()
	fact.id = fact_id
	fact.is_lie = true
	fact.lie_type = "must_lie"
	fact.lie_text = "ложь"
	fact.content_basic = "общее"
	fact.content_full = "подробность"
	var agent: CaseData.Agent = data.agent_by_id[agent_id]
	agent.facts.append(fact)
	data.fact_by_id[fact_id] = fact
	data.fact_owner[fact_id] = agent_id
	return fact


func _has_retell(items: Array) -> bool:
	for item in items:
		if item is Dictionary and str((item as Dictionary).get("type", "")) == "testimony_retold":
			return true
	return false


func _count(items: Array, fact_id: String) -> int:
	var total := 0
	for item in items:
		if str(item) == fact_id:
			total += 1
	return total


func _read(path: String) -> Dictionary:
	var parser := JSON.new()
	assert_eq(parser.parse(FileAccess.get_file_as_string(path)), OK)
	return parser.data
