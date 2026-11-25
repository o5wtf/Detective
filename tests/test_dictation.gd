extends TestCase

const FIXTURE := "res://tests/fixtures/turn_flow.json"
const CLIP := "res://tests/fixtures/dictation.wav"


func test_wav_header_and_resample() -> void:
	var pcm := VoiceAudio.tone(160, 1000)
	var wav := VoiceAudio.wav_bytes(pcm, 16000)
	assert_eq(wav.slice(0, 4).get_string_from_ascii(), "RIFF")
	assert_eq(wav.slice(8, 12).get_string_from_ascii(), "WAVE")
	assert_eq(wav.decode_u32(24), 16000)
	assert_eq(wav.decode_u32(40), pcm.size())
	var fast := VoiceAudio.tone(480, 2000)
	var slow := VoiceAudio.resample(fast, 48000, 16000)
	assert_eq(slow.size() / 2, 160)
	var stereo := PackedByteArray()
	stereo.resize(8)
	VoiceAudio.put_sample(stereo, 0, 1000)
	VoiceAudio.put_sample(stereo, 1, -1000)
	var single := VoiceAudio.mono(stereo, true)
	assert_eq(single.size(), 4)
	assert_eq(VoiceAudio.sample_at(single, 0), 1000)


func test_preroll_keeps_three_hundred_milliseconds() -> void:
	var clip := MicClip.new()
	clip.push_preroll(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE * 2, 1500))
	assert_eq(clip.preroll.size(), int(16000 * 0.3) * 2)


func test_short_tap_and_quiet_clip_are_discarded() -> void:
	var talk := _talk()
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(int(VoiceAudio.UPLOAD_RATE * 0.1), 4000))
	var tapped: Dictionary = await talk.release(false)
	assert_eq(str(tapped.get("action", "")), "discard")
	assert_eq(str(tapped.get("reason", "")), "tap")
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 0))
	var quiet: Dictionary = await talk.release(false)
	assert_eq(str(quiet.get("action", "")), "discard")
	assert_eq(str(quiet.get("reason", "")), "quiet")
	assert_eq((_scripted(talk) as ScriptedStt).calls, 0)
	talk.free()


func test_sixty_seconds_sends_audio_with_preroll() -> void:
	var talk := _talk()
	var head := VoiceAudio.tone(int(VoiceAudio.UPLOAD_RATE * 0.3), 2500)
	talk.push_pcm(head)
	assert_true(talk.press())
	var kind := talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE * 60, 2500))
	assert_eq(kind, "limit")
	await talk.release(true)
	assert_true(talk.last_wav.size() > 44 + head.size())
	assert_eq(talk.last_wav.slice(0, 4).get_string_from_ascii(), "RIFF")
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	talk.free()


func test_tail_audio_is_kept_and_cancel_drops_it() -> void:
	var talk := _talk()
	assert_true(talk.press())
	var hold := VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000)
	talk.push_pcm(hold)
	talk._queued_tail = VoiceAudio.tone(int(float(VoiceAudio.UPLOAD_RATE) * 0.2), 5000)
	var decision: Dictionary = await talk.release(false)
	assert_eq(str(decision.get("action", "")), "send")
	assert_true(talk.last_wav.size() > 44 + hold.size())
	assert_eq((_scripted(talk) as ScriptedStt).calls, 1)
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	talk.call_deferred("cancel")
	await talk.release(false)
	assert_eq((_scripted(talk) as ScriptedStt).calls, 1)
	talk.free()


func test_junk_filter_blocks_empty_punctuation_and_markers() -> void:
	assert_true(SpeechJunk.is_junk(""))
	assert_true(SpeechJunk.is_junk("  ...?! "))
	assert_true(SpeechJunk.is_junk("[music]"))
	assert_true(SpeechJunk.is_junk("неразборчиво"))
	assert_false(SpeechJunk.is_junk("Где вы были?"))
	assert_true(SpeechJunk.is_junk("00:00"))
	assert_true(SpeechJunk.is_junk("1:10"))
	assert_true(SpeechJunk.is_junk("12"))
	assert_true(SpeechJunk.is_junk("—"))
	assert_false(SpeechJunk.is_junk("Где вы были в 1:10?"))
	assert_false(SpeechJunk.is_junk("Да"))
	var talk := _talk()
	(_scripted(talk) as ScriptedStt).payload = {"ok": true, "text": "...", "error": "", "usage": {}}
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_eq(sent.size(), 0)
	assert_false(talk.locked)
	talk.free()


