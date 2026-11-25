extends TestCase


func test_separate_stt_drops_hint_echo_and_closed_titles() -> void:
	var prompt := GameLanguage.text("stt_prompt")
	assert_true(prompt.contains("только справочник"))
	assert_true(prompt.contains("не заменяй"))
	assert_true(prompt.contains("пустой ответ"))
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var hint := SttHint.for_turn("gemini", Game.case_data, Game.state, "mira_belova", "")
	assert_true(hint.contains("Кухонный нож"))
	assert_true(hint.contains("Место преступления"))
	var closed := ""
	for evidence in Game.case_data.evidence:
		if not Game.state.unlocked_evidence.has(evidence.id) and evidence.title.strip_edges() != "":
			closed = evidence.title
			break
	assert_false(closed == "")
	assert_false(hint.contains(closed))
	var dump := "Место преступления. Кухонный нож. Ночь. Дождь заливает асфальт. В аллее за ночным клубом найден труп."
	assert_true(SpeechJunk.is_echo(dump, PackedStringArray([hint, Game.case_data.briefing])))
	assert_true(SttGuard.reject(dump, Game.case_data, Game.state, hint))
	assert_false(SttGuard.reject("Где вы были вчера вечером?", Game.case_data, Game.state, hint))
	assert_false(SpeechJunk.is_echo("Кто убил вчера вечером?", PackedStringArray([hint, Game.case_data.briefing])))
	assert_true(SttGuard.reject("Я нашёл %s на полу" % closed, Game.case_data, Game.state, hint))


func test_back_closes_a_sheet_then_returns_and_confirms_exit() -> void:
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var main := (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(main._place, "menu")
	main.handle_back()
	assert_true(main._exit.visible)
	main.handle_back()
	assert_false(main._exit.visible)
	main.show_investigation()
	await (Engine.get_main_loop() as SceneTree).process_frame
	var board: Control = main._screen
	board._drawer.visible = true
	assert_true(board.consume_back())
	assert_false(board._drawer.visible)
	main.handle_back()
	assert_eq(main._place, "menu")
	main.show_accusation()
	main.handle_back()
	assert_eq(main._place, "investigation")
	main.free()


func test_new_feed_line_adds_one_node() -> void:
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/interrogation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	screen.open_agent("mira_belova")
	var before: int = screen._feed_box.get_child_count()
	screen._push({"kind": "player", "text": "Где вы были?"})
	assert_eq(screen._feed_box.get_child_count(), before + 1)
	screen.free()


func test_continue_restores_shown_evidence_and_keeps_events_out_of_messages() -> void:
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var dialogue: DialogueState = Game._dialogues["mira_belova"]
	dialogue.append_message("player", "Что скажете?", 1, "", "ev_kitchen_knife")
	dialogue.append_message("agent", "Я ничего не показывала.", 1)
	Game.state.feed_events.append({
		"type": "lie_broken",
		"agent_id": "mira_belova",
		"turn": 1,
	})
	Game.state.confrontations.append({
		"turn": 1,
		"agent_id": "mira_belova",
		"statement_id": "fact_mira_viktor|basic",
		"evidence_id": "ev_kitchen_knife",
		"verdict": "holds",
		"also_broken": [],
	})
	Game._sync_dialogues()
	assert_true(SaveState.write_state(Game.state))
	var continued := Game.continue_case("res://cases/rain_over_shadow.json")
	assert_true(continued.ok, str(continued.get("reason", "")))
	var kept: DialogueState = Game._dialogues["mira_belova"]
	for message in kept.messages:
		assert_false(str(message.get("text", "")).contains("больше не может"))
		assert_false(str(message.get("text", "")).contains("предъявили"))
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/interrogation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	screen.open_agent("mira_belova")
	var blob := ""
	for row in screen._feeds["mira_belova"]:
		blob += str(row.get("text", "")) + "\n"
	assert_true(blob.contains("Вы показали: Кухонный нож"))
	assert_true(blob.contains("Мира Белова больше не может это отрицать"))
	assert_true(blob.contains("Вы предъявили"))
	assert_true(blob.contains("Не опровергает"))
	var old := GameState.from_dict({"case_id": Game.state.case_id, "dialogues": {"mira_belova": {"messages": [{"role": "player", "text": "Старый вопрос", "turn": 1}]}}})
	assert_eq(old.feed_events.size(), 0)
	assert_eq(old.confrontations.size(), 0)
	screen.free()


func test_retry_stays_with_the_character_of_the_turn() -> void:
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/interrogation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	screen.open_agent("mira_belova")
	screen._error.visible = true
	screen._remember({"kind": "ask", "text": "Где вы были?"})
	screen._push({"kind": "player", "text": "Где вы были?"})
	screen._push({"kind": "system", "text": "Вы: [предъявлена улика: нож]"})
	screen.open_agent("arkady_volkov")
	assert_false(screen._error.visible)
	screen._on_error("offline", "")
	var mira: Array = screen._feeds["mira_belova"]
	assert_eq(mira.size(), 1)
	assert_eq(str(screen._last.get("agent_id", "")), "mira_belova")
	screen.free()
