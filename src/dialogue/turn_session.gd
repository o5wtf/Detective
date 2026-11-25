class_name TurnSession
extends RefCounted
## Ход допроса. Им пользуются партия и песочница; у каждой свои состояние и поколение.


const MODEL_CAP := 5


func perform(host: Object, agent_id: String, player_text: String, event_note: String, evidence_id: String, statement_id: String, wav: PackedByteArray) -> void:
	if host.is_busy:
		return
	if host._engine == null or not host._dialogues.has(agent_id):
		host.llm_error.emit("no_case", "Дело не открыто.")
		return
	host.is_busy = true
	host.busy_changed.emit(true)
	host._turn_token += 1
	var token: int = host._turn_token
	if host.links_speaker():
		Speaker.cancel_inflight()
		Speaker.dismiss_retry()
	host.speech_style = ""
	host.speech_line = ""
	var turn_config := LLMConfig.load_settings()
	var turn_started := Time.get_ticks_msec()
	var tally := LlmTiming.empty_tally()
	var turn_model := ""
	host._sync_dialogues()
	var snapshot: Dictionary = host.state.to_dict()
	host._turn_snapshot = snapshot
	var turn_events: Array = []
	if statement_id != "":
		var outcome: Dictionary = host._engine.confront(agent_id, statement_id, evidence_id)
		var quote := _statement_text(host, statement_id)
		var title := evidence_id
		if host.case_data.evidence_by_id.has(evidence_id):
			title = (host.case_data.evidence_by_id[evidence_id] as CaseData.EvidenceItem).title
		event_note = BreakSets.event_note(title, quote, str(outcome.get("verdict", "")))
		var also: Array = outcome.get("also_broken", [])
		if not also.is_empty():
			var names := PackedStringArray()
			for fact_id in also:
				var fact: CaseData.Fact = host.case_data.fact_by_id.get(str(fact_id)) as CaseData.Fact
				names.append(fact.lie_text if fact != null and fact.lie_text != "" else str(fact_id))
			event_note += " Разоблачено также: %s." % ", ".join(names)
	elif evidence_id != "":
		turn_events.append_array(host._engine.present_evidence(agent_id, evidence_id))
	turn_events.append_array(host._engine.note_question(agent_id))
	var dialogue: DialogueState = host._dialogues[agent_id]
	var packet: Array = host._engine.get_packet(agent_id)
	var fallback := _route_reason(host, wav, evidence_id, statement_id)
	tally["merged"] = "yes" if fallback == "" else "no"
	tally["fallback"] = "none" if fallback == "" else fallback
	var request := PromptBuilder.build_turn(host.case_data, host.state, agent_id, packet, dialogue, player_text, event_note, fallback == "")
	var chain := 1
	var result: Dictionary = {}
	var keep_merged := false
	if fallback == "":
		request["wav"] = wav
		if not _spend_model(tally, "reply", "merged"):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		TurnTiming.mark("dialogue_sent")
		host.dialogue_sent.emit(agent_id)
		result = await _generate(request)
		TurnTiming.mark("dialogue_done")
		if not _turn_current(host, token):
			return
		turn_model = str(result.get("model", turn_model))
		if _is_network_error(result):
			fallback = "network"
			tally["fallback"] = "network"
			result = {}
		else:
			var heard := ""
			if result.get("json") is Dictionary:
				heard = str((result.get("json") as Dictionary).get("heard", ""))
			if SpeechJunk.is_junk(heard):
				tally["fallback"] = "junk"
				_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", GameLanguage.text("stt_repeat"))
				return
			if HiddenTerms.mentioned(heard, HiddenTerms.build(host.case_data, host.state)):
				fallback = "leak"
				tally["fallback"] = "leak"
				result = {}
			else:
				keep_merged = true
				player_text = heard.strip_edges()
				request = PromptBuilder.build_turn(host.case_data, host.state, agent_id, packet, dialogue, player_text, event_note)
	if not keep_merged:
		if not wav.is_empty() and (fallback == "network" or fallback == "leak" or fallback == "off"):
			var transcript: Dictionary = await fallback_transcript(host, wav, agent_id, tally)
			if not _turn_current(host, token):
				return
			if str(transcript.get("error", "")) != "":
				var kind := str(transcript.get("error", ""))
				if kind == "cap":
					_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
				elif SpeechJunk.is_junk(str(transcript.get("text", ""))) or kind == "junk":
					if kind == "junk":
						tally["fallback"] = "junk"
					_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", GameLanguage.text("stt_repeat"))
				else:
					_abort_turn(host, snapshot, turn_started, turn_model, tally, kind, str(transcript.get("message", UiStrings.NO_LINK)))
				return
			player_text = str(transcript.get("text", "")).strip_edges()
		request = PromptBuilder.build_turn(host.case_data, host.state, agent_id, packet, dialogue, player_text, event_note)
		if not _spend_model(tally, "reply", "reply"):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		TurnTiming.mark("dialogue_sent")
		host.dialogue_sent.emit(agent_id)
		result = await _generate(request)
		TurnTiming.mark("dialogue_done")
		if not _turn_current(host, token):
			return
		turn_model = str(result.get("model", turn_model))
		if _is_network_error(result):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, str(result.get("error", "")), str(result.get("message", "")))
			return
	if _reply_missing(result):
		if chain >= 2:
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		chain += 1
		var filler := "Отвечай сдержаннее, без откровенных подробностей." if str(result.get("error", "")) == "blocked" else "Ответь одной целой репликой."
		if not _spend_model(tally, "regen", "blocked" if str(result.get("error", "")) == "blocked" else "empty"):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		result = await _generate(_without_audio(request, filler))
		if not _turn_current(host, token):
			return
		turn_model = str(result.get("model", turn_model))
		if _is_network_error(result):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, str(result.get("error", "")), str(result.get("message", "")))
			return
		if _reply_missing(result):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
	var agent: CaseData.Agent = host.case_data.agent_by_id[agent_id]
	var report := _validate_result(host, result, packet, agent_id, dialogue, player_text, turn_config.local_fixes)
	if _should_regenerate(report, turn_config.local_fixes):
		if chain >= 2:
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "bad_response", UiStrings.REPHRASE if _reply_missing(result) else "Целый ответ не принят.")
			return
		chain += 1
		if not _spend_model(tally, "regen", "validation"):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		result = await _generate(_without_audio(request, ResponseValidator.repair_note(report["violations"])))
		if not _turn_current(host, token):
			return
		turn_model = str(result.get("model", turn_model))
		if _is_network_error(result):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, str(result.get("error", "")), str(result.get("message", "")))
			return
		if _reply_missing(result):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		report = _validate_result(host, result, packet, agent_id, dialogue, player_text, turn_config.local_fixes)
	var reply := ""
	var remark := ""
	var tone := 0
	var emotion := str(host.state.emotion.get(agent_id, agent.starting_emotion))
	host.speech_style = ""
	host.speech_line = ""
	var statements: Array = []
	var reader := _read_choice(result)
	if not reader.reply_complete():
		_abort_turn(host, snapshot, turn_started, turn_model, tally, "bad_response", "Ответ оборвался до целой реплики.")
		return
	var options := TurnOptions.build(host.case_data, host.state, agent_id)
	var plan := TurnOptions.plan(host.case_data, host.state, agent_id, options, reader.chosen())
	_log_choice(host, agent_id, options, plan)
	if plan.get("restart", false) == true:
		turn_events.append_array(host._engine.commit_plan(agent_id, plan))
		packet = host._engine.get_packet(agent_id)
		var restarted := PromptBuilder.build_turn(host.case_data, host.state, agent_id, packet, dialogue, player_text, event_note)
		if not _spend_model(tally, "regen", "admit"):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		result = await _generate(_without_audio(restarted, _admit_note(host, plan)))
		if not _turn_current(host, token):
			return
		turn_model = str(result.get("model", turn_model))
		if _is_network_error(result):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, str(result.get("error", "")), str(result.get("message", "")))
			return
		if _reply_missing(result):
			_abort_turn(host, snapshot, turn_started, turn_model, tally, "empty", UiStrings.REPHRASE)
			return
		report = _validate_result(host, result, packet, agent_id, dialogue, player_text, turn_config.local_fixes)
	else:
		turn_events.append_array(host._engine.commit_plan(agent_id, plan))
	if report["ok"] and result.get("ok", false):
		reply = str(report["reply"])
		remark = str(report["remark"])
		tone = int(report["tone"])
		emotion = str(report["emotion"])
		statements = report["statements"]
		var store := SettingsStore.load_current()
		var gemini: bool = store.voice_engine == "gemini"
		host.speech_style = SpeechStyle.compose(agent.voice_style, str(report.get("speech_tone", "")), str(report.get("pace", "")), store.voice_intonation)
		host.speech_line = VocalTags.for_backend(str(report.get("spoken_reply", reply)), gemini, store.voice_intonation)
	else:
		_abort_turn(host, snapshot, turn_started, turn_model, tally, "bad_response", "Целый ответ не принят.")
		return
	host.state.turn += 1
	if not statements.is_empty():
		turn_events.append_array(host._engine.register_statements(agent_id, statements))
	turn_events.append_array(host._engine.apply_tone(agent_id, tone))
	if Balance.emotion_allowed(emotion):
		host._engine.set_emotion(agent_id, emotion)
	dialogue = _rebind_dialogue(host, agent_id, dialogue)
	host.accepted_player_line = player_text
	var marked := evidence_id if statement_id == "" else ""
	dialogue.append_message("player", player_text, host.state.turn, "", marked)
	_keep_feed_events(host, agent_id, turn_events)
	dialogue.append_message("agent", reply, host.state.turn, remark)
	if turn_model == "":
		turn_model = str(result.get("model", ""))
	var text_ms := Time.get_ticks_msec() - turn_started
	host._sync_dialogues()
	if not host.write_save():
		host.save_failed.emit("Не удалось записать сохранение.")
	host._turn_snapshot = {}
	host.agent_replied.emit(agent_id, reply, remark)
	host.events.emit(turn_events)
	_end_busy(host)
	if dialogue.needs_summary():
		LlmTiming.note_request(tally, "summary", "summary")
		dialogue = await _refresh_summary(host, agent_id, dialogue, token)
		if not _turn_current(host, token):
			return
		host._sync_dialogues()
		if not host.write_save():
			host.save_failed.emit("Не удалось записать сохранение.")
	_publish_turn_timing(host, text_ms, turn_model, tally)


