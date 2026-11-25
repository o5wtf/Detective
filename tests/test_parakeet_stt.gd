extends TestCase


func test_parakeet_choice_survives_save_and_unknown_becomes_gemini() -> void:
	var previous := _keep_config()
	SettingsStore.save_values("mock", "", "gemini-3.5-flash-lite", 1.0, null, null, null, null, null, null, "parakeet")
	var loaded := SettingsStore.load_current()
	assert_eq(loaded.stt_backend, "parakeet")
	var check := ConfigFile.new()
	assert_eq(check.load(SettingsStore.PATH), OK)
	assert_eq(str(check.get_value("mic", "stt", "")), "parakeet")
	SettingsStore.save_values("mock", "", "gemini-3.5-flash-lite", 1.0, null, null, null, null, null, null, "system")
	assert_eq(SettingsStore.load_current().stt_backend, "gemini")
	check = ConfigFile.new()
	assert_eq(check.load(SettingsStore.PATH), OK)
	assert_eq(str(check.get_value("mic", "stt", "")), "gemini")
	check.set_value("mic", "stt", "whisper")
	check.set_value("llm", "settings_version", LLMConfig.SETTINGS_VERSION)
	check.save(SettingsStore.PATH)
	SettingsStore.invalidate_cache()
	assert_eq(SettingsStore.load_current().stt_backend, "gemini")
	check = ConfigFile.new()
	assert_eq(check.load(SettingsStore.PATH), OK)
	assert_eq(str(check.get_value("mic", "stt", "")), "gemini")
	check.set_value("llm", "settings_version", 7)
	check.set_value("mic", "stt", "parakeet")
	check.set_value("mic", "stt_offline", true)
	check.save(SettingsStore.PATH)
	SettingsStore.invalidate_cache()
	assert_eq(SettingsStore.load_current().stt_backend, "parakeet")
	check = ConfigFile.new()
	assert_eq(check.load(SettingsStore.PATH), OK)
	assert_eq(str(check.get_value("mic", "stt", "")), "parakeet")
	assert_false(check.has_section_key("mic", "stt_offline"))
	_restore_config(previous)


func test_settings_screen_saves_parakeet_and_shows_license() -> void:
	begin_async()
	var previous := _keep_config()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/settings.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var choice := screen.find_child("SttChoice", true, false) as OptionButton
	var license := screen.find_child("ModelLicense", true, false) as Label
	assert_true(choice != null)
	assert_true(screen.find_child("DownloadModelButton", true, false) != null)
	assert_true(screen.find_child("DeleteModelButton", true, false) != null)
	assert_true(license != null)
	assert_true(license.text.contains("CC-BY-4.0"))
	assert_true(str((screen.find_child("ModelWifi", true, false) as Label).text).contains("640"))
	choice.select(1)
	screen._save()
	assert_eq(SettingsStore.load_current().stt_backend, "parakeet")
	screen.free()
	_restore_config(previous)
	end_async()


