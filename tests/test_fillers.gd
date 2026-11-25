extends TestCase

const HASHES := {
	"assets/voice/fillers/aoede/hm.wav": "aa0b49c2e7e6d8a6aeefb1c2af1a1d29c839f2ec73c6ef900454007ac0712d21",
	"assets/voice/fillers/aoede/nu.wav": "81c9b8f5a279744aa03e52960e4663512b78bee5310df3113700f7b4dfa329f7",
	"assets/voice/fillers/aoede/sekundu.wav": "1154272c2688218c545197412a5b2ff88c8343f596c83da51feb351e44e25458",
	"assets/voice/fillers/charon/hm.wav": "966eb055992eada895a3d4f8c6daa0b2cf22d100f0e10909940f8b21361c76d3",
	"assets/voice/fillers/charon/nu.wav": "3bd21d7190f8a56c5536aa7e7a267c72dc5c5fff4fa2025e7f9ddb6ec8f5e0c8",
	"assets/voice/fillers/charon/sekundu.wav": "315f9fdc92bb9e22c86c6411f11ccbffea80dec5aa2ce977d8466dd2eab95c4c",
	"assets/voice/fillers/fenrir/hm.wav": "2181742cedd308ea07bf3699ead3725792c6695bceea6cfd0f6562c24dd8df66",
	"assets/voice/fillers/fenrir/nu.wav": "9d8ada537bf63de114241a9c9fb7d91fc88b6c28445eb484b2bdea6769519db0",
	"assets/voice/fillers/fenrir/sekundu.wav": "2fe94d015e20261db5c51e3c4c9abcf4758098a4e7a97a7cbb84e013795dd45f",
	"assets/voice/fillers/kore/hm.wav": "964999b47c0b6e16b2005096cff5dbf76760b281f3348f271765193d23c3f5f0",
	"assets/voice/fillers/kore/nu.wav": "f5f8d1fd1d90bce9203659bfda3d594da7ba01aecd4d8b63556f8fc7efc53823",
	"assets/voice/fillers/kore/sekundu.wav": "7ecca41b350d194550886c6da99caac5d673306afa1d06f7112687470526ac02",
	"assets/voice/fillers/leda/hm.wav": "3698dffc99a122d28d7f4337af8fe8011c5999b71df890805377c2a85069f921",
	"assets/voice/fillers/leda/nu.wav": "2b1199aabb28200902dda44fde7b11e24743905387b09e89c7f63e7fbecd434b",
	"assets/voice/fillers/leda/sekundu.wav": "a3be929e1a0544bee0481278e891d832eb189b63b8772d64d788d4d7ca000aaf",
	"assets/voice/fillers/orus/hm.wav": "cb0d667439804dab7e3a9b868ebe45d9ce82f34c8ca194f2d6d73bd67cd8cc5b",
	"assets/voice/fillers/orus/nu.wav": "f8d02332e17da5f0af83bbde1713890fff07d2f259574340dbe53efac9bbb957",
	"assets/voice/fillers/orus/sekundu.wav": "5077f7dae3d7064a685fbcede366c844eb41086588a56d537b1714a7d3f0a7c1",
}


func test_builtin_wavs_match_and_import() -> void:
	assert_eq(HASHES.size(), 18)
	for path in HASHES:
		var res := "res://%s" % path
		assert_true(FileAccess.file_exists(res), res)
		assert_true(ResourceLoader.exists(res), res)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(FileAccess.get_file_as_bytes(res))
		assert_eq(ctx.finish().hex_encode(), str(HASHES[path]), res)
	assert_true(FileAccess.file_exists("res://assets/voice/fillers/README.md"))


