extends TestCase

const SCENES := {
	"res://src/main.tscn": ["NewCaseButton", "ContinueButton", "RestartButton", "SettingsButton"],
	"res://ui/screens/main_menu.tscn": ["NewCaseButton", "ContinueButton", "RestartButton", "SettingsButton"],
	"res://ui/screens/settings.tscn": ["KeyField", "ShowKeyButton", "TestConnectionButton", "ModelField", "ScaleSlider", "MockCheck", "TimingDebug", "DeveloperMode", "VoiceEnabled", "ToneEnabled", "VoiceEngine", "VoiceModel", "VoiceAuto", "ChirpHint", "ChirpKeyField", "VoiceModelNote", "VoiceCheckButton", "VoiceStatusLabel", "TurnLogLabel", "VoiceLogLabel", "MicDiagLabel", "MicEnabled", "MicMode", "PauseSlider", "PauseValue", "PlayLastMicButton", "SaveButton", "BackButton"],
	"res://ui/screens/briefing.tscn": ["TitleLabel", "BriefingLabel", "StartButton"],
	"res://ui/screens/suspects.tscn": ["List"],
	"res://ui/screens/interrogation.tscn": ["SendButton", "PromptField", "EvidenceButton", "NotebookButton", "HintYesButton", "RetryButton", "TurnTimingLabel", "StopSpeechButton", "VoiceErrorLabel", "VoiceRetryButton", "MicButton", "MicLevel", "MicStateLabel", "MicHintLabel", "MicSettingsButton", "SttRetryButton"],
	"res://ui/screens/notebook.tscn": ["NotebookTabs", "FilterButton"],
	"res://ui/screens/evidence_board.tscn": ["Grid", "PresentButton"],
	"res://ui/screens/accusation.tscn": ["KillerOption", "MotiveOption", "MethodOption", "AccuseButton", "BackButton", "TimelineLabel"],
	"res://ui/screens/investigation.tscn": ["AccuseButton", "MenuButton", "TopAccuseButton"],
	"res://ui/screens/damaged_case.tscn": ["TitleLabel", "BackButton"],
}


func test_scenes_instantiate_and_buttons_exist() -> void:
	_clear_saves()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for path in SCENES:
		var packed := load(path) as PackedScene
		assert_true(packed != null, path)
		var node := packed.instantiate()
		root.add_child(node)
		await (Engine.get_main_loop() as SceneTree).process_frame
		for node_name in SCENES[path]:
			var found := node.find_child(str(node_name), true, false)
			assert_true(found != null, "%s:%s" % [path, node_name])
		if path.ends_with("main_menu.tscn") or path == "res://src/main.tscn":
			var continue_button := node.find_child("ContinueButton", true, false) as Button
			var restart_button := node.find_child("RestartButton", true, false) as Button
			assert_true(continue_button != null)
			assert_false(continue_button.visible)
			assert_true(restart_button != null)
			assert_false(restart_button.visible)
		node.free()


