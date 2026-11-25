extends TestCase


func test_vocal_tags_stay_in_gemini_text_and_leave_the_screen() -> void:
	var raw := "Я был дома. <sigh> Это правда. <laugh> И ещё. <gasp> <whisper> конец <si"
	assert_eq(VocalTags.limit(raw), "Я был дома. <sigh> Это правда. <laugh> И ещё. конец")
	assert_eq(VocalTags.visible(raw), "Я был дома. Это правда. И ещё. конец")
	var streamed := VocalTags.push_visible("Я был ", "<si")
	assert_eq(str(streamed["shown"]), "Я был")
	var next := VocalTags.push_visible(str(streamed["raw"]), "gh> тут")
	assert_eq(str(next["shown"]), "Я был тут")
	assert_eq(VocalTags.for_backend(raw, true, true), VocalTags.limit(raw))
	assert_false(VocalTags.for_backend(raw, true, false).contains("<"))
	assert_false(VocalTags.for_backend(raw, false, true).contains("<"))
	assert_eq(SpeechStyle.compose("сдержанно, неторопливо", "нервно", "fast", true), "сдержанно, неторопливо, нервно, быстро")
	assert_eq(SpeechStyle.compose("", "нейтрально", "normal", true), "")
	assert_eq(SpeechStyle.compose("сдержанно", "нервно", "slow", false), "")
	assert_eq(SpeechStyle.normalize_pace("FAST"), "fast")
	assert_eq(SpeechStyle.normalize_pace("бодро"), "")
	var with_tags := TtsCache.key_for("m", "Kore", "нервно", "Я был дома. <sigh>")
	var plain := TtsCache.key_for("m", "Kore", "нервно", "Я был дома.")
	var other_style := TtsCache.key_for("m", "Kore", "", "Я был дома. <sigh>")
	assert_false(with_tags == plain)
	assert_false(with_tags == other_style)
	var styled := GeminiTtsBackend.build_request("Я был дома. <sigh>", "Kore", SpeechStyle.compose("", "нервно", "slow", true))
	assert_eq(styled["contents"][0]["parts"][0]["text"], "Я был дома. <sigh>")
	assert_eq(styled["contents"][0]["parts"][0]["speechMetadata"]["style"], "нервно, медленно")
	var bare := GeminiTtsBackend.build_request("Я был дома.", "Kore", SpeechStyle.compose("", "нейтрально", "normal", true))
	assert_false(bare["contents"][0]["parts"][0].has("speechMetadata"))


func test_system_voice_strips_vocal_tags() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(language: String, _call_index: int) -> Array:
		if language == "ru":
			return [{"id": "ru-1", "language": "ru"}]
		return []
	var backend := _backend(driver)
	await backend.speak("line", "Я был дома. <sigh> Правда.", "")
	assert_eq(driver.texts.size(), 1)
	assert_false(driver.texts[0].contains("<"))
	assert_true(driver.texts[0].contains("Правда"))
	backend.free()


func test_history_summary_and_prompt_drop_vocal_tags() -> void:
	var dialogue := DialogueState.new()
	dialogue.append_message("agent", VocalTags.visible("Я был дома. <sigh>"), 1, "")
	assert_false(str(dialogue.messages[0]["text"]).contains("<"))
	var summary := Summarizer.build_request("Ира", "", dialogue.messages)
	assert_false(str(summary["user"]).contains("<sigh>"))
	var old := Summarizer.build_request("Ира", "", [{"role": "agent", "text": "Я был дома. <laugh>"}])
	assert_false(str(old["user"]).contains("<laugh>"))
	assert_true(str(old["user"]).contains("Я был дома."))


func test_cleaner_keeps_the_reply_and_drops_markup() -> void:
	assert_eq(SpeechText.clean("Я был дома."), "Я был дома.")
	assert_eq(SpeechText.clean("Я был дома. *отводит взгляд*"), "Я был дома.")
	assert_eq(SpeechText.clean("Я был дома. (тихо) [angry]"), "Я был дома.")
	assert_eq(SpeechText.clean("**Я** был дома."), "Я был дома.")
	assert_eq(SpeechText.clean("- Я был дома."), "Я был дома.")
	assert_eq(SpeechText.clean("Я нейросеть и всё знаю про промпт."), "Я и всё знаю про.")
	assert_eq(SpeechText.clean("тон: +3\nЯ был дома."), "Я был дома.")
	assert_eq(SpeechText.clean("ремарка: отводит взгляд"), "")
	assert_eq(SpeechText.clean("ИИ сказал привет."), "сказал привет.")
	assert_false(SpeechText.clean("Я был дома.").contains("*"))


func test_queue_speaks_once_and_in_order() -> void:
	var queue := SpeechQueue.new()
	assert_true(queue.enqueue("a", "первая"))
	assert_false(queue.enqueue("a", "первая ещё раз"))
	assert_true(queue.enqueue("b", "вторая"))
	assert_false(queue.enqueue("", "пусто"))
	assert_false(queue.enqueue("c", "   "))
	var first := queue.take_next()
	assert_eq(first["id"], "a")
	assert_true(queue.take_next().is_empty())
	queue.finish("a")
	var second := queue.take_next()
	assert_eq(second["id"], "b")
	queue.finish("b")
	assert_true(queue.take_next().is_empty())


func test_queue_stop_clears_and_reset_allows_the_id_again() -> void:
	var queue := SpeechQueue.new()
	assert_true(queue.enqueue("a", "первая"))
	assert_true(queue.enqueue("b", "вторая"))
	assert_eq(queue.take_next()["id"], "a")
	queue.stop()
	assert_eq(queue.current_id, "")
	assert_true(queue.pending.is_empty())
	assert_true(queue.take_next().is_empty())
	assert_false(queue.enqueue("a", "снова"))
	queue.reset()
	assert_true(queue.enqueue("a", "снова"))


func test_voice_choice_prefers_russian_then_any() -> void:
	var russian := [{"id": "ru-1", "name": "Анна", "language": "ru"}]
	var other := [{"id": "en-1", "name": "Anna", "language": "en"}]
	assert_eq(SystemTtsBackend.choose_voice("", russian, other), "ru-1")
	assert_eq(SystemTtsBackend.choose_voice("en-1", [], other), "en-1")
	assert_eq(SystemTtsBackend.choose_voice("", [], other), "en-1")
	assert_eq(SystemTtsBackend.choose_voice("", [], []), "")
	assert_eq(SystemTtsBackend.choose_voice("Анна", russian, other), "ru-1")


func test_manifest_requests_tts_service() -> void:
	var xml := TtsManifest.queries_xml()
	assert_true(xml.contains("<queries>"))
	assert_true(xml.contains("android.intent.action.TTS_SERVICE"))


