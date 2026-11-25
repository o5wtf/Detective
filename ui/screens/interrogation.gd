extends Control

signal evidence_requested
signal notebook_requested
signal suspects_requested

var agent_id: String = ""

var _header: Label
var _feed_box: VBoxContainer
var _scroll: ScrollContainer
var _prompt: ChatInput
var _hint: HBoxContainer
var _hint_label: Label
var _thinking: Label
var _timing: Label
var _voice_error: Label
var _voice_retry: Button
var _mic: Button
var _mic_level: ProgressBar
var _mic_state: Label
var _mic_hint: Label
var _stt_retry: Button
var _mic_settings: Button
var _talk: PushToTalk
var _hands: HandsFreeListen
var _local: LocalStt
var _mic_input: MicInput
var _access: MicAccess
var _limit_busy: bool = false
var _voice_gate: bool = false
var _heard_speech: bool = false
var _meter: LevelMeter = LevelMeter.new()
var _error: Label
var _retry: Button
var _busy: bool = false
var _hint_id: String = ""
var _confront_statement: String = ""
var _confront_evidence: String = ""
var _dismissed: String = ""
var _last: Dictionary = {}
var _feeds: Dictionary = {}


func _ready() -> void:
	UiWidgets.fill(self)
	var column := VBoxContainer.new()
	UiWidgets.fill(column)
	add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var back := UiWidgets.button("←", "BackButton")
	back.pressed.connect(func() -> void: suspects_requested.emit())
	top.add_child(back)
	_header = UiWidgets.label("", "HeaderLabel")
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_feed_box = VBoxContainer.new()
	_feed_box.name = "Feed"
	_feed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll = UiWidgets.scrolling(_feed_box)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_thinking = UiWidgets.label("", "ThinkingLabel")
	_thinking.add_theme_color_override("font_color", NoirTheme.GOLD)
	_thinking.visible = false
	column.add_child(_thinking)
	_timing = UiWidgets.label("", "TurnTimingLabel")
	_timing.add_theme_color_override("font_color", NoirTheme.MUTED)
	_timing.visible = false
	column.add_child(_timing)
	_voice_error = UiWidgets.label("", "VoiceErrorLabel")
	_voice_error.add_theme_color_override("font_color", NoirTheme.GOLD)
	_voice_error.visible = false
	column.add_child(_voice_error)
	_voice_retry = UiWidgets.button(UiStrings.VOICE_RETRY, "VoiceRetryButton")
	_voice_retry.visible = false
	_voice_retry.pressed.connect(func() -> void: Speaker.retry_failed())
	column.add_child(_voice_retry)
	_error = UiWidgets.label("", "ErrorLabel")
	_error.add_theme_color_override("font_color", NoirTheme.GOLD)
	_error.visible = false
	column.add_child(_error)
	_retry = UiWidgets.button(UiStrings.RETRY, "RetryButton")
	_retry.visible = false
	_retry.pressed.connect(_retry_last)
	column.add_child(_retry)
	_hint = HBoxContainer.new()
	_hint.name = "HintBar"
	_hint.visible = false
	column.add_child(_hint)
	_hint_label = UiWidgets.label("", "HintLabel")
	_hint.add_child(_hint_label)
	var yes := UiWidgets.button(UiStrings.YES, "HintYesButton")
	yes.pressed.connect(_confirm_hint)
	_hint.add_child(yes)
	var dismiss := UiWidgets.button(UiStrings.DISMISS, "HintDismissButton")
	dismiss.pressed.connect(_dismiss_hint)
	_hint.add_child(dismiss)
	var input_row := HBoxContainer.new()
	column.add_child(input_row)
	_prompt = ChatInput.new()
	_prompt.name = "PromptField"
	_prompt.text_changed.connect(func() -> void: _refresh_hint_from_text())
	_prompt.submit_pressed.connect(_send)
	input_row.add_child(_prompt)
	var send := UiWidgets.button(UiStrings.SEND, "SendButton")
	send.pressed.connect(_send)
	input_row.add_child(send)
	_mic = UiWidgets.button("🎤", "MicButton")
	_mic.button_down.connect(_mic_down)
	_mic.button_up.connect(_mic_up)
	_mic_level = ProgressBar.new()
	_mic_level.name = "MicLevel"
	_mic_level.min_value = 0.0
	_mic_level.max_value = 1.0
	_mic_level.custom_minimum_size = Vector2(72, 16)
	_mic_level.show_percentage = false
	_mic_level.visible = true
	_mic_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_row.add_child(_mic_level)
	input_row.add_child(_mic)
	var tools := HBoxContainer.new()
	column.add_child(tools)
	var evidence := UiWidgets.button(UiStrings.EVIDENCE, "EvidenceButton")
	evidence.pressed.connect(func() -> void: evidence_requested.emit())
	tools.add_child(evidence)
	var notebook := UiWidgets.button(UiStrings.NOTEBOOK, "NotebookButton")
	notebook.pressed.connect(func() -> void: notebook_requested.emit())
	tools.add_child(notebook)
	var stop_speech := UiWidgets.button(UiStrings.STOP_SPEECH, "StopSpeechButton")
	stop_speech.pressed.connect(_skip_speech)
	tools.add_child(stop_speech)
	_mic_state = UiWidgets.label("", "MicStateLabel")
	_mic_state.add_theme_color_override("font_color", NoirTheme.GOLD)
	column.add_child(_mic_state)
	_mic_hint = UiWidgets.label("", "MicHintLabel")
	_mic_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mic_hint.visible = false
	column.add_child(_mic_hint)
	_mic_settings = UiWidgets.button(UiStrings.MIC_SETTINGS, "MicSettingsButton")
	_mic_settings.visible = false
	_mic_settings.pressed.connect(_open_mic_settings)
	column.add_child(_mic_settings)
	_stt_retry = UiWidgets.button(UiStrings.MIC_RETRY, "SttRetryButton")
	_stt_retry.visible = false
	_stt_retry.pressed.connect(_retry_stt)
	column.add_child(_stt_retry)
	_talk = PushToTalk.new()
	_talk.name = "PushToTalk"
	var recognizer := _make_stt()
	_talk.stt = recognizer
	add_child(_talk)
	_talk.add_child(recognizer)
	_hands = HandsFreeListen.new()
	_hands.name = "HandsFreeListen"
	_hands.stt = recognizer
	_hands.submit = _send_text
	add_child(_hands)
	_mic_input = MicInput.new()
	add_child(_mic_input)
	_access = MicAccess.new()
	add_child(_access)
	_talk.submit = _send_text
	_talk.hint_source = _stt_hint
	_hands.hint_source = _stt_hint
	_talk.state_changed.connect(_on_mic_state)
	_talk.hint_changed.connect(_on_mic_hint)
	_talk.level_changed.connect(_on_mic_level)
	_talk.retry_visible.connect(func(show_button: bool) -> void: _stt_retry.visible = show_button)
	_hands.state_changed.connect(_on_mic_state)
	_hands.hint_changed.connect(_on_mic_hint)
	_hands.level_changed.connect(_on_mic_level)
	_hands.retry_visible.connect(func(show_button: bool) -> void: _stt_retry.visible = show_button)
	if Speaker.last_error != "":
		_show_voice_error(Speaker.last_error)
	if not Speaker.voice_error.is_connected(_show_voice_error):
		Speaker.voice_error.connect(_show_voice_error)
	_sync_voice_retry()
	if not Speaker.voice_retry_available.is_connected(_show_voice_retry):
		Speaker.voice_retry_available.connect(_show_voice_retry)
	if not Speaker.is_speaking.is_connected(_on_speaker):
		Speaker.is_speaking.connect(_on_speaker)
	if not Speaker.voice_error.is_connected(_on_voice_settled):
		Speaker.voice_error.connect(_on_voice_settled)
	if not Speaker.voice_retry_available.is_connected(_on_retry_gate):
		Speaker.voice_retry_available.connect(_on_retry_gate)
	if not Speaker.voice_line_changed.is_connected(_render_feed):
		Speaker.voice_line_changed.connect(_render_feed)
	if not Game.agent_replied.is_connected(_on_replied):
		Game.agent_replied.connect(_on_replied)
		Game.events.connect(_on_events)
		Game.llm_error.connect(_on_error)
		Game.busy_changed.connect(_on_busy)
	if DisplayServer.get_name() != "headless":
		await _warm_link()


