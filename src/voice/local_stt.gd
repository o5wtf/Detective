class_name LocalStt
extends SttBackend
## Локальный STT. Язык модели не передаётся.
## Нет библиотеки, модели, она ещё грузится, не загрузилась или упала — ход идёт в облако.


static var last_reason: String = ""

var cloud: SttBackend
var native: Object = null
var case_data: CaseData
var game_state: GameState
var phase: String = "idle"
var fallback_reason: String = ""
var _load_ms: int = 0
var _load_pending: bool = false
var _load_started_msec: int = 0


func prepare() -> void:
	if phase == "ready" or phase == "loading":
		return
	if not ModelDownload.is_installed():
		phase = "idle"
		_set_reason("no_model")
		return
	var lib := _library()
	if lib.has_method("available") and not bool(lib.call("available")):
		phase = "failed"
		_set_reason("no_native")
		return
	if not lib.has_method("transcribe_wav"):
		phase = "failed"
		_set_reason("no_native")
		return
	if native != null and native.get("hold_load") == true:
		phase = "loading"
		_set_reason("loading")
		return
	phase = "loading"
	_set_reason("loading")
	_load_started_msec = Time.get_ticks_msec()
	var err := ""
	if lib.has_method("load_model"):
		err = str(lib.call("load_model", ModelDownload.install_dir()))
	if err == "loading":
		return
	_finish_load(err)


func _process(_delta: float) -> void:
	if phase != "loading":
		return
	var lib := _library()
	if not lib.has_method("load_state"):
		return
	var state := str(lib.call("load_state"))
	if state == "loading":
		return
	_finish_load(state)


func release_model() -> void:
	var lib := _library()
	if lib.has_method("unload"):
		lib.call("unload")
	if phase == "ready" or phase == "loading":
		phase = "idle"
		_set_reason("loading")


func _finish_load(err: String) -> void:
	_load_ms = maxi(Time.get_ticks_msec() - _load_started_msec, 0)
	_load_pending = true
	if err != "":
		phase = "failed"
		_set_reason("load_failed")
		return
	phase = "ready"
	_set_reason("")


func _library() -> Object:
	if native != null:
		return native
	return SherpaNative.new()


func transcribe(wav: PackedByteArray) -> Dictionary:
	if phase == "loading":
		return await _cloud(wav, "loading")
	if phase != "ready":
		var reason := fallback_reason if fallback_reason != "" else "no_model"
		return await _cloud(wav, reason)
	var started := Time.get_ticks_msec()
	var produced: Variant = _library().call("transcribe_wav", wav)
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