func drop(host: Object) -> void:
	if host.links_speaker():
		Speaker.stop_filler()
	host._turn_token += 1
	host._turn_snapshot = {}
	if host.is_busy:
		host.is_busy = false
		host.busy_changed.emit(false)


func restore(host: Object, snapshot: Dictionary) -> void:
	var fresh := GameState.from_dict(snapshot)
	host.state.pressure = fresh.pressure
	host.state.emotion = fresh.emotion
	host.state.unlocked_evidence = fresh.unlocked_evidence
	host.state.shown = fresh.shown
	host.state.broken_lies = fresh.broken_lies
	host.state.fact_levels = fresh.fact_levels
	host.state.heard = fresh.heard
	host.state.contradictions = fresh.contradictions
	host.state.contradiction_turns = fresh.contradiction_turns
	host.state.evidence_mentions = fresh.evidence_mentions
	host.state.topic_touches = fresh.topic_touches
	host.state.retold = fresh.retold
	host.state.confrontations = fresh.confrontations
	host.state.feed_events = fresh.feed_events
	host.state.talked_to = fresh.talked_to
	host.state.accusation = fresh.accusation
	host.state.dialogues = fresh.dialogues
	host.state.turn = fresh.turn
	host.state.case_id = fresh.case_id
	host.state.case_version_hash = fresh.case_version_hash
	for agent_id in host._dialogues.keys():
		var saved: Variant = fresh.dialogues.get(agent_id, {})
		if saved is Dictionary:
			host._dialogues[agent_id] = DialogueState.from_dict(saved)