func _make_stt() -> SttBackend:
	var cloud := GeminiStt.new()
	cloud.name = "GeminiStt"
	var local := LocalStt.new()
	local.name = "LocalStt"
	local.cloud = cloud
	var router := SttRouter.new()
	router.name = "SttRouter"
	router.cloud = cloud
	router.local = local
	router.add_child(cloud)
	router.add_child(local)
	_local = local
	local.prepare()
	return router


func _warm_link() -> void:
	await HttpSession.prewarm(self)


func _show_voice_retry(_show_button: bool) -> void:
	_sync_voice_retry()


func _sync_voice_retry() -> void:
	if _voice_retry == null:
		return
	var mine := Speaker.retry_visible_for(agent_id)
	_voice_retry.visible = mine
	if not mine:
		_voice_error.text = ""
		_voice_error.visible = false


func _show_voice_error(kind: String) -> void:
	var text := kind.strip_edges()
	_voice_error.text = "" if text == "" else "Голос: %s" % text
	_voice_error.visible = text != ""


func _process(delta: float) -> void:
	_refresh_mic_button()
	if not _capturing():
		_meter.push(0.0)
	if _mic_level != null and _meter.advance(delta):
		_mic_level.value = _meter.shown
	if _talk == null or _mic_input == null:
		return
	var active := is_visible_in_tree() and not get_tree().paused
	var hands := _hands_free()
	_talk.screen_active = active and not hands
	_talk.enabled = SettingsStore.load_current().mic_enabled
	_talk.character_busy = _voice_gate or Speaker.speaking
	if _hands != null:
		_hands.screen_active = active and hands
		_hands.enabled = _talk.enabled
		_hands.set_pause_ms(SettingsStore.load_current().mic_pause_ms)
		_hands.set_echo(Speaker.speaking)
		_hands.set_output_lock(_voice_gate or Speaker.speaking)
	if not active:
		if _talk._holding or _talk.locked:
			_talk.cancel()
		if _hands != null:
			_hands.stop()
		if _mic_input.api_name != "":
			_mic_input.stop()
		return
	if _talk.enabled and _access != null and _access.allowed():
		MicAccess.start_if_allowed(_access, _mic_input)
	if _mic_input.api_name == "":
		return
	var pcm := _mic_input.read_pcm()
	if hands:
		_hands.push_pcm(pcm)
		return
	if _talk._holding:
		_mic_input.observe_hold(pcm, delta * 1000.0)
	var kind := _talk.push_pcm(pcm)
	if kind == "limit" and not _limit_busy:
		_limit_busy = true
		await _talk.release(true)
		_limit_busy = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _talk != null:
			_talk.cancel()
		if _mic_input != null:
			_mic_input.stop()
	if what == NOTIFICATION_APPLICATION_PAUSED and _local != null:
		_local.release_model()
	if what == NOTIFICATION_APPLICATION_RESUMED and _local != null:
		_local.prepare()
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and is_visible_in_tree() and _local != null:
		_local.prepare()
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		Speaker.stop_and_clear(false)
		_voice_gate = false
		_heard_speech = false
		_apply_voice_gate()
		if _talk != null:
			_talk.cancel()
		if _hands != null:
			_hands.stop()
		if _mic_input != null:
			_mic_input.stop()


