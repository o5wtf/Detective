extends Control

signal back_pressed
signal saved

var explain_key: bool = false

var _key: LineEdit
var _model: OptionButton
var _spend: Label
var _loading: bool = false
var _scale: HSlider
var _mock: CheckBox
var _timing: CheckBox
var _developer: CheckBox
var _profanity: CheckBox
var _merged: CheckBox
var _voice: CheckBox
var _intonation: CheckBox
var _engine: OptionButton
var _tts_model_label: Label
var _tts_model: OptionButton
var _tts_auto: CheckBox
var _tts_note: Label
var _chirp_key: TextEdit
var _chirp_label: Label
var _chirp_hint: Label
var _voice_status: Label
var _mic: CheckBox
var _mic_mode: OptionButton
var _stt_choice: OptionButton
var _model_status: Label
var _model_progress: ProgressBar
var _cancel_model: Button
var _downloader: ModelDownload
var _pause: HSlider
var _pause_value: Label
var _voice_busy: bool = false
var _status: Label
var _show: Button
var _testing: bool = false


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var margin := MarginContainer.new()
	UiWidgets.fill(margin)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var scroll_box := VBoxContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(UiWidgets.scrolling(scroll_box))
	scroll_box.add_child(UiWidgets.label(UiStrings.SETTINGS))
	var hint := UiWidgets.label("", "KeyHint")
	hint.add_theme_color_override("font_color", NoirTheme.MUTED)
	hint.visible = explain_key
	hint.text = UiStrings.KEY_HINT
	scroll_box.add_child(hint)
	scroll_box.add_child(UiWidgets.label(UiStrings.KEY_LABEL))
	var key_row := HBoxContainer.new()
	scroll_box.add_child(key_row)
	_key = LineEdit.new()
	_key.name = "KeyField"
	_key.secret = true
	_key.secret_character = "•"
	_key.custom_minimum_size = Vector2(0, 48)
	_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_row.add_child(_key)
	_show = UiWidgets.button(UiStrings.SHOW_KEY, "ShowKeyButton")
	_show.pressed.connect(_toggle_key)
	key_row.add_child(_show)
	var test := UiWidgets.button(UiStrings.TEST_LINK, "TestConnectionButton")
	test.pressed.connect(_test_connection)
	scroll_box.add_child(test)
	scroll_box.add_child(UiWidgets.label(UiStrings.MODEL_LABEL))
	_model = OptionButton.new()
	_model.name = "ModelField"
	_model.custom_minimum_size = Vector2(0, 48)
	for model_id in LLMConfig.DIALOGUE_MODELS:
		_model.add_item(model_id)
	_model.item_selected.connect(_on_model_picked)
	scroll_box.add_child(_model)
	_spend = UiWidgets.label("", "SpendLabel")
	scroll_box.add_child(_spend)
	scroll_box.add_child(UiWidgets.label(UiStrings.SCALE_LABEL))
	_scale = HSlider.new()
	_scale.name = "ScaleSlider"
	_scale.min_value = 0.85
	_scale.max_value = 1.4
	_scale.step = 0.05
	_scale.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_scale)
	_mock = CheckBox.new()
	_mock.name = "MockCheck"
	_mock.text = UiStrings.MOCK_LABEL
	_mock.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_mock)
	_timing = CheckBox.new()
	_timing.name = "TimingDebug"
	_timing.text = UiStrings.TIMING_DEBUG
	_timing.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_timing)
	_developer = CheckBox.new()
	_developer.name = "DeveloperMode"
	_developer.text = UiStrings.DEVELOPER
	_developer.custom_minimum_size = Vector2(0, 48)
	_developer.toggled.connect(_on_developer_toggled)
	scroll_box.add_child(_developer)
	_voice = CheckBox.new()
	_voice.name = "VoiceEnabled"
	_voice.text = UiStrings.VOICE_ENABLED
	_voice.custom_minimum_size = Vector2(0, 48)
	_voice.toggled.connect(_on_voice_toggled)
	scroll_box.add_child(_voice)
	_intonation = CheckBox.new()
	_intonation.name = "ToneEnabled"
	_intonation.text = UiStrings.VOICE_INTONATION
	_intonation.custom_minimum_size = Vector2(0, 48)
	_intonation.toggled.connect(_on_intonation_toggled)
	scroll_box.add_child(_intonation)
	scroll_box.add_child(UiWidgets.label(UiStrings.VOICE_ENGINE))
	_engine = OptionButton.new()
	_engine.name = "VoiceEngine"
	_engine.custom_minimum_size = Vector2(0, 48)
	_engine.add_item(UiStrings.VOICE_SYSTEM)
	_engine.add_item(UiStrings.VOICE_GEMINI)
	_engine.item_selected.connect(_on_engine_picked)
	scroll_box.add_child(_engine)
	_tts_model_label = UiWidgets.label(UiStrings.VOICE_MODEL)
	scroll_box.add_child(_tts_model_label)
	_tts_model = OptionButton.new()
	_tts_model.name = "VoiceModel"
	_tts_model.custom_minimum_size = Vector2(0, 48)
	for model_id in TtsQuota.chain():
		_tts_model.add_item(TtsQuota.label_for(str(model_id)))
	_tts_model.item_selected.connect(_on_tts_model_picked)
	scroll_box.add_child(_tts_model)
	_tts_auto = CheckBox.new()
	_tts_auto.name = "VoiceAuto"
	_tts_auto.text = UiStrings.VOICE_AUTO
	_tts_auto.custom_minimum_size = Vector2(0, 48)
	_tts_auto.toggled.connect(_on_tts_auto_toggled)
	scroll_box.add_child(_tts_auto)
	_chirp_hint = UiWidgets.label(UiStrings.CHIRP_NO_KEY, "ChirpHint")
	_chirp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chirp_hint.add_theme_color_override("font_color", NoirTheme.MUTED)
	scroll_box.add_child(_chirp_hint)
	_chirp_label = UiWidgets.label(UiStrings.CHIRP_KEY)
	scroll_box.add_child(_chirp_label)
	_chirp_key = TextEdit.new()
	_chirp_key.name = "ChirpKeyField"
	_chirp_key.custom_minimum_size = Vector2(0, 96)
	_chirp_key.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_chirp_key.placeholder_text = UiStrings.CHIRP_KEY_HINT
	scroll_box.add_child(_chirp_key)
	_tts_note = UiWidgets.label("", "VoiceModelNote")
	_tts_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tts_note.add_theme_color_override("font_color", NoirTheme.MUTED)
	scroll_box.add_child(_tts_note)
	var voice_check := UiWidgets.button(UiStrings.VOICE_CHECK, "VoiceCheckButton")
	voice_check.pressed.connect(_check_voice)
	scroll_box.add_child(voice_check)
	scroll_box.add_child(UiWidgets.label(GameLanguage.text("dialogue_section")))
	_profanity = CheckBox.new()
	_profanity.name = "ProfanityEnabled"
	_profanity.text = GameLanguage.text("profanity_label")
	_profanity.custom_minimum_size = Vector2(0, 48)
	_profanity.toggled.connect(_on_profanity_toggled)
	scroll_box.add_child(_profanity)
	scroll_box.add_child(UiWidgets.label(UiStrings.MIC_SECTION))
	_mic = CheckBox.new()
	_mic.name = "MicEnabled"
	_mic.text = UiStrings.MIC_ENABLED
	_mic.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_mic)
	_merged = CheckBox.new()
	_merged.name = "MergedStt"
	_merged.text = GameLanguage.text("merged_label")
	_merged.custom_minimum_size = Vector2(0, 48)
	_merged.toggled.connect(_on_merged_toggled)
	scroll_box.add_child(_merged)
	scroll_box.add_child(UiWidgets.label(UiStrings.MIC_MODE))
	_mic_mode = OptionButton.new()
	_mic_mode.name = "MicMode"
	_mic_mode.custom_minimum_size = Vector2(0, 48)
	_mic_mode.add_item(UiStrings.MIC_PUSH)
	_mic_mode.add_item(UiStrings.MIC_HANDS_FREE)
	scroll_box.add_child(_mic_mode)
	scroll_box.add_child(UiWidgets.label(GameLanguage.text("stt_label")))
	_stt_choice = OptionButton.new()
	_stt_choice.name = "SttChoice"
	_stt_choice.custom_minimum_size = Vector2(0, 48)
	_stt_choice.add_item(GameLanguage.text("stt_cloud"))
	_stt_choice.add_item(GameLanguage.text("stt_device"))
	scroll_box.add_child(_stt_choice)
	var license := UiWidgets.label(GameLanguage.text("model_license"), "ModelLicense")
	license.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	license.add_theme_color_override("font_color", NoirTheme.MUTED)
	scroll_box.add_child(license)
	var wifi := UiWidgets.label(GameLanguage.text("model_wifi"), "ModelWifi")
	wifi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll_box.add_child(wifi)
	var download := UiWidgets.button(GameLanguage.text("model_download"), "DownloadModelButton")
	download.pressed.connect(_download_model)
	scroll_box.add_child(download)
	_model_progress = ProgressBar.new()
	_model_progress.name = "ModelProgress"
	_model_progress.min_value = 0
	_model_progress.max_value = 1
	_model_progress.value = 0
	_model_progress.show_percentage = false
	_model_progress.visible = false
	scroll_box.add_child(_model_progress)
	_cancel_model = UiWidgets.button(GameLanguage.text("model_cancel"), "CancelModelButton")
	_cancel_model.visible = false
	_cancel_model.pressed.connect(_cancel_model_download)
	scroll_box.add_child(_cancel_model)
	var delete_model := UiWidgets.button(GameLanguage.text("model_delete"), "DeleteModelButton")
	delete_model.pressed.connect(_delete_model)
	scroll_box.add_child(delete_model)
	_model_status = UiWidgets.label("", "ModelStatus")
	_model_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll_box.add_child(_model_status)
	_downloader = ModelDownload.new()
	_downloader.name = "ModelDownload"
	_downloader.progress_changed.connect(_on_model_progress)
	_downloader.state_changed.connect(_on_model_state)
	add_child(_downloader)
	scroll_box.add_child(UiWidgets.label(UiStrings.MIC_PAUSE_LABEL))
	_pause = HSlider.new()
	_pause.name = "PauseSlider"
	_pause.min_value = 400
	_pause.max_value = 2000
	_pause.step = 50
	_pause.value = 700
	_pause.custom_minimum_size = Vector2(0, 48)
	_pause.value_changed.connect(_on_pause_changed)
	scroll_box.add_child(_pause)
	_pause_value = UiWidgets.label("700 мс", "PauseValue")
	scroll_box.add_child(_pause_value)
	var play_last := UiWidgets.button(UiStrings.MIC_PLAY_LAST, "PlayLastMicButton")
	play_last.pressed.connect(_play_last_recording)
	scroll_box.add_child(play_last)
	_voice_status = UiWidgets.label("", "VoiceStatusLabel")
	_voice_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_status.add_theme_color_override("font_color", NoirTheme.MUTED)
	scroll_box.add_child(_voice_status)
	var mic_diag := UiWidgets.label("", "MicDiagLabel")
	mic_diag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mic_diag.add_theme_color_override("font_color", NoirTheme.MUTED)
	mic_diag.text = "\n".join(MicInput.status_lines())
	scroll_box.add_child(mic_diag)
	var turn_log := UiWidgets.label("", "TurnLogLabel")
	turn_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_log.add_theme_color_override("font_color", NoirTheme.MUTED)
	turn_log.text = "\n".join(TurnTiming.lines())
	scroll_box.add_child(turn_log)
	var voice_log := UiWidgets.label("", "VoiceLogLabel")
	voice_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voice_log.add_theme_color_override("font_color", NoirTheme.MUTED)
	scroll_box.add_child(voice_log)
	voice_log.text = "\n".join(Speaker.voice_log)
	if not Speaker.voice_log_changed.is_connected(_show_voice_log):
		Speaker.voice_log_changed.connect(_show_voice_log.bind(voice_log, mic_diag))
	if not Speaker.turn_log_changed.is_connected(_show_turn_log):
		Speaker.turn_log_changed.connect(_show_turn_log.bind(turn_log))
	_status = UiWidgets.label("", "StatusLabel")
	scroll_box.add_child(_status)
	var save := UiWidgets.button(UiStrings.SAVE, "SaveButton")
	save.pressed.connect(_save)
	scroll_box.add_child(save)
	var back := UiWidgets.button(UiStrings.BACK, "BackButton")
	back.pressed.connect(func() -> void: back_pressed.emit())
	scroll_box.add_child(back)
	_load_fields()