func test_turn_lock_releases_on_success_error_cancel_and_hide() -> void:
	var talk := _talk()
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
		assert_true(talk.locked)
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_eq(sent, ["Где вы были?"])
	assert_false(talk.locked)
	(_scripted(talk) as ScriptedStt).payload = {"ok": false, "text": "", "error": "bad_response", "usage": {}}
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	(_scripted(talk) as ScriptedStt).cancel_target = talk
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_false(talk.locked)
	assert_eq(sent.size(), 1)
	(_scripted(talk) as ScriptedStt).cancel_target = null
	assert_true(talk.press())
	talk.screen_active = false
	assert_eq(talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000)), "hidden")
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	talk.free()


func test_retry_resends_the_same_audio() -> void:
	var talk := _talk()
	var fake := _scripted(talk) as ScriptedStt
	fake.payload = {"ok": false, "text": "", "error": "offline", "usage": {}}
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	var first := talk.last_wav.duplicate()
	fake.payload = {"ok": true, "text": "Где вы были?", "error": "", "usage": {}}
	await talk.retry()
	assert_eq(fake.calls, 2)
	assert_eq(fake.last_wav, first)
	assert_eq(sent, ["Где вы были?"])
	assert_false(talk.locked)
	talk.free()


func test_stt_body_has_audio_and_no_key() -> void:
	var wav := FileAccess.get_file_as_bytes(CLIP)
	var secret := "sk-test-secret-not-in-body"
	var body := GeminiStt.build_body(wav, "MINIMAL")
	var encoded := JSON.stringify(body)
	assert_true(encoded.contains("audio/wav"))
	assert_true(encoded.contains(GameLanguage.text("stt_prompt")))
	assert_true(encoded.contains("MINIMAL"))
	assert_false(encoded.contains(secret))
	assert_false(encoded.contains("x-goog-api-key"))
	var recognizer := GeminiStt.new()
	recognizer.api_key = secret
	recognizer._log(200, JSON.stringify({"usageMetadata": {"promptTokenCount": 3, "candidatesTokenCount": 1}}))
	assert_false(recognizer.api_key.is_empty())


func test_settings_migration_adds_push_to_talk() -> void:
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var file := ConfigFile.new()
	file.parse(previous)
	file.set_value("llm", "settings_version", 5)
	if file.has_section_key("mic", "enabled"):
		file.erase_section_key("mic", "enabled")
	if file.has_section_key("mic", "mode"):
		file.erase_section_key("mic", "mode")
	file.save(path)
	var loaded := SettingsStore.load_current()
	assert_false(loaded.mic_enabled)
	assert_eq(loaded.mic_mode, "push_to_talk")
	var check := ConfigFile.new()
	assert_eq(check.load(path), OK)
	assert_eq(int(check.get_value("llm", "settings_version", 0)), LLMConfig.SETTINGS_VERSION)
	assert_eq(str(check.get_value("mic", "mode", "")), "push_to_talk")
	assert_eq(str(check.get_value("mic", "stt", "")), "gemini")
	assert_false(check.has_section_key("mic", "stt_offline"))
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()


func test_stt_spend_is_a_separate_line() -> void:
	var previous_path := SpendMeter.store_path
	var previous_session := SpendMeter.session_usd
	var previous_stt := SpendMeter.session_stt_usd
	SpendMeter.store_path = "user://spend-stt-test.cfg"
	SpendMeter.session_usd = 0.0
	SpendMeter.session_stt_usd = 0.0
	SpendMeter.note_stt("gemini-3.5-flash-lite", 1000000, 1000)
	assert_true(SpendMeter.session_stt_usd > 0.0)
	assert_true(SpendMeter.stt_total_usd() > 0.0)
	assert_true(SpendMeter.session_usd >= SpendMeter.session_stt_usd)
	DirAccess.remove_absolute("user://spend-stt-test.cfg")
	SpendMeter.store_path = previous_path
	SpendMeter.session_usd = previous_session
	SpendMeter.session_stt_usd = previous_stt


func test_async_stt_success_releases_lock_and_sends() -> void:
	var talk := _talk_delayed()
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_eq(sent, ["Где вы были?"])
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	talk.free()


func test_async_stt_error_shows_retry_and_releases_lock() -> void:
	var talk := _talk_delayed()
	var fake := talk.stt as DelayedStt
	fake.payload = {"ok": false, "text": "", "error": "bad_response", "usage": {}}
	var shown: Array[bool] = []
	talk.retry_visible.connect(func(show_button: bool) -> void: shown.append(show_button))
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	assert_eq(shown[shown.size() - 1], true)
	talk.free()


func test_async_stt_junk_releases_lock_without_sending() -> void:
	var talk := _talk_delayed()
	var fake := talk.stt as DelayedStt
	fake.payload = {"ok": true, "text": "...", "error": "", "usage": {}}
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_eq(sent.size(), 0)
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	talk.free()