func open_agent(next_id: String) -> void:
	if agent_id != "" and next_id != agent_id:
		Speaker.cancel_inflight()
	agent_id = next_id
	var greeting := Game.add_greeting(next_id)
	if greeting != "":
		Speaker.speak_greeting(next_id, greeting)
	if not _feeds.has(next_id):
		_feeds[next_id] = _saved_lines(next_id)
	_render_header()
	_render_feed()
	_sync_voice_retry()


func _saved_lines(id: String) -> Array:
	var lines: Array = []
	if Game.state == null:
		return lines
	var saved: Variant = Game.state.dialogues.get(id, {})
	if saved is not Dictionary:
		return lines
	var messages: Variant = (saved as Dictionary).get("messages", [])
	if messages is not Array:
		return lines
	for message in messages:
		if message is not Dictionary:
			continue
		var role := str((message as Dictionary).get("role", ""))
		if role == "player":
			lines.append({"kind": "player", "text": str((message as Dictionary).get("text", ""))})
		elif role == "agent":
			lines.append({
				"kind": "agent",
				"text": str((message as Dictionary).get("text", "")),
				"remark": str((message as Dictionary).get("remark", "")),
			})
	return lines


func set_back_visible(show_back: bool) -> void:
	var back := find_child("BackButton", true, false) as Button
	if back != null:
		back.visible = show_back