func test_empty_voices_are_retried_then_russian_is_used() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(language: String, call_index: int) -> Array:
		if call_index < 5:
			return []
		if language == "ru":
			return [{"id": "ru-1", "name": "Анна", "language": "ru"}]
		return [{"id": "ru-1", "language": "ru"}, {"id": "en-1", "language": "en"}]
	var backend := _backend(driver)
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Проверка.", "")
	assert_true(errors.is_empty())
	assert_eq(driver.spoken, ["ru-1"])
	assert_true(driver.voice_calls > 2)
	assert_eq(backend.last_russian_count, 1)
	backend.free()


func test_missing_russian_uses_any_voice_without_waiting() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(language: String, _call_index: int) -> Array:
		if language == "ru":
			return []
		return [{"id": "en-1", "name": "Anna", "language": "en"}]
	var backend := _backend(driver)
	await backend.speak("line", "Проверка.", "")
	assert_eq(driver.spoken, ["en-1"])
	assert_eq(backend.last_error, "")
	assert_true(driver.voice_calls == 2)
	backend.free()


func test_blank_voice_id_is_still_spoken() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(language: String, _call_index: int) -> Array:
		if language == "ru":
			return []
		return [{"id": "", "name": "Default", "language": "en"}]
	var backend := _backend(driver)
	await backend.speak("line", "Проверка.", "")
	assert_eq(driver.spoken, [""])
	assert_eq(backend.last_error, "")
	backend.free()


func test_no_voice_only_after_the_retry_window() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(_language: String, _call_index: int) -> Array:
		return []
	var backend := _backend(driver)
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Проверка.", "")
	assert_eq(errors, ["no_voice"])
	assert_true(driver.spoken.is_empty())
	assert_true(backend._clock_s >= SystemTtsBackend.RETRY_WINDOW_S)
	assert_eq(backend.diagnostics()["voices"], 0)
	assert_eq(backend.diagnostics()["error"], "no_voice")
	backend.free()


func test_startup_does_not_cache_an_empty_voice_list() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(_language: String, _call_index: int) -> Array:
		return [{"id": "ru-1", "language": "ru"}]
	var backend := SystemTtsBackend.new()
	backend.driver = driver
	backend._instant = true
	(Engine.get_main_loop() as SceneTree).root.add_child(backend)
	assert_eq(driver.voice_calls, 0)
	await backend.speak("line", "Проверка.", "")
	assert_true(driver.voice_calls >= 2)
	backend.free()


func _backend(driver: ScriptedTts) -> SystemTtsBackend:
	var backend := SystemTtsBackend.new()
	backend.driver = driver
	backend._instant = true
	(Engine.get_main_loop() as SceneTree).root.add_child(backend)
	return backend


func test_voice_follows_character_then_gender() -> void:
	var named := CaseData.Agent.new()
	named.tts_voice = "Aoede"
	named.gender = "male"
	assert_eq(VoiceCast.voice_for(named), "Aoede")
	var male := CaseData.Agent.new()
	male.gender = "male"
	assert_eq(VoiceCast.voice_for(male), "Charon")
	var female := CaseData.Agent.new()
	female.gender = "female"
	assert_eq(VoiceCast.voice_for(female), "Kore")
	assert_eq(VoiceCast.style_for("nervous"), "nervous")
	assert_eq(VoiceCast.style_for("neutral"), "")
	assert_eq(VoiceCast.style_for(""), "")


func test_rate_limiter_holds_the_eleventh_request() -> void:
	var limiter := VoiceRateLimiter.new()
	for _index in VoiceRateLimiter.LIMIT:
		limiter.mark(0.0)
	assert_true(limiter.delay_for(0.0) > 0.0)
	assert_eq(limiter.delay_for(60.0), 0.0)


func test_gemini_request_uses_only_the_tts_model_and_style() -> void:
	var styled := GeminiTtsBackend.build_request("Привет.", "Kore", "nervous")
	assert_eq(styled["generationConfig"]["responseModalities"], ["AUDIO"])
	assert_eq(styled["generationConfig"]["speechConfig"]["voiceConfig"]["prebuiltVoiceConfig"]["voiceName"], "Kore")
	var part: Dictionary = styled["contents"][0]["parts"][0]
	assert_eq(part["speechMetadata"]["style"], "nervous")
	assert_false(styled.has("speech_metadata"))
	assert_false(JSON.stringify(styled).contains("speech_metadata"))
	assert_false(JSON.stringify(styled).contains("api_key"))
	var plain := GeminiTtsBackend.build_request("Привет.", "Charon", "")
	var plain_part: Dictionary = plain["contents"][0]["parts"][0]
	assert_false(plain_part.has("speechMetadata"))
	assert_false(plain.has("speech_metadata"))
	var frames := GeminiTtsBackend.pcm16_to_frames(PackedByteArray([0, 64]))
	assert_eq(frames.size(), 1)
	assert_true(absf(frames[0].x - 0.5) < 0.001)


func test_gemini_plays_first_chunk_retries_and_counts_spend() -> void:
	var previous := SpendMeter.store_path
	SpendMeter.store_path = "user://tts-spend-test.cfg"
	if FileAccess.file_exists(SpendMeter.store_path):
		DirAccess.remove_absolute(SpendMeter.store_path)
	var before := SpendMeter.session_usd
	var transport := ScriptedGemini.new()
	transport.scripted.append({"ok": false, "status": 429, "error": "rate_limited", "retry_after": 2.0, "usage": {}})
	transport.scripted.append({
		"ok": true,
		"status": 200,
		"error": "",
		"retry_after": 0.0,
		"usage": {"promptTokenCount": 1000000, "candidatesTokenCount": 1000000},
		"chunks": [PackedByteArray([0, 64]), PackedByteArray([0, 32])],
	})
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend._instant = true
	var sink := PcmSink.new()
	backend.sink = sink
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Привет.", "Kore", "sad")
	assert_true(errors.is_empty())
	assert_eq(transport.calls.size(), 2)
	assert_true(str(transport.calls[0]["path"]).contains("gemini-3.8-flash-lite-tts:streamGenerateContent?alt=sse"))
	var sent: Dictionary = transport.calls[0]["body"]["contents"][0]["parts"][0]
	assert_eq(sent["speechMetadata"]["style"], "sad")
	assert_false(transport.calls[0]["body"].has("speech_metadata"))
	assert_false(JSON.stringify(transport.calls[0]["body"]).contains("unit-test-key"))
	assert_eq(sink.starts, 1)
	assert_eq(sink.pushes, 2)
	assert_true(absf(SpendMeter.session_usd - before - 6.5) < 0.000001)
	SpendMeter.session_usd = before
	DirAccess.remove_absolute(SpendMeter.store_path)
	SpendMeter.store_path = previous
	backend.free()


