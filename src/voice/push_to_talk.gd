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
var submit: Callable = Callable()
var _holding: bool = false
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
		if _holding:
			cancel()
		return "hidden"
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
	var decision := clip.end(force_send)
	if str(decision.get("action", "")) != "send":
		_set_state(STATE_IDLE)
		var reason := str(decision.get("reason", ""))
		hint_changed.emit("Тишина в записи." if reason == "quiet" else "Слишком коротко, не отправлено.")
		return decision
	last_wav = VoiceAudio.wav_bytes(decision.get("pcm", PackedByteArray()), VoiceAudio.UPLOAD_RATE)
	_save_last(last_wav)
	TurnTiming.mark("audio_ready")
	await _recognize(last_wav)
	decision["wav"] = last_wav
	return decision


func cancel() -> void:
	_generation += 1
	_holding = false
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


func _recognize(wav: PackedByteArray) -> void:
	var token := _generation
	locked = true
	_set_state(STATE_RECOGNIZING)
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
	if SpeechJunk.is_junk(text):
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


func _backend_name() -> String:
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
