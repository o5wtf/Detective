extends TestCase


func test_lowpass_keeps_speech_and_cuts_high_frequencies() -> void:
	var voice := _sine(44100, 1000.0, 0.25, 16000)
	var voice_step: Dictionary = VoiceAudio.capture_chunk(voice, 44100, {})
	var down: PackedByteArray = voice_step.pcm
	var voice_level := _rms(_middle(voice))
	var down_level := _rms(_middle(down))
	assert_true(down_level > voice_level * 0.9)
	assert_true(down_level < voice_level * 1.1)
	var hiss := _sine(44100, 12000.0, 0.25, 16000)
	var hiss_step: Dictionary = VoiceAudio.capture_chunk(hiss, 44100, {})
	var folded: PackedByteArray = hiss_step.pcm
	assert_true(_rms(folded) * 10.0 <= _rms(hiss))


func test_chunked_downsample_matches_the_whole_buffer() -> void:
	var pcm := _sine(44100, 1000.0, 0.2, 12000)
	var whole_step: Dictionary = VoiceAudio.capture_chunk(pcm, 44100, {})
	var whole: PackedByteArray = whole_step.pcm
	var half := pcm.size() / 4 * 2
	var first: Dictionary = VoiceAudio.capture_chunk(pcm.slice(0, half), 44100, {})
	var second: Dictionary = VoiceAudio.capture_chunk(pcm.slice(half), 44100, first.state)
	var joined := PackedByteArray()
	joined.append_array(first.pcm)
	joined.append_array(second.pcm)
	assert_eq(joined.size(), whole.size())
	var worst := 0
	for index in mini(joined.size(), whole.size()) / 2:
		worst = maxi(worst, absi(VoiceAudio.sample_at(joined, index) - VoiceAudio.sample_at(whole, index)))
	assert_true(worst <= 1, "стык кусков %d" % worst)


func test_level_match_is_capped_and_does_not_clip() -> void:
	var quiet := VoiceAudio.tone(160, 10000)
	var lifted := VoiceAudio.normalize_speech(quiet)
	assert_true(absi(VoiceAudio.peak(lifted) - VoiceAudio.TARGET_PEAK) <= 1)
	var whisper := VoiceAudio.tone(160, 1000)
	var capped := VoiceAudio.normalize_speech(whisper)
	assert_eq(VoiceAudio.peak(capped), 4000)
	var loud := VoiceAudio.tone(160, 30000)
	assert_eq(VoiceAudio.peak(VoiceAudio.normalize_speech(loud)), 30000)
	var hot := VoiceAudio.tone(160, 20000)
	var safe := VoiceAudio.normalize_speech(hot)
	assert_true(VoiceAudio.peak(safe) <= 32767)


func test_sixteen_khz_input_is_not_filtered() -> void:
	var pcm := VoiceAudio.tone(320, 9000)
	var same_step: Dictionary = VoiceAudio.capture_chunk(pcm, 16000, {})
	var same: PackedByteArray = same_step.pcm
	assert_eq(same.size(), pcm.size())
	assert_eq(VoiceAudio.sample_at(same, 0), 9000)


func _sine(rate: int, freq: float, seconds: float, amplitude: int) -> PackedByteArray:
	var frames := int(float(rate) * seconds)
	var out := PackedByteArray()
	out.resize(frames * 2)
	for index in frames:
		var value := int(round(sin(TAU * freq * float(index) / float(rate)) * float(amplitude)))
		VoiceAudio.put_sample(out, index, value)
	return out


func _middle(pcm: PackedByteArray) -> PackedByteArray:
	var frames := pcm.size() / 2
	var start := mini(frames / 5, frames)
	var finish := maxi(start + 1, frames - start)
	var out := PackedByteArray()
	for index in range(start, finish):
		var sample := VoiceAudio.sample_at(pcm, index)
		var at := out.size()
		out.resize(at + 2)
		VoiceAudio.put_sample(out, at / 2, sample)
	return out


func _rms(pcm: PackedByteArray) -> float:
	var frames := pcm.size() / 2
	if frames == 0:
		return 0.0
	var total := 0.0
	for index in frames:
		var sample := float(VoiceAudio.sample_at(pcm, index))
		total += sample * sample
	return sqrt(total / float(frames))
