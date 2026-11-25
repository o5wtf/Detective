class_name PushToTalk
extends Node
## Удержание кнопки: запись, расшифровка, один ход. Микрофон сюда не вшит.


signal state_changed(state_name: String)
signal hint_changed(text: String)
signal level_changed(unit: float)
signal retry_visible(show_button: bool)
signal partial_changed(text: String)

const STATE_IDLE := "idle"
const STATE_LISTENING := "listening"
const STATE_RECOGNIZING := "recognizing"
const STATE_ANSWERING := "answering"

var stt: SttBackend
var clip: MicClip = MicClip.new()
var enabled: bool = false
var screen_active: bool = false
var character_busy: bool = false
var locked: bool = false
var state_name: String = STATE_IDLE
var last_wav: PackedByteArray = PackedByteArray()
## Запись для одного запроса «речь + ответ». Пустая, если сначала идёт отдельное распознавание.
var pending_wav: PackedByteArray = PackedByteArray()
var submit: Callable = Callable()
var hint_source: Callable = Callable()
var _holding: bool = false
var _tailing: bool = false
var _queued_tail: PackedByteArray = PackedByteArray()
var _generation: int = 0


func press() -> bool:
	if not enabled or not screen_active or locked or character_busy or _holding:
		return false
	clip.begin()
	_holding = true
	_set_state(STATE_LISTENING)
	level_changed.emit(0.0)
	TurnTiming.begin(_backend_name())
	if _is_live():
		stt.start_listen()
	return true


func push_pcm(pcm: PackedByteArray, force_limit: bool = false) -> String:
	if not screen_active:
		if _holding or _tailing:
			cancel()
		return "hidden"
	if _tailing:
		if not pcm.is_empty():
			clip.push_hold(pcm)
		return "tail"
	if not _holding:
		clip.push_preroll(pcm)
		return "preroll"
	var reached := clip.push_hold(pcm) or force_limit
	level_changed.emit(clampf(float(VoiceAudio.peak(pcm)) / 8000.0, 0.0, 1.0))
	if _is_live():
		var heard := stt.partial_text()
		if heard != "":
			partial_changed.emit(heard)
	if reached or clip.hold_ms() >= float(MicClip.MAX_MS):
		hint_changed.emit("Запись длинная, отправляю её.")
		return "limit"
	return "hold"


func release(force_send: bool = false) -> Dictionary:
	if not _holding and not force_send:
		return {"action": "idle"}
	var over_limit := clip.hold_ms() >= float(MicClip.MAX_MS)
	_holding = false
	level_changed.emit(0.0)
	TurnTiming.mark("release")
	if _is_live():
		var token := _generation
		locked = true
		_set_state(STATE_RECOGNIZING)
		TurnTiming.mark("audio_ready")
		TurnTiming.mark("stt_sent")
		var live: Dictionary = await stt.finish_listen()
		TurnTiming.mark("stt_done")
		if token == _generation:
			await _apply(live)
		TurnTiming.publish()
		return {"action": "send", "reason": "speech", "wav": PackedByteArray()}
	if not force_send and not over_limit:
		var token := _generation
		_tailing = true
		locked = true
		_set_state(STATE_RECOGNIZING)
		var kept := await _await_tail(token)
		_tailing = false
		if not kept:
			return {"action": "discard", "reason": "cancel"}
	return await _finish_clip(force_send)


func cancel() -> void:
	_generation += 1
	_holding = false
	_tailing = false
	clip.cancel()
	if stt != null:
		stt.cancel_listen()
	locked = false
	level_changed.emit(0.0)
	retry_visible.emit(false)
	_set_state(STATE_IDLE)


func retry() -> void:
	if locked or not screen_active:
		return
	if _is_live():
		var live: Dictionary = await stt.recover()
		await _apply(live)
		TurnTiming.publish()
		return
	if last_wav.is_empty():
		return
	await _recognize(last_wav)