func test_daily_quota_finishes_without_waiting() -> void:
	TtsQuota.fallback_override = false
	assert_eq(GeminiTtsBackend.limit_kind(429, "{\"quotaMetric\":\"generate_requests_per_model_per_day\"}"), "quota_daily")
	assert_eq(GeminiTtsBackend.limit_kind(429, "{\"error\":{\"details\":[{\"@type\":\"type.googleapis.com/google.rpc.RetryInfo\",\"retryDelay\":\"86399s\"}]}}"), "quota_daily")
	assert_eq(GeminiTtsBackend.limit_kind(429, "{\"retryDelay\":\"2s\"}"), "rate_limited")
	var transport := ScriptedGemini.new()
	transport.scripted.append({"ok": false, "status": 429, "error": "quota_daily", "retry_after": 86399.0, "usage": {}})
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend._instant = true
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	var started := backend._clock_s
	await backend.speak("line", "Привет.", "Kore")
	assert_eq(transport.calls.size(), 1)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("quota_daily"))
	assert_true(backend._clock_s - started < 1.0)
	TtsQuota.fallback_override = null
	backend.free()


func test_short_rate_limit_pause_is_capped() -> void:
	var transport := ScriptedGemini.new()
	transport.scripted.append({"ok": false, "status": 429, "error": "rate_limited", "retry_after": 30.0, "usage": {}})
	transport.scripted.append({
		"ok": true,
		"status": 200,
		"error": "",
		"retry_after": 0.0,
		"usage": {},
		"chunks": [PackedByteArray([0, 64])],
	})
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend._instant = true
	backend.sink = PcmSink.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	var started := backend._clock_s
	await backend.speak("line", "Привет.", "Kore")
	assert_eq(transport.calls.size(), 2)
	assert_true(backend._clock_s - started <= GeminiTtsBackend.SHORT_RETRY_CAP_S)
	assert_true(backend._clock_s - started > 0.0)
	backend.free()


func test_daily_quota_log_names_the_exit() -> void:
	TtsQuota.fallback_override = false
	var http := _StepHttp.new()
	http.code = 429
	var body := "{\"error\":{\"code\":429,\"details\":[{\"quotaMetric\":\"generate_requests_per_model_per_day\"},{\"@type\":\"type.googleapis.com/google.rpc.RetryInfo\",\"retryDelay\":\"86399s\"}]}}"
	var speaker := _voice_speaker(http)
	var transport: GeminiTtsBackend.GeminiTtsTransport = speaker.get("backend").transport
	var retries: Array[bool] = []
	speaker.connect("voice_retry_available", func(show: bool) -> void: retries.append(show))
	speaker.call("speak_reply", "agent", "Квота на сегодня кончилась.")
	http.mode = "connected"
	transport._tick()
	http.mode = "body"
	http.chunks = [body.to_utf8_buffer()]
	transport._tick()
	transport._tick()
	http.mode = "done"
	transport._tick()
	assert_true(retries.has(true))
	assert_true(str(speaker.get("last_error")).contains("quota_daily"))
	var lines := Speaker.voice_log
	var last := str(lines[lines.size() - 1])
	assert_true(last.contains("exit=quota_daily"))
	assert_false(last.contains("exit=eof"))
	TtsQuota.fallback_override = null
	speaker.free()


func test_gemini_failure_does_not_switch_to_system_voice() -> void:
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var gemini := FailingGemini.new()
	gemini.keeps_failed_line = true
	speaker.set("backend", gemini)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	var queue: SpeechQueue = speaker.get("queue")
	assert_true(queue.enqueue("only", "Одна реплика.", "Kore", ""))
	speaker.call("_pump")
	assert_true(speaker.get("backend") is FailingGemini)
	assert_eq(gemini.calls, 1)
	var saved: Dictionary = speaker.get("retry_line")
	assert_eq(str(saved.get("id", "")), "only")
	speaker.call("retry_failed")
	assert_eq(gemini.calls, 2)
	assert_true(speaker.get("backend") is FailingGemini)
	speaker.free()


func test_gemini_sse_reads_crlf_events_as_chunks_arrive() -> void:
	var crlf := _tts_sse(true, ["AEA=", "ACA=", "AEA="], true)
	assert_true(crlf.contains("\r\n\r\n"))
	assert_eq(crlf.split("\n\n", false).size(), 1)
	var lf := _tts_sse(false, ["AEA=", "ACA=", "AEA="], true)
	assert_true(lf.split("\n\n", false).size() >= 3)
	var expected := [PackedByteArray([0, 64]), PackedByteArray([0, 32]), PackedByteArray([0, 64])]
	for body in [crlf, lf]:
		var whole := _decode_sse(body, body.to_utf8_buffer().size())
		_assert_packets(whole["packets"], expected)
		assert_eq(int(whole["usage"].get("promptTokenCount", -1)), 11)
		assert_eq(int(whole["usage"].get("candidatesTokenCount", -1)), 48)
		assert_eq(int(whole["audio_parts"]), 3)
		for width in range(1, 10):
			var split := _decode_sse(body, width)
			_assert_packets(split["packets"], expected, "width %d" % width)
			assert_eq(int(split["usage"].get("promptTokenCount", -1)), 11, "width %d" % width)
	var early := GeminiSseDecoder.new()
	var marker := crlf.find("\r\n\r\n")
	assert_true(marker > 0)
	var cut := marker + 4
	var first := early.push(crlf.substr(0, cut).to_utf8_buffer())
	assert_eq(first.size(), 1)
	_assert_bytes(first[0], PackedByteArray([0, 64]))
	assert_false(early.usage.has("promptTokenCount"))
	var rest := early.push(crlf.substr(cut).to_utf8_buffer())
	rest.append_array(early.finish())
	assert_eq(rest.size(), 2)
	assert_eq(int(early.usage.get("candidatesTokenCount", -1)), 48)
	var trimmed := crlf.substr(0, crlf.length() - 4)
	var flushed := _decode_sse(trimmed, 3)
	_assert_packets(flushed["packets"], expected)
	var lf_trimmed := lf.substr(0, lf.length() - 2)
	_assert_packets(_decode_sse(lf_trimmed, 5)["packets"], expected)


