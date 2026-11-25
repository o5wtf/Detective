class_name GeminiTtsBackend
extends SpeechBackend
## Gemini 3.8 Flash-Lite TTS. PCM 24 кГц начинается с первого целого сэмпла.
## События SSE разбираются по мере чтения тела. При ошибке после повторов
## системный голос не включается: это решает очередь.


const MODEL := "gemini-3.8-flash-lite-tts"
const SAMPLE_RATE := 24000
const BUFFER_SECONDS := 1.0
## Меньше 0.15 с, но не ниже одного короткого буфера: иначе на устройстве слышны разрывы.
const PREFILL_SECONDS := 0.06
const PREFILL_MIN_SECONDS := 0.04
const MAX_ATTEMPTS := 3
## Короткий 429 (в минуту) можно повторить, но не дольше этой паузы.
const SHORT_RETRY_CAP_S := 2.0
## retryDelay длиннее этого, или метрика per_day, — суточная квота, без ожидания.
const DAILY_DELAY_S := 60.0
const INPUT_USD_PER_MILLION := 0.50
const OUTPUT_USD_PER_MILLION := 6.0
## Тот же учёт токенов, что у lite. Минута flash ~$0.014 против ~$0.009 у lite.
const FLASH_INPUT_USD_PER_MILLION := 0.50 * (0.014 / 0.009)
const FLASH_OUTPUT_USD_PER_MILLION := 6.0 * (0.014 / 0.009)

var transport: Object = null
var api_key: String = ""
var limiter: VoiceRateLimiter = VoiceRateLimiter.new()
var sink: Object = null
var use_cache: bool = true
var _instant: bool = false
var _clock_s: float = 0.0
var _generation: int = 0
var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _line_id: String = ""
var _started_line: bool = false
var _download_done: bool = false
var _device_capacity: int = 0
var _pcm_carry: PackedByteArray = PackedByteArray()
var _pending: PackedVector2Array = PackedVector2Array()
var _capture: PackedByteArray = PackedByteArray()
var _silent: bool = false
var _live: bool = false
var _prefetch_gen: int = 0
var _closed_line: String = ""
var _fail_kind: String = ""
var _active_text: String = ""
var _active_voice: String = ""
var _active_style: String = ""
var _voiced_model: String = ""
var _cache_text: String = ""
var _cache_voice: String = ""
var _cache_style: String = ""
var _capture_stored: bool = false
var _extra_chars: int = -1
var _extra_chunks: int = 0
var _chirp_queue: Array[PackedByteArray] = []
var _chirp_busy: bool = false
var _chirp_token: int = -1
var _chirp_results: Array = []
var _chirp_results_token: int = -1
var chirp_events: PackedStringArray = PackedStringArray()

signal chirp_piece_ready
## Вызывается один раз перед ожиданием лимита. Нужен, чтобы живая реплика обогнала подготовку.
var before_wait: Callable = Callable()


func _ready() -> void:
	keeps_failed_line = true
	if api_key == "":
		var config := LLMConfig.load_settings()
		api_key = config.api_key
	if transport == null:
		var live := GeminiTtsTransport.new()
		transport = live
		add_child(live)


func speak(line_id: String, text: String, voice_hint: String = "", style: String = "") -> void:
	_begin_live()
	var token := _generation
	var spoken := text.strip_edges()
	_closed_line = ""
	_fail_kind = ""
	_line_id = line_id
	_capture_stored = false
	_extra_chars = -1
	_extra_chunks = 0
	_cache_text = ""
	_reset_audio()
	_line_id = line_id
	if spoken == "":
		_finish_speak(token, line_id, spoken, "", style)
		return
	var voice := voice_hint.strip_edges()
	if voice == "":
		voice = VoiceCast.FEMALE
	var fetched: Dictionary = await _fetch(token, spoken, voice, style, false)
	if _closed_line == line_id or token != _generation:
		if _closed_line != line_id:
			_fail_kind = "stopped"
			_finish_speak(token, line_id, spoken, voice, style)
		return
	if not fetched.get("ok", false):
		_fail_kind = format_voice_error(str(fetched.get("error", "bad_response")), int(fetched.get("status", 0)), api_key)
		_finish_speak(token, line_id, spoken, voice, style)
		return
	_announce(str(fetched.get("model", "")), str(fetched.get("reason", "")))
	if fetched.get("cached", false):
		await _wait_until_heard(token)
		_finish_speak(token, line_id, spoken, voice, style)
		return
	_note_usage(str(fetched.get("model", "")), fetched.get("usage", {}))
	_download_done = true
	_maybe_open(true)
	if _started_line:
		await _wait_until_heard(token)
	else:
		_fail_kind = format_voice_error("no_audio", int(fetched.get("status", 200)), api_key)
	_finish_speak(token, line_id, spoken, voice, style)


func prefetch(text: String, voice_hint: String = "", style: String = "") -> String:
	var token := _prefetch_gen
	_capture_stored = false
	_extra_chars = -1
	var spoken := text.strip_edges()
	if spoken == "":
		return "skip"
	var voice := voice_hint.strip_edges()
	if voice == "":
		voice = VoiceCast.FEMALE
	var fetched: Dictionary = await _fetch(token, spoken, voice, style, true)
	if token != _prefetch_gen or _live or str(fetched.get("error", "")) == "stopped":
		_silent = false
		return "yielded"
	_silent = false
	if not fetched.get("ok", false):
		return "error"
	if fetched.get("cached", false):
		return "cached"
	_note_usage(str(fetched.get("model", "")), fetched.get("usage", {}))
	if use_cache and not _capture_stored:
		var cache_text := _cache_text if _cache_text != "" else spoken
		var cache_voice := _cache_voice if _cache_voice != "" else voice
		var cache_style := _cache_style if _cache_style != "" else style
		TtsCache.write(_cache_key(cache_text, cache_voice, cache_style, str(fetched.get("model", ""))), _capture)
	_reset_audio()
	return "stored"