func _finish_clip(force_send: bool) -> Dictionary:
	var decision := clip.end(force_send)
	if str(decision.get("action", "")) != "send":
		_set_state(STATE_IDLE)
		locked = false
		var reason := str(decision.get("reason", ""))
		hint_changed.emit("Тишина в записи." if reason == "quiet" else "Слишком коротко, не отправлено.")
		return decision
	var pcm: PackedByteArray = decision.get("pcm", PackedByteArray())
	last_wav = VoiceAudio.wav_bytes(pcm, VoiceAudio.UPLOAD_RATE)
	_save_last(last_wav)
	TurnTiming.mark("audio_ready")
	if SettingsStore.wants_merged_stt():
		pending_wav = last_wav
		locked = true
		_set_state(STATE_ANSWERING)
		if submit.is_valid():
			await submit.call("")
		pending_wav = PackedByteArray()
		if _live(_generation):
			_finish_idle()
		decision["wav"] = last_wav
		return decision
	await _recognize(last_wav)
	decision["wav"] = last_wav
	return decision


func _await_tail(token: int) -> bool:
	var tree := get_tree()
	if tree == null:
		return token == _generation
	if not _queued_tail.is_empty():
		clip.push_hold(_queued_tail)
		_queued_tail = PackedByteArray()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < MicClip.TAIL_MS:
		if token != _generation or not _tailing:
			return false
		if character_busy or not screen_active:
			cancel()
			return false
		await tree.process_frame
	if token != _generation or not _tailing:
		return false
	await tree.process_frame
	return token == _generation and _tailing


func _recognize(wav: PackedByteArray) -> void:
	var token := _generation
	locked = true
	_set_state(STATE_RECOGNIZING)
	_apply_hint()
	var result := {"ok": false, "text": "", "error": "offline"}
	if stt != null:
		# Godot 4.7 обрывает вызывающего, если корутина наследника вызвана без await.
		TurnTiming.mark("stt_sent")
		result = await stt.transcribe(wav)
		TurnTiming.mark("stt_done")
	if not _live(token):
		TurnTiming.publish()
		return
	await _apply(result)
	TurnTiming.publish()


func _apply(result: Dictionary) -> void:
	var token := _generation
	if not _live(token):
		return
	if not result.get("ok", false):
		_finish_idle()
		var message := str(result.get("message", "")).strip_edges()
		if message == "":
			message = "Не удалось распознать."
		hint_changed.emit(message)
		retry_visible.emit(true)
		return
	var text := str(result.get("text", "")).strip_edges()
	if _reject_transcript(text):
		_finish_idle()
		hint_changed.emit(GameLanguage.text("stt_repeat"))
		return
	retry_visible.emit(false)
	TurnTiming.mark("line_shown")
	_set_state(STATE_ANSWERING)
	if submit.is_valid():
		await submit.call(text)
	if not _live(token):
		return
	_finish_idle()


func _is_live() -> bool:
	return stt != null and stt.has_method("listens_live") and stt.listens_live()


func _reject_transcript(text: String) -> bool:
	var hint := ""
	if hint_source.is_valid():
		hint = str(hint_source.call())
	return SttGuard.reject(text, Game.case_data, Game.state, hint)


func _apply_hint() -> void:
	if stt != null and stt.has_method("set_hint") and hint_source.is_valid():
		stt.set_hint(str(hint_source.call()))


func _backend_name() -> String:
	if SettingsStore.load_current().stt_backend == "parakeet":
		return "parakeet"
	return "gemini"


func _live(token: int) -> bool:
	if token == _generation and screen_active:
		return true
	if token == _generation:
		_finish_idle()
	return false


func _finish_idle() -> void:
	locked = false
	retry_visible.emit(false)
	_set_state(STATE_IDLE)


func _set_state(next: String) -> void:
	state_name = next
	state_changed.emit(next)


func _save_last(wav: PackedByteArray) -> void:
	if wav.is_empty():
		return
	var file := FileAccess.open("user://mic-last.wav", FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(wav)
	file.close()