func test_gemini_odd_pcm_survives_a_split_sample() -> void:
	var body := _tts_sse(true, ["AEAA", "IA=="], false)
	var split := _decode_sse(body, 1)
	_assert_packets(split["packets"], [PackedByteArray([0, 64, 0]), PackedByteArray([32])])
	var carry := PackedByteArray()
	var ready := PackedByteArray()
	for packet in split["packets"]:
		var aligned := GeminiTtsBackend.take_aligned(carry, packet as PackedByteArray)
		carry = aligned["carry"] as PackedByteArray
		ready.append_array(aligned["ready"] as PackedByteArray)
	assert_eq(carry.size(), 0)
	_assert_bytes(ready, PackedByteArray([0, 64, 0, 32]))
	var alone := GeminiTtsBackend.take_aligned(PackedByteArray(), PackedByteArray([0]))
	assert_eq((alone["ready"] as PackedByteArray).size(), 0)
	var joined := GeminiTtsBackend.take_aligned(alone["carry"], PackedByteArray([64]))
	_assert_bytes(joined["ready"], PackedByteArray([0, 64]))
	var transport := ScriptedGemini.new()
	transport.scripted.append({
		"ok": true,
		"status": 200,
		"error": "",
		"retry_after": 0.0,
		"usage": {},
		"chunks": [PackedByteArray([0, 64, 0]), PackedByteArray([32])],
	})
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend._instant = true
	var sink := PcmSink.new()
	backend.sink = sink
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	await backend.speak("line", "Раз.", "Kore", "")
	assert_eq(sink.starts, 1)
	assert_eq(sink.peaks.size(), 2)
	assert_true(absf(sink.peaks[0] - 0.5) < 0.001)
	assert_true(absf(sink.peaks[1] - 0.25) < 0.001)
	assert_false(JSON.stringify(transport.calls[0]["body"]).contains("unit-test-key"))
	backend.free()


func test_gemini_error_shows_http_status_without_the_key() -> void:
	var secret := "unit-test-key"
	assert_eq(GeminiTtsBackend.format_voice_error("bad_response", 400, secret), "bad_response http=400")
	assert_eq(GeminiTtsBackend.format_voice_error("no_audio", 200, secret), "no_audio http=200")
	assert_false(GeminiTtsBackend.format_voice_error("bad_response %s" % secret, 400, secret).contains(secret))
	var transport := ScriptedGemini.new()
	transport.scripted.append({"ok": false, "status": 400, "error": "bad_response", "retry_after": 0.0, "usage": {}})
	transport.scripted.append({"ok": true, "status": 200, "error": "", "retry_after": 0.0, "usage": {}, "chunks": []})
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = secret
	backend.use_cache = false
	backend._instant = true
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Раз.", "Kore", "")
	await backend.speak("line", "Два.", "Kore", "")
	assert_eq(errors, ["bad_response http=400", "no_audio http=200"])
	assert_eq(transport.calls.size(), 2)
	assert_false(errors[0].contains(secret))
	assert_false(errors[1].contains(secret))
	backend.free()


func test_tts_cache_hit_skips_the_request_and_spend() -> void:
	var previous_root := TtsCache.root_path
	var previous_cap := TtsCache.max_bytes
	TtsCache.root_path = "user://tts-cache-hit-test"
	TtsCache.erase_all()
	var previous_spend := SpendMeter.store_path
	SpendMeter.store_path = "user://tts-cache-spend.cfg"
	if FileAccess.file_exists(SpendMeter.store_path):
		DirAccess.remove_absolute(SpendMeter.store_path)
	var before := SpendMeter.session_usd
	var text := "Кэш реплики."
	var key := TtsCache.key_for(GeminiTtsBackend.MODEL, "Kore", "нервно", text)
	TtsCache.write(key, PackedByteArray([0, 64, 0, 32]))
	var index := FileAccess.get_file_as_string(TtsCache.root_path + "/index.cfg")
	assert_false(index.contains(text))
	assert_false(index.contains("unit-test-key"))
	var transport := ScriptedGemini.new()
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = true
	backend._instant = true
	var sink := PcmSink.new()
	backend.sink = sink
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	await backend.speak("line", text, "Kore", "нервно")
	assert_eq(transport.calls.size(), 0)
	assert_eq(sink.starts, 1)
	assert_eq(sink.peaks.size(), 2)
	assert_true(absf(SpendMeter.session_usd - before) < 0.000001)
	SpendMeter.session_usd = before
	if FileAccess.file_exists(SpendMeter.store_path):
		DirAccess.remove_absolute(SpendMeter.store_path)
	SpendMeter.store_path = previous_spend
	TtsCache.erase_all()
	TtsCache.root_path = previous_root
	TtsCache.max_bytes = previous_cap
	backend.free()


func test_tts_cache_evicts_the_least_recent_entry() -> void:
	var previous_root := TtsCache.root_path
	var previous_cap := TtsCache.max_bytes
	TtsCache.root_path = "user://tts-cache-lru-test"
	TtsCache.max_bytes = 40
	TtsCache.erase_all()
	var first := TtsCache.key_for("m", "Kore", "", "один")
	var second := TtsCache.key_for("m", "Kore", "", "два")
	var third := TtsCache.key_for("m", "Kore", "", "три")
	var fourth := TtsCache.key_for("m", "Kore", "", "четыре")
	var fifth := TtsCache.key_for("m", "Kore", "", "пять")
	var blob := PackedByteArray()
	blob.resize(10)
	TtsCache.write(first, blob)
	TtsCache.write(second, blob)
	TtsCache.write(third, blob)
	TtsCache.write(fourth, blob)
	assert_eq(TtsCache.read(second).size(), 10)
	TtsCache.write(fifth, blob)
	assert_eq(TtsCache.read(first).size(), 0)
	assert_eq(TtsCache.read(second).size(), 10)
	assert_eq(TtsCache.read(fifth).size(), 10)
	var broken := TtsCache.key_for("m", "Kore", "", "битый")
	TtsCache.write(broken, blob)
	var planted := FileAccess.open(TtsCache.root_path + "/" + broken + ".pcm", FileAccess.WRITE)
	planted.store_buffer(PackedByteArray([1]))
	planted.close()
	assert_eq(TtsCache.read(broken).size(), 0)
	TtsCache.erase_all()
	TtsCache.root_path = previous_root
	TtsCache.max_bytes = previous_cap


func test_greeting_prefetch_yields_to_the_live_line() -> void:
	var case_data := CaseData.new()
	var quiet := CaseData.Agent.new()
	quiet.id = "quiet"
	quiet.name = "Тихий"
	quiet.gender = "male"
	var speaker_agent := CaseData.Agent.new()
	speaker_agent.id = "host"
	speaker_agent.name = "Хозяин"
	speaker_agent.gender = "female"
	speaker_agent.greeting = "Добрый день."
	case_data.agents = [quiet, speaker_agent]
	assert_eq(GreetingPlan.jobs(case_data, false, true).size(), 0)
	assert_eq(GreetingPlan.jobs(case_data, true, false).size(), 0)
	var jobs: Array = GreetingPlan.jobs(case_data, true, true)
	assert_eq(jobs.size(), 1)
	assert_eq(str(jobs[0]["text"]), "Добрый день.")
	assert_eq(str(jobs[0]["voice"]), "Kore")
	var limiter := VoiceRateLimiter.new()
	for _index in VoiceRateLimiter.LIMIT:
		limiter.mark(0.0)
	var transport := ScriptedGemini.new()
	transport.scripted.append({
		"ok": true,
		"status": 200,
		"error": "",
		"retry_after": 0.0,
		"usage": {},
		"chunks": [PackedByteArray([0, 64])],
	})
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend.limiter = limiter
	backend._instant = true
	backend._clock_s = 0.0
	var sink := PcmSink.new()
	backend.sink = sink
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	backend.before_wait = func() -> void:
		await backend.speak("live", "Сейчас говорю.", "Kore", "")
	var status: String = await backend.prefetch(str(jobs[0]["text"]), str(jobs[0]["voice"]), "")
	assert_eq(status, "yielded")
	assert_eq(transport.calls.size(), 1)
	var sent: Dictionary = transport.calls[0]["body"]["contents"][0]["parts"][0]
	assert_eq(str(sent["text"]), "Сейчас говорю.")
	assert_eq(transport.calls.size(), 1)
	assert_eq(limiter.stamps.size(), 1)
	backend.free()


