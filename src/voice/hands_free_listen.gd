class_name HandsFreeListen
extends Node
## Постоянное прослушивание. Фраза кончается паузой и идёт в тот же облачный STT.


signal state_changed(state_name: String)
signal hint_changed(text: String)
signal level_changed(unit: float)
signal retry_visible(show_button: bool)

const STATE_LISTEN := "listening"
const STATE_RECOGNIZE := "recognizing"
const STATE_CHARACTER := "character"
const STATE_PAUSED := "paused"

var stt: SttBackend
var enabled: bool = false
var screen_active: bool = false
var paused: bool = false
var echo: bool = false
var output_lock: bool = false
var locked: bool = false
var state_name: String = STATE_LISTEN
var submit: Callable = Callable()
var vad: PhraseVad = PhraseVad.new()
var _generation: int = 0


func set_pause_ms(ms: int) -> void:
	vad.set_pause_ms(ms)


func set_output_lock(active: bool) -> void:
	output_lock = active
	vad.set_blocked(active or echo)
	if active or echo:
		_set_state(STATE_CHARACTER)
	elif not paused and not locked:
		_set_state(STATE_LISTEN)


func set_echo(active: bool) -> void:
	var was := echo
	echo = active
	vad.set_blocked(active or output_lock)
	if active:
		_set_state(STATE_CHARACTER)
	elif was and not output_lock:
		_set_state(STATE_PAUSED if paused else STATE_LISTEN)


func toggle_pause() -> void:
	paused = not paused
	if paused:
		vad.reset_utterance()
		_log("vad pause")
		if not echo:
			_set_state(STATE_PAUSED)
		return
	_log("vad resume")
	if not echo and not locked:
		_set_state(STATE_LISTEN)


func stop() -> void:
	_generation += 1
	locked = false
	vad.reset_utterance()
	if stt != null:
		stt.cancel_listen()
	level_changed.emit(0.0)
	retry_visible.emit(false)
	_set_state(STATE_PAUSED if paused else STATE_LISTEN)


func push_pcm(pcm: PackedByteArray) -> void:
	if not enabled or not screen_active or paused or locked or echo or output_lock:
		return
	var before := vad.events.size()
	vad.push(pcm)
	level_changed.emit(clampf(float(VoiceAudio.peak(pcm)) / 8000.0, 0.0, 1.0))
	while before < vad.events.size():
		var line := str(vad.events[before])
		before += 1
		if line.begins_with("vad end"):
			call("_recognize", vad.last_pcm)


func label() -> String:
	if echo or output_lock:
		return UiStrings.MIC_HF_CHARACTER
	if paused:
		return UiStrings.MIC_HF_PAUSE
	if state_name == STATE_RECOGNIZE:
		return UiStrings.MIC_HF_RECOGNIZE
	return UiStrings.MIC_HF_LISTEN


func _recognize(pcm: PackedByteArray) -> void:
	var token := _generation
	locked = true
	_set_state(STATE_RECOGNIZE)
	TurnTiming.begin(_backend_name())
	var wav := VoiceAudio.wav_bytes(pcm, PhraseVad.RATE)
	var result := {"ok": false, "text": "", "error": "offline"}
	if stt != null:
		result = await stt.transcribe(wav)
	if token != _generation:
		return
	locked = false
	if not result.get("ok", false):
		var message := str(result.get("message", "")).strip_edges()
		if message == "":
			message = "Не удалось распознать."
		hint_changed.emit(message)
		retry_visible.emit(true)
		_set_state(_idle_state())
		return
	var text := str(result.get("text", "")).strip_edges()
	if SpeechJunk.is_junk(text):
		_log("vad junk")
		hint_changed.emit(GameLanguage.text("stt_repeat"))
		_set_state(_idle_state())
		return
	retry_visible.emit(false)
	if submit.is_valid():
		await submit.call(text)
	if token != _generation:
		return
	_set_state(_idle_state())


func _backend_name() -> String:
	if SettingsStore.load_current().stt_backend == "parakeet":
		return "parakeet"
	return "gemini"


func _idle_state() -> String:
	if echo:
		return STATE_CHARACTER
	if paused:
		return STATE_PAUSED
	return STATE_LISTEN


func _set_state(next: String) -> void:
	state_name = next
	state_changed.emit(next)


func _log(line: String) -> void:
	vad.events.append(line)
	if is_instance_valid(Speaker):
		Speaker.note_line(line)