func fallback_transcript(host: Object, wav: PackedByteArray, agent_id: String, tally: Dictionary) -> Dictionary:
	if not _spend_model(tally, "reply", "stt"):
		return {"text": "", "error": "cap", "message": ""}
	var backend: SttBackend = host.fallback_stt
	var owned := false
	if backend == null:
		var cloud := GeminiStt.new()
		host.add_child(cloud)
		backend = cloud
		owned = true
	var hint := SttHint.for_turn("gemini", host.case_data, host.state, agent_id, "")
	if backend.has_method("set_hint"):
		backend.set_hint(hint)
	var result: Dictionary = await backend.transcribe(wav)
	if owned:
		backend.queue_free()
	var text := str(result.get("text", "")).strip_edges()
	if not result.get("ok", false):
		return {"text": "", "error": str(result.get("error", "offline")), "message": str(result.get("message", ""))}
	if SttGuard.reject(text, host.case_data, host.state, hint):
		return {"text": "", "error": "junk", "message": ""}
	return {"text": text, "error": "", "message": ""}


func _abort_turn(host: Object, snapshot: Dictionary, started_ms: int, model: String, tally: Dictionary, error_kind: String, message: String) -> void:
	if host.links_speaker():
		Speaker.stop_filler()
	_publish_turn_timing(host, Time.get_ticks_msec() - started_ms, model, tally)
	restore(host, snapshot)
	host._turn_snapshot = {}
	host._sync_dialogues()
	host.llm_error.emit(error_kind, message)
	_end_busy(host)