func _load_fields() -> void:
	var store := SettingsStore.load_current()
	_key.placeholder_text = UiStrings.KEY_SAVED_PLACEHOLDER if store.api_key != "" else UiStrings.KEY_PLACEHOLDER
	_key.text = ""
	_loading = true
	_model.select(_model_index(store.dialogue_model))
	_voice.button_pressed = store.voice_enabled
	_intonation.button_pressed = store.voice_intonation
	_mic.button_pressed = store.mic_enabled
	_mic_mode.select(1 if store.mic_mode == "hands_free" else 0)
	_stt_choice.select(1 if store.stt_backend == "parakeet" else 0)
	_refresh_model_status()
	_pause.value = store.mic_pause_ms
	_pause_value.text = "%d мс" % store.mic_pause_ms
	_engine.select(1 if store.voice_engine == "gemini" else 0)
	_tts_model.select(_tts_model_index(store.tts_model))
	_tts_auto.button_pressed = store.tts_auto
	_chirp_key.placeholder_text = UiStrings.KEY_SAVED_PLACEHOLDER if store.chirp_key != "" else UiStrings.CHIRP_KEY_HINT
	_chirp_key.text = ""
	_refresh_tts_panel()
	_show_chirp_key_state()
	_loading = false
	_spend.text = _spend_text()
	_scale.value = store.text_scale
	_mock.button_pressed = store.provider == "mock"
	_timing.button_pressed = store.timing_debug
	_developer.button_pressed = store.developer
	_profanity.button_pressed = store.profanity
	_merged.button_pressed = store.mic_merged
	_merged.visible = store.developer


