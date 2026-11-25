class_name MicClip
extends RefCounted
## Предзапись 300 мс и решение: выбросить короткое нажатие или отправить звук.


const RATE := 16000
const PREROLL_MS := 300
const TAP_MS := 300
const MAX_MS := 60000
const ENERGY := 400
const TAIL_MS := 300

var preroll: PackedByteArray = PackedByteArray()
var hold: PackedByteArray = PackedByteArray()
var holding: bool = false


func push_preroll(pcm: PackedByteArray) -> void:
	if holding or pcm.is_empty():
		return
	preroll.append_array(pcm)
	var max_bytes := int(RATE * PREROLL_MS / 1000.0) * 2
	if preroll.size() > max_bytes:
		preroll = preroll.slice(preroll.size() - max_bytes)


func begin() -> void:
	holding = true
	hold = PackedByteArray()


func push_hold(pcm: PackedByteArray) -> bool:
	if not holding or pcm.is_empty():
		return hold_ms() >= MAX_MS
	hold.append_array(pcm)
	return hold_ms() >= MAX_MS


func hold_ms() -> float:
	return float(hold.size() / 2) / float(RATE) * 1000.0


func level() -> float:
	var source := hold if holding else preroll
	return clampf(float(VoiceAudio.peak(source)) / 8000.0, 0.0, 1.0)


func end(force_send: bool) -> Dictionary:
	holding = false
	var ms := hold_ms()
	var loud := VoiceAudio.peak(hold) >= ENERGY
	if not force_send and (ms < float(TAP_MS) or not loud):
		hold = PackedByteArray()
		return {"action": "discard", "reason": "tap" if ms < float(TAP_MS) else "quiet", "pcm": PackedByteArray()}
	var pcm := PackedByteArray()
	pcm.append_array(preroll)
	pcm.append_array(hold)
	hold = PackedByteArray()
	preroll = PackedByteArray()
	return {"action": "send", "reason": "long" if force_send else "speech", "pcm": VoiceAudio.normalize_speech(pcm)}


func cancel() -> void:
	holding = false
	hold = PackedByteArray()
	preroll = PackedByteArray()