func test_lines_rotate_and_custom_replaces_standard() -> void:
	FillerBank.last_line = ""
	var standard := FillerBank.standard_lines()
	assert_eq(standard[0], "Хм…")
	assert_eq(standard[1], "Ну…")
	assert_eq(standard[2], "Секунду…")
	var first := FillerBank.pick(standard)
	var second := FillerBank.pick(standard)
	assert_false(first == second)
	assert_eq(FillerBank.pick(standard) != second, true)
	var agent := CaseData.Agent.new()
	assert_eq(FillerBank.lines_for(agent), standard)
	var blank: Array[String] = ["", "  "]
	agent.filler_lines = blank
	assert_eq(FillerBank.lines_for(agent), standard)
	var custom_lines: Array[String] = ["Раз", "Два", "Три", "Лишняя"]
	agent.filler_lines = custom_lines
	var custom := FillerBank.lines_for(agent)
	assert_eq(custom.size(), 3)
	assert_eq(custom[0], "Раз")
	assert_eq(custom[2], "Три")
	assert_eq(FillerBank.builtin_path("Aoede", "Хм…"), "res://assets/voice/fillers/aoede/hm.wav")
	assert_eq(FillerBank.builtin_path("Aoede", "Раз"), "")
	FillerBank.last_line = ""


func test_fillers_setting_defaults_on_and_survives_save() -> void:
	var path := SettingsStore.PATH
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var file := ConfigFile.new()
	file.load(path)
	if file.has_section_key("voice", "fillers"):
		file.erase_section_key("voice", "fillers")
		file.save(path)
	SettingsStore.invalidate_cache()
	assert_true(SettingsStore.load_current().fillers)
	SettingsStore.save_value("voice", "fillers", false)
	assert_false(SettingsStore.load_current().fillers)
	SettingsStore.save_values("mock", "cache-marker", "gemini-3.5-flash-lite", 1.0)
	assert_false(SettingsStore.load_current().fillers)
	_restore_config(previous)


func test_fast_reply_skips_filler_and_a_slow_one_plays_builtin() -> void:
	var previous := _remember_config()
	_voice("gemini", "gemini-3.8-flash-lite-tts", true, true)
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	FillerBank.delay_ms = 0
	FillerBank.last_line = ""
	Speaker.stop_filler()
	Speaker.arm_filler("mira_belova")
	Speaker.stop_filler()
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(Speaker.filler_line, "")
	Speaker.arm_filler("mira_belova")
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(Speaker.filler_line, "Хм…")
	assert_true(Speaker.filler_playing or Speaker.filler_line == "Хм…")
	Speaker.enabled = false
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/interrogation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	screen.open_agent("mira_belova")
	var blob := ""
	for row in screen._feeds["mira_belova"]:
		blob += str(row.get("text", ""))
	assert_false(blob.contains("Хм…"))
	var before: int = screen._feed_box.get_child_count()
	screen._show_player_placeholder()
	assert_eq(screen._feed_box.get_child_count(), before + 1)
	assert_true(screen._replace_placeholder("mira_belova", "Где вы были?"))
	assert_eq(screen._feed_box.get_child_count(), before + 1)
	Game._drop_turn()
	assert_false(Speaker.filler_playing)
	screen.free()
	FillerBank.delay_ms = -1
	FillerBank.last_line = ""
	Speaker.stop_filler()
	_restore_config(previous)


func test_system_and_chirp_stay_silent_and_checkbox_is_disabled() -> void:
	var previous := _remember_config()
	_voice("system", "gemini-3.8-flash-lite-tts", true, true)
	assert_false(FillerBank.allowed())
	assert_false(FillerBank.controls_enabled())
	FillerBank.delay_ms = 0
	Speaker.stop_filler()
	Speaker.arm_filler("mira_belova")
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(Speaker.filler_line, "")
	_voice("gemini", "chirp-3-hd", true, true)
	TtsQuota.selected_override = "chirp-3-hd"
	assert_false(FillerBank.allowed())
	assert_false(FillerBank.controls_enabled())
	Speaker.arm_filler("mira_belova")
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(Speaker.filler_line, "")
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/settings.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var box := screen.find_child("FillersEnabled", true, false) as CheckBox
	var note := screen.find_child("FillersNote", true, false) as Label
	assert_true(box.disabled)
	assert_true(note.visible)
	assert_eq(note.text, "Только для голосов Gemini")
	TtsQuota.selected_override = null
	_voice("gemini", "gemini-3.8-flash-lite-tts", true, true)
	screen._load_fields()
	assert_false(box.disabled)
	assert_false(note.visible)
	screen.free()
	FillerBank.delay_ms = -1
	Speaker.stop_filler()
	_restore_config(previous)