func _stt_value() -> String:
	if _stt_choice != null and _stt_choice.selected == 1:
		return "parakeet"
	return "gemini"


func _download_model() -> void:
	_model_status.text = GameLanguage.text("model_wifi")
	_cancel_model.visible = true
	_model_progress.visible = true
	await _downloader.start()


func _cancel_model_download() -> void:
	if _downloader != null:
		_downloader.cancel()


func _delete_model() -> void:
	if _downloader != null:
		_downloader.cancel()
	ModelDownload.delete_all()
	_refresh_model_status()


func _refresh_model_status() -> void:
	if _model_status == null:
		return
	if LocalStt.last_reason == "load_failed" or LocalStt.last_reason == "no_native" or LocalStt.last_reason == "crash":
		_model_status.text = GameLanguage.text("model_load_failed")
	elif ModelDownload.is_installed():
		_model_status.text = GameLanguage.text("model_ready")
	else:
		_model_status.text = ""


func _on_model_progress(received: int, total: int) -> void:
	if _model_progress == null:
		return
	_model_progress.max_value = maxi(total, 1)
	_model_progress.value = received


func _on_model_state(status: String, detail: String) -> void:
	var active := status == "running"
	if _cancel_model != null:
		_cancel_model.visible = active
	if _model_progress != null:
		_model_progress.visible = active
	if _model_status == null:
		return
	if detail != "":
		_model_status.text = detail
	elif status == "ready":
		_model_status.text = GameLanguage.text("model_ready")