func _render_header() -> void:
	if Game.case_data == null or agent_id == "":
		_header.text = ""
		return
	var agent: CaseData.Agent = Game.case_data.agent_by_id[agent_id]
	var band := Balance.band(int(Game.state.pressure.get(agent_id, 0)))
	var emotion := str(Game.state.emotion.get(agent_id, agent.starting_emotion))
	var pressure_value := int(Game.state.pressure.get(agent_id, 0))
	_header.text = "%s, %s   %s" % [agent.name, agent.role, UiStrings.state_line(band, emotion, pressure_value, SettingsStore.load_current().developer)]


func _send() -> void:
	if _prompt == null:
		return
	var text := _prompt.text.strip_edges()
	if _busy or (_talk != null and _talk.locked):
		return
	if text == "" and _confront_statement == "":
		return
	_prompt.text = ""
	await _send_text(text)


func begin_confront(statement_id: String, evidence_id: String) -> void:
	_confront_statement = statement_id
	_confront_evidence = evidence_id
	var title := _evidence_title(evidence_id)
	_hint_label.text = "Предъявить «%s»? Можно добавить фразу в поле." % title
	_hint.visible = true


func _send_text(text: String) -> void:
	if _busy or agent_id == "":
		return
	var wav := _take_pending_wav()
	if _confront_statement != "":
		await _send_confront(text, wav)
		return
	if not wav.is_empty():
		_clear_error()
		_voice_gate = true
		_heard_speech = false
		_apply_voice_gate()
		_last = {"kind": "ask", "text": "", "wav": wav, "agent_id": agent_id}
		await Game.ask(agent_id, "", wav)
		_release_voice_gate()
		return
	var spoken := text.strip_edges()
	if spoken == "":
		return
	_hide_hint()
	_clear_error()
	_voice_gate = true
	_heard_speech = false
	_apply_voice_gate()
	_last = {"kind": "ask", "text": spoken, "agent_id": agent_id}
	_push({"kind": "player", "text": spoken})
	TurnTiming.mark("line_shown")
	await Game.ask(agent_id, spoken)
	_release_voice_gate()


func _apply_voice_gate() -> void:
	if _hands != null:
		_hands.set_output_lock(_voice_gate or Speaker.speaking)
	if _talk != null:
		_talk.character_busy = _voice_gate or Speaker.speaking


func _release_voice_gate() -> void:
	var voice_off := not SettingsStore.load_current().voice_enabled
	var failed := Speaker.last_error != "" or not Speaker.retry_line.is_empty()
	if voice_off or failed:
		_voice_gate = false
		_heard_speech = false
	elif Speaker.speaking or Speaker.queue.current_id != "" or not Speaker.queue.pending.is_empty():
		_voice_gate = true
	else:
		_voice_gate = false
		_heard_speech = false
	_apply_voice_gate()


func _on_speaker(active: bool) -> void:
	if active:
		_heard_speech = true
		_voice_gate = true
	elif _heard_speech:
		_voice_gate = false
		_heard_speech = false
	_apply_voice_gate()


func _on_voice_settled(_kind: String) -> void:
	_voice_gate = false
	_heard_speech = false
	_apply_voice_gate()


func _on_retry_gate(show_button: bool) -> void:
	if show_button:
		_voice_gate = false
		_heard_speech = false
		_apply_voice_gate()
	_show_voice_retry(show_button)


func _skip_speech() -> void:
	Speaker.stop_and_clear()
	_voice_gate = false
	_heard_speech = false
	_apply_voice_gate()


