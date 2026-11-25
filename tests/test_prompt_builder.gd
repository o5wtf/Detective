extends TestCase

const REAL_CASE := "res://cases/rain_over_shadow.json"


func test_turn_template_key_lines() -> void:
	var built := _sample_request(0)
	var system := str(built["system"])
	var user := str(built["user"])
	for line in [
		"Ты играешь персонажа в детективной игре-допросе.",
		"КТО ТЫ: Ира, соседка.",
		"О СЕБЕ: Живёт на третьем этаже.",
		"ХАРАКТЕР И МАНЕРА РЕЧИ: Говорит коротко.",
		"ОТНОШЕНИЕ К ДРУГИМ:",
		"- Пётр: Не доверяет ему.",
		"ЧТО СЛУЧИЛОСЬ (это знают все): В доме погас свет.",
		"АТМОСФЕРА: Дождь.",
		"ПРАВИЛА (нарушать нельзя):",
		"ПОЛЯ ОТВЕТА:",
		"player_tone:",
	]:
		assert_true(system.contains(line), "нет строки системного промпта")
	assert_false(system.contains("ТАЙНАЯ ХРОНОЛОГИЯ"))
	assert_false(system.contains("СЕКРЕТ АВТОРА"))
	assert_false(system.contains("ЧУЖОЙ СЕКРЕТ"))
	for line in [
		"ТВОЁ СОСТОЯНИЕ: Ты спокоен и уверен в себе. Эмоция: neutral.",
		"ЧТО ТЫ МОЖЕШЬ СКАЗАТЬ:",
		"k1 [ПРАВДА]: Полная версия теперь видна",
		"k2 [ЛОЖЬ]: Я этого не делал совсем",
		"УЛИКИ, КОТОРЫЕ ТЕБЕ ПОКАЗАЛИ:",
		"нет",
		"УЛИКИ, ИЗВЕСТНЫЕ СЛЕДОВАТЕЛЮ (только названия):",
		"e1 — Записка на столе",
		"БЛОКНОТ СЛЕДОВАТЕЛЯ:",
		"пусто",
		"РАНЕЕ В РАЗГОВОРЕ: —",
		"ПОСЛЕДНИЕ РЕПЛИКИ:",
		"ВОПРОС СЛЕДОВАТЕЛЯ: Что вы видели?",
	]:
		assert_true(user.contains(line), "нет строки промпта хода")
	assert_false(user.contains("Ты устал от допроса"))
	assert_false(user.contains("ПОЛНАЯ ВЕРСИЯ СКРЫТА"))
	assert_false(user.contains("ПРАВДА MUST LIE"))
	assert_false(user.contains("ЗАКРЫТАЯ ПОЛНАЯ"))


func test_pressure_texts() -> void:
	assert_eq(PromptBuilder.pressure_text(0), "Ты спокоен и уверен в себе")
	assert_eq(PromptBuilder.pressure_text(24), "Ты спокоен и уверен в себе")
	assert_eq(PromptBuilder.pressure_text(25), "Ты напряжён, но держишься")
	assert_eq(PromptBuilder.pressure_text(49), "Ты напряжён, но держишься")
	assert_eq(PromptBuilder.pressure_text(50), "Ты заметно нервничаешь, отвечаешь неровно")
	assert_eq(PromptBuilder.pressure_text(74), "Ты заметно нервничаешь, отвечаешь неровно")
	assert_eq(PromptBuilder.pressure_text(75), "Ты на грани, тебе трудно держать себя в руках")
	assert_eq(PromptBuilder.pressure_text(100), "Ты на грани, тебе трудно держать себя в руках")
	var tired := _sample_request(80, "Следователь предъявляет улику «Записка на столе»: На бумаге одно слово.")
	assert_true(str(tired["user"]).contains(PromptBuilder.pressure_text(80)))
	assert_false(str(tired["user"]).contains("Ты устал от допроса"))
	assert_true(str(tired["user"]).contains("[СОБЫТИЕ: Следователь предъявляет улику «Записка на столе»: На бумаге одно слово.]"))


