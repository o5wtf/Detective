class_name LocalStt
extends SttBackend
## Локальный STT. Язык модели не передаётся. Нативной библиотеки в этой сборке нет:
## нет библиотеки, модели или она не загрузилась — ход идёт в облако, причина в журнале.
## Следующий PR подставляет arm64 sherpa-onnx и грузит модель вне главного потока.


static var last_reason: String = ""

var cloud: SttBackend
var native: Object = null
var case_data: CaseData
var game_state: GameState
var phase: String = "idle"
var fallback_reason: String = ""
var _load_ms: int = 0
var _load_pending: bool = false


func prepare() -> void:
	if phase == "ready" or phase == "loading":
		return
	if not ModelDownload.is_installed():
		phase = "idle"
		_set_reason("no_model")
		return
	if not _has_native():
		phase = "failed"
		_set_reason("no_native")
		return
	if bool(native.get("hold_load")):
		phase = "loading"
		_set_reason("loading")
		return
	phase = "loading"
	_set_reason("loading")
	var started := Time.get_ticks_msec()
	var err := ""
	if native.has_method("load_model"):
		err = str(native.call("load_model", ModelDownload.install_dir()))
	_load_ms = maxi(Time.get_ticks_msec() - started, 0)
	_load_pending = true
	if err != "":
		phase = "failed"
		_set_reason("load_failed")
		return
	phase = "ready"
	_set_reason("")


func release_model() -> void:
	if _has_native() and native.has_method("unload"):
		native.call("unload")
	if phase == "ready" or phase == "loading":
		phase = "idle"
		_set_reason("loading")


func transcribe(wav: PackedByteArray) -> Dictionary:
	if phase == "loading":
		return await _cloud(wav, "loading")
	if phase != "ready":
		var reason := fallback_reason if fallback_reason != "" else "no_model"
		return await _cloud(wav, reason)
	var started := Time.get_ticks_msec()
	var produced: Variant = native.call("transcribe_wav", wav)
	var crashed := false
	var raw := ""
	if produced is Dictionary:
		crashed = bool(produced.get("crash", false))
		raw = str(produced.get("text", ""))
	else:
		raw = str(produced)
	if crashed:
		phase = "failed"
		_set_reason("crash")
		return await _cloud(wav, "crash")
	var text := SttNameCorrect.correct(raw, _case(), _state())
	_note("parakeet", Time.get_ticks_msec() - started, "")
	await _tick()
	if SpeechJunk.is_junk(text):
		return {"ok": false, "text": "", "error": "empty", "message": GameLanguage.text("stt_repeat"), "usage": {}}
	return {"ok": true, "text": text, "error": "", "usage": {}}


func _cloud(wav: PackedByteArray, reason: String) -> Dictionary:
	var started := Time.get_ticks_msec()
	var result := {"ok": false, "text": "", "error": "offline", "message": "", "usage": {}}
	if cloud != null:
		result = await cloud.transcribe(wav)
	else:
		await _tick()
	_note("gemini", Time.get_ticks_msec() - started, reason)
	return result


func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _has_native() -> bool:
	var lib: Object = native if native != null else SherpaNative.new()
	if lib.has_method("available") and not bool(lib.call("available")):
		return false
	return lib.has_method("transcribe_wav")


func _note(engine: String, elapsed: int, reason: String) -> void:
	var load := -1
	if _load_pending:
		load = _load_ms
		_load_pending = false
	TurnTiming.note_stt(engine, elapsed, reason, load)


func _set_reason(reason: String) -> void:
	fallback_reason = reason
	last_reason = reason


func _case() -> CaseData:
	if case_data != null:
		return case_data
	if is_instance_valid(Game):
		return Game.case_data
	return null


func _state() -> GameState:
	if game_state != null:
		return game_state
	if is_instance_valid(Game):
		return Game.state
	return null