func stop() -> void:
	_generation += 1
	_prefetch_gen += 1
	_live = false
	_silent = false
	_chirp_queue.clear()
	_chirp_busy = false
	_chirp_token = -1
	_chirp_results_token = -1
	_chirp_results.clear()
	_reset_audio()
	_close_playback()
	ChirpAuth.cancel_active()
	chirp_piece_ready.emit.call_deferred()
	if transport != null and transport.has_method("cancel"):
		transport.call("cancel")


func diagnostics() -> Dictionary:
	return {"has_feature": true, "voices": 0, "russian": 0, "voice_id": "", "error": ""}


static func build_request(text: String, voice_name: String, style: String) -> Dictionary:
	var part := {"text": text}
	var tone := style.strip_edges()
	if tone != "":
		part["speechMetadata"] = {"style": tone}
	return {
		"contents": [{"role": "user", "parts": [part]}],
		"generationConfig": {
			"responseModalities": ["AUDIO"],
			"speechConfig": {
				"voiceConfig": {
					"prebuiltVoiceConfig": {"voiceName": voice_name},
				},
			},
		},
	}


static func format_voice_error(kind: String, status: int, secret: String = "") -> String:
	var clean := kind.strip_edges()
	if clean == "":
		clean = "bad_response"
	var friendly := _friendly_voice_error(clean, status)
	if friendly != "":
		return _redact(friendly, secret)
	var shown := clean
	if status > 0:
		shown = "%s http=%d" % [clean, status]
	return _redact(shown, secret)


static func _friendly_voice_error(kind: String, status: int) -> String:
	match kind:
		"chirp_key":
			return "Нет ключа Chirp"
		"gemini_key":
			return "Нет ключа Gemini"
		"bad_json":
			return "Ключ Chirp: это не JSON сервисного аккаунта"
		"chirp_auth":
			return "Ключ Chirp отклонён" if status <= 0 else "Ключ Chirp отклонён (%d)" % status
		"chirp_denied":
			return "Ключ Chirp: доступ запрещён" if status <= 0 else "Ключ Chirp: доступ запрещён (%d)" % status
		"chirp_api":
			return "Cloud Text-to-Speech API выключен в проекте"
		"sign":
			return "Ключ Chirp: не удалось подписать запрос"
		_:
			return ""


static func _redact(shown: String, secret: String) -> String:
	var hidden := secret.strip_edges()
	if hidden.length() >= 8 and shown.contains(hidden):
		shown = shown.replace(hidden, "[redacted]")
	var chirp := ChirpAuth.account_json()
	if chirp.length() >= 8 and shown.contains(chirp):
		shown = shown.replace(chirp, "[redacted]")
	return shown


## Чтение тела только пока статус ещё BODY. Иначе движок печатает condition error.
static func body_chunk(status: int, reader: Callable) -> PackedByteArray:
	if status != HTTPClient.STATUS_BODY or not reader.is_valid():
		return PackedByteArray()
	var data: Variant = reader.call()
	if data is PackedByteArray:
		return data
	return PackedByteArray()


## Склеивает PCM16 между кусками. Нечётный хвост остаётся до следующего куска.
static func take_aligned(carry: PackedByteArray, incoming: PackedByteArray) -> Dictionary:
	var joined := PackedByteArray()
	joined.append_array(carry)
	joined.append_array(incoming)
	var even := joined.size() - (joined.size() % 2)
	return {"ready": joined.slice(0, even), "carry": joined.slice(even)}


static func pcm16_to_frames(bytes: PackedByteArray) -> PackedVector2Array:
	var count := int(bytes.size() / 2)
	var frames := PackedVector2Array()
	frames.resize(count)
	for index in count:
		var sample := int(bytes[index * 2]) | (int(bytes[index * 2 + 1]) << 8)
		if sample >= 32768:
			sample -= 65536
		var amp := float(sample) / 32768.0
		frames[index] = Vector2(amp, amp)
	return frames


