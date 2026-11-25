class_name VoiceAudio
extends RefCounted
## PCM 16-bit и WAV. Распознавание получает моно 16 кГц.


const UPLOAD_RATE := 16000


static func wav_bytes(pcm: PackedByteArray, mix_rate: int) -> PackedByteArray:
	var data_size := pcm.size()
	var out := PackedByteArray()
	out.resize(44 + data_size)
	_ascii(out, 0, "RIFF")
	_u32(out, 4, 36 + data_size)
	_ascii(out, 8, "WAVE")
	_ascii(out, 12, "fmt ")
	_u32(out, 16, 16)
	_u16(out, 20, 1)
	_u16(out, 22, 1)
	_u32(out, 24, mix_rate)
	_u32(out, 28, mix_rate * 2)
	_u16(out, 32, 2)
	_u16(out, 34, 16)
	_ascii(out, 36, "data")
	_u32(out, 40, data_size)
	for index in data_size:
		out[44 + index] = pcm[index]
	return out


static func to_pcm16k(pcm: PackedByteArray, mix_rate: int, stereo: bool) -> PackedByteArray:
	var single := mono(pcm, stereo)
	var rate := mix_rate if mix_rate > 0 else UPLOAD_RATE
	if rate == UPLOAD_RATE:
		return single
	return capture_chunk(single, rate, {}).pcm


static func resample(pcm: PackedByteArray, from_rate: int, to_rate: int) -> PackedByteArray:
	var frames := pcm.size() / 2
	if frames == 0 or from_rate <= 0 or to_rate <= 0:
		return PackedByteArray()
	if from_rate == to_rate:
		return pcm
	var out_frames := maxi(1, int(round(float(frames) * float(to_rate) / float(from_rate))))
	var out := PackedByteArray()
	out.resize(out_frames * 2)
	for index in out_frames:
		var source := float(index) * float(from_rate) / float(to_rate)
		var left := mini(int(floor(source)), frames - 1)
		var right := mini(left + 1, frames - 1)
		var frac := source - float(left)
		var mixed := int(round(float(sample_at(pcm, left)) + (float(sample_at(pcm, right)) - float(sample_at(pcm, left))) * frac))
		put_sample(out, index, clampi(mixed, -32768, 32767))
	return out


static func mono(pcm: PackedByteArray, stereo: bool) -> PackedByteArray:
	if not stereo:
		return pcm
	var frames := pcm.size() / 4
	var out := PackedByteArray()
	out.resize(frames * 2)
	for frame in frames:
		out[frame * 2] = pcm[frame * 4]
		out[frame * 2 + 1] = pcm[frame * 4 + 1]
	return out


