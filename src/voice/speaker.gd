extends Node
## Очередь озвучки реплик. Бэкенд подменяется, игровой ход его не знает.
## Сигнал is_speaking нужен будущему микрофону; самого микрофона здесь нет.

signal is_speaking(active: bool)
signal voice_error(kind: String)
signal voice_retry_available(show_button: bool)
signal voice_line_changed
signal voice_log_changed
signal turn_log_changed

const LOG_LIMIT := 20

var backend: SpeechBackend
var enabled: bool = false
var speaking: bool = false
var last_error: String = ""
var listen_to_game: bool = true
var queue: SpeechQueue = SpeechQueue.new()
var retry_line: Dictionary = {}
var _lengths: Dictionary = {}
var _inflight: Dictionary = {}
var _prefetch_jobs: Array = []
var _prefetch_busy: bool = false
var _prefetch_token: int = 0
var voice_log: PackedStringArray = PackedStringArray()
var turn_log: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var store := SettingsStore.load_current()
	enabled = store.voice_enabled
	if backend == null:
		backend = _backend_for(store.voice_engine)
	if backend.get_parent() == null:
		add_child(backend)
	_bind_backend()
	if listen_to_game and not Game.agent_replied.is_connected(_on_replied):
		Game.agent_replied.connect(_on_replied)
	if listen_to_game and not Game.case_opened.is_connected(_on_case_opened):
		Game.case_opened.connect(_on_case_opened)


func apply_settings() -> void:
	var store := SettingsStore.load_current()
	enabled = store.voice_enabled
	var want := store.voice_engine
	var current := "gemini" if backend is GeminiTtsBackend else "system"
	if backend == null or current != want:
		use_backend(_backend_for(want))
	if not enabled:
		stop_and_clear()


func _backend_for(engine: String) -> SpeechBackend:
	if engine == "gemini":
		return GeminiTtsBackend.new()
	return SystemTtsBackend.new()


func use_backend(next: SpeechBackend) -> void:
	if backend != null and is_instance_valid(backend) and backend.get_parent() == self:
		backend.queue_free()
	backend = next
	if next.get_parent() != self:
		add_child(next)
	_bind_backend()


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop_and_clear()


func speak_test() -> String:
	stop_and_clear()
	var text := "Проверка голоса."
	_lengths["voice-test"] = text.length()
	if backend != null:
		await backend.speak("voice-test", text, "")
	return voice_status_line()


func voice_status_line() -> String:
	var info := {}
	if backend != null and backend.has_method("diagnostics"):
		info = backend.call("diagnostics")
	var feature := "yes" if bool(info.get("has_feature", false)) else "no"
	var voice := str(info.get("voice_id", ""))
	if voice == "":
		voice = "-"
	var err := str(info.get("error", ""))
	if err == "":
		err = "none"
	last_error = "" if err == "none" else err
	return "TEXT_TO_SPEECH %s · voices %d · russian %d · voice %s · error %s" % [
		feature,
		int(info.get("voices", 0)),
		int(info.get("russian", 0)),
		voice,
		err,
	]


func speak_greeting(agent_id: String, text: String) -> void:
	if not enabled:
		return
	var spoken := SpeechText.clean(text)
	if spoken == "":
		return
	var case_id := ""
	if Game.state != null:
		case_id = str(Game.state.case_id)
	var line_id := "greet:%s:%s" % [case_id, agent_id]
	if not queue.enqueue(line_id, spoken, _voice_for(agent_id), ""):
		_note("skipped id=%s reason=duplicate" % line_id)
		return
	_lengths[line_id] = spoken.length()
	_note("enqueued id=%s len=%d preview=%s" % [line_id, spoken.length(), _preview(spoken)])
	_pump()


func speak_reply(agent_id: String, reply: String) -> void:
	if not enabled:
		return
	var line_id := line_id_for(agent_id)
	var text := SpeechText.clean(reply)
	var style := _style_for(agent_id)
	if text == "":
		_remember_retry(line_id, reply, _voice_for(agent_id), style)
		_note("skipped id=%s reason=empty" % line_id)
		voice_error.emit("empty")
		voice_retry_available.emit(true)
		return
	if not queue.enqueue(line_id, text, _voice_for(agent_id), style):
		_note("skipped id=%s reason=duplicate" % line_id)
		return
	_lengths[line_id] = text.length()
	_note("enqueued id=%s len=%d preview=%s" % [line_id, text.length(), _preview(text)])
	_pump()