func _fetch(token: int, spoken: String, voice: String, style: String, silent_job: bool) -> Dictionary:
	if before_wait.is_valid():
		var hook := before_wait
		before_wait = Callable()
		await hook.call()
	if token != _generation and not silent_job:
		return {"ok": false, "error": "stopped", "status": 0}
	if silent_job and (token != _prefetch_gen or _live):
		return {"ok": false, "error": "stopped", "status": 0}
	var now := TtsQuota.now_unix()
	var choice := TtsQuota.choose(now)
	var model := str(choice.get("model", TtsQuota.selected()))
	var reason := str(choice.get("reason", "primary"))
	var probe := bool(choice.get("probe", false))
	if bool(choice.get("skip", false)):
		var skipped := "chirp_key" if reason == "no_key" else "quota_daily"
		return {"ok": false, "error": skipped, "status": 0 if skipped == "chirp_key" else 429, "model": model, "reason": reason}
	var hops := 0
	while hops < TtsQuota.chain().size():
		hops += 1
		var parts := _cache_parts(model, spoken, voice, style)
		var key := _cache_key(str(parts.get("text", "")), str(parts.get("voice", "")), str(parts.get("style", "")), model)
		if use_cache and not TtsCache.read(key).is_empty():
			if not silent_job:
				_push_pcm(TtsCache.read(key))
				_download_done = true
				_maybe_open(true)
			return {"ok": true, "cached": true, "model": model, "reason": "cache", "status": 200, "usage": {}}
		if TtsQuota.is_chirp(model):
			if not TtsQuota.chirp_ready():
				return {"ok": false, "error": "chirp_key", "status": 0, "model": model, "reason": reason}
		elif api_key.strip_edges() == "":
			return {"ok": false, "error": "gemini_key", "status": 0, "model": model, "reason": reason}
		if probe and not TtsQuota.is_chirp(model):
			TtsQuota.mark_probe(now)
			probe = false
		if silent_job:
			_silent = true
			_line_id = "prefetch"
		var result: Dictionary = {}
		if TtsQuota.is_chirp(model):
			result = await _chirp_line(token, spoken, voice, style, silent_job, reason)
		else:
			result = await _one_model(token, spoken, voice, style, model, silent_job)
		if str(result.get("error", "")) == "stopped":
			return result
		if result.get("ok", false):
			if model == TtsQuota.selected():
				TtsQuota.clear(model)
			_voiced_model = model
			_cache_text = str(parts.get("text", spoken))
			_cache_voice = str(parts.get("voice", voice))
			_cache_style = str(parts.get("style", style))
			return {
				"ok": true,
				"cached": false,
				"model": model,
				"reason": reason,
				"status": int(result.get("status", 200)),
				"usage": result.get("usage", {}),
			}
		var kind := str(result.get("error", "bad_response"))
		if kind == "quota_daily" and TtsQuota.fallback_enabled() and not TtsQuota.is_chirp(model):
			TtsQuota.mark_exhausted(model, TtsQuota.now_unix())
			var nxt := TtsQuota.next_open(model, TtsQuota.now_unix())
			if nxt != "":
				model = nxt
				reason = "quota_daily"
				_reset_audio()
				if silent_job:
					_line_id = "prefetch"
				continue
		return {"ok": false, "error": kind, "status": int(result.get("status", 0)), "model": model, "reason": reason, "message": str(result.get("message", ""))}
	return {"ok": false, "error": "quota_daily", "status": 429, "model": model, "reason": reason}


func _cache_parts(model: String, spoken: String, voice: String, style: String) -> Dictionary:
	if TtsQuota.is_chirp(model):
		return {
			"text": ChirpVoices.spoken_text(spoken),
			"voice": ChirpVoices.for_gemini(voice, _gender_hint(voice)),
			"style": str(ChirpVoices.speaking_rate(style)),
		}
	return {"text": spoken, "voice": voice, "style": style}


func _gender_hint(voice: String) -> String:
	if voice == VoiceCast.MALE:
		return "male"
	if voice == VoiceCast.FEMALE:
		return "female"
	if Game.case_data == null:
		return ""
	for agent in Game.case_data.agents:
		if agent.tts_voice == voice:
			return agent.gender
	return ""


func _chirp_line(token: int, spoken: String, voice: String, style: String, silent_job: bool, reason: String) -> Dictionary:
	var text := ChirpVoices.spoken_text(spoken)
	var name := ChirpVoices.for_gemini(voice, _gender_hint(voice))
	var rate := ChirpVoices.speaking_rate(style)
	var pieces := ChirpVoices.chunks(text)
	if pieces.is_empty():
		return {"ok": false, "error": "empty", "status": 0, "usage": {}}
	_chirp_queue.clear()
	_chirp_busy = false
	_chirp_token = token
	_chirp_results_token = token
	chirp_events = PackedStringArray()
	var count := pieces.size()
	_chirp_results = []
	_chirp_results.resize(count)
	var launched := 0
	var next_play := 0
	var focus := 0
	var joined := PackedByteArray()
	while next_play < count:
		if _chirp_stopped(token, silent_job):
			_abandon_chirp(token)
			return {"ok": false, "error": "stopped", "status": 0, "usage": {}}
		while launched < count and launched <= focus + ChirpVoices.PREFETCH_AHEAD:
			if _chirp_stopped(token, silent_job):
				_abandon_chirp(token)
				return {"ok": false, "error": "stopped", "status": 0, "usage": {}}
			chirp_events.append("synth:%d" % launched)
			# Результат пишется в слот самим заданием. Состояние корутины нельзя
			# ждать позже: если она завершится раньше, Godot теряет результат.
			call("_run_piece", launched, str(pieces[launched]), name, rate, token, silent_job)
			launched += 1
		if _chirp_results[next_play] == null:
			await chirp_piece_ready
			continue
		var resolved: Dictionary = _chirp_results[next_play]
		if _chirp_stopped(token, silent_job):
			_abandon_chirp(token)
			return {"ok": false, "error": "stopped", "status": 0, "usage": {}}
		if not resolved.get("ok", false):
			_abandon_chirp(token)
			return resolved
		var pcm: PackedByteArray = resolved.get("pcm", PackedByteArray())
		if not silent_job and _chirp_busy:
			_pump_chirp_playback()
			if _chirp_busy and _instant and sink != null and sink.has_method("advance"):
				sink.call("advance")
				if _chirp_stopped(token, silent_job):
					ChirpAuth.cancel_active()
					return {"ok": false, "error": "stopped", "status": 0, "usage": {}}
				_pump_chirp_playback()
			if _chirp_busy:
				if _instant:
					return {"ok": false, "error": "playback", "status": 0, "usage": {}}
				await get_tree().process_frame
				continue
		if not silent_job:
			_chirp_queue.append(pcm)
			_pump_chirp_playback()
		joined.append_array(pcm)
		focus = next_play
		next_play += 1
	if not silent_job:
		var spins := 0
		while token == _generation and _chirp_busy:
			_pump_chirp_playback()
			if not _chirp_busy:
				break
			spins += 1
			if spins > 100000:
				return {"ok": false, "error": "playback", "status": 0, "usage": {}}
			if _instant:
				if sink != null and sink.has_method("advance"):
					sink.call("advance")
				elif _chirp_busy:
					return {"ok": false, "error": "playback", "status": 0, "usage": {}}
			else:
				await get_tree().process_frame
	_capture = joined
	_extra_chars = text.length()
	_extra_chunks = count
	if use_cache and token == _generation:
		TtsCache.write(_cache_key(text, name, str(rate), ChirpVoices.MODEL_ID), joined)
		_capture_stored = true
	if silent_job and is_instance_valid(Speaker):
		Speaker.note_line("tts model=%s reason=%s chars=%d chunks=%d" % [ChirpVoices.MODEL_ID, reason, text.length(), pieces.size()])
	return {"ok": true, "status": 200, "usage": {"chars": text.length()}, "error": ""}


