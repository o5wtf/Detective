extends TestCase

const FIXTURE := "res://tests/fixtures/turn_flow.json"
const SECRET := "super-secret-key-xyz"


func test_roundtrip_restores_progress() -> void:
	assert_true(Game.open_case(FIXTURE).ok, "фикстура не открылась")
	Game.state.pressure["a"] = 12
	Game.state.emotion["a"] = "angry"
	if not Game.state.unlocked_evidence.has("ev"):
		Game.state.unlocked_evidence.append("ev")
	if not Game.state.contradictions.has("c1"):
		Game.state.contradictions.append("c1")
	Game.state.heard.append({"agent_id": "a", "fact_id": "fa", "form": "lie", "turn": 1})
	Game.state.accusation["killer_ok"] = true
	Game.state.accusation["attempts"] = 2
	var dialogue: DialogueState = Game._dialogues["a"]
	dialogue.summary = "Краткое резюме хода."
	dialogue.summarized_count = 1
	dialogue.append_message("player", "Короткий вопрос", 1)
	dialogue.append_message("agent", "Короткий ответ", 1, "кивает")
	Game._sync_dialogues()
	assert_true(SaveState.write_state(Game.state))
	var text := FileAccess.get_file_as_string(SaveState.slot_path(Game.state.case_id))
	assert_false(text.contains("api_key"), "в сохранении есть поле ключа")
	assert_false(text.contains(SECRET), "в сохранении есть секрет")
	assert_true(Game.continue_case(FIXTURE).ok)
	assert_eq(int(Game.state.pressure["a"]), 12)
	assert_eq(str(Game.state.emotion["a"]), "angry")
	assert_true(Game.state.unlocked_evidence.has("ev"))
	assert_true(Game.state.contradictions.has("c1"))
	assert_eq(Game.state.heard.size(), 1)
	assert_true(Game.state.accusation["killer_ok"])
	assert_eq(int(Game.state.accusation["attempts"]), 2)
	var restored: DialogueState = Game._dialogues["a"]
	assert_eq(restored.summary, "Краткое резюме хода.")
	assert_eq(restored.summarized_count, 1)
	assert_eq(restored.messages.size(), 2)
	SaveState.discard(Game.state.case_id)


func test_old_save_ignores_fatigue() -> void:
	assert_true(Game.open_case(FIXTURE).ok, "фикстура не открылась")
	var case_id := Game.state.case_id
	var body: Dictionary = Game.state.to_dict()
	body["pressure"] = {"a": 12}
	body["fatigue"] = {"a": 40}
	_write(case_id, JSON.stringify({
		"format": 1,
		"case_id": case_id,
		"case_version_hash": Game.state.case_version_hash,
		"state": body,
	}))
	var loaded := Game.continue_case(FIXTURE)
	assert_true(loaded.ok)
	assert_eq(int(Game.state.pressure["a"]), 12)
	assert_false(Game.state.to_dict().has("fatigue"))
	assert_true(SaveState.write_state(Game.state))
	var text := FileAccess.get_file_as_string(SaveState.slot_path(case_id))
	assert_false(text.contains("fatigue"))
	var parsed: Variant = JSON.parse_string(JSON.stringify(body))
	var again := GameState.from_dict(parsed)
	assert_eq(int(again.pressure["a"]), 12)
	assert_false(again.to_dict().has("fatigue"))
	SaveState.discard(case_id)