func _on_pause_changed(value: float) -> void:
	if _pause_value != null:
		_pause_value.text = "%d мс" % int(value)


func _toggle_key() -> void:
	if _key.secret:
		if _key.text == "":
			_key.text = SettingsStore.load_current().api_key
		_key.secret = false
		_show.text = UiStrings.HIDE_KEY
	else:
		_key.secret = true
		_show.text = UiStrings.SHOW_KEY


func _on_profanity_toggled(pressed: bool) -> void:
	if _loading:
		return
	SettingsStore.save_value("dialogue", "profanity", pressed)


func _on_merged_toggled(pressed: bool) -> void:
	if _loading:
		return
	SettingsStore.save_value("mic", "merged", pressed)


func _on_developer_toggled(pressed: bool) -> void:
	if _merged != null:
		_merged.visible = pressed
	if _loading:
		return
	var previous := SettingsStore.load_current()
	var provider := "mock" if _mock.button_pressed else previous.provider
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, null, null, null, null, null, null, null, null, null, null, null, pressed)


func _save() -> void:
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, _voice.button_pressed, _engine_value(), _intonation.button_pressed, _mic.button_pressed, "hands_free" if _mic_mode.selected == 1 else "push_to_talk", _stt_value(), false, _tts_model_value(), _tts_auto.button_pressed, _chirp_key_value(), int(_pause.value), _developer.button_pressed)
	Speaker.apply_settings()
	_key.text = ""
	_key.secret = true
	_show.text = UiStrings.SHOW_KEY
	_load_fields()
	_status.text = UiStrings.SAVED
	saved.emit()


