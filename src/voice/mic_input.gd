class_name MicInput
extends Node
## Тёплый микрофон. В Godot 4.7 основной путь — AudioServer.get_input_frames.
## Если устройство не открылось или молчит ~400 мс удержания, остаётся шина микрофона.


const API_INPUT_FRAMES := "AudioServer.get_input_frames"
const API_BUS := "AudioStreamMicrophone+AudioEffectCapture"
const BUS_NAME := "MicCapture"
const ZERO_MS := 400.0

static var last_activate: int = -1
static var active_api: String = ""
static var active_error: String = ""
static var primary_error_text: String = ""
static var record_granted: bool = false
static var hold_frames_total: int = 0
static var hold_peak_value: int = 0
static var hold_ms_value: float = 0.0

var api_name: String = ""
var last_error: String = ""
var primary_error: String = ""
var needs_restart: bool = false
var fallback_enabled: bool = true
var hold_frames: int = 0
var hold_peak: int = 0
var hold_ms: float = 0.0
## Подмена AudioServer в тестах: activate() -> int, без живого устройства.
var server: Object = null
var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _bus := -1
var _silent_ms := 0.0
var _capture_state: Dictionary = {}


static func preferred_api() -> String:
	return API_INPUT_FRAMES


static func hint_for(kind: String, frames: int = 0) -> String:
	if kind == "denied":
		return UiStrings.MIC_NO_PERMISSION
	if kind == "quiet":
		return UiStrings.MIC_TOO_QUIET if frames > 0 else UiStrings.MIC_NOT_STARTED
	if kind == "input_inactive" or kind == "zero_frames" or kind == "no_device" or kind == "driver":
		return UiStrings.MIC_NOT_STARTED
	return ""


static func status_lines() -> PackedStringArray:
	var devices := AudioServer.get_input_device_list()
	var listed := ",".join(devices)
	return PackedStringArray([
		"enable_input=%s" % str(ProjectSettings.get_setting("audio/driver/enable_input", false)),
		"driver=%s" % AudioServer.get_driver_name(),
		"devices=%s" % listed,
		"device=%s" % AudioServer.get_input_device(),
		"mix_rate=%s" % str(AudioServer.get_input_mix_rate()),
		"activate=%s" % str(last_activate),
		"api=%s" % active_api,
		"error=%s" % active_error,
		"record_audio=%s" % str(record_granted),
		"hold_frames=%s peak=%s hold_ms=%s" % [str(hold_frames_total), str(hold_peak_value), str(int(hold_ms_value))],
	])


func warm() -> bool:
	_silent_ms = 0.0
	last_error = ""
	if _server_input():
		api_name = API_INPUT_FRAMES
		_publish("warm")
		return true
	return _use_fallback(primary_error if primary_error != "" else "input_inactive")


func stop() -> void:
	if api_name == API_INPUT_FRAMES and server == null:
		AudioServer.set_input_device_active(false)
	if _player != null and is_instance_valid(_player):
		_player.stop()
	api_name = ""
	_capture_state = {}
	_remember()


func read_pcm() -> PackedByteArray:
	if api_name == API_INPUT_FRAMES:
		var available := _available_frames()
		if available <= 0:
			return PackedByteArray()
		var frames := PackedVector2Array()
		if server != null and server.has_method("pull_frames"):
			var pulled: Variant = server.call("pull_frames", available)
			if pulled is PackedVector2Array:
				frames = pulled
		else:
			frames = AudioServer.get_input_frames(available)
		var pcm := VoiceAudio.from_vectors(frames)
		return _capture_pcm(pcm, _mix_rate())
	if _capture == null:
		return PackedByteArray()
	var chunk := _capture.get_buffer(_capture.get_frames_available())
	if chunk.is_empty():
		return PackedByteArray()
	var pcm := PackedByteArray()
	pcm.resize(chunk.size() * 2)
	for index in chunk.size():
		VoiceAudio.put_sample(pcm, index, clampi(int(round(chunk[index].x * 32767.0)), -32768, 32767))
	return _capture_pcm(pcm, int(AudioServer.get_mix_rate()))


func _capture_pcm(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var step: Dictionary = VoiceAudio.capture_chunk(pcm, rate, _capture_state)
	_capture_state = step.get("state", {})
	return step.get("pcm", PackedByteArray())


func begin_hold() -> void:
	_silent_ms = 0.0
	hold_frames = 0
	hold_peak = 0
	hold_ms = 0.0
	_remember_hold()


func observe_hold(pcm: PackedByteArray, dt_ms: float) -> void:
	hold_ms += dt_ms
	var frames := pcm.size() / 2
	hold_frames += frames
	if frames > 0:
		hold_peak = maxi(hold_peak, VoiceAudio.peak(pcm))
		_silent_ms = 0.0
	elif api_name == API_INPUT_FRAMES:
		_silent_ms += dt_ms
		if _silent_ms >= ZERO_MS:
			_use_fallback("zero_frames")
	_remember_hold()


func log_hold() -> void:
	_remember_hold()
	_publish("hold")


func _server_input() -> bool:
	var err := _activate()
	last_activate = err
	if err != OK:
		last_error = "input_inactive"
		primary_error = "input_inactive"
		_remember()
		return false
	last_error = ""
	_remember()
	return true


func _activate() -> int:
	if server != null:
		return int(server.call("activate"))
	return AudioServer.set_input_device_active(true)


func _available_frames() -> int:
	if server != null and server.has_method("frames_available"):
		return int(server.call("frames_available"))
	return AudioServer.get_input_frames_available()


func _mix_rate() -> int:
	if server != null and server.has_method("mix_rate"):
		return int(server.call("mix_rate"))
	var rate := AudioServer.get_input_mix_rate()
	return rate if rate > 0 else VoiceAudio.UPLOAD_RATE


func _use_fallback(reason: String) -> bool:
	primary_error = reason
	if api_name == API_INPUT_FRAMES and server == null:
		AudioServer.set_input_device_active(false)
	if _player != null and is_instance_valid(_player):
		_player.stop()
	api_name = ""
	if _bus_input():
		api_name = API_BUS
		last_error = ""
		_silent_ms = 0.0
		_publish("fallback")
		return true
	last_error = reason if reason != "" else "no_device"
	_remember()
	_publish("fallback-failed")
	return false


func _bus_input() -> bool:
	if not fallback_enabled:
		last_error = "no_device"
		return false
	if _player != null and is_instance_valid(_player) and _capture != null:
		_player.volume_db = 0.0
		if not _player.playing:
			_player.play()
		return true
	_bus = AudioServer.get_bus_index(BUS_NAME)
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, BUS_NAME)
		AudioServer.set_bus_mute(_bus, true)
	else:
		AudioServer.set_bus_mute(_bus, true)
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_bus, _capture)
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	_player.volume_db = 0.0
	add_child(_player)
	_player.play()
	return true


func _remember() -> void:
	active_api = api_name
	active_error = last_error
	primary_error_text = primary_error


func _remember_hold() -> void:
	hold_frames_total = hold_frames
	hold_peak_value = hold_peak
	hold_ms_value = hold_ms
	_remember()


func _publish(kind: String) -> void:
	_remember_hold()
	var line := "mic %s %s" % [kind, " ".join(status_lines())]
	if is_instance_valid(Speaker):
		Speaker.note_line(line)