func test_packet_lines_and_empty_packet() -> void:
	var data := _sample_case()
	var state := GameState.new()
	var engine := RulesEngine.new(data, state)
	engine.start_new()
	var dialogue := DialogueState.new()
	var slip: Dictionary = engine.get_packet("ira")[2]
	assert_eq(slip["mode"], "lie_or_basic")
	var request := PromptBuilder.build_turn(data, state, "ira", [slip], dialogue, "Вопрос", "")
	assert_true(str(request["user"]).contains(
		"k3 [ЛОЖЬ, МОЖНО ОГОВОРИТЬСЯ]: твоя версия: «Никого не видела». Проговориться можно только так: «Кажется, в коридоре кто-то был»"
	))
	var empty := PromptBuilder.build_turn(data, state, "ira", [], dialogue, "Вопрос", "")
	assert_true(str(empty["user"]).contains(PromptBuilder.EMPTY_PACKET))
	var schema: Dictionary = empty["schema"]
	assert_eq(schema["properties"]["stated"]["items"]["properties"]["key"]["enum"], ["none"])


func test_schema_enums_match_packet_and_evidence() -> void:
	var built := _sample_request(0)
	var schema: Dictionary = built["schema"]
	var properties: Dictionary = schema["properties"]
	assert_eq(schema["required"], ["chosen", "player_tone", "reply", "remark", "emotion", "stated", "mentioned_evidence", "requested_evidence", "tone"])
	assert_eq(schema["propertyOrdering"], ["chosen", "player_tone", "reply", "remark", "emotion", "stated", "mentioned_evidence", "requested_evidence", "tone", "pace"])
	assert_false(schema["required"].has("pace"))
	assert_eq(properties["pace"]["enum"], ["slow", "normal", "fast"])
	assert_eq(properties["tone"]["enum"], ["нейтрально", "нервно", "устало", "раздражённо", "испуганно", "грустно", "уверенно", "уклончиво", "саркастично"])
	assert_eq(built["max_output_tokens"], LLMConfig.REPLY_MAX_OUTPUT_TOKENS)
	assert_eq(properties["stated"]["items"]["properties"]["key"]["enum"], ["k1", "k2", "k3"])
	assert_eq(properties["stated"]["items"]["properties"]["form"]["enum"], ["lie", "basic", "full"])
	assert_eq(properties["mentioned_evidence"]["items"]["enum"], ["e1"])
	assert_eq(properties["emotion"]["enum"], ["calm", "neutral", "nervous", "scared", "sad", "angry", "controlled", "contemptuous"])
	assert_false(properties["player_tone"].has("minimum"))
	assert_false(properties["player_tone"].has("maximum"))
	assert_eq(built["model_role"], "dialogue")
	assert_eq(built["temperature"], 0.9)


func test_prompt_hides_unrevealed_and_foreign_secrets() -> void:
	var data := _sample_case()
	var state := GameState.new()
	var engine := RulesEngine.new(data, state)
	engine.start_new()
	var packet: Array = engine.get_packet("ira")
	var dialogue := DialogueState.new()
	var request := PromptBuilder.build_turn(data, state, "ira", packet, dialogue, "Что вы видели?", "")
	var prompt := str(request["system"]) + "\n" + str(request["user"])
	_assert_case_hidden(data, state, data.agent_by_id["ira"], packet, prompt, _allowed(data, state, data.agent_by_id["ira"], packet, dialogue, "Что вы видели?", ""))
	assert_true(prompt.contains("Живёт на третьем этаже."))
	assert_false(prompt.contains("СЕКРЕТ АВТОРА ИРЫ"))
	assert_false(prompt.contains("ЧУЖОЙ СЕКРЕТ ПЕТРА"))
	assert_false(prompt.contains("ТАЙНАЯ ХРОНОЛОГИЯ ДЕЛА"))
	assert_false(prompt.contains("secret_killer"))
	assert_false(prompt.contains("ПОЛНАЯ ВЕРСИЯ СКРЫТА ОТ BASIC"))
	assert_false(prompt.contains("ПРАВДА MUST LIE BASIC"))
	assert_false(prompt.contains("ПРАВДА MUST LIE FULL"))
	assert_false(prompt.contains("ЗАКРЫТАЯ ПОЛНАЯ ВЕРСИЯ"))
	assert_false(prompt.contains("ЧУЖОЙ ФАКТ ПЕТРА ПОЛНОСТЬЮ"))