func _test_connection() -> void:
	if _testing:
		return
	_testing = true
	_status.text = UiStrings.CHECKING
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	if provider != "mock" and key == "":
		_status.text = UiStrings.LINK_NEED_KEY
		_testing = false
		return
	var model := _selected_model()
	SettingsStore.save_values(provider, key, model, _scale.value)
	LLM.reload_client()
	var message := UiStrings.LINK_MOCK
	if provider != "mock":
		var result: Dictionary = await LLM.client.generate(_ping_request())
		message = UiStrings.connection_message(provider, result)
		message = _without_secret(message, key)
	_status.text = message
	_testing = false


func _ping_timeout() -> float:
	if LLM.client is GeminiClient:
		return (LLM.client as GeminiClient).ping_timeout_s
	return 32.0


func _ping_request() -> Dictionary:
	return {
		"system": "Верни короткий JSON.",
		"user": "ping",
		"probe": true,
		"timeout_s": _ping_timeout(),
		"temperature": 0.0,
		"max_output_tokens": 64,
		"schema": {
			"type": "object",
			"properties": {"ok": {"type": "string"}},
			"required": ["ok"],
		},
	}


func _show_voice_log(label: Label, mic_diag: Label) -> void:
	if label != null and is_instance_valid(label):
		label.text = "\n".join(Speaker.voice_log)
	if mic_diag != null and is_instance_valid(mic_diag):
		mic_diag.text = "\n".join(MicInput.status_lines())


func _show_turn_log(label: Label) -> void:
	if label != null and is_instance_valid(label):
		label.text = "\n".join(Speaker.turn_log)


func _check_voice() -> void:
	if _voice_busy:
		return
	_voice_busy = true
	_voice_status.text = UiStrings.CHECKING
	var line: String = await Speaker.speak_test()
	var chirp := SettingsStore.load_current().chirp_key
	if chirp != "" and _engine_value() == "gemini":
		var auth: Dictionary = await ChirpAuth.access_token(self)
		var note := str(auth.get("message", "Ключ Chirp принят")) if not auth.get("ok", false) else "Ключ Chirp принят"
		line = "%s\n%s" % [line, note]
	_voice_status.text = line
	_voice_busy = false


func _on_voice_toggled(pressed: bool) -> void:
	if _loading:
		return
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, pressed, _engine_value())
	Speaker.apply_settings()


func _on_intonation_toggled(pressed: bool) -> void:
	if _loading:
		return
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, _voice.button_pressed, _engine_value(), pressed)


func _on_engine_picked(_index: int) -> void:
	if _loading:
		return
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, _voice.button_pressed, _engine_value(), null, null, null, null, null, _tts_model_value(), _tts_auto.button_pressed)
	_refresh_tts_panel()
	Speaker.apply_settings()


func _on_tts_model_picked(_index: int) -> void:
	if _loading:
		return
	_save_tts_choice()


func _on_tts_auto_toggled(_pressed: bool) -> void:
	if _loading:
		return
	_save_tts_choice()