func _run_piece(index: int, piece: String, voice_name: String, rate: float, token: int, silent_job: bool) -> void:
	var result: Dictionary = await _synth_piece(piece, voice_name, rate, token, silent_job)
	if token != _chirp_results_token or _chirp_stopped(token, silent_job):
		chirp_piece_ready.emit.call_deferred()
		return
	if index >= 0 and index < _chirp_results.size():
		_chirp_results[index] = result
	chirp_piece_ready.emit.call_deferred()


func _abandon_chirp(token: int) -> void:
	if _chirp_results_token == token:
		_chirp_results_token = -1
	ChirpAuth.cancel_active()
	chirp_piece_ready.emit.call_deferred()


func _synth_piece(piece: String, voice_name: String, rate: float, token: int, silent_job: bool) -> Dictionary:
	var attempt := 0
	var result: Dictionary = {"ok": false, "error": "bad_response", "status": 0}
	while attempt < MAX_ATTEMPTS:
		if _chirp_stopped(token, silent_job):
			return {"ok": false, "error": "stopped", "status": 0}
		result = await ChirpTts.synthesize(self, piece, voice_name, rate)
		if _chirp_stopped(token, silent_job):
			return {"ok": false, "error": "stopped", "status": 0}
		if result.get("ok", false):
			return result
		var kind := str(result.get("error", "bad_response"))
		if kind != "rate_limited":
			return result
		attempt += 1
		if attempt >= MAX_ATTEMPTS:
			return result
		var pause := minf(float(result.get("retry_after", 1.0)), SHORT_RETRY_CAP_S)
		if _instant:
			_clock_s += pause
		else:
			await get_tree().create_timer(pause).timeout
	return result


func _chirp_stopped(token: int, silent_job: bool) -> bool:
	if silent_job:
		return token != _prefetch_gen or _live
	return token != _generation


func _pump_chirp_playback() -> void:
	if _chirp_token != _generation:
		_chirp_queue.clear()
		_chirp_busy = false
		return
	if _chirp_busy:
		if not _chirp_chunk_done():
			return
		_chirp_busy = false
		chirp_events.append("end:%d" % _chirp_end_index())
	if _chirp_queue.is_empty():
		return
	var pcm: PackedByteArray = _chirp_queue[0]
	_chirp_queue.remove_at(0)
	_chirp_busy = true
	chirp_events.append("play:%d" % _chirp_play_count())
	_push_pcm(pcm)
	_maybe_open(true)
	_feed()


func _chirp_chunk_done() -> bool:
	return _pending.is_empty() and _device_buffered() == 0


func _chirp_play_count() -> int:
	var count := 0
	for event in chirp_events:
		if str(event).begins_with("play:"):
			count += 1
	return count


func _chirp_end_index() -> int:
	return maxi(_chirp_play_count() - 1, 0)