func test_model_table_is_pinned_and_part_is_not_a_model() -> void:
	assert_true(ModelDownload.URL_PREFIX.ends_with(ModelDownload.REVISION))
	assert_eq(ModelDownload.file_url("tokens.txt"), ModelDownload.URL_PREFIX + "/tokens.txt")
	assert_eq(ModelDownload.FILES.size(), 4)
	assert_eq(str(ModelDownload.FILES[0]["sha256"]), "1afbe69c1ffdabee94755f42e4daf1d93549131a3da11356bda84fcef0f2c479")
	assert_eq(int(ModelDownload.FILES[0]["size"]), 652282294)
	assert_eq(str(ModelDownload.FILES[1]["sha256"]), "0222a86147299d4dee90edf95b6d13827edb42ad8b7c9cf0b2582f030937c0b5")
	assert_eq(str(ModelDownload.FILES[2]["sha256"]), "cbd02f3696e9944970111fb439d9c3fd365a80374565f13f2b9c7007d253fc98")
	assert_eq(str(ModelDownload.FILES[3]["sha256"]), "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d")
	assert_eq(int(ModelDownload.FILES[3]["size"]), 93939)
	assert_false(ModelDownload.space_ok(ModelDownload.NEED_FREE - 1))
	assert_true(ModelDownload.space_ok(ModelDownload.NEED_FREE))
	var fresh: Dictionary = ModelDownload.resume_plan(0, true)
	assert_true(bool(fresh["restart"]))
	var restart: Dictionary = ModelDownload.resume_plan(12, false)
	assert_true(bool(restart["restart"]))
	var resume: Dictionary = ModelDownload.resume_plan(12, true)
	assert_false(bool(resume["restart"]))
	assert_eq(str(resume["range"]), "bytes=12-")
	_use_test_dir()
	var part := ModelDownload.part_path("encoder.int8.onnx")
	var handle := FileAccess.open(part, FileAccess.WRITE)
	handle.store_string("partial")
	handle.close()
	assert_false(ModelDownload.is_installed())
	var bad := ModelDownload.commit_part(part, ModelDownload.final_path("encoder.int8.onnx"), "0000000000000000000000000000000000000000000000000000000000000000")
	assert_eq(bad, "bad_hash")
	assert_false(FileAccess.file_exists(part))
	assert_false(FileAccess.file_exists(ModelDownload.final_path("encoder.int8.onnx")))
	var good_part := ModelDownload.part_path("tokens.txt")
	handle = FileAccess.open(good_part, FileAccess.WRITE)
	handle.store_string("hello")
	handle.close()
	var sha := FileAccess.get_sha256(good_part)
	assert_eq(ModelDownload.commit_part(good_part, ModelDownload.final_path("tokens.txt"), sha), "")
	assert_false(FileAccess.file_exists(good_part))
	assert_true(FileAccess.file_exists(ModelDownload.final_path("tokens.txt")))
	var body := ModelDownload.part_path("decoder.int8.onnx") + ".chunk"
	handle = FileAccess.open(ModelDownload.part_path("decoder.int8.onnx"), FileAccess.WRITE)
	handle.store_string("AA")
	handle.close()
	handle = FileAccess.open(body, FileAccess.WRITE)
	handle.store_string("BB")
	handle.close()
	assert_eq(ModelDownload.absorb(ModelDownload.part_path("decoder.int8.onnx"), 206, body, true), "ok")
	assert_eq(FileAccess.get_file_as_string(ModelDownload.part_path("decoder.int8.onnx")), "AABB")
	assert_false(FileAccess.file_exists(body))
	handle = FileAccess.open(body, FileAccess.WRITE)
	handle.store_string("ZZ")
	handle.close()
	assert_eq(ModelDownload.absorb(ModelDownload.part_path("decoder.int8.onnx"), 200, body, true), "ok")
	assert_eq(FileAccess.get_file_as_string(ModelDownload.part_path("decoder.int8.onnx")), "ZZ")
	_clear_test_dir()


func test_download_uses_fakes_for_space_hash_and_success() -> void:
	begin_async()
	_use_test_dir()
	var host: Window = (Engine.get_main_loop() as SceneTree).root
	var blocked := ModelDownload.new()
	var probe := _Probe.new()
	blocked.transport = probe
	blocked.free_override = 0
	host.add_child(blocked)
	var status := {"name": ""}
	blocked.state_changed.connect(func(next: String, _detail: String) -> void: status["name"] = next)
	await blocked.start()
	assert_eq(str(status["name"]), "space")
	assert_eq(probe.calls, 0)
	blocked.free()
	var bad := ModelDownload.new()
	var writer := _Writer.new()
	writer.body = "x"
	bad.transport = writer
	bad.free_override = ModelDownload.NEED_FREE
	ModelDownload.files_override = [{"name": "tokens.txt", "sha256": "0000000000000000000000000000000000000000000000000000000000000000", "size": 1}]
	host.add_child(bad)
	status["name"] = ""
	bad.state_changed.connect(func(next: String, _detail: String) -> void: status["name"] = next)
	await bad.start()
	assert_eq(str(status["name"]), "bad_hash")
	assert_false(ModelDownload.is_installed())
	assert_false(FileAccess.file_exists(ModelDownload.part_path("tokens.txt")))
	bad.free()
	var sample := FileAccess.open("user://models/parakeet-v3-test/sample.txt", FileAccess.WRITE)
	sample.store_string("x")
	sample.close()
	var sha := FileAccess.get_sha256("user://models/parakeet-v3-test/sample.txt")
	DirAccess.remove_absolute("user://models/parakeet-v3-test/sample.txt")
	var good := ModelDownload.new()
	var again := _Writer.new()
	again.body = "x"
	good.transport = again
	good.free_override = ModelDownload.NEED_FREE
	ModelDownload.files_override = [{"name": "tokens.txt", "sha256": sha, "size": 1}]
	host.add_child(good)
	status["name"] = ""
	good.state_changed.connect(func(next: String, _detail: String) -> void: status["name"] = next)
	await good.start()
	assert_eq(str(status["name"]), "ready")
	assert_true(ModelDownload.is_installed())
	assert_eq(FileAccess.get_sha256(ModelDownload.final_path("tokens.txt")), sha)
	assert_false(FileAccess.file_exists(ModelDownload.part_path("tokens.txt")))
	good.free()
	_clear_test_dir()
	end_async()