static func from_vectors(frames: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(frames.size() * 2)
	for index in frames.size():
		var frame := frames[index]
		var mixed := (frame.x + frame.y) * 0.5
		put_sample(out, index, clampi(int(round(mixed * 32767.0)), -32768, 32767))
	return out


const FIR_TAPS := 31
const FIR_CUTOFF := 7000.0
const TARGET_PEAK := 23197
const MAX_GAIN := 4.0

static var _kernels: Dictionary = {}


static func capture_chunk(pcm: PackedByteArray, from_rate: int, state: Dictionary) -> Dictionary:
	var rate := from_rate if from_rate > 0 else UPLOAD_RATE
	if rate <= UPLOAD_RATE:
		return {"pcm": pcm, "state": {"history": PackedFloat32Array(), "origin": 0, "prev": 0.0, "has_prev": false}}
	var history: PackedFloat32Array = state.get("history", PackedFloat32Array())
	var origin := int(state.get("origin", 0))
	var prev := float(state.get("prev", 0.0))
	var has_prev: bool = state.get("has_prev", false) == true
	var filtered := _fir(_floats(pcm), history, _kernel(rate))
	var samples: PackedFloat32Array = filtered.samples
	var span := _resample_span(samples, rate, UPLOAD_RATE, origin, prev, has_prev)
	var next_prev := prev
	var next_has := has_prev
	if samples.size() > 0:
		next_prev = samples[samples.size() - 1]
		next_has = true
	return {
		"pcm": _from_floats(span),
		"state": {
			"history": filtered.history,
			"origin": origin + samples.size(),
			"prev": next_prev,
			"has_prev": next_has,
		},
	}


static func normalize_speech(pcm: PackedByteArray) -> PackedByteArray:
	var loudest := peak(pcm)
	if loudest <= 0 or loudest >= TARGET_PEAK:
		return pcm
	var gain := minf(float(TARGET_PEAK) / float(loudest), MAX_GAIN)
	var frames := pcm.size() / 2
	var out := PackedByteArray()
	out.resize(pcm.size())
	for index in frames:
		var value := int(round(float(sample_at(pcm, index)) * gain))
		put_sample(out, index, clampi(value, -32768, 32767))
	return out


static func peak(pcm: PackedByteArray) -> int:
	var best := 0
	var frames := pcm.size() / 2
	for index in frames:
		best = maxi(best, absi(sample_at(pcm, index)))
	return best


static func tone(frames: int, amplitude: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(frames * 2)
	for index in frames:
		put_sample(out, index, amplitude)
	return out


static func sample_at(pcm: PackedByteArray, index: int) -> int:
	var at := index * 2
	if at + 1 >= pcm.size():
		return 0
	var value := int(pcm[at]) | (int(pcm[at + 1]) << 8)
	if value >= 32768:
		value -= 65536
	return value


static func put_sample(pcm: PackedByteArray, index: int, value: int) -> void:
	var stored := value
	if stored < 0:
		stored += 65536
	var at := index * 2
	pcm[at] = stored & 255
	pcm[at + 1] = (stored >> 8) & 255


static func _kernel(rate: int) -> PackedFloat32Array:
	if _kernels.has(rate):
		return _kernels[rate]
	var mid := FIR_TAPS / 2
	var cutoff := FIR_CUTOFF / float(rate)
	var kernel := PackedFloat32Array()
	kernel.resize(FIR_TAPS)
	var total := 0.0
	for index in FIR_TAPS:
		var offset := float(index - mid)
		var sinc := 2.0 * cutoff
		if offset != 0.0:
			sinc = sin(TAU * cutoff * offset) / (PI * offset)
		var window := 0.54 - 0.46 * cos(TAU * float(index) / float(FIR_TAPS - 1))
		var value := sinc * window
		kernel[index] = value
		total += value
	if total != 0.0:
		for index in FIR_TAPS:
			kernel[index] = kernel[index] / total
	_kernels[rate] = kernel
	return kernel


static func _floats(pcm: PackedByteArray) -> PackedFloat32Array:
	var frames := pcm.size() / 2
	var out := PackedFloat32Array()
	out.resize(frames)
	for index in frames:
		out[index] = float(sample_at(pcm, index))
	return out


static func _from_floats(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size() * 2)
	for index in samples.size():
		put_sample(out, index, clampi(int(round(samples[index])), -32768, 32767))
	return out


static func _fir(samples: PackedFloat32Array, history: PackedFloat32Array, kernel: PackedFloat32Array) -> Dictionary:
	var keep := kernel.size() - 1
	var padded := PackedFloat32Array()
	if history.is_empty():
		padded.resize(keep)
	else:
		padded.append_array(history)
	padded.append_array(samples)
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for index in samples.size():
		var acc := 0.0
		for tap in kernel.size():
			acc += padded[index + tap] * kernel[tap]
		out[index] = acc
	var next := PackedFloat32Array()
	if padded.size() >= keep:
		next = padded.slice(padded.size() - keep)
	else:
		next = padded
	return {"samples": out, "history": next}


static func _resample_span(samples: PackedFloat32Array, from_rate: int, to_rate: int, origin: int, prev: float, has_prev: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if samples.is_empty() or from_rate <= 0 or to_rate <= 0:
		return out
	var start := origin
	var finish := origin + samples.size()
	var index := 0
	if start > 0:
		index = int(floor(float(start) * float(to_rate) / float(from_rate)))
	var guard := 0
	var limit := samples.size() + 4
	while guard < limit:
		guard += 1
		var source := float(index) * float(from_rate) / float(to_rate)
		if source >= float(finish):
			break
		var left := int(floor(source))
		var right := left + 1
		if right < start:
			index += 1
			continue
		if right >= finish:
			break
		var frac := source - float(left)
		var first := _span_at(samples, left, start, prev, has_prev)
		var second := _span_at(samples, right, start, prev, has_prev)
		out.append(first + (second - first) * frac)
		index += 1
	return out


static func _span_at(samples: PackedFloat32Array, index: int, start: int, prev: float, has_prev: bool) -> float:
	var local := index - start
	if local >= 0 and local < samples.size():
		return samples[local]
	if local == -1 and has_prev:
		return prev
	return 0.0


static func _ascii(buffer: PackedByteArray, at: int, text: String) -> void:
	for index in text.length():
		buffer[at + index] = text.unicode_at(index)


static func _u16(buffer: PackedByteArray, at: int, value: int) -> void:
	buffer[at] = value & 255
	buffer[at + 1] = (value >> 8) & 255


static func _u32(buffer: PackedByteArray, at: int, value: int) -> void:
	buffer.encode_u32(at, value)