func test_unknown_voice_uses_gemini_cache_and_does_not_change_the_turn() -> void:
	var previous := _remember_config()
	var quota_path := TtsQuota.store_path
	var cache_path := TtsCache.root_path
	TtsQuota.store_path = "user://filler-quota.cfg"
	TtsCache.root_path = "user://filler-cache"
	TtsQuota.reset()
	TtsCache.erase_all()
	_voice("gemini", "gemini-3.8-flash-lite-tts", true, true)
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var before := Game.state.to_dict()
	var fetch := _Fetch.new()
	FillerSynth.instant = true
	FillerSynth.pauses.clear()
	var made: Dictionary = await FillerSynth.ensure("Zephyr", "Эх…", false, Callable(fetch, "one"))
	assert_true(made.get("ok", false))
	assert_false(fetch.models.has("chirp-3-hd"))
	assert_eq(Game.state.to_dict(), before)
	var key := TtsCache.key_for(str(fetch.models[0]), "Zephyr", "", "Эх…")
	assert_eq(TtsCache.read(key).size(), 4)
	fetch.models.clear()
	var blocked: Dictionary = await FillerSynth.ensure("Zephyr", "Эх…", true, Callable(fetch, "one"))
	assert_false(blocked.get("ok", false))
	assert_eq(fetch.models.size(), 0)
	fetch.mode = "retry"
	fetch.tries = 0
	FillerSynth.pauses.clear()
	var retried: Dictionary = await FillerSynth.ensure("Zephyr", "Ну да…", false, Callable(fetch, "one"))
	assert_true(retried.get("ok", false))
	assert_eq(fetch.models.size(), 3)
	assert_eq(fetch.models[0], fetch.models[1])
	assert_false(FillerSynth.pauses.is_empty())
	for pause in FillerSynth.pauses:
		assert_true(float(pause) <= 2.0)
	fetch.mode = "daily"
	fetch.tries = 0
	fetch.models.clear()
	var walked: Dictionary = await FillerSynth.ensure("Zephyr", "Ладно…", false, Callable(fetch, "one"))
	assert_true(walked.get("ok", false))
	assert_false(fetch.models.has("chirp-3-hd"))
	assert_true(fetch.models.size() >= 2)
	assert_eq(Game.state.to_dict(), before)
	FillerSynth.instant = false
	FillerSynth.pauses.clear()
	TtsCache.erase_all()
	TtsQuota.reset()
	TtsQuota.store_path = quota_path
	TtsCache.root_path = cache_path
	_restore_config(previous)


func test_filler_waits_until_dialogue_sent_plus_the_delay() -> void:
	var previous := _remember_config()
	_voice("gemini", "gemini-3.8-flash-lite-tts", true, true)
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	FillerBank.delay_ms = 5000
	FillerBank.last_line = ""
	Speaker.stop_filler()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/interrogation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var mock := _Turn.new()
	LLM.add_child(mock)
	var old_client: Variant = LLM.client
	LLM.client = mock
	assert_false(Speaker._filler_waiting)
	await Game.ask("mira_belova", "Где вы были?")
	assert_true(mock.waiting_at_generate)
	assert_true(Speaker._filler_waiting)
	assert_eq(Speaker.filler_line, "")
	Speaker.stop_and_clear()
	assert_eq(Speaker.queue.current_id, "")
	assert_true(Speaker.queue.pending.is_empty())
	FillerBank.delay_ms = 180
	FillerBank.last_line = ""
	var started := Time.get_ticks_msec()
	Speaker.arm_filler("mira_belova")
	await (Engine.get_main_loop() as SceneTree).create_timer(0.08).timeout
	assert_eq(Speaker.filler_line, "")
	assert_true(Speaker._filler_waiting)
	await (Engine.get_main_loop() as SceneTree).create_timer(0.16).timeout
	assert_eq(Speaker.filler_line, "Хм…")
	assert_true(Time.get_ticks_msec() - started >= 180)
	Speaker.stop_filler()
	LLM.client = old_client
	mock.free()
	screen.free()
	FillerBank.delay_ms = -1
	FillerBank.last_line = ""
	_restore_config(previous)