func test_async_stt_screen_exit_discards_late_result() -> void:
	var talk := _talk_delayed()
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	(talk.stt as DelayedStt).began.connect(func() -> void:
		talk.screen_active = false
	, CONNECT_ONE_SHOT)
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_eq(sent.size(), 0)
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	talk.free()


func test_async_stt_retry_sends_after_delay() -> void:
	var talk := _talk_delayed()
	var fake := talk.stt as DelayedStt
	fake.payload = {"ok": false, "text": "", "error": "offline", "usage": {}}
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	assert_true(talk.press())
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 4000))
	await talk.release(false)
	assert_false(talk.locked)
	var first := talk.last_wav.duplicate()
	fake.payload = {"ok": true, "text": "Где вы были?", "error": "", "usage": {}}
	await talk.retry()
	assert_eq(fake.calls, 2)
	assert_eq(fake.last_wav, first)
	assert_eq(sent, ["Где вы были?"])
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	talk.free()


func test_fixture_wav_becomes_a_character_turn() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var screen := (load("res://ui/screens/interrogation.gd") as GDScript).new() as Control
	_attach(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var mock := _use_mock()
	mock.enqueue(_reply("k1", "lie", "Я держусь своей версии."))
	screen.agent_id = "a"
	var fake := ScriptedStt.new()
	fake.payload = {"ok": true, "text": "Где вы были?", "error": "", "usage": {}}
	screen._talk.stt = fake
	screen._talk.enabled = true
	screen._talk.screen_active = true
	var pcm := FileAccess.get_file_as_bytes(CLIP).slice(44)
	assert_true(screen._talk.press())
	screen._talk.push_pcm(pcm)
	await screen._talk.release(false)
	assert_eq(fake.calls, 1)
	assert_true(fake.last_wav.slice(0, 4).get_string_from_ascii() == "RIFF")
	assert_false(screen._talk.locked)
	assert_false(Game.is_busy)
	var rows: Array = screen._feeds["a"]
	assert_eq(str(rows[0].get("kind", "")), "player")
	assert_eq(str(rows[0].get("text", "")), "Где вы были?")
	var dialogue: DialogueState = Game._dialogues["a"]
	assert_eq(str(dialogue.messages[0].get("role", "")), "player")
	assert_eq(str(dialogue.messages[0].get("text", "")), "Где вы были?")
	assert_true(_heard("a", "fa", "lie"))
	screen.free()
	if LLM.client == mock:
		LLM.client = null
	mock.free()


func _talk_delayed() -> PushToTalk:
	var talk := PushToTalk.new()
	var fake := DelayedStt.new()
	talk.stt = fake
	talk.enabled = true
	talk.screen_active = true
	_attach(talk)
	talk.add_child(fake)
	return talk


func _talk() -> PushToTalk:
	var talk := PushToTalk.new()
	var fake := ScriptedStt.new()
	talk.stt = fake
	talk.enabled = true
	talk.screen_active = true
	_attach(talk)
	return talk


func _attach(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


func _scripted(talk: PushToTalk) -> ScriptedStt:
	return talk.stt as ScriptedStt


func _boot() -> bool:
	return Game.open_case(FIXTURE).ok


func _use_mock() -> MockLLMClient:
	var mock := MockLLMClient.new()
	LLM.add_child(mock)
	LLM.client = mock
	return mock


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


func _heard(agent_id: String, fact_id: String, form: String) -> bool:
	for row in Game.state.heard:
		if str(row["agent_id"]) == agent_id and str(row["fact_id"]) == fact_id and str(row["form"]) == form:
			return true
	return false


class DelayedStt:
	extends SttBackend

	signal began

	var payload: Dictionary = {"ok": true, "text": "Где вы были?", "error": "", "usage": {}}
	var calls: int = 0
	var last_wav: PackedByteArray = PackedByteArray()
	var frames: int = 2

	func transcribe(wav: PackedByteArray) -> Dictionary:
		calls += 1
		last_wav = wav
		began.emit()
		var tree := Engine.get_main_loop() as SceneTree
		for _index in frames:
			await tree.process_frame
		return payload


class ScriptedStt:
	extends SttBackend

	var payload: Dictionary = {"ok": true, "text": "Где вы были?", "error": "", "usage": {}}
	var calls: int = 0
	var last_wav: PackedByteArray = PackedByteArray()
	var cancel_target: PushToTalk

	func transcribe(wav: PackedByteArray) -> Dictionary:
		calls += 1
		last_wav = wav
		if cancel_target != null:
			cancel_target.cancel()
		return payload
