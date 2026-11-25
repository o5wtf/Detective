extends TestCase

const FIXTURE := "res://tests/fixtures/turn_flow.json"


func test_hidden_terms_are_only_closed_evidence_titles() -> void:
	var loaded := CaseLoader.load_case(FIXTURE)
	assert_true(loaded.ok)
	var titles := HiddenTerms.build(loaded.case_data, GameState.new())
	assert_true(titles.has("Записка"))
	var state := GameState.new()
	state.unlocked_evidence.append("ev")
	assert_false(HiddenTerms.build(loaded.case_data, state).has("Записка"))
	assert_true(HiddenTerms.mentioned("Где эта записка лежит?", titles))
	assert_false(HiddenTerms.mentioned("Где нож?", titles))
	assert_false(HiddenTerms.mentioned("Борис, меня там не было.", titles))


func test_heard_is_the_first_schema_field_and_audio_is_not_logged() -> void:
	var loaded := CaseLoader.load_case(FIXTURE)
	var request := PromptBuilder.build_turn(loaded.case_data, GameState.new(), "a", [], DialogueState.new(), "", "", true)
	var ordering: Array = request["schema"]["propertyOrdering"]
	assert_eq(str(ordering[0]), "heard")
	assert_true(str(request["user"]).begins_with(GameLanguage.text("heard_prompt")))
	var client := GeminiClient.new()
	var wav := PackedByteArray([82, 73, 70, 70])
	var body := client._body({"system": "система", "user": "вопрос", "schema": {"type": "object"}, "wav": wav}, "responseJsonSchema", "MINIMAL", false)
	var parts: Array = body["contents"][0]["parts"]
	assert_eq(str(parts[0]["inlineData"]["mimeType"]), "audio/wav")
	assert_eq(str(parts[1]["text"]), "вопрос")
	var dumped := JSON.stringify(body)
	assert_false(dumped.contains("unit-test-key"))
	assert_false(LlmTiming.turn_line(1, "m", {"requests": 1, "merged": "yes", "fallback": "none"}).contains("вопрос"))
	client.free()


func test_junk_heard_drops_the_turn_and_does_not_speak() -> void:
	_enable_merged()
	assert_true(Game.open_case(FIXTURE).ok)
	var mock := _Mock.new()
	LLM.add_child(mock)
	LLM.client = mock
	mock.queue.append(_reply("…", "Я всё равно отвечу."))
	var replies: Array[String] = []
	var errors: Array[String] = []
	Game.agent_replied.connect(func(_id: String, text: String, _remark: String) -> void: replies.append(text))
	Game.llm_error.connect(func(_kind: String, message: String) -> void: errors.append(message))
	var before := Game.state.to_dict()
	await Game.ask("a", "", PackedByteArray([1, 2, 3, 4]))
	assert_true(replies.is_empty())
	assert_eq(Game.speech_line, "")
	assert_eq(errors[0], GameLanguage.text("stt_repeat"))
	assert_eq(Game.state.to_dict(), before)
	assert_eq(str(Game.last_turn_stats.get("merged", "")), "yes")
	assert_eq(str(Game.last_turn_stats.get("fallback", "")), "junk")
	assert_eq(mock.calls.size(), 1)
	_restore_settings()
	mock.free()


func test_hidden_term_uses_stt_text_and_not_the_merged_reply() -> void:
	_enable_merged()
	assert_true(Game.open_case(FIXTURE).ok)
	var mock := _Mock.new()
	LLM.add_child(mock)
	LLM.client = mock
	mock.queue.append(_reply("Где записка?", "Это подстановка."))
	mock.queue.append(_reply("", "Я был на улице."))
	var stt := _Stt.new()
	stt.text = "Где вы были?"
	Game.fallback_stt = stt
	await Game.ask("a", "", PackedByteArray([1, 2, 3, 4]))
	assert_eq(Game.accepted_player_line, "Где вы были?")
	assert_eq(str((Game._dialogues["a"] as DialogueState).messages[0]["text"]), "Где вы были?")
	assert_false(str((Game._dialogues["a"] as DialogueState).messages[1]["text"]).contains("подстановка"))
	assert_eq(stt.calls, 1)
	assert_eq(mock.calls.size(), 2)
	assert_true(bool(mock.calls[0]["audio"]))
	assert_false(bool(mock.calls[1]["audio"]))
	assert_eq(str(Game.last_turn_stats.get("fallback", "")), "leak")
	_restore_settings()
	Game.fallback_stt = null
	stt.free()
	mock.free()


func test_term_in_stt_still_uses_the_stt_line() -> void:
	_enable_merged()
	assert_true(Game.open_case(FIXTURE).ok)
	var mock := _Mock.new()
	LLM.add_child(mock)
	LLM.client = mock
	mock.queue.append(_reply("Где записка?", "Не брать."))
	mock.queue.append(_reply("", "Спрошу ещё раз."))
	var stt := _Stt.new()
	stt.text = "Покажи записку."
	Game.fallback_stt = stt
	await Game.ask("a", "", PackedByteArray([9, 9, 9, 9]))
	assert_eq(Game.accepted_player_line, "Покажи записку.")
	_restore_settings()
	Game.fallback_stt = null
	stt.free()
	mock.free()


func test_keyboard_and_parakeet_do_not_send_audio() -> void:
	_enable_merged()
	assert_true(Game.open_case(FIXTURE).ok)
	var mock := _Mock.new()
	LLM.add_child(mock)
	LLM.client = mock
	mock.queue.append(_reply("", "Текстом."))
	await Game.ask("a", "Где вы были?")
	assert_false(bool(mock.calls[0]["audio"]))
	assert_eq(str(Game.last_turn_stats.get("fallback", "")), "keyboard")
	SettingsStore.save_value("mic", "stt", "parakeet")
	mock.queue.append(_reply("", "Локально."))
	await Game.ask("a", "Где вы были?", PackedByteArray([1, 2, 3, 4]))
	assert_false(bool(mock.calls[1]["audio"]))
	assert_eq(str(Game.last_turn_stats.get("fallback", "")), "parakeet")
	assert_eq(Game.accepted_player_line, "Где вы были?")
	_restore_settings()
	mock.free()


