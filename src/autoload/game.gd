extends Node
## Сессия партии: ход, сигналы для UI, блокнот. Экранов здесь нет.

signal agent_replied(agent_id: String, text: String, remark: String)
signal case_opened
signal events(list: Array)
signal llm_error(kind: String, message: String)
signal save_failed(message: String)
signal busy_changed(is_busy: bool)

var case_data: CaseData = null
var state: GameState = null
var notebook: Notebook = null
var case_path: String = ""

var _engine: RulesEngine = null
var _dialogues: Dictionary = {}
var last_turn_line: String = ""
var last_turn_stats: Dictionary = {}
## Интонация последней реплики для синтеза. В текст реплики не входит.
var speech_style: String = ""
## Текст для синтеза. На экране и в истории остаётся ответ без меток.
var speech_line: String = ""
var is_busy: bool = false
var _turn_token: int = 0
## Снимок партии до present_evidence / note_question. Пока ход не закончен, сворачивание пишет его.
var _turn_snapshot: Dictionary = {}


func open_case(path: String) -> CaseLoader.Result:
	_drop_turn()
	var loaded := CaseLoader.load_case(path)
	if not loaded.ok:
		case_data = null
		state = null
		notebook = null
		case_path = ""
		_engine = null
		_dialogues = {}
		return loaded
	case_data = loaded.case_data
	case_path = path
	state = GameState.new()
	state.case_id = case_data.id
	state.case_version_hash = SaveState.file_hash(path)
	_engine = RulesEngine.new(case_data, state)
	_engine.start_new()
	_dialogues = {}
	for agent in case_data.agents:
		_dialogues[agent.id] = DialogueState.new()
		state.dialogues[agent.id] = (_dialogues[agent.id] as DialogueState).to_dict()
	notebook = Notebook.new(case_data, state)
	case_opened.emit()
	return loaded


func mentioned_evidence(text: String) -> Array[String]:
	if case_data == null or state == null:
		return []
	var open: Array = []
	for evidence in case_data.evidence:
		if state.unlocked_evidence.has(evidence.id):
			open.append(evidence)
	return EvidenceMatcher.find_mentioned(text, open)


func ask(agent_id: String, player_text: String) -> void:
	if is_busy:
		return
	await _turn(agent_id, player_text, "", "")


func present(agent_id: String, evidence_id: String, player_text: String = "") -> void:
	if is_busy:
		return
	var question := player_text.strip_edges()
	if question == "":
		question = "Что скажете?"
	var note := ""
	if case_data != null and case_data.evidence_by_id.has(evidence_id):
		var evidence: CaseData.EvidenceItem = case_data.evidence_by_id[evidence_id]
		note = "Следователь предъявляет улику «%s»: %s" % [evidence.title, evidence.full_text]
	await _turn(agent_id, question, note, evidence_id)


func accuse(killer_id: String, motive_id: String, method_id: String) -> Dictionary:
	if _engine == null:
		return {"killer_ok": false, "motive_ok": false, "method_ok": false, "solved": false}
	var report := _engine.check_accusation(killer_id, motive_id, method_id)
	_autosave()
	return report


func continue_case(path: String) -> Dictionary:
	var case_id := SaveState.case_id_from_path(path)
	if case_id == "":
		return {"ok": false, "reason": "case"}
	var saved := SaveState.read(case_id)
	if not saved.ok:
		return saved
	var current_hash := SaveState.file_hash(path)
	if str(saved.get("hash", "")) != current_hash or str(saved.get("case_id", "")) != case_id:
		return {"ok": false, "reason": "hash"}
	var loaded := open_case(path)
	if not loaded.ok:
		return {"ok": false, "reason": "case"}
	_replace_state(saved.get("state", {}))
	return {"ok": true, "reason": ""}


## Первая фраза персонажа. Не ход: talked_to и turn не меняются.
func add_greeting(agent_id: String) -> String:
	if is_busy or case_data == null or state == null or not _dialogues.has(agent_id):
		return ""
	var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
	if agent == null or agent.greeting.strip_edges() == "":
		return ""
	var dialogue: DialogueState = _dialogues[agent_id]
	if not dialogue.messages.is_empty():
		return ""
	var text := agent.greeting.strip_edges()
	dialogue.append_message("agent", text, state.turn)
	_sync_dialogues()
	_autosave()
	return text