func _capturing() -> bool:
	if _hands_free() and _hands != null:
		return _hands.enabled and not _hands.paused and not _hands.echo and not _hands.output_lock and not _hands.locked
	return _talk != null and _talk._holding


func _mic_down() -> void:
	if _talk == null or _mic.disabled:
		return
	if _hands_free():
		var allowed := true
		if _access != null:
			allowed = await _access.ensure()
		if not allowed:
			_on_mic_hint(UiStrings.MIC_NO_PERMISSION)
			if _mic_settings != null:
				_mic_settings.visible = true
			return
		if _mic_input != null and _access != null:
			MicAccess.start_if_allowed(_access, _mic_input)
		_hands.toggle_pause()
		_refresh_mic_button()
		return
	Speaker.cancel_inflight()
	var allowed := true
	if _access != null:
		allowed = await _access.ensure()
	if not allowed:
		_on_mic_hint(UiStrings.MIC_NO_PERMISSION)
		if _mic_settings != null:
			_mic_settings.visible = true
		return
	if _access != null and _access.just_granted and _mic_input != null:
		_mic_input.needs_restart = true
	if _mic_input != null and _access != null:
		MicAccess.start_if_allowed(_access, _mic_input)
	elif _mic_input != null and _mic_input.api_name == "":
		_mic_input.warm()
	if _mic_input != null and _mic_input.api_name == "":
		if OS.get_name() == "Windows":
			_on_mic_hint(UiStrings.MIC_WINDOWS)
		else:
			_on_mic_hint(MicInput.hint_for("input_inactive"))
		return
	if _talk.press() and _mic_input != null:
		_mic_input.begin_hold()


func _mic_up() -> void:
	if _hands_free():
		return
	if _talk == null or not _talk._holding:
		return
	await _talk.release(false)
	if _mic_input != null:
		_mic_input.log_hold()


func _retry_stt() -> void:
	if _talk != null:
		await _talk.retry()


func _open_mic_settings() -> void:
	var package_name := "com.o5wtf.detective"
	if OS.get_name() == "Android":
		OS.shell_open("intent:#Intent;action=android.settings.APPLICATION_DETAILS_SETTINGS;data=package:%s;end" % package_name)
	elif OS.get_name() == "Windows":
		OS.shell_open("ms-settings:privacy-microphone")
	if _access != null and await _access.ensure():
		if _mic_settings != null:
			_mic_settings.visible = false
		if _mic_input != null:
			_mic_input.needs_restart = true
			MicAccess.start_if_allowed(_access, _mic_input)


func _refresh_mic_button() -> void:
	if _mic == null or _talk == null:
		return
	if _hands_free() and _hands != null:
		_mic.disabled = not _hands.enabled or _voice_gate or Speaker.speaking
		_mic_state.text = _hands.label()
		return
	var blocked := Speaker.speaking or _talk.locked or not _talk.enabled
	_mic.disabled = blocked and not _talk._holding
	if _mic.disabled and _talk._holding:
		_talk.cancel()
	if Speaker.speaking:
		_mic_state.text = UiStrings.MIC_ANSWER
	elif _talk.state_name == PushToTalk.STATE_LISTENING:
		_mic_state.text = UiStrings.MIC_LISTEN
	elif _talk.state_name == PushToTalk.STATE_RECOGNIZING:
		_mic_state.text = UiStrings.MIC_RECOGNIZE
	elif _talk.state_name == PushToTalk.STATE_ANSWERING:
		_mic_state.text = UiStrings.MIC_ANSWER
	else:
		_mic_state.text = ""


func _stt_hint() -> String:
	var last_line := ""
	if Game.state != null:
		var saved: Variant = Game.state.dialogues.get(agent_id, {})
		if saved is Dictionary:
			var messages: Variant = (saved as Dictionary).get("messages", [])
			if messages is Array:
				for message in messages:
					if message is Dictionary and str((message as Dictionary).get("role", "")) == "agent":
						last_line = str((message as Dictionary).get("text", ""))
	return SttHint.for_turn(SettingsStore.load_current().stt_backend, Game.case_data, Game.state, agent_id, last_line)


func _hands_free() -> bool:
	return SettingsStore.load_current().mic_mode == "hands_free"