func _end_busy(host: Object) -> void:
	host.is_busy = false
	host.busy_changed.emit(false)


func _turn_current(host: Object, token: int) -> bool:
	return token == host._turn_token


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


func _statement_text(host: Object, statement_id: String) -> String:
	var parts := statement_id.split("|")
	var fact_id := statement_id
	var form := "basic"
	if parts.size() > 0:
		fact_id = parts[0]
	if parts.size() > 1:
		form = parts[1]
	var fact: CaseData.Fact = host.case_data.fact_by_id.get(fact_id) as CaseData.Fact
	return Notebook.text_for(fact, form)


func _admit_note(host: Object, plan: Dictionary) -> String:
	var truths := PackedStringArray()
	for line in plan.get("admit", []):
		if str(line) != "":
			truths.append(str(line))
	var mention := ""
	for evidence_id in plan.get("unlock", []):
		var item: CaseData.EvidenceItem = host.case_data.evidence_by_id.get(str(evidence_id)) as CaseData.EvidenceItem
		if item != null:
			mention += " Скажи, что существует «%s»." % item.title
	return "ЭТОТ ОТВЕТ ЗАМЕНЯЕТ ПРЕДЫДУЩИЙ, ЕГО НЕ ПОКАЗЫВАЮТ И НЕ ОЗВУЧИВАЮТ. Признай в этой реплике только это и ничего сверх: %s. Не повторяй старую ложь.%s" % [" ".join(truths), mention]


func _log_choice(host: Object, agent_id: String, options: Array, plan: Dictionary) -> void:
	if not SettingsStore.load_current().developer:
		return
	var picked: Array = plan.get("picked", [])
	var shown := PackedStringArray()
	for number in picked:
		shown.append(str(number))
	_emit_log(host, "choice agent=%s offered=%d picked=%s decision=%s unlock=%s break=%s" % [
		agent_id,
		options.size(),
		",".join(shown),
		str(plan.get("decision", "")),
		",".join(plan.get("unlock", [])),
		",".join(plan.get("break_lies", [])),
	])


func _refresh_summary(host: Object, agent_id: String, dialogue: DialogueState, token: int) -> DialogueState:
	var live := _rebind_dialogue(host, agent_id, dialogue)
	if not live.needs_summary():
		return live
	var agent: CaseData.Agent = host.case_data.agent_by_id[agent_id]
	var fold_until := live.messages.size() - 6
	var folded: Array = live.messages.slice(live.summarized_count, fold_until)
	var request := Summarizer.build_request(agent.name, live.summary, folded)
	var result: Dictionary = await _generate(request)
	if not _turn_current(host, token):
		return live
	live = _rebind_dialogue(host, agent_id, live)
	var summary := ""
	if result.get("ok", false) and result.get("json") is Dictionary:
		summary = str((result["json"] as Dictionary).get("summary", "")).strip_edges()
	if summary == "":
		var heard: Array = host.notebook.entries() if host.notebook != null else host.state.heard
		Summarizer.apply_fallback(live, agent.name, heard)
		return live
	live.summary = summary
	live.summarized_count = fold_until
	return live


func _rebind_dialogue(host: Object, agent_id: String, previous: DialogueState) -> DialogueState:
	var live: DialogueState = host._dialogues.get(agent_id) as DialogueState
	if live == null:
		return previous
	return live


