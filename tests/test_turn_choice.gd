extends TestCase


func test_option_list_has_topic_ask_and_none() -> void:
	var data := _case()
	_evidence(data, "log", {
		"type": "evidence_mentioned",
		"agent_id": "b",
		"evidence_id": "log",
		"topic": "кто входил и выходил",
	})
	var engine := _engine(data)
	var options := TurnOptions.build(data, engine.state, "b")
	assert_eq(options.size(), 3)
	assert_eq(str(options[0]["kind"]), "topic")
	assert_true(str(options[0]["text"]).contains("кто входил и выходил"))
	assert_eq(str(options[1]["kind"]), "ask")
	assert_eq(str(options[2]["kind"]), "none")
	assert_true(TurnOptions.build(data, engine.state, "a").is_empty())


func test_choice_parses_from_the_start_of_the_stream() -> void:
	var reader := TurnChoice.new()
	reader.push("{\"chosen\":[2]")
	assert_true(reader.choice_ready())
	assert_eq(reader.chosen(), [2])
	assert_false(reader.reply_complete())
	reader.push(",\"reply\":\"Признаю.\"}")
	assert_true(reader.reply_complete())
	assert_eq(str(reader.payload()["reply"]), "Признаю.")


func test_topic_counter_unlocks_on_the_second_touch_and_direct_ask() -> void:
	var data := _case()
	_evidence(data, "log", {
		"type": "evidence_mentioned",
		"agent_id": "b",
		"evidence_id": "log",
		"topic": "кто входил и выходил",
	})
	var engine := _engine(data)
	var options := TurnOptions.build(data, engine.state, "b")
	var first := TurnOptions.plan(data, engine.state, "b", options, [int(options[0]["n"])])
	assert_true((first["unlock"] as Array).is_empty())
	engine.commit_plan("b", first)
	assert_false(engine.state.unlocked_evidence.has("log"))
	assert_eq(TurnOptions.touch_count(engine.state, "b", "log"), 1)
	var second := TurnOptions.plan(data, engine.state, "b", options, [int(options[0]["n"])])
	engine.commit_plan("b", second)
	assert_true(engine.state.unlocked_evidence.has("log"))
	var fresh := _engine(data)
	var asked := TurnOptions.plan(data, fresh.state, "b", options, [int(options[1]["n"])])
	fresh.commit_plan("b", asked)
	assert_true(fresh.state.unlocked_evidence.has("log"))
	var ignored := TurnOptions.plan(data, fresh.state, "b", options, [99])
	assert_eq(str(ignored["decision"]), "none")


func test_citation_accepts_only_a_heard_pair() -> void:
	var data := _case()
	var lie := _fact(data, "a", "fa")
	lie.is_lie = true
	lie.lie_type = "must_lie"
	lie.lie_text = "Меня там не было."
	lie.content_full = "Я был после закрытия."
	_fact(data, "b", "fb")
	var contradiction := CaseData.Contradiction.new()
	contradiction.id = "c"
	contradiction.fact_a_id = "fa"
	contradiction.fact_a_form = "lie"
	contradiction.fact_b_id = "fb"
	contradiction.fact_b_form = "truth"
	data.contradictions = [contradiction]
	var engine := _engine(data)
	engine.state.heard.append({"agent_id": "b", "fact_id": "fb", "form": "basic", "turn": 1})
	var options := TurnOptions.build(data, engine.state, "a")
	assert_eq(str(options[0]["kind"]), "cite")
	assert_true(str(options[0]["text"]).contains("Борис"))
	var valid := TurnOptions.plan(data, engine.state, "a", options, [int(options[0]["n"])])
	assert_true(bool(valid["restart"]))
	assert_eq((valid["break_lies"] as Array)[0], "fa")
	var missing := TurnOptions.plan(data, engine.state, "a", options, [])
	engine.state.heard.clear()
	var not_heard := TurnOptions.build(data, engine.state, "a")
	assert_true(not_heard.is_empty())
	engine.state.heard.append({"agent_id": "b", "fact_id": "other", "form": "basic", "turn": 1})
	var unpaired := TurnOptions.build(data, engine.state, "a")
	assert_true(unpaired.is_empty())
	assert_eq(str(missing["decision"]), "none")