func test_real_case_prompts_do_not_leak() -> void:
	var loaded := CaseLoader.load_case(REAL_CASE)
	assert_true(loaded.ok, "дело не загрузилось")
	var data := loaded.case_data
	for agent in data.agents:
		for mode in ["start", "tone40", "tone90", "shown"]:
			var engine := _engine_in_mode(data, agent.id, mode)
			var packet: Array = engine.get_packet(agent.id)
			var dialogue := DialogueState.new()
			var player_text := "Что вы можете сказать?"
			var request := PromptBuilder.build_turn(
				data, engine.state, agent.id, packet, dialogue, player_text, ""
			)
			var prompt := str(request["system"]) + "\n" + str(request["user"])
			var allowed := _allowed(data, engine.state, agent, packet, dialogue, player_text, "")
			_assert_case_hidden(data, engine.state, agent, packet, prompt, allowed)
			var schema: Dictionary = request["schema"]
			var packet_keys: Array = []
			for entry in packet:
				packet_keys.append(str(entry["key"]))
			var expected_keys: Array = packet_keys if not packet_keys.is_empty() else ["none"]
			var stated_enum: Array = schema["properties"]["stated"]["items"]["properties"]["key"]["enum"]
			assert_eq(stated_enum, expected_keys, "enum пакета")
			var evidence_enum: Array = schema["properties"]["mentioned_evidence"]["items"]["enum"]
			if engine.state.unlocked_evidence.is_empty():
				assert_eq(evidence_enum, ["none"], "enum улик")
			else:
				assert_true(evidence_enum.size() >= engine.state.unlocked_evidence.size(), "enum улик")
				assert_false(evidence_enum.has("none"), "enum улик")


func test_mock_client_returns_queued_json() -> void:
	var mock := MockLLMClient.new()
	var first := {"ok": true, "json": {"reply": "первый"}, "raw_text": "{}", "error": "", "retry_after_s": 0.0}
	var second := {"ok": true, "json": {"reply": "второй"}, "raw_text": "{}", "error": "", "retry_after_s": 0.0}
	mock.enqueue(first)
	mock.enqueue(second)
	var request := {"system": "система", "user": "ход", "schema": {}, "model_role": "dialogue", "temperature": 0.9, "max_output_tokens": 2048}
	var got_first: Dictionary = mock.generate(request)
	var got_second: Dictionary = mock.generate(request)
	var got_empty: Dictionary = mock.generate(request)
	assert_eq(got_first["json"]["reply"], "первый")
	assert_eq(got_second["json"]["reply"], "второй")
	assert_false(got_empty["ok"])
	assert_eq(got_empty["error"], "bad_response")
	assert_eq(mock.calls.size(), 3)
	mock.free()


func _engine_in_mode(data: CaseData, agent_id: String, mode: String) -> RulesEngine:
	var engine := RulesEngine.new(data, GameState.new())
	engine.start_new()
	if mode == "tone40":
		engine.apply_tone(agent_id, 40)
	elif mode == "tone90":
		engine.apply_tone(agent_id, 90)
	elif mode == "shown":
		for evidence_id in engine.state.unlocked_evidence.duplicate():
			engine.present_evidence(agent_id, evidence_id)
		engine.apply_tone(agent_id, 60)
	return engine