func _validate_result(host: Object, result: Dictionary, packet: Array, agent_id: String, dialogue: DialogueState, player_text: String, local_fixes: bool) -> Dictionary:
	if not result.get("ok", false):
		return {"ok": false, "violations": PackedStringArray(["пустая реплика"]), "statements": []}
	return ResponseValidator.validate(result.get("json", {}), packet, {
		"case_data": host.case_data,
		"state": host.state,
		"agent_id": agent_id,
		"dialogue": dialogue,
		"player_text": player_text,
		"previous_emotion": str(host.state.emotion.get(agent_id, "neutral")),
		"leak_max_stems": 1,
		"log_leaks": true,
		"local_fixes": local_fixes,
		"evidence_keys": PromptBuilder.report_evidence_keys(host.case_data, host.state, agent_id),
		"notebook_ids": PromptBuilder.notebook_ids(host.case_data, host.state),
	})


func _should_regenerate(report: Dictionary, local_fixes: bool) -> bool:
	if local_fixes:
		return ResponseValidator.needs_regeneration(report)
	return not report.get("ok", false)


func _reply_missing(result: Dictionary) -> bool:
	if not result.get("ok", false):
		return true
	if not _read_choice(result).reply_complete():
		return true
	var payload: Variant = result.get("json", {})
	if payload is Dictionary and str((payload as Dictionary).get("reply", "")).strip_edges() == "":
		return true
	return false


func _keep_feed_events(host: Object, agent_id: String, turn_events: Array) -> void:
	for event in turn_events:
		if event is not Dictionary:
			continue
		var type_name := str((event as Dictionary).get("type", ""))
		if type_name != "evidence_unlocked" and type_name != "lie_broken" and type_name != "contradiction_registered":
			continue
		var row: Dictionary = (event as Dictionary).duplicate(true)
		row["agent_id"] = agent_id if str(row.get("agent_id", "")) == "" else str(row.get("agent_id", ""))
		row["turn"] = host.state.turn
		host.state.feed_events.append(row)


func _publish_turn_timing(host: Object, elapsed: int, model: String, tally: Dictionary) -> void:
	var shown := model if model != "" else "-"
	host.last_turn_stats = {
		"ask_to_text_ms": elapsed,
		"model": shown,
		"requests": int(tally.get("requests", 0)),
		"summary": int(tally.get("summary", 0)),
		"regen": int(tally.get("regen", 0)),
		"reasons": LlmTiming.reasons_text(tally),
		"merged": str(tally.get("merged", "no")),
		"fallback": str(tally.get("fallback", "keyboard")),
		"model_calls": int(tally.get("model_calls", 0)),
	}
	host.last_turn_line = LlmTiming.screen_line(elapsed, int(tally.get("requests", 0)), shown)
	_emit_log(host, LlmTiming.turn_line(elapsed, shown, tally))


func _route_reason(host: Object, wav: PackedByteArray, evidence_id: String, statement_id: String) -> String:
	if wav.is_empty():
		if evidence_id != "" or statement_id != "":
			return "present_text"
		return "keyboard"
	if not host.links_speaker():
		return "keyboard"
	if SettingsStore.load_current().stt_backend == "parakeet":
		return "parakeet"
	if not SettingsStore.load_current().mic_merged:
		return "off"
	return ""


func _spend_model(tally: Dictionary, kind: String, reason: String) -> bool:
	if int(tally.get("model_calls", 0)) >= MODEL_CAP:
		return false
	tally["model_calls"] = int(tally.get("model_calls", 0)) + 1
	LlmTiming.note_request(tally, kind, reason)
	return true


func _without_audio(request: Dictionary, suffix: String) -> Dictionary:
	var copy := _with_suffix(request, suffix)
	copy.erase("wav")
	return copy


func _with_suffix(request: Dictionary, suffix: String) -> Dictionary:
	var copy := request.duplicate(true)
	copy["user"] = str(copy.get("user", "")) + "\n" + suffix
	return copy


func _generate(request: Dictionary) -> Dictionary:
	if LLM.client == null:
		return {"ok": false, "json": {}, "raw_text": "", "error": "offline", "retry_after_s": 0.0, "message": "Клиент модели не создан."}
	var pending: Variant = LLM.client.call("generate", request)
	if pending is Dictionary:
		return pending
	return await pending


func _is_network_error(result: Dictionary) -> bool:
	if result.get("ok", false):
		return false
	var code := str(result.get("error", ""))
	return code == "offline" or code == "timeout" or code == "rate_limited" or code == "auth" or code == "server" or code == "unavailable" or code == "overloaded" or code == "rejected"


func _emit_log(host: Object, line: String) -> void:
	print(line)
	if host.has_method("note_line"):
		host.note_line(line)