func test_incomplete_stream_does_not_commit() -> void:
	var reader := TurnChoice.new()
	reader.push("{\"chosen\":[1]")
	reader.finish()
	assert_true(reader.choice_ready())
	assert_false(reader.reply_complete())


func test_topic_counter_survives_an_old_save() -> void:
	var state := GameState.new()
	state.topic_touches["b|log"] = 1
	state.pressure["a"] = 4
	var restored := GameState.from_dict(state.to_dict())
	assert_eq(int(restored.topic_touches["b|log"]), 1)
	var legacy := GameState.from_dict({"pressure": {"a": 4}, "fatigue": {"a": 9}, "revealed_parts": {"fa": [{"text": "кусок"}]}})
	assert_eq(int(legacy.pressure["a"]), 4)
	assert_true(legacy.topic_touches.is_empty())
	assert_true(legacy.evidence_mentions.is_empty())
	assert_false(legacy.to_dict().has("revealed_parts"))


func test_restart_keeps_only_the_final_reply() -> void:
	begin_async()
	assert_true(Game.open_case("res://tests/fixtures/turn_flow.json").ok)
	var mock := MockLLMClient.new()
	LLM.add_child(mock)
	LLM.client = mock
	mock.enqueue(_reply("k1", "lie", "Меня там не было."))
	await Game.ask("a", "Где вы были?")
	mock.enqueue(_reply("k1", "basic", "Я видел его после закрытия."))
	await Game.ask("b", "Что вы видели?")
	var options := TurnOptions.build(Game.case_data, Game.state, "a")
	var cite := 0
	for option in options:
		if str(option["kind"]) == "cite":
			cite = int(option["n"])
	assert_true(cite > 0)
	var first := _reply("k1", "lie", "Я ушёл в половине первого.")
	(first["json"] as Dictionary)["chosen"] = [cite]
	mock.enqueue(first)
	mock.enqueue(_reply("k1", "full", "Да, я был после закрытия."))
	var spoken: PackedStringArray = PackedStringArray()
	Game.agent_replied.connect(func(_id: String, text: String, _remark: String) -> void:
		spoken.append(text)
	)
	await Game.ask("a", "Павел говорит, что видел вас после закрытия.")
	assert_eq(spoken.size(), 1)
	assert_eq(spoken[0], "Да, я был после закрытия.")
	assert_false(spoken[0].contains("половине"))
	assert_true(Game.state.broken_lies.has("fa"))
	var agent_lines := 0
	for message in (Game._dialogues["a"] as DialogueState).messages:
		if str(message.get("role", "")) == "agent" and str(message.get("text", "")).contains("половине"):
			agent_lines += 1
	assert_eq(agent_lines, 0)
	mock.free()
	_async_pending = false


func _reply(key: String, form: String, text: String) -> Dictionary:
	return {
		"ok": true,
		"json": {
			"player_tone": 0,
			"reply": text,
			"remark": "кивает",
			"emotion": "neutral",
			"stated": [{"key": key, "form": form}],
			"mentioned_evidence": [],
			"requested_evidence": null,
		},
		"raw_text": "",
		"error": "",
		"retry_after_s": 0.0,
		"message": "",
	}


func _case() -> CaseData:
	var data := CaseData.new()
	data.id = "choice"
	for agent_id in ["a", "b"]:
		var agent := CaseData.Agent.new()
		agent.id = agent_id
		agent.name = "Аня" if agent_id == "a" else "Борис"
		agent.role = "сосед" if agent_id == "a" else "бармен"
		agent.starting_emotion = "neutral"
		data.agents.append(agent)
		data.agent_by_id[agent_id] = agent
	return data


func _fact(data: CaseData, agent_id: String, fact_id: String) -> CaseData.Fact:
	var fact := CaseData.Fact.new()
	fact.id = fact_id
	fact.content_basic = "кратко"
	fact.content_full = "полно"
	fact.lie_type = "cannot_lie"
	var agent: CaseData.Agent = data.agent_by_id[agent_id]
	agent.facts.append(fact)
	data.fact_by_id[fact_id] = fact
	data.fact_owner[fact_id] = agent_id
	return fact