func _on_mic_state(_next: String) -> void:
	_refresh_mic_button()


func _on_mic_hint(text: String) -> void:
	if _mic_hint == null:
		return
	var shown := text
	if shown == "Тишина в записи.":
		if OS.get_name() == "Windows":
			shown = UiStrings.MIC_WINDOWS
		else:
			var frames := 0 if _mic_input == null else _mic_input.hold_frames
			shown = MicInput.hint_for("quiet", frames)
	if shown == UiStrings.MIC_NO_PERMISSION and _mic_settings != null:
		_mic_settings.visible = true
	_mic_hint.text = shown
	_mic_hint.visible = shown != ""


func _on_mic_level(unit: float) -> void:
	_meter.push(unit)


func _take_pending_wav() -> PackedByteArray:
	if _talk != null and not _talk.pending_wav.is_empty():
		var wav := _talk.pending_wav
		_talk.pending_wav = PackedByteArray()
		return wav
	if _hands != null and not _hands.pending_wav.is_empty():
		var wav := _hands.pending_wav
		_hands.pending_wav = PackedByteArray()
		return wav
	return PackedByteArray()


func _send_confront(text: String, wav: PackedByteArray = PackedByteArray()) -> void:
	var statement_id := _confront_statement
	var evidence_id := _confront_evidence
	_confront_statement = ""
	_confront_evidence = ""
	_hide_hint()
	_clear_error()
	_voice_gate = true
	_heard_speech = false
	_apply_voice_gate()
	_last = {
		"kind": "confront",
		"text": text.strip_edges(),
		"wav": wav,
		"statement_id": statement_id,
		"evidence_id": evidence_id,
		"agent_id": agent_id,
	}
	var quote := _statement_quote(statement_id)
	var title := _evidence_title(evidence_id)
	_push({"kind": "player", "text": UiStrings.confront_line(title, quote)})
	await Game.confront(agent_id, statement_id, evidence_id, text, wav)
	_push_verdict(agent_id, statement_id, evidence_id)
	_release_voice_gate()


func _push_verdict(who: String, statement_id: String, evidence_id: String) -> void:
	if Game.state == null:
		return
	for item in Game.state.confrontations:
		if str(item.get("agent_id", "")) != who:
			continue
		if str(item.get("statement_id", "")) != statement_id or str(item.get("evidence_id", "")) != evidence_id:
			continue
		var label := UiStrings.player_verdict(str(item.get("verdict", "")))
		var line := label
		var also: Variant = item.get("also_broken", [])
		if also is Array and not (also as Array).is_empty():
			var names: PackedStringArray = PackedStringArray()
			for fact_id in also:
				var fact: CaseData.Fact = Game.case_data.fact_by_id.get(str(fact_id)) as CaseData.Fact
				names.append(fact.lie_text if fact != null and fact.lie_text != "" else str(fact_id))
			line = "%s. %s" % [label, UiStrings.also_broken(", ".join(names))]
		_push_to(who, {"kind": "system", "text": line})
		return


func _statement_quote(statement_id: String) -> String:
	var parts := statement_id.split("|")
	var fact_id := parts[0] if not parts.is_empty() else statement_id
	var form := parts[1] if parts.size() > 1 else "basic"
	var fact: CaseData.Fact = null
	if Game.case_data != null:
		fact = Game.case_data.fact_by_id.get(fact_id) as CaseData.Fact
	return Notebook.text_for(fact, form)


func _confirm_from_board(evidence_id: String) -> void:
	if _busy or agent_id == "":
		return
	_clear_error()
	_voice_gate = true
	_heard_speech = false
	_apply_voice_gate()
	_last = {"kind": "present", "text": "", "evidence_id": evidence_id, "agent_id": agent_id}
	_push({"kind": "system", "text": "Вы: %s" % UiStrings.presented_line(_evidence_title(evidence_id))})
	await Game.present(agent_id, evidence_id, "")
	_release_voice_gate()