func test_briefing_has_no_atmosphere_and_accusation_scrolls() -> void:
	var briefing := (load("res://ui/screens/briefing.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(briefing)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(briefing.find_child("AtmosphereLabel", true, false) == null)
	assert_true(briefing.find_child("BriefingLabel", true, false) != null)
	briefing.free()
	var accusation := (load("res://ui/screens/accusation.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(accusation)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var scroll := accusation.find_child("AccusationScroll", true, false) as ScrollContainer
	assert_true(scroll != null)
	assert_true(scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
	accusation.free()


func test_portrait_scale_keeps_physical_size() -> void:
	var base := UiLayout.BASE_SIZE
	assert_true(absf(UiLayout.content_scale_factor_for(Vector2(1280, 800)) - 1.0) < 0.001)
	assert_true(absf(UiLayout.content_scale_factor_for(Vector2(1920, 1080)) - 1.0) < 0.001)
	var factor := UiLayout.content_scale_factor_for(Vector2(800, 1280))
	var fit := minf(800.0 / base.x, 1280.0 / base.y)
	assert_true(absf(factor * fit - 1.0) < 0.001)


func test_layout_modes_skip_phone() -> void:
	assert_eq(UiLayout.mode_for_size(Vector2(1280, 800)), "wide")
	assert_eq(UiLayout.mode_for_size(Vector2(1000, 700)), "wide")
	assert_eq(UiLayout.mode_for_size(Vector2(800, 1280)), "medium")
	assert_eq(UiLayout.mode_for_size(Vector2(999, 700)), "medium")
	assert_eq(UiLayout.mode_for_size(Vector2(640, 400)), "medium")


func test_developer_pressure_sits_next_to_the_remark() -> void:
	var plain := UiStrings.state_line("tense", "angry", 42, false)
	assert_false(plain.contains("давление"))
	assert_true(plain.contains("напряжён"))
	assert_true(UiStrings.state_line("tense", "angry", 42, true).contains("давление 42"))
	assert_eq(UiStrings.state_remark("nervous", "nervous"), "«заметно нервничает»")
	assert_eq(UiStrings.state_remark("tense", "angry"), "«напряжён», злится")
	assert_eq(UiStrings.evidence_kind("scene"), "сцена")
	assert_eq(UiStrings.evidence_kind("документ"), "документ")
	var meter := LevelMeter.new()
	meter.push(1.0)
	assert_false(meter.advance(0.01))
	assert_true(meter.shown > 0.1)
	meter.push(0.0)
	var steps := 0
	while steps < 30 and meter.shown > 0.05:
		meter.advance(0.05)
		steps += 1
	assert_true(meter.shown < 0.2)


func test_settings_cache_matches_the_file_and_drops_after_each_writer() -> void:
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	SettingsStore.invalidate_cache()
	SettingsStore.save_values("mock", "cache-marker", "gemini-3.5-flash-lite", 1.0, null, null, null, null, true, "push_to_talk")
	var first := SettingsStore.load_current()
	var second := SettingsStore.load_current()
	assert_eq(first.dialogue_model, second.dialogue_model)
	assert_eq(first.mic_mode, "push_to_talk")
	assert_eq(first.api_key, "cache-marker")
	SettingsStore.save_values("mock", "cache-marker", "gemini-3.6-flash", 1.0, null, null, null, null, true, "hands_free")
	var saved := SettingsStore.load_current()
	assert_eq(saved.dialogue_model, "gemini-3.6-flash")
	assert_eq(saved.mic_mode, "hands_free")
	SettingsStore.remember_thinking("gemini-3.6-flash", "LOW")
	var after_thinking := SettingsStore.load_current()
	assert_eq(after_thinking.dialogue_model, "gemini-3.6-flash")
	var file := ConfigFile.new()
	assert_eq(file.load(path), OK)
	file.set_value("mic", "pause_ms", 1500)
	file.save(path)
	var reread := SettingsStore.load_current()
	assert_eq(reread.mic_pause_ms, 1500)
	assert_eq(LLMConfig.load_settings().dialogue_model, "gemini-3.6-flash")
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()
	SettingsStore.invalidate_cache()


func test_remarks_have_no_digits() -> void:
	for band_name in ["calm", "tense", "nervous", "breaking"]:
		for emotion in Balance.EMOTIONS:
			var text := UiStrings.state_remark(band_name, emotion)
			assert_false(_has_digit(text), band_name)


func test_connection_message_hides_secret() -> void:
	var secret := "test-key-value"
	var message := UiStrings.connection_message("gemini", {
		"ok": false,
		"error": "auth",
		"message": "Ключ API отклонён.",
	})
	assert_false(message.contains(secret))
	assert_eq(message, "Ключ API отклонён.")
	var linked := UiStrings.connection_message("gemini", {
		"ok": true,
		"model": "gemini-3.5-flash-lite",
		"elapsed_s": 1.2,
	})
	assert_true(linked.contains("gemini-3.5-flash-lite"))
	assert_true(linked.contains("1.2"))
	assert_false(UiStrings.error_text("timeout").contains("Нет сети"))
	assert_eq(UiStrings.connection_message("mock", {}), UiStrings.LINK_MOCK)


func test_settings_roundtrip_keeps_key_out_of_status_copy() -> void:
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	SettingsStore.save_values("mock", "test-key-value", "gemini-3.8-flash", 1.1)
	var loaded := SettingsStore.load_current()
	assert_eq(loaded.provider, "mock")
	assert_eq(loaded.api_key, "test-key-value")
	assert_eq(loaded.dialogue_model, LLMConfig.DEFAULT_DIALOGUE_MODEL)
	assert_true(absf(loaded.text_scale - 1.1) < 0.001)
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(previous)
		file.close()


func _clear_saves() -> void:
	var saves := DirAccess.open("user://saves")
	if saves == null:
		return
	saves.list_dir_begin()
	var file_name := saves.get_next()
	while file_name != "":
		if not saves.current_is_dir() and file_name.ends_with(".json"):
			saves.remove(file_name)
		file_name = saves.get_next()
	saves.list_dir_end()


func _has_digit(text: String) -> bool:
	for index in text.length():
		if text[index] >= "0" and text[index] <= "9":
			return true
	return false