func _evidence(data: CaseData, evidence_id: String, condition: Dictionary) -> void:
	var evidence := CaseData.EvidenceItem.new()
	evidence.id = evidence_id
	evidence.title = "Журнал охраны"
	evidence.unlock_condition = condition
	data.evidence.append(evidence)
	data.evidence_by_id[evidence_id] = evidence


func _engine(data: CaseData) -> RulesEngine:
	var engine := RulesEngine.new(data, GameState.new())
	engine.start_new()
	return engine


func test_citation_admits_the_general_layer_until_evidence_is_shown() -> void:
	var data := _case()
	var lie := _fact(data, "a", "fa")
	lie.is_lie = true
	lie.lie_type = "must_lie"
	lie.lie_text = "Ушёл в полночь."
	lie.content_basic = "общее"
	lie.content_full = "общее и тайная подробность"
	lie.requires_evidence = true
	lie.related_evidence_ids = ["log"]
	lie.breaks_lie_on = ["contradiction", "evidence"]
	_fact(data, "b", "fb")
	var contradiction := CaseData.Contradiction.new()
	contradiction.id = "c"
	contradiction.fact_a_id = "fa"
	contradiction.fact_a_form = "lie"
	contradiction.fact_b_id = "fb"
	contradiction.fact_b_form = "truth"
	data.contradictions = [contradiction]
	var engine := _engine(data)
	engine.state.heard.append({"agent_id": "b", "fact_id": "fb", "form": "basic", "turn": 1})
	var options := TurnOptions.build(data, engine.state, "a")
	var plan := TurnOptions.plan(data, engine.state, "a", options, [int(options[0]["n"])])
	assert_eq((plan["break_lies"] as Array)[0], "fa")
	assert_eq(str((plan["admit"] as Array)[0]), "общее")
	engine.commit_plan("a", plan)
	var dumped := JSON.stringify(engine.get_packet("a"))
	assert_true(dumped.contains("общее"))
	assert_false(dumped.contains("тайная"))
	var blocked := _fact(data, "a", "late")
	blocked.is_lie = true
	blocked.lie_type = "must_lie"
	blocked.lie_text = "Не я."
	blocked.requires_broken_lies = ["not_yet"]
	blocked.breaks_lie_on = "contradiction"
	var late := CaseData.Contradiction.new()
	late.id = "late_c"
	late.fact_a_id = "late"
	late.fact_a_form = "lie"
	late.fact_b_id = "fb"
	late.fact_b_form = "truth"
	data.contradictions = [contradiction, late]
	var waiting := TurnOptions.build(data, engine.state, "a")
	for option in waiting:
		assert_true(str(option.get("lie_id", "")) != "late")


func test_voice_present_uses_only_unlocked_evidence_and_its_substance() -> void:
	var data := _case()
	var evidence := CaseData.EvidenceItem.new()
	evidence.id = "log"
	evidence.title = "Журнал охраны"
	evidence.full_text = "В журнале записан выход Аркадия в 01:18."
	evidence.unlock_condition = {"type": "evidence_mentioned", "evidence_id": "log"}
	data.evidence.append(evidence)
	data.evidence_by_id["log"] = evidence
	var engine := _engine(data)
	for option in TurnOptions.build(data, engine.state, "a"):
		assert_true(str(option.get("kind", "")) != "present")
	engine.state.unlocked_evidence.append("log")
	var options := TurnOptions.build(data, engine.state, "a")
	var present: Dictionary = {}
	for option in options:
		if str(option.get("kind", "")) == "present":
			present = option
	assert_eq(str(present.get("evidence_id", "")), "log")
	assert_true(str(present.get("text", "")).contains("01:18"))
	assert_false(str(present.get("text", "")).begins_with("у меня есть"))
	var plan := TurnOptions.plan(data, engine.state, "a", options, [int(present.get("n", 0))])
	assert_true((plan["present"] as Array).has("log"))
	assert_true(bool(plan["restart"]))