func _turn(agent_id: String, player_text: String, event_note: String, evidence_id: String) -> void:
	if is_busy:
		return
	if _engine == null or not _dialogues.has(agent_id):
		llm_error.emit("no_case", "Дело не открыто.")
		return
	is_busy = true
	busy_changed.emit(true)
	_turn_token += 1
	var token := _turn_token
	Speaker.cancel_inflight()
	Speaker.dismiss_retry()
	var turn_config := LLMConfig.load_settings()
	var turn_started := Time.get_ticks_msec()
	var tally := LlmTiming.empty_tally()
	var turn_model := ""
	_sync_dialogues()
	var snapshot := state.to_dict()
	_turn_snapshot = snapshot
	var turn_events: Array = []
	if evidence_id != "":
		turn_events.append_array(_engine.present_evidence(agent_id, evidence_id))
	turn_events.append_array(_engine.note_question(agent_id))
	var dialogue: DialogueState = _dialogues[agent_id]
	var packet: Array = _engine.get_packet(agent_id)
	var request := PromptBuilder.build_turn(case_data, state, agent_id, packet, dialogue, player_text, event_note)
	var chain := 1
	LlmTiming.note_request(tally, "reply", "reply")
	TurnTiming.mark("dialogue_sent")
	var result := await _generate(request)
	TurnTiming.mark("dialogue_done")
	if not _turn_current(token):
		return
	turn_model = str(result.get("model", turn_model))
	if _is_network_error(result):
		_abort_turn(snapshot, turn_started, turn_model, tally, str(result.get("error", "")), str(result.get("message", "")))
		return
	if _reply_missing(result):
		if chain >= 2:
			_abort_turn(snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		chain += 1
		var filler := "Отвечай сдержаннее, без откровенных подробностей." if str(result.get("error", "")) == "blocked" else "Ответь одной целой репликой."
		LlmTiming.note_request(tally, "regen", "blocked" if str(result.get("error", "")) == "blocked" else "empty")
		result = await _generate(_with_suffix(request, filler))
		if not _turn_current(token):
			return
		turn_model = str(result.get("model", turn_model))
		if _is_network_error(result):
			_abort_turn(snapshot, turn_started, turn_model, tally, str(result.get("error", "")), str(result.get("message", "")))
			return
		if _reply_missing(result):
			_abort_turn(snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
	var agent: CaseData.Agent = case_data.agent_by_id[agent_id]
	var report := _validate_result(result, packet, agent_id, dialogue, player_text, turn_config.local_fixes)
	if _should_regenerate(report, turn_config.local_fixes):
		if chain >= 2:
			_abort_turn(snapshot, turn_started, turn_model, tally, "bad_response", UiStrings.REPHRASE if _reply_missing(result) else "Целый ответ не принят.")
			return
		chain += 1
		LlmTiming.note_request(tally, "regen", "validation")
		result = await _generate(_with_suffix(request, ResponseValidator.repair_note(report["violations"])))
		if not _turn_current(token):
			return
		turn_model = str(result.get("model", turn_model))
		if _is_network_error(result):
			_abort_turn(snapshot, turn_started, turn_model, tally, str(result.get("error", "")), str(result.get("message", "")))
			return
		if _reply_missing(result):
			_abort_turn(snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		report = _validate_result(result, packet, agent_id, dialogue, player_text, turn_config.local_fixes)
	var reply := ""
	var remark := ""
	var tone := 0
	var emotion := str(state.emotion.get(agent_id, agent.starting_emotion))
	speech_style = ""
	speech_line = ""
	var statements: Array = []
	var reader := _read_choice(result)
	if not reader.reply_complete():
		_abort_turn(snapshot, turn_started, turn_model, tally, "bad_response", "Ответ оборвался до целой реплики.")
		return
	var options := TurnOptions.build(case_data, state, agent_id)
	var plan := TurnOptions.plan(case_data, state, agent_id, options, reader.chosen())
	_log_choice(agent_id, options, plan)
	if bool(plan.get("restart", false)):
		turn_events.append_array(_engine.commit_plan(agent_id, plan))
		packet = _engine.get_packet(agent_id)
		var restarted := PromptBuilder.build_turn(case_data, state, agent_id, packet, dialogue, player_text, event_note)
		LlmTiming.note_request(tally, "regen", "admit")
		result = await _generate(_with_suffix(restarted, _admit_note(plan)))
		if not _turn_current(token):
			return
		turn_model = str(result.get("model", turn_model))
		if _is_network_error(result):
			_abort_turn(snapshot, turn_started, turn_model, tally, str(result.get("error", "")), str(result.get("message", "")))
			return
		if _reply_missing(result):
			_abort_turn(snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		report = _validate_result(result, packet, agent_id, dialogue, player_text, turn_config.local_fixes)
	else:
		turn_events.append_array(_engine.commit_plan(agent_id, plan))
	if report["ok"] and result.get("ok", false):
		reply = str(report["reply"])
		remark = str(report["remark"])
		tone = int(report["tone"])
		emotion = str(report["emotion"])
		statements = report["statements"]
		var store := SettingsStore.load_current()
		var gemini := store.voice_engine == "gemini"
		speech_style = SpeechStyle.compose(agent.voice_style, str(report.get("speech_tone", "")), str(report.get("pace", "")), store.voice_intonation)
		speech_line = VocalTags.for_backend(str(report.get("spoken_reply", reply)), gemini, store.voice_intonation)
	else:
		_abort_turn(snapshot, turn_started, turn_model, tally, "bad_response", "Целый ответ не принят.")
		return
	state.turn += 1
	if not statements.is_empty():
		turn_events.append_array(_engine.register_statements(agent_id, statements))
	turn_events.append_array(_engine.apply_tone(agent_id, tone))
	if Balance.emotion_allowed(emotion):
		_engine.set_emotion(agent_id, emotion)
	dialogue = _rebind_dialogue(agent_id, dialogue)
	dialogue.append_message("player", player_text, state.turn)
	dialogue.append_message("agent", reply, state.turn, remark)
	if turn_model == "":
		turn_model = str(result.get("model", ""))
	var text_ms := Time.get_ticks_msec() - turn_started
	_sync_dialogues()
	if not _autosave():
		save_failed.emit("Не удалось записать сохранение.")
	_turn_snapshot = {}
	agent_replied.emit(agent_id, reply, remark)
	events.emit(turn_events)
	_end_busy()
	if dialogue.needs_summary():
		LlmTiming.note_request(tally, "summary", "summary")
		dialogue = await _refresh_summary(agent_id, dialogue, token)
		if not _turn_current(token):
			return
		_sync_dialogues()
		if not _autosave():
			save_failed.emit("Не удалось записать сохранение.")
	_publish_turn_timing(text_ms, turn_model, tally)


func _read_choice(result: Dictionary) -> TurnChoice:
	var reader := TurnChoice.new()
	var raw := str(result.get("raw_text", ""))
	if raw == "" and result.get("json") is Dictionary:
		raw = JSON.stringify(result.get("json"))
	var index := 0
	while index < raw.length():
		reader.push(raw.substr(index, 24))
		index += 24
	reader.finish()
	return reader


func _admit_note(plan: Dictionary) -> String:
	var truths := PackedStringArray()
	for line in plan.get("admit", []):
		if str(line) != "":
			truths.append(str(line))
	var mention := ""
	for evidence_id in plan.get("unlock", []):
		var item: CaseData.EvidenceItem = case_data.evidence_by_id.get(str(evidence_id)) as CaseData.EvidenceItem
		if item != null:
			mention += " Скажи, что существует «%s»." % item.title
	return "ЭТОТ ОТВЕТ ЗАМЕНЯЕТ ПРЕДЫДУЩИЙ, ЕГО НЕ ПОКАЗЫВАЮТ И НЕ ОЗВУЧИВАЮТ. Признай в этой реплике только это и ничего сверх: %s. Не повторяй старую ложь.%s" % [" ".join(truths), mention]


func _log_choice(agent_id: String, options: Array, plan: Dictionary) -> void:
	if not SettingsStore.load_current().developer:
		return
	var picked: Array = plan.get("picked", [])
	var shown: PackedStringArray = PackedStringArray()
	for number in picked:
		shown.append(str(number))
	print("choice agent=%s offered=%d picked=%s decision=%s unlock=%s break=%s" % [
		agent_id,
		options.size(),
		",".join(shown),
		str(plan.get("decision", "")),
		",".join(plan.get("unlock", [])),
		",".join(plan.get("break_lies", [])),
	])


func _autosave() -> bool:
	if state == null:
		return false
	return SaveState.write_state(state)


func _replace_state(data: Variant) -> void:
	_drop_turn()
	if data is not Dictionary:
		return
	state = GameState.from_dict(data)
	state.case_id = case_data.id
	state.case_version_hash = SaveState.file_hash(case_path)
	_engine = RulesEngine.new(case_data, state)
	_dialogues = {}
	for agent in case_data.agents:
		var saved: Variant = state.dialogues.get(agent.id, {})
		if saved is Dictionary:
			_dialogues[agent.id] = DialogueState.from_dict(saved)
		else:
			_dialogues[agent.id] = DialogueState.new()
		state.dialogues[agent.id] = (_dialogues[agent.id] as DialogueState).to_dict()
	notebook = Notebook.new(case_data, state)


func _refresh_summary(agent_id: String, dialogue: DialogueState, token: int) -> DialogueState:
	var live := _rebind_dialogue(agent_id, dialogue)
	if not live.needs_summary():
		return live
	var agent: CaseData.Agent = case_data.agent_by_id[agent_id]
	var fold_until := live.messages.size() - 6
	var folded: Array = live.messages.slice(live.summarized_count, fold_until)
	var request := Summarizer.build_request(agent.name, live.summary, folded)
	var result := await _generate(request)
	if not _turn_current(token):
		return live
	live = _rebind_dialogue(agent_id, live)
	var summary := ""
	if result.get("ok", false) and result.get("json") is Dictionary:
		summary = str((result["json"] as Dictionary).get("summary", "")).strip_edges()
	if summary == "":
		var heard: Array = notebook.entries() if notebook != null else state.heard
		Summarizer.apply_fallback(live, agent.name, heard)
		return live
	live.summary = summary
	live.summarized_count = fold_until
	return live


func _rebind_dialogue(agent_id: String, previous: DialogueState) -> DialogueState:
	var live: DialogueState = _dialogues.get(agent_id) as DialogueState
	if live == null:
		return previous
	return live


func _validate_result(result: Dictionary, packet: Array, agent_id: String, dialogue: DialogueState, player_text: String, local_fixes: bool) -> Dictionary:
	if not result.get("ok", false):
		return {"ok": false, "violations": PackedStringArray(["пустая реплика"]), "statements": []}
	return ResponseValidator.validate(result.get("json", {}), packet, {
		"case_data": case_data,
		"state": state,
		"agent_id": agent_id,
		"dialogue": dialogue,
		"player_text": player_text,
		"previous_emotion": str(state.emotion.get(agent_id, "neutral")),
		"leak_max_stems": 1,
		"log_leaks": true,
		"local_fixes": local_fixes,
		"evidence_keys": PromptBuilder.report_evidence_keys(case_data, state, agent_id),
		"notebook_ids": PromptBuilder.notebook_ids(case_data, state),
	})


func _should_regenerate(report: Dictionary, local_fixes: bool) -> bool:
	if local_fixes:
		return ResponseValidator.needs_regeneration(report)
	return not report.get("ok", false)


func _abort_turn(snapshot: Dictionary, started_ms: int, model: String, tally: Dictionary, error_kind: String, message: String) -> void:
	_publish_turn_timing(Time.get_ticks_msec() - started_ms, model, tally)
	_restore(snapshot)
	_turn_snapshot = {}
	_sync_dialogues()
	llm_error.emit(error_kind, message)
	_end_busy()


func _drop_turn() -> void:
	_turn_token += 1
	_turn_snapshot = {}
	if is_busy:
		is_busy = false
		busy_changed.emit(false)


func _turn_current(token: int) -> bool:
	return token == _turn_token


func _reply_missing(result: Dictionary) -> bool:
	if not result.get("ok", false):
		return true
	if not _read_choice(result).reply_complete():
		return true
	var payload: Variant = result.get("json", {})
	if payload is Dictionary and str((payload as Dictionary).get("reply", "")).strip_edges() == "":
		return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_for_suspend()


func _save_for_suspend() -> void:
	if state == null or state.case_id.strip_edges() == "":
		return
	var saved := false
	if is_busy and not _turn_snapshot.is_empty():
		var frozen := GameState.from_dict(_turn_snapshot)
		frozen.case_id = state.case_id
		frozen.case_version_hash = state.case_version_hash
		saved = SaveState.write_state(frozen)
	else:
		_sync_dialogues()
		saved = _autosave()
	if not saved:
		save_failed.emit("Не удалось записать сохранение.")


func _end_busy() -> void:
	is_busy = false
	busy_changed.emit(false)


func _publish_turn_timing(elapsed: int, model: String, tally: Dictionary) -> void:
	var shown := model if model != "" else "-"
	last_turn_stats = {
		"ask_to_text_ms": elapsed,
		"model": shown,
		"requests": int(tally.get("requests", 0)),
		"summary": int(tally.get("summary", 0)),
		"regen": int(tally.get("regen", 0)),
		"reasons": LlmTiming.reasons_text(tally),
	}
	last_turn_line = LlmTiming.screen_line(elapsed, int(tally.get("requests", 0)), shown)
	print(LlmTiming.turn_line(elapsed, shown, tally))


func _generate(request: Dictionary) -> Dictionary:
	if LLM.client == null:
		return {"ok": false, "json": {}, "raw_text": "", "error": "offline", "retry_after_s": 0.0, "message": "Клиент модели не создан."}
	var pending: Variant = LLM.client.call("generate", request)
	if pending is Dictionary:
		return pending
	return await pending


func _with_suffix(request: Dictionary, suffix: String) -> Dictionary:
	var copy := request.duplicate(true)
	copy["user"] = str(copy.get("user", "")) + "\n" + suffix
	return copy


func _is_network_error(result: Dictionary) -> bool:
	if result.get("ok", false):
		return false
	var code := str(result.get("error", ""))
	return code == "offline" or code == "timeout" or code == "rate_limited" or code == "auth" or code == "server" or code == "unavailable" or code == "overloaded" or code == "rejected"


func _sync_dialogues() -> void:
	if state == null:
		return
	for agent_id in _dialogues:
		state.dialogues[agent_id] = (_dialogues[agent_id] as DialogueState).to_dict()


func _restore(snapshot: Dictionary) -> void:
	var fresh := GameState.from_dict(snapshot)
	state.pressure = fresh.pressure
	state.emotion = fresh.emotion
	state.unlocked_evidence = fresh.unlocked_evidence
	state.shown = fresh.shown
	state.broken_lies = fresh.broken_lies
	state.fact_levels = fresh.fact_levels
	state.heard = fresh.heard
	state.contradictions = fresh.contradictions
	state.contradiction_turns = fresh.contradiction_turns
	state.evidence_mentions = fresh.evidence_mentions
	state.topic_touches = fresh.topic_touches
	state.talked_to = fresh.talked_to
	state.accusation = fresh.accusation
	state.dialogues = fresh.dialogues
	state.turn = fresh.turn
	state.case_id = fresh.case_id
	state.case_version_hash = fresh.case_version_hash
	for agent_id in _dialogues.keys():
		var saved: Variant = fresh.dialogues.get(agent_id, {})
		if saved is Dictionary:
			_dialogues[agent_id] = DialogueState.from_dict(saved)