func test_regeneration_repeats_heard_without_audio() -> void:
	_enable_merged()
	assert_true(Game.open_case(FIXTURE).ok)
	var mock := _Mock.new()
	LLM.add_child(mock)
	LLM.client = mock
	mock.queue.append(_reply("Где вы были?", "Я нейросеть и всё знаю."))
	mock.queue.append(_reply("", "Я был дома."))
	await Game.ask("a", "", PackedByteArray([5, 5, 5, 5]))
	assert_eq(mock.calls.size(), 2)
	assert_true(bool(mock.calls[0]["audio"]))
	assert_false(bool(mock.calls[1]["audio"]))
	assert_true(str(mock.calls[1]["user"]).contains("Где вы были?"))
	assert_eq(Game.accepted_player_line, "Где вы были?")
	_restore_settings()
	mock.free()


func test_network_failure_restores_the_turn_and_the_cap_stops_at_five() -> void:
	_enable_merged()
	assert_true(Game.open_case(FIXTURE).ok)
	var mock := _Mock.new()
	LLM.add_child(mock)
	LLM.client = mock
	mock.queue.append({"ok": false, "json": {}, "raw_text": "", "error": "offline", "retry_after_s": 0.0, "message": "Нет связи."})
	var stt := _Stt.new()
	stt.fail = "offline"
	Game.fallback_stt = stt
	Game.state.unlocked_evidence.append("ev")
	var before := Game.state.to_dict()
	await Game.present("a", "ev", "", PackedByteArray([7, 7, 7, 7]))
	assert_eq(Game.state.to_dict(), before)
	assert_eq(str(Game.last_turn_stats.get("fallback", "")), "network")
	assert_eq(mock.calls.size(), 1)
	var tally := LlmTiming.empty_tally()
	for _index in Game.MODEL_CAP:
		assert_true(Game._spend_model(tally, "reply", "reply"))
	assert_false(Game._spend_model(tally, "reply", "reply"))
	assert_eq(int(tally["requests"]), Game.MODEL_CAP)
	_restore_settings()
	Game.fallback_stt = null
	stt.free()
	mock.free()


func test_merged_setting_defaults_off_and_survives_save() -> void:
	var path := SettingsStore.PATH
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	SettingsStore.invalidate_cache()
	assert_false(SettingsStore.load_current().mic_merged)
	assert_false(SettingsStore.wants_merged_stt())
	SettingsStore.save_value("mic", "merged", true)
	assert_true(SettingsStore.load_current().mic_merged)
	assert_true(SettingsStore.load_current().detached().mic_merged)
	SettingsStore.save_values("mock", "", "gemini-3.5-flash-lite", 1.0)
	assert_true(SettingsStore.load_current().mic_merged)
	var file := ConfigFile.new()
	assert_eq(file.load(path), OK)
	file.set_value("mic", "merged", "true")
	file.save(path)
	SettingsStore.invalidate_cache()
	assert_false(SettingsStore.load_current().mic_merged)
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/settings.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var box := screen.find_child("MergedStt", true, false) as CheckBox
	assert_false(box.visible)
	var developer := screen.find_child("DeveloperMode", true, false) as CheckBox
	developer.button_pressed = true
	assert_true(box.visible)
	box.button_pressed = true
	assert_true(SettingsStore.load_current().mic_merged)
	screen.free()
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()
	SettingsStore.invalidate_cache()


var _previous_settings := ""


func _enable_merged() -> void:
	var path := SettingsStore.PATH
	_previous_settings = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	SettingsStore.save_value("mic", "merged", true)
	SettingsStore.save_value("mic", "stt", "gemini")


func _restore_settings() -> void:
	var path := SettingsStore.PATH
	if _previous_settings == "":
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(_previous_settings)
		restore.close()
	SettingsStore.invalidate_cache()


func _reply(heard: String, text: String) -> Dictionary:
	var body := {
		"player_tone": 0,
		"reply": text,
		"remark": "кивает",
		"emotion": "neutral",
		"stated": [],
		"mentioned_evidence": [],
		"requested_evidence": null,
	}
	if heard != "":
		body["heard"] = heard
	return {
		"ok": true,
		"json": body,
		"raw_text": JSON.stringify(body),
		"error": "",
		"retry_after_s": 0.0,
		"message": "",
	}


class _Mock:
	extends LLMClient

	var queue: Array = []
	var calls: Array = []

	func generate(request: Dictionary) -> Dictionary:
		var wav: Variant = request.get("wav", PackedByteArray())
		calls.append({
			"audio": wav is PackedByteArray and not (wav as PackedByteArray).is_empty(),
			"user": str(request.get("user", "")),
		})
		await (Engine.get_main_loop() as SceneTree).process_frame
		if queue.is_empty():
			return {"ok": false, "json": {}, "raw_text": "", "error": "offline", "retry_after_s": 0.0, "message": "Нет связи."}
		return queue.pop_front()


class _Stt:
	extends SttBackend

	var text: String = ""
	var fail: String = ""
	var calls: int = 0

	func transcribe(_wav: PackedByteArray) -> Dictionary:
		calls += 1
		await (Engine.get_main_loop() as SceneTree).process_frame
		if fail != "":
			return {"ok": false, "text": "", "error": fail, "message": "Нет связи."}
		return {"ok": true, "text": text, "error": "", "message": ""}