func _allowed(
	data: CaseData,
	state: GameState,
	agent: CaseData.Agent,
	packet: Array,
	dialogue: DialogueState,
	player_text: String,
	event_note: String
) -> String:
	var chunks: PackedStringArray = PackedStringArray([
		agent.name, agent.role, agent.prompt_background, agent.personality,
		data.briefing, data.intro_atmosphere, player_text, event_note, dialogue.summary,
	])
	for other_id in agent.relationships:
		var other: CaseData.Agent = data.agent_by_id.get(str(other_id)) as CaseData.Agent
		if other != null:
			chunks.append(other.name)
		chunks.append(str(agent.relationships[other_id]))
	for entry in packet:
		if entry is not Dictionary:
			continue
		var body := entry as Dictionary
		var mode := str(body.get("mode", ""))
		if mode == "basic" or mode == "full" or mode == "lie_or_basic":
			chunks.append(str(body.get("content", "")))
		if mode == "lie" or mode == "lie_or_basic":
			chunks.append(str(body.get("lie_text", "")))
	for evidence in data.evidence:
		if state.unlocked_evidence.has(evidence.id):
			chunks.append(evidence.title)
			chunks.append(evidence.full_text)
		var shown: Array = state.shown.get(evidence.id, [])
		if shown.has(agent.id):
			chunks.append(evidence.title)
			chunks.append(evidence.full_text)
	for message in dialogue.recent(6):
		chunks.append(str(message.get("text", "")))
	return "\n".join(chunks)


func _forbid(prompt: String, allowed: String, needle: String, kind: String) -> void:
	var text := needle.strip_edges()
	if text.length() < 8:
		return
	if allowed.contains(text):
		return
	assert_false(prompt.contains(text), "утечка: %s" % kind)


func _assert_case_hidden(data: CaseData, state: GameState, agent: CaseData.Agent, packet: Array, prompt: String, allowed: String) -> void:
	_forbid(prompt, allowed, agent.background, "background")
	_forbid(prompt, allowed, data.truth_timeline, "truth_timeline")
	_forbid(prompt, allowed, data.killer_id, "killer_id")
	var mode_by_fact := {}
	for entry in packet:
		if entry is Dictionary:
			mode_by_fact[str((entry as Dictionary).get("fact_id", ""))] = str((entry as Dictionary).get("mode", ""))
	for fact in agent.facts:
		var mode := str(mode_by_fact.get(fact.id, ""))
		if mode == "":
			_forbid(prompt, allowed, fact.content_basic, "closed_fact")
			_forbid(prompt, allowed, fact.content_full, "closed_fact")
			_forbid(prompt, allowed, fact.lie_text, "closed_fact")
		elif mode == "basic":
			_forbid(prompt, allowed, fact.content_full, "content_full")
		elif mode == "lie":
			_forbid(prompt, allowed, fact.content_basic, "must_lie_truth")
			_forbid(prompt, allowed, fact.content_full, "must_lie_truth")
		elif mode == "lie_or_basic":
			_forbid(prompt, allowed, fact.content_full, "content_full")
	for other in data.agents:
		if other.id == agent.id:
			continue
		_forbid(prompt, allowed, other.background, "other_background")
		for fact in other.facts:
			_forbid(prompt, allowed, fact.content_basic, "other_secret")
			_forbid(prompt, allowed, fact.content_full, "other_secret")
			_forbid(prompt, allowed, fact.lie_text, "other_secret")


func _sample_request(pressure_value: int, event_note: String = "") -> Dictionary:
	var data := _sample_case()
	var state := GameState.new()
	var engine := RulesEngine.new(data, state)
	engine.start_new()
	state.pressure["ira"] = pressure_value
	var packet: Array = engine.get_packet("ira")
	# Пакет собран до подмены давления: для строк шаблона берём фактический пакет движка,
	# а тексты состояния читаются из GameState в момент сборки.
	if pressure_value >= 75:
		state.pressure["ira"] = pressure_value
	return PromptBuilder.build_turn(data, state, "ira", packet, DialogueState.new(), "Что вы видели?", event_note)