func _confirm_hint() -> void:
	if _confront_statement != "":
		var extra := _prompt.text.strip_edges()
		_prompt.text = ""
		await _send_confront(extra)
		return
	if _busy or _hint_id == "" or agent_id == "":
		return
	var text := _prompt.text.strip_edges()
	var evidence_id := _hint_id
	_prompt.text = ""
	_hide_hint()
	_clear_error()
	_last = {"kind": "present", "text": text, "evidence_id": evidence_id, "agent_id": agent_id}
	var title := _evidence_title(evidence_id)
	_push({"kind": "system", "text": "Вы: %s" % UiStrings.presented_line(title)})
	await Game.present(agent_id, evidence_id, text)


func _retry_last() -> void:
	if _last.is_empty() or _busy:
		return
	_clear_error()
	var who := str(_last.get("agent_id", agent_id))
	if who == "":
		who = agent_id
	var retry_wav: PackedByteArray = _last.get("wav", PackedByteArray()) if _last.get("wav") is PackedByteArray else PackedByteArray()
	if str(_last.get("kind", "")) == "confront":
		await Game.confront(who, str(_last.get("statement_id", "")), str(_last.get("evidence_id", "")), str(_last.get("text", "")), retry_wav)
	elif not retry_wav.is_empty() and str(_last.get("text", "")) == "":
		await Game.ask(who, "", retry_wav)
	elif str(_last.get("kind", "")) == "present":
		await Game.present(who, str(_last.get("evidence_id", "")), str(_last.get("text", "")))
	else:
		_push_to(who, {"kind": "player", "text": str(_last.get("text", ""))})
		if who == agent_id:
			_render_feed()
		await Game.ask(who, str(_last.get("text", "")))


func _refresh_hint_from_text() -> void:
	if Game.case_data == null:
		return
	var found := Game.mentioned_evidence(_prompt.text)
	if found.is_empty():
		if _hint.visible:
			_hide_hint()
		return
	var evidence_id := str(found[0])
	if evidence_id == _dismissed:
		return
	_show_hint(evidence_id)


func _show_hint(evidence_id: String) -> void:
	_hint_id = evidence_id
	_hint_label.text = UiStrings.present_hint(_evidence_title(evidence_id))
	_hint.visible = true


func _dismiss_hint() -> void:
	_dismissed = _hint_id
	_hide_hint()


func _hide_hint() -> void:
	_hint_id = ""
	_hint.visible = false


func _on_replied(reply_agent: String, text: String, remark: String) -> void:
	var spoken := Game.accepted_player_line.strip_edges()
	if spoken != "" and not _feed_has_player(reply_agent, spoken):
		_push_to(reply_agent, {"kind": "player", "text": spoken})
		if str(_last.get("agent_id", "")) == reply_agent and str(_last.get("text", "")) == "":
			_last["text"] = spoken
	if reply_agent != agent_id:
		_push_to(reply_agent, {"kind": "agent", "text": text, "remark": remark})
		return
	_push({"kind": "agent", "text": text, "remark": remark})
	_render_header()
	_show_turn_timing()


func _on_events(list: Array) -> void:
	for event in list:
		if event is not Dictionary:
			continue
		var line := _event_line(event as Dictionary)
		if line != "":
			_push({"kind": "system", "text": line})
	_render_header()


func _on_error(kind: String, message: String) -> void:
	_pop_player_line()
	var text := message.strip_edges()
	if kind == "offline" or kind == "timeout" or text == UiStrings.NO_LINK:
		var held: PackedByteArray = _last.get("wav", PackedByteArray()) if _last.get("wav") is PackedByteArray else PackedByteArray()
		if str(_last.get("kind", "")) == "ask" and _prompt != null and held.is_empty():
			_prompt.text = str(_last.get("text", ""))
		text = UiStrings.NO_LINK
	elif text == "":
		text = UiStrings.error_text(kind)
	_error.text = text
	_error.visible = true
	_retry.visible = true
	_show_turn_timing()


func _show_turn_timing() -> void:
	var enabled := SettingsStore.load_current().timing_debug
	_timing.text = Game.last_turn_line
	_timing.visible = enabled and Game.last_turn_line != ""