func test_fallback_transcript_uses_the_separate_guard() -> void:
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var closed := ""
	for evidence in Game.case_data.evidence:
		if not Game.state.unlocked_evidence.has(evidence.id):
			closed = evidence.title
			break
	assert_false(closed == "")
	var stt := _Stt.new()
	stt.text = "Я нашёл %s на полу" % closed
	Game.fallback_stt = stt
	var hidden: Dictionary = await Game._fallback_transcript(PackedByteArray([1, 2, 3, 4]), "mira_belova", LlmTiming.empty_tally())
	assert_eq(str(hidden.get("error", "")), "junk")
	var hint := SttHint.for_turn("gemini", Game.case_data, Game.state, "mira_belova", "")
	stt.text = "Место преступления. Кухонный нож. Ночь. Дождь заливает асфальт. В аллее за ночным клубом найден труп."
	var echo: Dictionary = await Game._fallback_transcript(PackedByteArray([1, 2, 3, 4]), "mira_belova", LlmTiming.empty_tally())
	assert_eq(str(echo.get("error", "")), "junk")
	assert_true(SpeechJunk.is_echo(stt.text, PackedStringArray([hint, Game.case_data.briefing])))
	stt.text = "Где вы были вчера вечером?"
	var clean: Dictionary = await Game._fallback_transcript(PackedByteArray([1, 2, 3, 4]), "mira_belova", LlmTiming.empty_tally())
	assert_eq(str(clean.get("text", "")), "Где вы были вчера вечером?")
	Game.fallback_stt = null
	stt.free()


func _voice(engine: String, model: String, enabled: bool, fillers: bool) -> void:
	SettingsStore.save_value("voice", "engine", engine)
	SettingsStore.save_value("voice", "tts_model", model)
	SettingsStore.save_value("voice", "enabled", enabled)
	SettingsStore.save_value("voice", "fillers", fillers)
	SettingsStore.save_value("voice", "tts_auto", true)
	Speaker.apply_settings()


func _remember_config() -> String:
	var path := SettingsStore.PATH
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _restore_config(previous: String) -> void:
	var path := SettingsStore.PATH
	if previous == "":
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()
	SettingsStore.invalidate_cache()
	Speaker.apply_settings()


class _Turn:
	extends LLMClient

	var waiting_at_generate: bool = false

	func generate(_request: Dictionary) -> Dictionary:
		waiting_at_generate = Speaker._filler_waiting
		return {
			"ok": true,
			"json": {
				"player_tone": 0,
				"reply": "Я была дома.",
				"remark": "кивает",
				"emotion": "neutral",
				"stated": [],
				"mentioned_evidence": [],
				"requested_evidence": null,
			},
			"raw_text": "",
			"error": "",
			"retry_after_s": 0.0,
			"message": "",
		}


class _Fetch:
	extends RefCounted

	var models: PackedStringArray = PackedStringArray()
	var mode: String = "ok"
	var tries: int = 0

	func one(model: String, _voice: String, _text: String) -> Dictionary:
		models.append(model)
		tries += 1
		if mode == "retry" and tries < 3:
			return {"ok": false, "error": "rate_limited", "retry_after": 9.0, "pcm": PackedByteArray()}
		if mode == "daily" and model == TtsQuota.chain()[0]:
			return {"ok": false, "error": "quota_daily", "pcm": PackedByteArray()}
		if TtsQuota.is_chirp(model):
			return {"ok": false, "error": "chirp", "pcm": PackedByteArray()}
		return {"ok": true, "error": "", "pcm": PackedByteArray([1, 2, 3, 4])}


class _Stt:
	extends SttBackend

	var text: String = ""

	func transcribe(_wav: PackedByteArray) -> Dictionary:
		return {"ok": true, "text": text, "error": "", "message": ""}