func _sample_case() -> CaseData:
	var data := CaseData.new()
	data.id = "sample"
	data.killer_id = "secret_killer"
	data.true_motive_id = "m"
	data.true_method_id = "w"
	data.briefing = "В доме погас свет."
	data.intro_atmosphere = "Дождь."
	data.truth_timeline = "ТАЙНАЯ ХРОНОЛОГИЯ ДЕЛА ЦЕЛИКОМ"
	var ira := _agent("ira", "Ира", "соседка", "Живёт на третьем этаже.", "Говорит коротко.", "СЕКРЕТ АВТОРА ИРЫ ДЛИННЫЙ")
	ira.relationships = {"petr": "Не доверяет ему."}
	var petr := _agent("petr", "Пётр", "дворник", "Подметает двор.", "Молчит.", "ЧУЖОЙ СЕКРЕТ ПЕТРА ДЛИННЫЙ")
	data.agents = [ira, petr]
	data.agent_by_id = {"ira": ira, "petr": petr}
	_fact(data, ira, "visible", 0, 100, "Краткая версия видна", "Полная версия теперь видна", false, "", null)
	_fact(data, ira, "must", 0, 100, "ПРАВДА MUST LIE BASIC", "ПРАВДА MUST LIE FULL", true, "Я этого не делал совсем", "evidence")
	_fact(data, ira, "slip", 0, 100, "Кажется, в коридоре кто-то был", "ПОЛНАЯ ОГОВОРКА СКРЫТА", true, "Никого не видела", "evidence")
	var slip: CaseData.Fact = data.fact_by_id["slip"]
	slip.lie_type = "can_lie"
	_fact(data, ira, "closed", 100, 100, "ЗАКРЫТАЯ КРАТКАЯ ВЕРСИЯ", "ЗАКРЫТАЯ ПОЛНАЯ ВЕРСИЯ ФАКТА", false, "", null)
	var closed: CaseData.Fact = data.fact_by_id["closed"]
	closed.requires_evidence = true
	closed.related_evidence_ids = ["note"]
	_fact(data, petr, "foreign", 0, 0, "ЧУЖОЙ ФАКТ ПЕТРА КРАТКО", "ЧУЖОЙ ФАКТ ПЕТРА ПОЛНОСТЬЮ", false, "", null)
	var evidence := CaseData.EvidenceItem.new()
	evidence.id = "note"
	evidence.title = "Записка на столе"
	evidence.full_text = "На бумаге одно слово."
	data.evidence = [evidence]
	data.evidence_by_id = {"note": evidence}
	return data


func _agent(agent_id: String, agent_name: String, role: String, prompt_background: String, personality: String, background: String) -> CaseData.Agent:
	var agent := CaseData.Agent.new()
	agent.id = agent_id
	agent.name = agent_name
	agent.role = role
	agent.prompt_background = prompt_background
	agent.personality = personality
	agent.background = background
	agent.starting_emotion = "neutral"
	return agent


func _fact(
	data: CaseData,
	agent: CaseData.Agent,
	fact_id: String,
	basic: int,
	full: int,
	content_basic: String,
	content_full: String,
	is_lie: bool,
	lie_text: String,
	breaks: Variant
) -> void:
	var fact := CaseData.Fact.new()
	fact.id = fact_id
	fact.content_basic = content_basic
	fact.content_full = content_full
	fact.pressure_for_basic = basic
	fact.pressure_for_full = full
	fact.is_lie = is_lie
	fact.lie_type = "must_lie" if is_lie else "cannot_lie"
	fact.lie_text = lie_text
	fact.breaks_lie_on = breaks
	agent.facts.append(fact)
	data.fact_by_id[fact_id] = fact
	data.fact_owner[fact_id] = agent.id