func test_missing_model_loading_and_crash_use_cloud() -> void:
	begin_async()
	_use_test_dir()
	var cloud := _Cloud.new()
	var local := LocalStt.new()
	local.cloud = cloud
	local.prepare()
	TurnTiming.begin("gemini")
	var result: Dictionary = await local.transcribe(PackedByteArray())
	assert_eq(cloud.calls, 1)
	assert_eq(str(result["text"]), "облачная фраза")
	var line := _row()
	assert_true(line.contains("stt=gemini"))
	assert_true(line.contains("stt_reason=no_model"))
	assert_false(line.contains("облачная"))
	_install_stubs()
	local.native = null
	local.phase = "idle"
	local.prepare()
	cloud.calls = 0
	TurnTiming.begin("gemini")
	result = await local.transcribe(PackedByteArray())
	assert_eq(cloud.calls, 1)
	line = _row()
	assert_true(line.contains("stt_reason=no_native"))
	assert_false(line.contains("облачная"))
	var native := _Native.new()
	native.hold_load = true
	native.heard = "секретная фраза"
	local.native = native
	local.phase = "idle"
	local.prepare()
	assert_eq(local.phase, "loading")
	cloud.calls = 0
	TurnTiming.begin("gemini")
	result = await local.transcribe(PackedByteArray())
	assert_eq(cloud.calls, 1)
	line = _row()
	assert_true(line.contains("stt_reason=loading"))
	assert_false(line.contains("секретная"))
	native.hold_load = false
	native.fail = "oom"
	local.phase = "idle"
	local.prepare()
	assert_eq(local.phase, "failed")
	cloud.calls = 0
	TurnTiming.begin("gemini")
	result = await local.transcribe(PackedByteArray())
	assert_eq(cloud.calls, 1)
	line = _row()
	assert_true(line.contains("stt_reason=load_failed"))
	assert_true(line.contains("stt_load_ms="))
	native.fail = ""
	native.crash = true
	local.phase = "idle"
	local.prepare()
	cloud.calls = 0
	TurnTiming.begin("gemini")
	result = await local.transcribe(PackedByteArray())
	assert_eq(cloud.calls, 1)
	line = _row()
	assert_true(line.contains("stt_reason=crash"))
	assert_false(line.contains("секретная"))
	local.free()
	cloud.free()
	_clear_test_dir()
	TurnTiming.reset()
	end_async()


func test_empty_and_junk_do_not_send_a_turn() -> void:
	begin_async()
	_use_test_dir()
	_install_stubs()
	var names := _names()
	var cloud := _Cloud.new()
	var local := LocalStt.new()
	local.cloud = cloud
	local.case_data = names[0]
	local.game_state = names[1]
	var native := _Native.new()
	native.heard = ""
	local.native = native
	local.prepare()
	var result: Dictionary = await local.transcribe(PackedByteArray())
	assert_false(bool(result["ok"]))
	assert_eq(str(result["text"]), "")
	assert_eq(str(result["message"]), GameLanguage.text("stt_repeat"))
	assert_eq(cloud.calls, 0)
	var sent := {"n": 0}
	var talk := PushToTalk.new()
	talk.screen_active = true
	talk.submit = func(_text: String) -> void: sent["n"] = int(sent["n"]) + 1
	var hints: Array = []
	talk.hint_changed.connect(func(text: String) -> void: hints.append(text))
	await talk._apply(result)
	assert_eq(int(sent["n"]), 0)
	assert_true(hints.has(GameLanguage.text("stt_repeat")))
	native.heard = "неразборчиво"
	local.phase = "ready"
	result = await local.transcribe(PackedByteArray())
	assert_false(bool(result["ok"]))
	assert_eq(cloud.calls, 0)
	await talk._apply(result)
	assert_eq(int(sent["n"]), 0)
	talk.free()
	local.free()
	cloud.free()
	_clear_test_dir()
	end_async()