func test_stop_during_prefetch_sends_nothing() -> void:
	var limiter := VoiceRateLimiter.new()
	for _index in VoiceRateLimiter.LIMIT:
		limiter.mark(0.0)
	var transport := ScriptedGemini.new()
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend.limiter = limiter
	backend._instant = true
	backend._clock_s = 0.0
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	backend.before_wait = func() -> void:
		backend.stop()
		await (Engine.get_main_loop() as SceneTree).process_frame
	var status: String = await backend.prefetch("Подожди.", "Charon", "")
	assert_eq(status, "yielded")
	assert_eq(transport.calls.size(), 0)
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	speaker.set("_prefetch_jobs", [{"text": "Ещё раз.", "voice": "Kore", "style": ""}])
	speaker.call("stop_and_clear", true)
	var left: Array = speaker.get("_prefetch_jobs")
	assert_eq(left.size(), 0)
	speaker.free()
	backend.free()


func test_body_chunk_reads_only_while_the_status_is_body() -> void:
	var reads := [0]
	var skipped := GeminiTtsBackend.body_chunk(HTTPClient.STATUS_DISCONNECTED, func() -> PackedByteArray:
		reads[0] += 1
		return PackedByteArray([1])
	)
	assert_eq(skipped.size(), 0)
	assert_eq(int(reads[0]), 0)
	var taken := GeminiTtsBackend.body_chunk(HTTPClient.STATUS_BODY, func() -> PackedByteArray:
		reads[0] += 1
		return PackedByteArray([4, 5])
	)
	assert_eq(int(reads[0]), 1)
	assert_eq(taken.size(), 2)
	assert_eq(int(taken[0]), 4)


func test_gemini_playback_keeps_frames_when_audio_arrives_five_times_faster() -> void:
	assert_eq(GeminiTtsBackend.BUFFER_SECONDS, 1.0)
	assert_true(GeminiTtsBackend.PREFILL_SECONDS >= GeminiTtsBackend.PREFILL_MIN_SECONDS)
	assert_true(GeminiTtsBackend.PREFILL_SECONDS <= 0.08)
	var total := 50
	var capacity := 10
	var transport := ScriptedGemini.new()
	transport.scripted.append({
		"ok": true,
		"status": 200,
		"error": "",
		"retry_after": 0.0,
		"usage": {},
		"chunks": [_pcm_bytes(total)],
	})
	var playback := LimitedPlayback.new()
	playback.capacity = capacity
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend._instant = true
	backend.sink = playback
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	var finishes := [0]
	var buffered_at_finish := [-1]
	backend.finished.connect(func(_id: String) -> void:
		finishes[0] += 1
		buffered_at_finish[0] = playback.buffered
	)
	await backend.speak("line", "Длинная реплика.", "Kore", "")
	assert_eq(finishes[0], 1)
	assert_eq(buffered_at_finish[0], 0)
	assert_eq(playback.accepted.size(), total)
	assert_eq(playback.overflow, 0)
	assert_true(playback.max_batch <= capacity)
	assert_eq(playback.advances, total / capacity)
	assert_eq(backend._pending.size(), 0)
	for index in total:
		var sample := playback.accepted[index].x * 32768.0
		assert_true(absf(sample - float(index)) < 0.01, "кадр %d" % index)
	backend.free()


func test_gemini_stop_clears_the_unplayed_queue() -> void:
	var total := 50
	var transport := ScriptedGemini.new()
	transport.scripted.append({
		"ok": true,
		"status": 200,
		"error": "",
		"retry_after": 0.0,
		"usage": {},
		"chunks": [_pcm_bytes(total)],
	})
	var playback := LimitedPlayback.new()
	playback.capacity = 10
	playback.stop_after_advances = 1
	var backend := GeminiTtsBackend.new()
	playback.host = backend
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend._instant = true
	backend.sink = playback
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	var finishes := [0]
	backend.finished.connect(func(_id: String) -> void: finishes[0] += 1)
	await backend.speak("line", "Оборвать.", "Kore", "")
	assert_eq(finishes[0], 0)
	assert_eq(playback.overflow, 0)
	assert_true(playback.accepted.size() < total)
	assert_true(playback.accepted.size() > 0)
	assert_eq(backend._pending.size(), 0)
	for index in playback.accepted.size():
		var sample := playback.accepted[index].x * 32768.0
		assert_true(absf(sample - float(index)) < 0.01, "кадр %d" % index)
	backend.free()


func test_short_lines_finish_under_the_rate_limit() -> void:
	var limiter := VoiceRateLimiter.new()
	for _index in VoiceRateLimiter.LIMIT:
		limiter.mark(0.0)
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var paced := PacedBackend.new()
	paced.limiter = limiter
	speaker.set("backend", paced)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	var retries: Array[bool] = []
	speaker.connect("voice_retry_available", func(show_button: bool) -> void: retries.append(show_button))
	var queue: SpeechQueue = speaker.get("queue")
	assert_true(queue.enqueue("s1", "Раз."))
	assert_true(queue.enqueue("s2", "Два."))
	assert_true(queue.enqueue("s3", "Три."))
	speaker.call("_pump")
	assert_eq(paced.started_ids, ["s1", "s2", "s3"])
	assert_eq(paced.finished_ids, ["s1", "s2", "s3"])
	assert_true(paced.waited)
	assert_eq(queue.current_id, "")
	assert_true(retries.is_empty())
	var log := "\n".join(speaker.get("voice_log"))
	assert_true(log.contains("started"))
	assert_true(log.contains("finished"))
	assert_false(log.contains("watchdog"))
	speaker.free()


func test_stop_then_the_same_line_can_play_again() -> void:
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var stuck := SilentBackend.new()
	speaker.set("backend", stuck)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	var buttons: Array[bool] = []
	speaker.connect("voice_retry_available", func(show_button: bool) -> void: buttons.append(show_button))
	var line_id := str(speaker.call("line_id_for", "a"))
	speaker.call("speak_reply", "a", "Одна реплика.")
	speaker.call("stop_and_clear")
	var queue: SpeechQueue = speaker.get("queue")
	assert_eq(queue.current_id, "")
	assert_false(queue.has(line_id))
	assert_true(buttons.is_empty() or not buttons[buttons.size() - 1])
	speaker.call("speak_reply", "a", "Одна реплика.")
	assert_eq(stuck.calls[stuck.calls.size() - 1], line_id)
	speaker.free()