func _one_model(token: int, spoken: String, voice: String, style: String, model: String, silent_job: bool) -> Dictionary:
	var attempt := 0
	var result: Dictionary = {"ok": false, "error": "bad_response", "status": 0, "usage": {}}
	while attempt < MAX_ATTEMPTS:
		if (not silent_job and token != _generation) or (silent_job and (token != _prefetch_gen or _live)):
			return {"ok": false, "error": "stopped", "status": 0, "usage": {}}
		var wait := limiter.delay_for(_now())
		if wait > 0.0:
			if _instant:
				if silent_job:
					await get_tree().process_frame
				if (not silent_job and token != _generation) or (silent_job and (token != _prefetch_gen or _live)):
					return {"ok": false, "error": "stopped", "status": 0, "usage": {}}
				_clock_s += minf(wait, SHORT_RETRY_CAP_S if silent_job else wait)
			else:
				await get_tree().create_timer(minf(wait, 1.0) if silent_job else wait).timeout
		if (not silent_job and token != _generation) or (silent_job and (token != _prefetch_gen or _live)):
			return {"ok": false, "error": "stopped", "status": 0, "usage": {}}
		limiter.mark(_now())
		_reset_audio()
		_line_id = "prefetch" if silent_job else _line_id
		if not silent_job:
			_line_id = _line_id if _line_id != "" else "line"
		result = await _send(spoken, voice, style, model)
		if _closed_line == _line_id and not silent_job:
			return {"ok": false, "error": "stopped", "status": 0, "usage": {}}
		if str(result.get("error", "")) == "stopped":
			return result
		if result.get("ok", false):
			return result
		var kind := str(result.get("error", "bad_response"))
		if kind == "":
			kind = "bad_response"
		attempt += 1
		_reset_audio()
		if not silent_job:
			_line_id = _line_id
		if attempt >= MAX_ATTEMPTS or not _retries(kind):
			result["error"] = kind
			return result
		var pause := float(result.get("retry_after", 1.0))
		if pause < 0.0:
			pause = 1.0
		if kind == "rate_limited":
			pause = minf(pause, SHORT_RETRY_CAP_S)
		if _instant:
			_clock_s += pause
		else:
			await get_tree().create_timer(pause).timeout
	return result


func _announce(model: String, reason: String) -> void:
	var line := "tts model=%s reason=%s" % [model, reason]
	if _extra_chars >= 0:
		line += " chars=%d chunks=%d" % [_extra_chars, _extra_chunks]
	if is_instance_valid(Speaker):
		Speaker.note_line(line)
	TurnTiming.note_tts(model, reason)


func _send(text: String, voice_name: String, style: String, model: String) -> Dictionary:
	var request := {
		"path": "/v1beta/models/%s:streamGenerateContent?alt=sse" % model,
		"body": build_request(text, voice_name, style),
		"timeout_s": 30.0,
		"api_key": api_key,
		"on_chunk": _push_pcm,
	}
	TurnTiming.mark("tts_sent")
	_active_text = text
	_active_voice = voice_name
	_active_style = style
	if transport is GeminiTtsTransport:
		(transport as GeminiTtsTransport).on_settled = _on_transport_done
	var pending: Variant = transport.call("stream", request)
	if pending is Dictionary:
		return pending
	return await pending


func _process(_delta: float) -> void:
	if _line_id == "" or _closed_line == _line_id:
		return
	_feed()
	if _chirp_busy or not _chirp_queue.is_empty():
		_pump_chirp_playback()
	if _download_done and _started_line and _heard() and _chirp_queue.is_empty() and not _chirp_busy:
		_finish_speak(_generation, _line_id, _active_text, _active_voice, _active_style)


func _on_transport_done(outcome: Dictionary) -> void:
	_log_tts(outcome)
	if _closed_line == _line_id:
		return
	if not bool(outcome.get("ok", false)):
		var kind := str(outcome.get("error", "bad_response"))
		if kind == "" or kind == "stopped" or kind == "quota_daily" or _retries(kind):
			return
		_fail_kind = format_voice_error(kind, int(outcome.get("status", 0)), api_key)
		_finish_speak(_generation, _line_id, _active_text, _active_voice, _active_style)
		return
	_download_done = true
	_maybe_open(true)
	if _started_line and _heard():
		_finish_speak(_generation, _line_id, _active_text, _active_voice, _active_style)
	elif not _started_line:
		_fail_kind = format_voice_error("no_audio", int(outcome.get("status", 200)), api_key)
		_finish_speak(_generation, _line_id, _active_text, _active_voice, _active_style)


func _log_tts(outcome: Dictionary) -> void:
	var diag: Dictionary = outcome.get("diag", {})
	if diag.is_empty():
		return
	var body := str(diag.get("body", "")).replace("\n", " ")
	var line := "tts status=%s type=%s bytes=%s events=%s audio=%s exit=%s body=%s" % [
		str(diag.get("status", "")),
		str(diag.get("content_type", "")),
		str(diag.get("bytes", 0)),
		str(diag.get("events", 0)),
		str(diag.get("audio", 0)),
		str(diag.get("exit", "")),
		body,
	]
	if is_instance_valid(Speaker):
		Speaker.note_line(line)


func _push_pcm(bytes: PackedByteArray) -> void:
	if _line_id == "":
		return
	var aligned := take_aligned(_pcm_carry, bytes)
	_pcm_carry = aligned["carry"] as PackedByteArray
	var ready := aligned["ready"] as PackedByteArray
	if ready.is_empty():
		return
	var frames := pcm16_to_frames(ready)
	if frames.is_empty():
		return
	_capture.append_array(ready)
	_pending.append_array(frames)
	TurnTiming.mark("first_audio")
	_maybe_open(false)
	_feed()


func _begin_live() -> void:
	_live = true
	_prefetch_gen += 1
	_silent = false
	if transport != null and transport.has_method("cancel"):
		transport.call("cancel")


func _end_live() -> void:
	_live = false


func _cache_key(text: String, voice: String, style: String, model: String) -> String:
	return TtsCache.key_for(model, voice, style, text)


func _play_cached(token: int, text: String, voice: String, style: String, model: String) -> bool:
	if not use_cache or token != _generation:
		return false
	var cached := TtsCache.read(_cache_key(text, voice, style, model))
	if cached.is_empty():
		return false
	_push_pcm(cached)
	_download_done = true
	_maybe_open(true)
	return _started_line