func _on_busy(is_busy: bool) -> void:
	_busy = is_busy
	_prompt.editable = not is_busy
	var send := find_child("SendButton", true, false) as Button
	if send != null:
		send.disabled = is_busy
	if is_busy and agent_id != "":
		var agent: CaseData.Agent = Game.case_data.agent_by_id.get(agent_id) as CaseData.Agent
		_thinking.text = UiStrings.thinking(agent.name if agent != null else "")
		_thinking.visible = true
	else:
		_thinking.visible = false


func _event_line(event: Dictionary) -> String:
	var type_name := str(event.get("type", ""))
	if type_name == "evidence_unlocked":
		return UiStrings.evidence_opened(_evidence_title(str(event.get("evidence_id", ""))))
	if type_name == "contradiction_registered":
		var found: CaseData.Contradiction = Game.case_data.contradiction_by_id.get(str(event.get("contradiction_id", ""))) as CaseData.Contradiction
		if found == null:
			return ""
		return UiStrings.contradiction_line(found.description)
	if type_name == "lie_broken":
		var owner := str(event.get("agent_id", ""))
		var agent: CaseData.Agent = Game.case_data.agent_by_id.get(owner) as CaseData.Agent
		if agent == null:
			return ""
		return UiStrings.lie_broken(agent.name)
	return ""


func _feed_has_player(who: String, text: String) -> bool:
	var rows: Array = _feeds.get(who, [])
	for row in rows:
		if row is Dictionary and str((row as Dictionary).get("kind", "")) == "player" and str((row as Dictionary).get("text", "")) == text:
			return true
	return false


func _push(line: Dictionary) -> void:
	_push_to(agent_id, line)
	if line.get("kind") != "player":
		_render_feed()
	else:
		_render_feed()


func _push_to(owner: String, line: Dictionary) -> void:
	if owner == "":
		return
	if not _feeds.has(owner):
		_feeds[owner] = []
	(_feeds[owner] as Array).append(line)


func _pop_player_line() -> void:
	if not _feeds.has(agent_id):
		return
	var rows: Array = _feeds[agent_id]
	if rows.is_empty():
		return
	var last: Dictionary = rows[rows.size() - 1]
	if str(last.get("kind", "")) == "player":
		rows.pop_back()
		_render_feed()


func _render_feed() -> void:
	if _feed_box == null:
		return
	for child in _feed_box.get_children():
		child.queue_free()
	var rows: Array = _feeds.get(agent_id, [])
	var last_agent := -1
	for index in rows.size():
		if str(rows[index].get("kind", "")) == "agent":
			last_agent = index
	for index in rows.size():
		var row: Dictionary = rows[index]
		var kind := str(row.get("kind", ""))
		if kind == "player":
			_feed_box.add_child(UiWidgets.label("Вы: %s" % str(row.get("text", ""))))
		elif kind == "agent":
			var agent: CaseData.Agent = Game.case_data.agent_by_id.get(agent_id) as CaseData.Agent
			var name := agent.name if agent != null else ""
			var shown := VocalTags.visible(str(row.get("text", "")))
			_feed_box.add_child(UiWidgets.label("%s: %s" % [name, shown]))
			if index == last_agent and Speaker.can_skip():
				var skip := UiWidgets.button(UiStrings.VOICE_SKIP, "SkipSpeechButton")
				skip.pressed.connect(func() -> void: Speaker.skip_current())
				_feed_box.add_child(skip)
			var remark := str(row.get("remark", ""))
			if remark != "":
				var note := UiWidgets.label("(%s)" % remark)
				note.add_theme_font_override("font", NoirTheme.italic())
				note.add_theme_color_override("font_color", NoirTheme.MUTED)
				_feed_box.add_child(note)
		else:
			var system := UiWidgets.label(str(row.get("text", "")))
			system.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			system.add_theme_color_override("font_color", NoirTheme.GOLD)
			_feed_box.add_child(system)
	call_deferred("_scroll_down")


func _scroll_down() -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _clear_error() -> void:
	_error.visible = false
	_retry.visible = false


func _evidence_title(evidence_id: String) -> String:
	if Game.case_data == null or not Game.case_data.evidence_by_id.has(evidence_id):
		return evidence_id
	return (Game.case_data.evidence_by_id[evidence_id] as CaseData.EvidenceItem).title