func retry_failed() -> void:
	if retry_line.is_empty() or not enabled:
		return
	var item := retry_line.duplicate(true)
	retry_line = {}
	voice_retry_available.emit(false)
	var line_id := str(item.get("id", ""))
	queue.allow_again(line_id)
	if queue.enqueue(line_id, str(item.get("text", "")), str(item.get("voice_hint", "")), str(item.get("style", "")), true):
		_lengths[line_id] = str(item.get("text", "")).length()
		_pump()


func stop_and_clear(cancel_prefetch: bool = true) -> void:
	if cancel_prefetch:
		_prefetch_token += 1
		_prefetch_jobs.clear()
		_prefetch_busy = false
	_release_seen()
	queue.stop()
	_lengths.clear()
	retry_line = {}
	_inflight = {}
	voice_retry_available.emit(false)
	if backend != null:
		backend.stop()
	_set_speaking(false)
	if not cancel_prefetch:
		_kick_prefetch()


func reset_for_case() -> void:
	stop_and_clear()
	queue.reset()
	_lengths.clear()


func line_id_for(agent_id: String) -> String:
	var case_id := ""
	var turn := 0
	if Game.state != null:
		case_id = str(Game.state.case_id)
		turn = int(Game.state.turn)
	return "%s:%s:%d" % [case_id, agent_id, turn]


func _on_replied(agent_id: String, text: String, _remark: String) -> void:
	var spoken := Game.speech_line if Game.speech_line != "" else text
	speak_reply(agent_id, spoken)


func cancel_inflight() -> void:
	var line_id := queue.current_id
	if line_id != "":
		queue.allow_again(line_id)
		queue.finish(line_id)
	_inflight = {}
	if backend != null:
		backend.stop()
	_set_speaking(false)
	voice_line_changed.emit()


func skip_current() -> void:
	if _inflight.is_empty() and queue.current_id == "":
		return
	var item: Dictionary = _inflight.duplicate(true)
	if not item.is_empty():
		_remember_retry(str(item.get("id", queue.current_id)), str(item.get("text", "")), str(item.get("voice_hint", "")), str(item.get("style", "")))
	var line_id := queue.current_id
	if line_id != "":
		queue.allow_again(line_id)
		queue.finish(line_id)
	_inflight = {}
	if backend != null:
		backend.stop()
	_set_speaking(false)
	voice_retry_available.emit(true)
	voice_line_changed.emit()


func can_skip() -> bool:
	return queue.current_id != "" or not _inflight.is_empty()


func _pump() -> void:
	if queue.current_id != "":
		return
	var item := queue.take_next()
	if item.is_empty():
		_set_speaking(false)
		voice_line_changed.emit()
		return
	_inflight = item.duplicate(true)
	voice_line_changed.emit()
	var spoken := str(item.get("text", ""))
	backend.speak(str(item["id"]), spoken, str(item.get("voice_hint", "")), str(item.get("style", "")))


func _bind_backend() -> void:
	if backend == null:
		return
	if not backend.started.is_connected(_on_started):
		backend.started.connect(_on_started)
	if not backend.finished.is_connected(_on_finished):
		backend.finished.connect(_on_finished)
	if not backend.speech_error.is_connected(_on_error):
		backend.speech_error.connect(_on_error)


func _on_started(line_id: String) -> void:
	TurnTiming.mark("playback_start")
	if not retry_line.is_empty():
		retry_line = {}
		voice_retry_available.emit(false)
	if last_error != "":
		last_error = ""
		voice_error.emit("")
	_set_speaking(true)
	voice_line_changed.emit()
	_note("started id=%s len=%d" % [line_id, int(_lengths.get(line_id, 0))])


func _on_finished(line_id: String) -> void:
	if queue.current_id != "" and queue.current_id != line_id:
		_note("skipped id=%s reason=mismatch" % line_id)
		return
	_note("finished id=%s len=%d" % [line_id, int(_lengths.get(line_id, 0))])
	voice_line_changed.emit()
	_lengths.erase(line_id)
	if queue.current_id == line_id:
		queue.finish(line_id)
	_pump()
	_kick_prefetch()