func test_autosave_after_turn_and_not_after_network_error() -> void:
	assert_true(Game.open_case(FIXTURE).ok, "фикстура не открылась")
	SaveState.discard(Game.state.case_id)
	var mock := MockLLMClient.new()
	LLM.client = mock
	mock.enqueue({"ok": false, "json": {}, "raw_text": "", "error": "offline", "retry_after_s": 0.0, "message": ""})
	await Game.ask("a", "Где вы были?")
	assert_false(SaveState.exists(Game.state.case_id))
	mock.enqueue({
		"ok": true,
		"json": {
			"player_tone": 0,
			"reply": "Я держусь своей версии.",
			"remark": "кивает",
			"emotion": "neutral",
			"stated": [{"key": "k1", "form": "lie"}],
			"mentioned_evidence": [],
			"requested_evidence": null,
		},
		"raw_text": "",
		"error": "",
		"retry_after_s": 0.0,
		"message": "",
	})
	await Game.ask("a", "Где вы были?")
	assert_true(SaveState.exists(Game.state.case_id))
	var saved := SaveState.read(Game.state.case_id)
	assert_true(saved.ok)
	var state := GameState.from_dict(saved.state)
	assert_true(state.heard.size() > 0)
	assert_true(state.accusation["killer_ok"] == false)
	Game.accuse("a", "nope", "w")
	var after := SaveState.read(Game.state.case_id)
	var ticks := GameState.from_dict(after.state)
	assert_true(ticks.accusation["killer_ok"])
	assert_false(ticks.accusation["motive_ok"])
	assert_true(Game.continue_case(FIXTURE).ok)
	assert_true(Game.state.accusation["killer_ok"])
	assert_eq(Game.state.heard.size(), state.heard.size())
	SaveState.discard(Game.state.case_id)
	mock.free()


func test_hash_version_and_corrupt_saves_are_refused() -> void:
	assert_true(Game.open_case(FIXTURE).ok, "фикстура не открылась")
	var case_id := Game.state.case_id
	_write(case_id, "это не json")
	assert_eq(str(SaveState.read(case_id).reason), "corrupt")
	_write(case_id, JSON.stringify({"format": 0, "state": {}}))
	assert_eq(str(SaveState.read(case_id).reason), "version")
	_write(case_id, JSON.stringify({
		"format": 1,
		"case_id": case_id,
		"case_version_hash": "другой",
		"state": Game.state.to_dict(),
	}))
	var before := Game.state.heard.size()
	var refused := Game.continue_case(FIXTURE)
	assert_false(refused.ok)
	assert_eq(str(refused.reason), "hash")
	assert_eq(Game.state.heard.size(), before)
	SaveState.discard(case_id)


func test_continue_button_follows_the_save_file() -> void:
	assert_true(Game.open_case(FIXTURE).ok, "фикстура не открылась")
	SaveState.discard(Game.state.case_id)
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var menu := (load("res://ui/screens/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	menu.refresh_for(FIXTURE)
	assert_false((menu.find_child("ContinueButton", true, false) as Button).visible)
	assert_true(SaveState.write_state(Game.state))
	menu.refresh_for(FIXTURE)
	assert_true((menu.find_child("ContinueButton", true, false) as Button).visible)
	assert_true((menu.find_child("RestartButton", true, false) as Button).visible)
	menu.show_save_problem("hash")
	assert_true(str((menu.find_child("SaveProblemLabel", true, false) as Label).text).contains("Начните заново"))
	SaveState.discard(Game.state.case_id)
	menu.free()


func test_settings_key_is_not_copied_into_the_save() -> void:
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	SettingsStore.save_values("mock", SECRET, "gemini-3.8-flash", 1.0)
	assert_true(Game.open_case(FIXTURE).ok, "фикстура не открылась")
	assert_true(SaveState.write_state(Game.state))
	var text := FileAccess.get_file_as_string(SaveState.slot_path(Game.state.case_id))
	assert_false(text.contains(SECRET), "ключ из настроек попал в сохранение")
	assert_false(text.contains("api_key"), "в сохранении есть поле ключа")
	SaveState.discard(Game.state.case_id)
	if previous == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(previous)
		file.close()


func test_failed_replace_keeps_the_previous_save() -> void:
	assert_true(Game.open_case(FIXTURE).ok)
	Game.state.pressure["a"] = 3
	assert_true(SaveState.write_state(Game.state))
	var path := SaveState.slot_path(Game.state.case_id)
	var before := FileAccess.get_file_as_string(path)
	Game.state.pressure["a"] = 9
	SaveState.fail_before_rename = true
	assert_false(SaveState.write_state(Game.state))
	SaveState.fail_before_rename = false
	assert_eq(FileAccess.get_file_as_string(path), before)
	assert_false(FileAccess.file_exists(path + ".tmp"))
	SaveState.discard(Game.state.case_id)


func _write(case_id: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var file := FileAccess.open(SaveState.slot_path(case_id), FileAccess.WRITE)
	file.store_string(text)
	file.close()