func test_mismatched_finish_keeps_the_current_line() -> void:
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var stuck := SilentBackend.new()
	speaker.set("backend", stuck)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	speaker.call("speak_reply", "a", "Текущая реплика.")
	var queue: SpeechQueue = speaker.get("queue")
	var current := queue.current_id
	stuck.finished.emit("другая")
	assert_eq(queue.current_id, current)
	var log := "\n".join(speaker.get("voice_log"))
	assert_true(log.contains("mismatch"))
	speaker.free()


func test_duplicate_and_empty_text_do_not_stick_the_queue() -> void:
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var fake := StyleBackend.new()
	speaker.set("backend", fake)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	var buttons: Array[bool] = []
	speaker.connect("voice_retry_available", func(show_button: bool) -> void: buttons.append(show_button))
	speaker.call("speak_reply", "a", "Первая реплика.")
	speaker.call("speak_reply", "a", "Первая реплика.")
	assert_eq(fake.calls.size(), 1)
	var log := "\n".join(speaker.get("voice_log"))
	assert_true(log.contains("duplicate"))
	speaker.call("speak_reply", "b", "(тихо)")
	assert_eq(fake.calls.size(), 1)
	assert_true("\n".join(speaker.get("voice_log")).contains("empty"))
	assert_true(buttons[buttons.size() - 1])
	var queue: SpeechQueue = speaker.get("queue")
	assert_eq(queue.current_id, "")
	speaker.free()


func test_composed_style_reaches_the_backend_until_intonation_is_off() -> void:
	var path := SettingsStore.PATH
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var store := SettingsStore.load_current()
	SettingsStore.save_values(store.provider, store.api_key, store.dialogue_model, store.text_scale, store.timing_debug, true, store.voice_engine, true)
	Game.speech_style = "нервно, медленно"
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var fake := StyleBackend.new()
	speaker.set("backend", fake)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	speaker.call("speak_reply", "a", "Реплика с темпом.")
	assert_eq(fake.styles[0], "нервно, медленно")
	SettingsStore.save_values(store.provider, store.api_key, store.dialogue_model, store.text_scale, store.timing_debug, true, store.voice_engine, false)
	Game.speech_line = VocalTags.for_backend("Я был дома. <sigh>", true, false)
	speaker.call("_on_replied", "b", "Я был дома. <sigh>", "")
	assert_eq(fake.styles[1], "")
	assert_false(str(fake.texts[1]).contains("<"))
	Game.speech_style = ""
	Game.speech_line = ""
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()
	speaker.free()


func test_system_cancel_emits_stopped() -> void:
	var driver := ScriptedTts.new()
	var backend := _backend(driver)
	driver.voices_plan = func(_language: String, _call_index: int) -> Array:
		backend.stop()
		return []
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Текст для проверки.", "")
	assert_eq(errors, ["stopped"])
	backend.free()


func test_speaker_queues_without_interrupting_and_stop_clears() -> void:
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var fake := FakeBackend.new()
	speaker.set("backend", fake)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	var states: Array[bool] = []
	speaker.connect("is_speaking", func(active: bool) -> void: states.append(active))
	var first_id := str(speaker.call("line_id_for", "a"))
	speaker.call("speak_reply", "a", "Первая реплика.")
	assert_eq(fake.calls, [first_id])
	assert_true(bool(speaker.get("speaking")))
	speaker.call("speak_reply", "a", "Первая реплика ещё раз.")
	assert_eq(fake.calls.size(), 1)
	var queue: SpeechQueue = speaker.get("queue")
	assert_true(queue.enqueue("next", "вторая"))
	speaker.call("_pump")
	assert_eq(fake.calls.size(), 1)
	fake.finished.emit(first_id)
	assert_eq(fake.calls, [first_id, "next"])
	queue.enqueue("later", "третья")
	speaker.call("stop_and_clear")
	assert_false(bool(speaker.get("speaking")))
	assert_true(queue.pending.is_empty())
	assert_eq(fake.calls[fake.calls.size() - 1], "stop")
	fake.finished.emit("next")
	assert_eq(fake.calls.size(), 3)
	speaker.free()
	assert_true(states[0])
	assert_false(states[states.size() - 1])