func _store_capture(text: String, voice: String, style: String) -> void:
	if _capture_stored or not use_cache or _capture.is_empty():
		return
	var model := _voiced_model if _voiced_model != "" else MODEL
	var cache_text := _cache_text if _cache_text != "" else text
	var cache_voice := _cache_voice if _cache_voice != "" else voice
	var cache_style := _cache_style if _cache_style != "" else style
	TtsCache.write(_cache_key(cache_text, cache_voice, cache_style, model), _capture)
	_capture_stored = true


func _maybe_open(download_finished: bool) -> void:
	if _silent or _started_line or _line_id == "" or _pending.is_empty():
		return
	var hardware := sink == null
	var prefill := maxf(PREFILL_SECONDS, PREFILL_MIN_SECONDS)
	if hardware and not download_finished and _pending.size() < int(SAMPLE_RATE * prefill):
		return
	_started_line = true
	_open_playback()
	TurnTiming.mark("playback_start")
	started.emit(_line_id)


func _feed() -> void:
	if not _started_line or _pending.is_empty():
		return
	var room := _frames_room()
	if room <= 0:
		return
	var count := mini(room, _pending.size())
	var batch := _pending.slice(0, count)
	_pending = _pending.slice(count)
	_write(batch)


func _frames_room() -> int:
	if sink != null:
		if sink.has_method("frames_available"):
			return maxi(int(sink.call("frames_available")), 0)
		return _pending.size()
	if _playback != null:
		return maxi(_playback.get_frames_available(), 0)
	return 0


func _device_buffered() -> int:
	if sink != null:
		if sink.has_method("buffered_frames"):
			return maxi(int(sink.call("buffered_frames")), 0)
		return 0
	if _playback == null:
		return 0
	var available := maxi(_playback.get_frames_available(), 0)
	if available > _device_capacity:
		_device_capacity = available
	if _device_capacity <= 0:
		return 1
	return maxi(_device_capacity - available, 0)


func _heard() -> bool:
	return _download_done and _pending.is_empty() and _device_buffered() == 0


func _wait_until_heard(token: int) -> void:
	var steps := 0
	while token == _generation:
		_maybe_open(true)
		_feed()
		if _heard():
			return
		steps += 1
		if steps > 100000:
			_fail_kind = "playback"
			return
		if _instant:
			if sink != null and sink.has_method("advance"):
				sink.call("advance")
			else:
				_fail_kind = "playback"
				return
		else:
			await get_tree().process_frame
	_fail_kind = "stopped"


func _finish_speak(token: int, line_id: String, spoken: String, voice: String, style: String) -> void:
	if _closed_line == line_id:
		_end_live()
		return
	var kind := _fail_kind
	if spoken == "":
		kind = "empty"
	elif token != _generation:
		kind = "stopped"
	elif kind == "" and _started_line and _heard():
		_store_capture(spoken, voice, style)
		kind = ""
	elif kind == "":
		kind = "no_audio" if not _started_line else "playback"
	_closed_line = line_id
	if kind == "":
		finished.emit(line_id)
	else:
		speech_error.emit(line_id, kind)
	_end_live()


func _write(frames: PackedVector2Array) -> void:
	if frames.is_empty():
		return
	if sink != null and sink.has_method("push"):
		sink.call("push", frames)
		return
	if _playback != null:
		_playback.push_buffer(frames)


func _reset_audio() -> void:
	_started_line = false
	_download_done = false
	_device_capacity = 0
	_pcm_carry = PackedByteArray()
	_pending = PackedVector2Array()
	_capture = PackedByteArray()


func _open_playback() -> void:
	if sink != null:
		if sink.has_method("start"):
			sink.call("start")
		return
	if _player == null:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = SAMPLE_RATE
		generator.buffer_length = BUFFER_SECONDS
		_player = AudioStreamPlayer.new()
		_player.stream = generator
		add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback != null:
		_device_capacity = _playback.get_frames_available()


func _close_playback() -> void:
	_playback = null
	_device_capacity = 0
	if _player != null and is_instance_valid(_player):
		_player.stop()


func _note_usage(model: String, usage: Variant) -> void:
	if usage is not Dictionary:
		return
	var counts := usage as Dictionary
	if TtsQuota.is_chirp(model):
		SpendMeter.note_chirp(int(counts.get("chars", 0)))
		return
	var prompt := int(counts.get("promptTokenCount", counts.get("prompt", 0)))
	var output := int(counts.get("candidatesTokenCount", counts.get("output", 0)))
	SpendMeter.note(model, prompt, 0, output)


static func limit_kind(status: int, body: String) -> String:
	if status != 429:
		return ""
	var lower := body.to_lower()
	if lower.contains("per_day") or retry_seconds(body) > DAILY_DELAY_S:
		return "quota_daily"
	return "rate_limited"


static func retry_seconds(body: String) -> float:
	var parsed: Variant = JSON.parse_string(body)
	if parsed is not Dictionary:
		return 1.0
	var err: Variant = (parsed as Dictionary).get("error", {})
	if err is not Dictionary:
		return 1.0
	var details: Variant = (err as Dictionary).get("details", [])
	if details is not Array:
		return 1.0
	for item in details:
		if item is not Dictionary:
			continue
		var info := item as Dictionary
		if not str(info.get("@type", "")).contains("RetryInfo"):
			continue
		var raw := str(info.get("retryDelay", "")).strip_edges()
		if raw.ends_with("ms"):
			return float(raw.trim_suffix("ms")) / 1000.0
		if raw.ends_with("s"):
			return float(raw.trim_suffix("s"))
	return 1.0