func _save_tts_choice() -> void:
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, _voice.button_pressed, _engine_value(), _intonation.button_pressed, _mic.button_pressed, null, _stt_value(), false, _tts_model_value(), _tts_auto.button_pressed, _chirp_key_value())
	_refresh_tts_panel()
	_show_chirp_key_state()
	Speaker.apply_settings()


func _refresh_tts_panel() -> void:
	var google := _engine_value() == "gemini"
	_tts_model_label.visible = google
	_tts_model.visible = google
	_tts_auto.visible = google
	_tts_note.visible = google
	_chirp_key.visible = google
	_chirp_label.visible = google
	_chirp_hint.visible = google and not TtsQuota.chirp_ready()
	_tts_note.text = TtsQuota.status_line(TtsQuota.now_unix()) if google else ""
	var chirp_index := TtsQuota.chain().find(ChirpVoices.MODEL_ID)
	if chirp_index >= 0:
		var blocked := not TtsQuota.chirp_ready()
		_tts_model.set_item_disabled(chirp_index, blocked)
		if blocked and _tts_model.selected == chirp_index:
			_tts_model.select(0)


func _chirp_key_value():
	var typed := _chirp_key.text.strip_edges()
	if typed == "":
		return null
	return typed


func _show_chirp_key_state() -> void:
	var parsed := ChirpAuth.parse(SettingsStore.load_current().chirp_key)
	if SettingsStore.load_current().chirp_key == "":
		_chirp_hint.text = UiStrings.CHIRP_NO_KEY
		return
	_chirp_hint.text = str(parsed.get("message", "Ключ Chirp принят")) if not parsed.get("ok", false) else "Ключ Chirp принят"
	_chirp_hint.visible = _engine_value() == "gemini"
	if parsed.get("ok", false):
		_chirp_key.text = ""
		_chirp_key.placeholder_text = UiStrings.KEY_SAVED_PLACEHOLDER


func _tts_model_value() -> String:
	var index := _tts_model.selected
	if index < 0 or index >= TtsQuota.chain().size():
		return TtsQuota.chain()[0]
	return TtsQuota.chain()[index]


func _tts_model_index(model: String) -> int:
	var index := TtsQuota.chain().find(model)
	return index if index >= 0 else 0


func _engine_value() -> String:
	return "gemini" if _engine.selected == 1 else "system"


func _selected_model() -> String:
	var index := _model.selected
	if index < 0 or index >= LLMConfig.DIALOGUE_MODELS.size():
		return LLMConfig.DEFAULT_DIALOGUE_MODEL
	return LLMConfig.DIALOGUE_MODELS[index]


func _model_index(model: String) -> int:
	var canonical := LLMConfig.canonical_model(model)
	var index := LLMConfig.DIALOGUE_MODELS.find(canonical)
	return index if index >= 0 else 0


func _on_model_picked(_index: int) -> void:
	if _loading:
		return
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed)
	LLM.reload_client()
	_spend.text = _spend_text()


func _play_last_recording() -> void:
	if not FileAccess.file_exists("user://mic-last.wav"):
		_status.text = UiStrings.MIC_NO_CLIP
		return
	var bytes := FileAccess.get_file_as_bytes("user://mic-last.wav")
	if bytes.size() <= 44:
		_status.text = UiStrings.MIC_NO_CLIP
		return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = VoiceAudio.UPLOAD_RATE
	stream.stereo = false
	stream.data = bytes.slice(44)
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _spend_text() -> String:
	return "%s: сессия %s · всего %s\n%s: сессия %s · всего %s\nChirp: %d симв. в этом месяце · 1 млн бесплатно" % [
		UiStrings.SPEND_LABEL,
		SpendMeter.format_usd(SpendMeter.session_usd),
		SpendMeter.format_usd(SpendMeter.total_usd()),
		UiStrings.SPEND_STT,
		SpendMeter.format_usd(SpendMeter.session_stt_usd),
		SpendMeter.format_usd(SpendMeter.stt_total_usd()),
		SpendMeter.chirp_chars_this_month(),
	]


func _without_secret(text: String, secret: String) -> String:
	var clean := secret.strip_edges()
	if clean == "":
		return text
	return text.replace(clean, "")