func _on_error(line_id: String, kind: String) -> void:
	_note("error id=%s len=%d reason=%s" % [line_id, int(_lengths.get(line_id, 0)), kind])
	voice_line_changed.emit()
	if kind == "stopped":
		queue.allow_again(line_id)
		if queue.current_id == line_id:
			queue.finish(line_id)
			_lengths.erase(line_id)
			_pump()
			_kick_prefetch()
		return
	var current := queue.current_id
	if current != "" and current != line_id:
		queue.allow_again(line_id)
		_note("skipped id=%s reason=mismatch" % line_id)
		return
	last_error = kind
	voice_error.emit(kind)
	if current == line_id:
		_remember_retry(line_id, str(_inflight.get("text", "")), str(_inflight.get("voice_hint", "")), str(_inflight.get("style", "")))
		queue.finish(line_id)
		queue.allow_again(line_id)
		_lengths.erase(line_id)
		_inflight = {}
	voice_retry_available.emit(true)
	_pump()
	_kick_prefetch()


func _voice_for(agent_id: String) -> String:
	if Game.case_data == null:
		return ""
	var agent: CaseData.Agent = Game.case_data.agent_by_id.get(agent_id) as CaseData.Agent
	return VoiceCast.voice_for(agent)


func _style_for(_agent_id: String) -> String:
	if not SettingsStore.load_current().voice_intonation:
		return ""
	return Game.speech_style.strip_edges()


func _release_seen() -> void:
	if queue.current_id != "":
		queue.allow_again(queue.current_id)
	for item in queue.pending:
		queue.allow_again(str(item.get("id", "")))


func dismiss_retry() -> void:
	if retry_line.is_empty():
		return
	retry_line = {}
	voice_retry_available.emit(false)


func retry_visible_for(agent_id: String) -> bool:
	if retry_line.is_empty() or agent_id == "":
		return false
	return str(retry_line.get("agent_id", "")) == agent_id


func _remember_retry(line_id: String, text: String, voice_hint: String, style: String) -> void:
	retry_line = {
		"id": line_id,
		"text": text,
		"voice_hint": voice_hint,
		"style": style,
		"agent_id": _agent_from_line(line_id),
	}


func _agent_from_line(line_id: String) -> String:
	var parts := line_id.split(":")
	if parts.size() >= 3 and parts[0] == "greet":
		return parts[2]
	if parts.size() >= 3:
		return parts[1]
	return ""


func note_line(line: String) -> void:
	_note(line)


func set_turn_log(lines: PackedStringArray) -> void:
	turn_log = lines.duplicate()
	turn_log_changed.emit()


func replace_or_note(prefix: String, line: String) -> void:
	for index in range(voice_log.size() - 1, -1, -1):
		if str(voice_log[index]).begins_with(prefix):
			voice_log[index] = line
			voice_log_changed.emit()
			return
	_note(line)


func _note(line: String) -> void:
	voice_log.append(line)
	while voice_log.size() > LOG_LIMIT:
		voice_log.remove_at(0)
	print("voice %s" % line)
	voice_log_changed.emit()


func _preview(text: String) -> String:
	var flat := text.replace("\n", " ").strip_edges()
	if flat.length() > 16:
		return flat.substr(0, 16)
	return flat


func _on_case_opened() -> void:
	_prefetch_token += 1
	_prefetch_jobs.clear()
	var store := SettingsStore.load_current()
	if not enabled or store.voice_engine != "gemini":
		return
	var token := _prefetch_token
	for job in GreetingPlan.jobs(Game.case_data, true, true):
		if job is Dictionary:
			_prefetch_jobs.append(job)
	if token == _prefetch_token:
		_kick_prefetch()


func _kick_prefetch() -> void:
	if _prefetch_busy or _prefetch_jobs.is_empty():
		return
	if speaking or queue.current_id != "" or not queue.pending.is_empty():
		return
	if backend == null or not backend.has_method("prefetch"):
		return
	_prefetch_busy = true
	_run_prefetch(_prefetch_token)


func _run_prefetch(token: int) -> void:
	while token == _prefetch_token and not _prefetch_jobs.is_empty():
		if speaking or queue.current_id != "" or not queue.pending.is_empty():
			break
		var job: Dictionary = _prefetch_jobs[0]
		var status: String = await backend.prefetch(str(job.get("text", "")), str(job.get("voice", "")), str(job.get("style", "")))
		if token != _prefetch_token:
			_prefetch_busy = false
			return
		if status == "yielded":
			if speaking or queue.current_id != "" or not queue.pending.is_empty():
				break
			continue
		_prefetch_jobs.pop_front()
		if status != "cached" and status != "stored":
			continue
	_prefetch_busy = false


func _set_speaking(active: bool) -> void:
	if queue.current_id == "" and queue.pending.is_empty():
		active = false
	if active == speaking:
		return
	speaking = active
	is_speaking.emit(active)