func test_name_correction_keeps_ordinary_words_and_closed_evidence() -> void:
	begin_async()
	var names := _names()
	var case_data: CaseData = names[0]
	var state: GameState = names[1]
	assert_eq(SttNameCorrect.correct("pavla", case_data, state), "Павла")
	assert_eq(SttNameCorrect.correct("пауло", case_data, state), "Павла")
	assert_eq(SttNameCorrect.correct("палку", case_data, state), "палку")
	assert_eq(SttNameCorrect.correct("права", case_data, state), "права")
	assert_eq(SttNameCorrect.correct("пару", case_data, state), "пару")
	var alone := CaseData.new()
	var only := CaseData.Agent.new()
	only.name = "Павла Соколова"
	alone.agents.append(only)
	assert_eq(SttNameCorrect.correct("права", alone, state), "права")
	var heard := SttNameCorrect.correct("видели пару у архива", case_data, state)
	assert_eq(heard, "видели пару у архива")
	assert_false(heard.contains("Секретный"))
	_use_test_dir()
	_install_stubs()
	var cloud := _Cloud.new()
	var local := LocalStt.new()
	local.cloud = cloud
	local.case_data = case_data
	local.game_state = state
	var native := _Native.new()
	native.heard = "pavla"
	local.native = native
	local.prepare()
	TurnTiming.begin("gemini")
	var result: Dictionary = await local.transcribe(PackedByteArray())
	assert_true(bool(result["ok"]))
	assert_eq(str(result["text"]), "Павла")
	var line := _row()
	assert_true(line.contains("stt=parakeet"))
	assert_false(line.contains("pavla"))
	assert_false(line.contains("Павла"))
	assert_false(line.contains("stt_reason="))
	local.free()
	cloud.free()
	_clear_test_dir()
	TurnTiming.reset()
	end_async()


func _names() -> Array:
	var case_data := CaseData.new()
	var paula := CaseData.Agent.new()
	paula.name = "Павла Соколова"
	var pavel := CaseData.Agent.new()
	pavel.name = "Павел Иванов"
	case_data.agents.append(paula)
	case_data.agents.append(pavel)
	var secret := CaseData.EvidenceItem.new()
	secret.id = "secret_archive"
	secret.title = "Секретный архив"
	case_data.evidence.append(secret)
	return [case_data, GameState.new()]


func _row() -> String:
	return TurnTiming.format_row(TurnTiming.turns.back())


func _keep_config() -> String:
	if FileAccess.file_exists(SettingsStore.PATH):
		return FileAccess.get_file_as_string(SettingsStore.PATH)
	return ""


func _restore_config(previous: String) -> void:
	if previous == "":
		if FileAccess.file_exists(SettingsStore.PATH):
			DirAccess.remove_absolute(SettingsStore.PATH)
	else:
		var handle := FileAccess.open(SettingsStore.PATH, FileAccess.WRITE)
		handle.store_string(previous)
		handle.close()
	SettingsStore.invalidate_cache()


func _use_test_dir() -> void:
	ModelDownload.files_override = []
	ModelDownload.storage_dir = "user://models/parakeet-v3-test"
	ModelDownload.ensure_dir()
	ModelDownload.delete_all()
	TurnTiming.reset()


func _install_stubs() -> void:
	for spec in ModelDownload.FILES:
		var handle := FileAccess.open(ModelDownload.final_path(str(spec["name"])), FileAccess.WRITE)
		handle.store_string("stub")
		handle.close()


func _clear_test_dir() -> void:
	ModelDownload.storage_dir = "user://models/parakeet-v3-test"
	ModelDownload.files_override = []
	ModelDownload.delete_all()
	ModelDownload.storage_dir = ModelDownload.DEFAULT_DIR
	ModelDownload.files_override = []


class _Cloud:
	extends SttBackend
	var calls: int = 0

	func transcribe(_wav: PackedByteArray) -> Dictionary:
		calls += 1
		return {"ok": true, "text": "облачная фраза", "error": "", "usage": {}}


class _Native:
	extends RefCounted
	var hold_load: bool = false
	var fail: String = ""
	var heard: String = ""
	var crash: bool = false

	func load_model(_dir: String) -> String:
		return fail

	func transcribe_wav(_wav: PackedByteArray) -> Dictionary:
		return {"text": heard, "crash": crash}

	func unload() -> void:
		pass


class _Probe:
	extends RefCounted
	var calls: int = 0

	func request(_url: String, _headers: PackedStringArray, _dest: String) -> Dictionary:
		calls += 1
		return {"result": 1, "status": 0}


class _Writer:
	extends RefCounted
	var body: String = ""
	var calls: int = 0

	func request(_url: String, _headers: PackedStringArray, dest: String) -> Dictionary:
		calls += 1
		var handle := FileAccess.open(dest, FileAccess.WRITE)
		handle.store_string(body)
		handle.close()
		return {"result": 0, "status": 200}