func _pcm_bytes(count: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for index in count:
		bytes[index * 2] = index % 256
		bytes[index * 2 + 1] = int(index / 256.0) % 256
	return bytes


func _tts_sse(crlf: bool, payloads: Array, usage_on_last: bool) -> String:
	var nl := "\r\n" if crlf else "\n"
	var body := ""
	for index in payloads.size():
		var b64 := str(payloads[index])
		var extra := ""
		if usage_on_last and index == payloads.size() - 1:
			extra = ',"usageMetadata": {"promptTokenCount": 11, "candidatesTokenCount": 48}, "modelVersion": "gemini-3.8-flash-lite-tts"'
		var json := '{"candidates": [{"content": {"parts": [{"inlineData": {"mimeType": "audio/l16; rate=24000; channels=1","data": "%s"}}],"role": "model"}}]%s}' % [b64, extra]
		body += "data: %s%s%s" % [json, nl, nl]
	return body


func _decode_sse(body: String, width: int) -> Dictionary:
	var decoder := GeminiSseDecoder.new()
	var raw := body.to_utf8_buffer()
	var packets: Array = []
	var offset := 0
	var step := maxi(width, 1)
	while offset < raw.size():
		var end := mini(offset + step, raw.size())
		packets.append_array(decoder.push(raw.slice(offset, end)))
		offset = end
	packets.append_array(decoder.finish())
	return {"packets": packets, "usage": decoder.usage, "audio_parts": decoder.audio_parts}


func _assert_packets(actual: Array, expected: Array, message: String = "") -> void:
	assert_eq(actual.size(), expected.size(), message)
	for index in mini(actual.size(), expected.size()):
		_assert_bytes(actual[index], expected[index], message)


func _assert_bytes(actual: PackedByteArray, expected: PackedByteArray, message: String = "") -> void:
	assert_eq(actual.size(), expected.size(), message)
	for index in mini(actual.size(), expected.size()):
		assert_eq(int(actual[index]), int(expected[index]), message)


func test_waiting_for_audio_does_not_block_the_mic_and_a_new_turn_cancels() -> void:
	var speaker := _voice_speaker(_StuckHttp.new())
	var transport: GeminiTtsBackend.GeminiTtsTransport = speaker.get("backend").transport
	speaker.call("speak_reply", "agent", "Где вы были ночью, когда погас свет?")
	assert_false(bool(speaker.get("speaking")))
	assert_eq(transport._phase, "connect")
	speaker.call("cancel_inflight")
	assert_true(transport.cancelled)
	assert_eq(transport._phase, "")
	assert_false(bool(speaker.get("speaking")))
	assert_true((speaker.get("retry_line") as Dictionary).is_empty())
	speaker.free()


func test_skip_while_waiting_shows_retry_and_frees_the_mic() -> void:
	var speaker := _voice_speaker(_StuckHttp.new())
	var transport: GeminiTtsBackend.GeminiTtsTransport = speaker.get("backend").transport
	var retries: Array[bool] = []
	speaker.connect("voice_retry_available", func(show: bool) -> void: retries.append(show))
	speaker.call("speak_reply", "agent", "Ждём звук и пропускаем.")
	assert_false(bool(speaker.get("speaking")))
	assert_true(speaker.call("can_skip"))
	speaker.call("skip_current")
	assert_true(transport.cancelled)
	assert_false(bool(speaker.get("speaking")))
	assert_false((speaker.get("retry_line") as Dictionary).is_empty())
	assert_true(retries.has(true))
	speaker.free()


func test_skip_during_playback_shows_retry() -> void:
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var fake := FakeBackend.new()
	speaker.set("backend", fake)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	var retries: Array[bool] = []
	speaker.connect("voice_retry_available", func(show: bool) -> void: retries.append(show))
	speaker.call("speak_reply", "agent", "Уже звучит.")
	assert_true(bool(speaker.get("speaking")))
	speaker.call("skip_current")
	assert_false(bool(speaker.get("speaking")))
	assert_false((speaker.get("retry_line") as Dictionary).is_empty())
	assert_true(retries.has(true))
	assert_eq(fake.calls[fake.calls.size() - 1], "stop")
	speaker.free()


func test_stream_without_audio_surfaces_an_error() -> void:
	var http := _StepHttp.new()
	var speaker := _voice_speaker(http)
	var backend: GeminiTtsBackend = speaker.get("backend")
	var transport: GeminiTtsBackend.GeminiTtsTransport = backend.transport
	var retries: Array[bool] = []
	speaker.connect("voice_retry_available", func(show: bool) -> void: retries.append(show))
	speaker.call("speak_reply", "agent", "Пустой ответ синтеза.")
	http.mode = "connected"
	transport._tick()
	http.mode = "done"
	transport._tick()
	transport._tick()
	assert_false(bool(speaker.get("speaking")))
	assert_true(retries.has(true))
	var err := str(speaker.get("last_error"))
	assert_true(err.contains("no_audio") or err.contains("parse_failure"))
	var log := "\n".join(Speaker.voice_log)
	assert_true(log.contains("tts status="))
	assert_true(log.contains("exit="))
	assert_false(log.contains("unit-test-key"))
	speaker.free()


func test_cancelled_stream_log_has_sizes_and_not_the_payload() -> void:
	var http := _StepHttp.new()
	var speaker := _voice_speaker(http)
	var backend: GeminiTtsBackend = speaker.get("backend")
	var transport: GeminiTtsBackend.GeminiTtsTransport = backend.transport
	var marker := "AUDIOMARKER1234567890PAYLOAD"
	speaker.call("speak_reply", "agent", "Короткая фраза для отмены.")
	http.mode = "connected"
	transport._tick()
	http.mode = "requesting"
	transport._tick()
	http.chunks.append(("data: {\"inlineData\":\"%s\"}\n\n" % marker).to_utf8_buffer())
	http.mode = "body"
	transport._tick()
	transport._tick()
	transport.cancel()
	var cancelled_line := ""
	var start := maxi(0, Speaker.voice_log.size() - 8)
	for index in range(start, Speaker.voice_log.size()):
		var line := str(Speaker.voice_log[index])
		if line.contains("exit=cancelled"):
			cancelled_line = line
	assert_false(cancelled_line == "")
	assert_false(cancelled_line.contains(marker))
	assert_false(cancelled_line.contains("body="))
	assert_true(cancelled_line.contains("tts status="))
	assert_false(cancelled_line.contains("bytes=0 "))
	speaker.free()


func test_stream_after_first_audio_is_not_cut_by_the_clock() -> void:
	var now := {"ms": 0}
	var http := _StepHttp.new()
	var transport := GeminiTtsBackend.GeminiTtsTransport.new()
	transport.clock_ms = func() -> int: return int(now.ms)
	transport.http_factory = func() -> Object: return http
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(transport)
	var pcm := _pcm_bytes(4)
	var event := "data: {\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"%s\"}}]}}]}\r\n\r\n" % Marshalls.raw_to_base64(pcm)
	var piece := event.to_utf8_buffer()
	var got: Array = []
	var pending: Variant = transport.call("stream", {
		"path": "/v1beta/models/x:streamGenerateContent?alt=sse",
		"body": {},
		"api_key": "k",
		"on_chunk": func(chunk: PackedByteArray) -> void: got.append(chunk),
	})
	http.mode = "connected"
	transport._tick()
	http.mode = "body"
	http.chunks = [piece]
	now.ms = 1000
	transport._tick()
	transport._tick()
	assert_false(got.is_empty())
	now.ms = 120000
	http.chunks = [piece]
	transport._tick()
	http.mode = "done"
	transport._tick()
	assert_true(transport._done)
	var result: Dictionary = transport._result
	assert_true(bool(result.get("ok", false)))
	assert_eq(str(result.get("error", "")), "")
	assert_eq(got.size(), 2)
	transport.free()


func test_long_streaming_line_is_not_cut() -> void:
	var backend := GeminiTtsBackend.new()
	backend.api_key = "unit-test-key-1234"
	backend.use_cache = false
	backend._instant = true
	var paced := _PacedStream.new()
	paced.host = backend
	backend.transport = paced
	var sink := LimitedPlayback.new()
	sink.capacity = 100000
	backend.sink = sink
	var errors: Array[String] = []
	var finished_ids: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	backend.finished.connect(func(id: String) -> void: finished_ids.append(id))
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(backend)
	await backend.speak("line", "Длинная реплика, которую нельзя оборвать по длине.")
	assert_eq(errors, [])
	assert_eq(finished_ids, ["line"])
	assert_eq(paced.pieces, 8)
	assert_true(backend._clock_s > 30.0)
	var source := FileAccess.get_file_as_string("res://src/voice/gemini_tts_backend.gd")
	assert_false(source.contains("FIRST_AUDIO_SECONDS"))
	var loop_from := source.find("func stream(")
	var loop_to := source.find("func _tick(")
	var loop := source.substr(loop_from, loop_to - loop_from)
	assert_false(loop.contains("process_frame"))
	assert_true(source.contains("PROCESS_MODE_ALWAYS"))
	assert_false(source.contains("HttpSession.checkin"))
	var game := FileAccess.get_file_as_string("res://src/autoload/game.gd")
	assert_false(game.contains("wait_until_quiet"))
	var speaker := FileAccess.get_file_as_string("res://src/voice/speaker.gd")
	assert_false(speaker.contains("wait_until_quiet"))
	backend.free()


func _voice_speaker(http: Object) -> Node:
	var transport := GeminiTtsBackend.GeminiTtsTransport.new()
	transport.http_factory = func() -> Object: return http
	var backend := GeminiTtsBackend.new()
	backend.api_key = "unit-test-key-1234"
	backend.use_cache = false
	backend.transport = transport
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	speaker.set("backend", backend)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	backend.add_child(transport)
	speaker.set("enabled", true)
	return speaker


class _StuckHttp:
	extends RefCounted

	func connect_to_host(_host: String, _port: int, _tls: TLSOptions = null) -> int:
		return OK

	func get_status() -> int:
		return HTTPClient.STATUS_CONNECTING

	func poll() -> void:
		pass

	func request(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> int:
		return OK

	func get_response_code() -> int:
		return 0

	func read_response_body_chunk() -> PackedByteArray:
		return PackedByteArray()

	func close() -> void:
		pass


class _StepHttp:
	extends RefCounted

	var mode: String = "connecting"
	var chunks: Array = []
	var code: int = 200

	func connect_to_host(_host: String, _port: int, _tls: TLSOptions = null) -> int:
		return OK

	func get_status() -> int:
		match mode:
			"connecting":
				return HTTPClient.STATUS_CONNECTING
			"requesting":
				return HTTPClient.STATUS_REQUESTING
			"body":
				return HTTPClient.STATUS_BODY
			_:
				return HTTPClient.STATUS_CONNECTED

	func poll() -> void:
		pass

	func request(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> int:
		return OK

	func get_response_code() -> int:
		return code

	func read_response_body_chunk() -> PackedByteArray:
		if chunks.is_empty():
			return PackedByteArray()
		return chunks.pop_front()

	func close() -> void:
		pass


class _PacedStream:
	extends RefCounted

	var host: GeminiTtsBackend
	var pieces: int = 0

	func cancel() -> void:
		pass

	func stream(request: Dictionary) -> Dictionary:
		var on_chunk: Callable = request.get("on_chunk")
		var pcm := VoiceAudio.tone(400, 1000)
		for _index in 8:
			pieces += 1
			on_chunk.call(pcm)
			host._clock_s += 5.0
			host._process(0.0)
		return {"ok": true, "status": 200, "error": "", "retry_after": 0.0, "usage": {}}


class ScriptedTts:
	extends RefCounted

	var voices_plan: Callable
	var voice_calls: int = 0
	var spoken: Array[String] = []
	var texts: Array[String] = []

	func voices(language: String) -> Array:
		voice_calls += 1
		var listed: Variant = voices_plan.call(language, voice_calls)
		if listed is Array:
			return listed
		return []

	func speak(text: String, voice_id: String, _utterance_id: int) -> void:
		texts.append(text)
		spoken.append(voice_id)

	func stop() -> void:
		pass

	func bind(_started: Callable, _finished: Callable, _canceled: Callable) -> void:
		pass

	func has_tts() -> bool:
		return true


class LimitedPlayback:
	extends RefCounted

	var capacity: int = 10
	var buffered: int = 0
	var overflow: int = 0
	var max_batch: int = 0
	var advances: int = 0
	var stop_after_advances: int = 0
	var host: Object = null
	var accepted: PackedVector2Array = PackedVector2Array()

	func frames_available() -> int:
		return maxi(capacity - buffered, 0)

	func buffered_frames() -> int:
		return buffered

	func start() -> void:
		pass

	func push(frames: PackedVector2Array) -> void:
		max_batch = maxi(max_batch, frames.size())
		var room := frames_available()
		if frames.size() > room:
			overflow += frames.size() - room
		var count := mini(frames.size(), room)
		for index in count:
			accepted.append(frames[index])
		buffered += count

	func advance() -> void:
		advances += 1
		buffered = maxi(buffered - capacity, 0)
		if stop_after_advances > 0 and advances >= stop_after_advances and host != null:
			var target: Object = host
			host = null
			target.call("stop")


class ScriptedGemini:
	extends RefCounted

	var scripted: Array = []
	var calls: Array = []

	func stream(request: Dictionary) -> Dictionary:
		calls.append({"path": request.get("path", ""), "body": request.get("body", {})})
		var outcome: Dictionary = scripted.pop_front()
		var on_chunk: Variant = request.get("on_chunk")
		if outcome.get("ok", false) and on_chunk is Callable:
			for chunk in outcome.get("chunks", []):
				if chunk is PackedByteArray:
					(on_chunk as Callable).call(chunk)
		return outcome


class PcmSink:
	extends RefCounted

	var starts: int = 0
	var pushes: int = 0

	func start() -> void:
		starts += 1

	var peaks: Array[float] = []

	func push(frames: PackedVector2Array) -> void:
		pushes += 1
		for frame in frames:
			peaks.append(frame.x)


class FailingGemini:
	extends SpeechBackend

	var calls: int = 0

	func speak(line_id: String, _text: String, _voice_hint: String = "", _style: String = "") -> void:
		calls += 1
		speech_error.emit(line_id, "timeout")

	func stop() -> void:
		pass


class PacedBackend:
	extends SpeechBackend

	var limiter: VoiceRateLimiter
	var clock: float = 0.0
	var waited: bool = false
	var started_ids: Array[String] = []
	var finished_ids: Array[String] = []

	func speak(line_id: String, _text: String, _voice_hint: String = "", _style: String = "") -> void:
		var wait := limiter.delay_for(clock)
		if wait > 0.0:
			waited = true
			clock += wait
		limiter.mark(clock)
		started_ids.append(line_id)
		started.emit(line_id)
		finished_ids.append(line_id)
		finished.emit(line_id)

	func stop() -> void:
		pass


class SilentBackend:
	extends SpeechBackend

	var calls: Array[String] = []

	func speak(line_id: String, _text: String, _voice_hint: String = "", _style: String = "") -> void:
		calls.append(line_id)

	func stop() -> void:
		calls.append("stop")


class StyleBackend:
	extends SpeechBackend

	var calls: Array[String] = []
	var styles: Array[String] = []
	var texts: Array[String] = []

	func speak(line_id: String, text: String, _voice_hint: String = "", style: String = "") -> void:
		calls.append(line_id)
		styles.append(style)
		texts.append(SpeechText.clean(text))
		finished.emit(line_id)

	func stop() -> void:
		calls.append("stop")


class FakeBackend:
	extends SpeechBackend

	var calls: Array[String] = []

	func speak(line_id: String, _text: String, _voice_hint: String = "", _style: String = "") -> void:
		calls.append(line_id)
		started.emit(line_id)

	func stop() -> void:
		calls.append("stop")