func _retries(kind: String) -> bool:
	return kind == "rate_limited" or kind == "overloaded"


func _now() -> float:
	if _instant:
		return _clock_s
	return Time.get_ticks_msec() / 1000.0


class GeminiTtsTransport:
	extends Node

	signal settled(outcome: Dictionary)

	var cancelled: bool = false
	## Вызывается в том же тике, что закрыл поток, даже если await сигнала не продолжился.
	var on_settled: Callable = Callable()
	## Тесты подставляют часы и клиент. В игре оба пустые: системные время и HTTPClient.
	var clock_ms: Callable = Callable()
	var http_factory: Callable = Callable()
	var _phase: String = ""
	var _done: bool = false
	var _saw_audio: bool = false
	var _status: int = 0
	var _bytes: int = 0
	var _content_type: String = ""
	var _preview: String = ""
	var _exit: String = ""
	var _http: Object = null
	var _decoder: GeminiSseDecoder = null
	var _error_body: PackedByteArray = PackedByteArray()
	var _on_chunk: Variant = null
	var _path: String = ""
	var _body: String = ""
	var _api_key: String = ""
	var _result: Dictionary = {}
	var _timer: Timer = null
	var _parked: Object = null
	var _parked_ms: int = 0
	var _reused: bool = false
	var _stale_tried: bool = false
	var _saw_code: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_timer = Timer.new()
		_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_timer.process_callback = Timer.TIMER_PROCESS_IDLE
		_timer.wait_time = 0.05
		_timer.one_shot = false
		_timer.timeout.connect(_tick)
		add_child(_timer)

	func _process(_delta: float) -> void:
		if _phase != "":
			_tick()

	func cancel() -> void:
		cancelled = true
		if _phase != "":
			_tick()
		elif _parked != null:
			_parked.close()
			_parked = null

	func stream(request: Dictionary) -> Dictionary:
		cancelled = false
		_done = false
		_saw_audio = false
		_status = 0
		_bytes = 0
		_content_type = ""
		_preview = ""
		_exit = ""
		_error_body = PackedByteArray()
		_decoder = null
		_on_chunk = request.get("on_chunk", Callable())
		_path = str(request.get("path", ""))
		_body = JSON.stringify(request.get("body", {}))
		_api_key = str(request.get("api_key", ""))
		_stale_tried = false
		_saw_code = false
		_http = _take_client()
		TurnTiming.note_tts_reused(_reused)
		if not _reused:
			var err: int = _http.connect_to_host(HttpSession.HOST, 443, TLSOptions.client())
			if err != OK:
				return _close_with(_outcome(false, 0, "offline", 0.0, {}))
		_phase = "connect"
		if _timer != null:
			_timer.start()
		_tick()
		if _done:
			return _result
		var outcome: Dictionary = await settled
		return outcome

	func _tick() -> void:
		if _phase == "" or _done or _http == null:
			return
		if cancelled:
			_exit = "cancelled"
			_complete(_outcome(false, _status, "stopped", 0.0, {}))
			return
		_http.poll()
		var state: int = _http.get_status()
		if _phase == "connect":
			if state == HTTPClient.STATUS_CONNECTING or state == HTTPClient.STATUS_RESOLVING:
				return
			if state != HTTPClient.STATUS_CONNECTED:
				if _retry_stale():
					return
				_exit = "connect_%d" % state
				_complete(_outcome(false, 0, "offline", 0.0, {}))
				return
			var headers := PackedStringArray([
				"Content-Type: application/json",
				"x-goog-api-key: %s" % _api_key,
			])
			var err: int = _http.request(HTTPClient.METHOD_POST, _path, headers, _body)
			if err != OK or _link_dropped():
				if _retry_stale():
					return
				_exit = "request_%d" % err
				_complete(_outcome(false, 0, "offline", 0.0, {}))
				return
			_phase = "request"
			return
		if _phase == "request":
			if state == HTTPClient.STATUS_REQUESTING:
				return
			_status = int(_http.get_response_code())
			_saw_code = true
			_content_type = _header_value("content-type")
			if _status == 200:
				_decoder = GeminiSseDecoder.new()
			_phase = "body"
			return
		if state == HTTPClient.STATUS_BODY:
			var chunk := _take_chunk(_http)
			while not chunk.is_empty():
				_note_bytes(chunk)
				if _decoder == null:
					_error_body.append_array(chunk)
				else:
					for pcm in _decoder.push(chunk):
						_emit_pcm(_on_chunk, pcm)
				chunk = _take_chunk(_http)
			return
		_exit = "eof"
		if _decoder == null:
			var raw := _redact(_error_body.get_string_from_utf8())
			_preview = raw.substr(0, 300)
			var kind := "eof"
			if _status == 429:
				kind = GeminiTtsBackend.limit_kind(_status, raw)
			elif _status != 200 and _status != 0:
				kind = _kind(_status)
			elif _status != 0:
				kind = "http_%d" % _status
			if _status != 0 and _status != 200:
				_exit = kind
			_complete(_outcome(false, _status, kind, GeminiTtsBackend.retry_seconds(raw), {}))
			return
		for pcm in _decoder.finish():
			_emit_pcm(_on_chunk, pcm)
		var events := _decoder.event_count
		var audio := _decoder.audio_parts
		if _bytes > 0 and events == 0:
			_exit = "parse_failure"
			_complete(_outcome(false, _status, "parse_failure", 0.0, _decoder.usage))
		elif audio == 0 or _status != 200:
			_exit = "no_audio" if _status == 200 else "http_%d" % _status
			var fail := "no_audio" if _status == 200 else _kind(_status)
			_complete(_outcome(false, _status, fail, 0.0, _decoder.usage))
		else:
			_complete(_outcome(true, _status, "", 0.0, _decoder.usage))

	func _complete(outcome: Dictionary) -> void:
		if _done:
			return
		_done = true
		_phase = ""
		if _timer != null:
			_timer.stop()
		var keep := bool(outcome.get("ok", false)) and not cancelled and _http != null and int(_http.get_status()) == HTTPClient.STATUS_CONNECTED
		if keep:
			_parked = _http
			_parked_ms = _now_ms()
			_http = null
		elif _http != null:
			_http.close()
			_http = null
		_result = outcome
		outcome["diag"] = _diag()
		_result = outcome
		settled.emit(outcome)
		if on_settled.is_valid():
			var callback := on_settled
			on_settled = Callable()
			callback.call(outcome)

	func _close_with(outcome: Dictionary) -> Dictionary:
		_complete(outcome)
		return outcome

	func _now_ms() -> int:
		if clock_ms.is_valid():
			return int(clock_ms.call())
		return Time.get_ticks_msec()

	func _take_client() -> Object:
		if _parked != null:
			var age := _now_ms() - _parked_ms
			var alive := int(_parked.get_status()) == HTTPClient.STATUS_CONNECTED and age <= int(HttpSession.IDLE_REUSE_S * 1000.0)
			if alive:
				var kept: Object = _parked
				_parked = null
				_reused = true
				return kept
			_parked.close()
			_parked = null
		_reused = false
		return _make_http()


	func _retry_stale() -> bool:
		if not _reused or _stale_tried or _saw_code:
			return false
		_stale_tried = true
		_reused = false
		if _http != null:
			_http.close()
		_http = _make_http()
		var err: int = _http.connect_to_host(HttpSession.HOST, 443, TLSOptions.client())
		TurnTiming.note_tts_reused(false)
		if err != OK:
			return false
		_phase = "connect"
		return true


	func _link_dropped() -> bool:
		var state := int(_http.get_status())
		return state == HTTPClient.STATUS_DISCONNECTED or state == HTTPClient.STATUS_CONNECTION_ERROR


	func _make_http() -> Object:
		if http_factory.is_valid():
			var made: Variant = http_factory.call()
			if made != null:
				return made
		return HTTPClient.new()

	func _note_bytes(chunk: PackedByteArray) -> void:
		_bytes += chunk.size()
		if _preview.length() >= 300:
			return
		var text := _redact(chunk.get_string_from_utf8())
		_preview = (_preview + text).substr(0, 300)

	func _header_value(name: String) -> String:
		if _http == null or not _http.has_method("get_response_headers"):
			return ""
		var wanted := name.to_lower()
		var headers: PackedStringArray = _http.call("get_response_headers")
		for header in headers:
			var line := str(header)
			var split := line.split(":", true, 1)
			if split.size() == 2 and split[0].strip_edges().to_lower() == wanted:
				return split[1].strip_edges()
		return ""

	func _redact(text: String) -> String:
		var clean := text
		if _api_key.length() >= 6:
			clean = clean.replace(_api_key, "[redacted]")
		return clean

	func _diag() -> Dictionary:
		var events := 0
		var audio := 0
		if _decoder != null:
			events = _decoder.event_count
			audio = _decoder.audio_parts
		return {
			"status": _status,
			"content_type": _content_type,
			"bytes": _bytes,
			"events": events,
			"audio": audio,
			"exit": _exit,
			"body": _preview,
		}

	func _outcome(ok: bool, status: int, error_kind: String, retry_after: float, usage: Dictionary) -> Dictionary:
		return {"ok": ok, "status": status, "error": error_kind, "retry_after": retry_after, "usage": usage}

	func _take_chunk(http: Object) -> PackedByteArray:
		return GeminiTtsBackend.body_chunk(http.get_status(), Callable(http, "read_response_body_chunk"))

	func _emit_pcm(on_chunk: Variant, pcm: PackedByteArray) -> void:
		if pcm.is_empty() or on_chunk is not Callable:
			return
		_saw_audio = true
		(on_chunk as Callable).call(pcm)

	func _kind(status: int) -> String:
		if status == 429:
			return "rate_limited"
		if status == 503 or status == 502 or status == 504:
			return "overloaded"
		if status == 401 or status == 403:
			return "auth"
		return "bad_response"

	func _retry_after(body: String) -> float:
		var parsed: Variant = JSON.parse_string(body)
		if parsed is not Dictionary:
			return 1.0
		var err: Variant = (parsed as Dictionary).get("error", {})
		if err is not Dictionary:
			return 1.0
		var details: Variant = (err as Dictionary).get("details", [])
		if details is not Array:
			return 1.0
		for item in details:
			if item is not Dictionary:
				continue
			var info := item as Dictionary
			if not str(info.get("@type", "")).contains("RetryInfo"):
				continue
			var raw := str(info.get("retryDelay", "")).strip_edges()
			if raw.ends_with("ms"):
				return float(raw.trim_suffix("ms")) / 1000.0
			if raw.ends_with("s"):
				return float(raw.trim_suffix("s"))
		return 1.0
