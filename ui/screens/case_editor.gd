class_name CaseEditor
extends Control
## Каркас редактора: общая картина и карточка персонажа без показаний.

signal leave_pressed
signal copied(case_id: String)

var case_id: String = ""
var _doc: CaseDocument
var _read_only := false
var _agent := 0
var _undo_open := false
var _timer: Timer
var _help: Control
var _failed: Control
var _warn: Control
var _scroll: ScrollContainer
var keyboard_inset := -1
var _tab := 0
var _hold_tab := false
var _remove_kind := ""
var _remove_id := ""


func open_id(next_id: String) -> void:
	case_id = next_id
	_read_only = CaseLibrary.is_example(next_id)
	_doc = CaseDocument.open(CaseLibrary.read_source(next_id))
	_agent = 0
	_build()


func consume_back() -> bool:
	if _help != null and _help.visible:
		_help.visible = false
		return true
	if _warn != null and _warn.visible:
		_warn.visible = false
		return true
	if _failed != null and _failed.visible:
		return true
	if _read_only:
		return false
	if not flush_autosave():
		_failed.visible = true
		return true
	return false


func flush_autosave() -> bool:
	if _doc == null or _read_only:
		return true
	_apply_open_fields()
	return CaseLibrary.write_draft(case_id, _doc.export_raw())


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 1.0
	_timer.timeout.connect(func() -> void: flush_autosave())
	add_child(_timer)


func rebuild_editor() -> void:
	_build()
	_schedule()


func ask_remove(kind: String, item_id: String) -> void:
	if _read_only:
		return
	_remove_kind = kind
	_remove_id = item_id
	var lines := _doc.usage_lines(kind, item_id)
	var label := find_child("DeleteText", true, false) as Label
	if label != null:
		if lines.is_empty():
			label.text = "Удалить?"
		else:
			label.text = "Используется в %d местах:\n%s" % [lines.size(), "\n".join(lines)]
	var dialog := find_child("DeleteConfirm", true, false)
	if dialog != null:
		dialog.visible = true


func goto_issue(issue: Dictionary) -> void:
	var target: Dictionary = issue.get("target", {})
	var tab := str(target.get("tab", "overview"))
	_tab = 0 if tab == "overview" else 2 if tab == "evidence" else 1
	_hold_tab = true
	var agent := int(target.get("agent", _agent))
	if agent >= 0:
		_agent = agent
	_build()
	var node := find_child(str(target.get("node", "")), true, false) as Control
	if node != null:
		_keep_visible(node)


func _section_label(text: String) -> Control:
	return UiWidgets.label(text)


func _build() -> void:
	var previous := find_child("EditorTabs", true, false) as TabContainer
	if previous != null and not _hold_tab:
		_tab = previous.current_tab
	_hold_tab = false
	for child in get_children():
		if child == _timer:
			continue
		child.free()
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.name = "EditorMargin"
	UiWidgets.fill(margin)
	add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var back := UiWidgets.button(UiStrings.BACK, "BackButton")
	back.pressed.connect(func() -> void: _try_leave())
	bar.add_child(back)
	if not _read_only:
		var undo := UiWidgets.button(UiStrings.UNDO, "UndoButton")
		undo.pressed.connect(_undo)
		bar.add_child(undo)
		var publish := UiWidgets.button(UiStrings.PUBLISH, "PublishButton")
		publish.pressed.connect(func() -> void: _publish(false))
		bar.add_child(publish)
	var copy := UiWidgets.button(UiStrings.COPY_CASE, "CopyButton")
	copy.pressed.connect(_copy)
	bar.add_child(copy)
	if _read_only:
		column.add_child(UiWidgets.label(UiStrings.EXAMPLE_LOCK, "ExampleLock"))
	var tabs := TabContainer.new()
	tabs.name = "EditorTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	tabs.add_child(_overview())
	tabs.add_child(_people())
	tabs.add_child(EditorSheet.evidence_page(self))
	tabs.set_tab_title(0, UiStrings.TAB_OVERVIEW)
	tabs.set_tab_title(1, UiStrings.TAB_PEOPLE)
	tabs.set_tab_title(2, UiStrings.TAB_EVIDENCE)
	tabs.current_tab = clampi(_tab, 0, 2)
	tabs.tab_changed.connect(func(index: int) -> void: _tab = index)
	_help = _popup("HelpPopup")
	_failed = _fail_popup()
	_warn = _warn_popup()
	var remove_dialog := _delete_popup()
	add_child(_help)
	add_child(_failed)
	add_child(_warn)
	add_child(remove_dialog)
	_lock_if_needed()
	var errors := VBoxContainer.new()
	errors.name = "EditorIssues"
	column.add_child(errors)
	_show_errors()


func _overview() -> Control:
	var box := VBoxContainer.new()
	box.name = "Overview"
	_scroll = UiWidgets.scrolling(box)
	_scroll.name = "EditorScroll"
	box.add_child(_line("Название", "TitleEdit", str(_doc.raw.get("title", "")), "Дождь над «Тенью»", "title"))
	box.add_child(_area("Брифинг", "BriefingEdit", str(_doc.raw.get("briefing", "")), "Ночь. Дождь заливает асфальт. В аллее за клубом найден труп владельца…", "briefing"))
	_help_button(box, "BriefingHelp", "Это читает игрок в начале и это знают ВСЕ персонажи — тайн не писать")
	box.add_child(_area("Общий стиль персонажей", "AtmosphereEdit", str(_doc.raw.get("intro_atmosphere", "")), "Современный нуар. Голоса хриплые, напряжённые. Каждый врёт по-своему", "intro_atmosphere"))
	var note: Dictionary = _doc.raw.get("editor", {})
	box.add_child(_area("Места и хронология", "TimelineEdit", str(note.get("timeline_text", "")), "00:50 — Мира уходит. 01:00 — клуб закрыт.", "editor"))
	_help_button(box, "TimelineHelp", "Игра это не использует, это ваша шпаргалка")
	box.add_child(_area("Как всё было", "TruthEdit", str(_doc.raw.get("truth_timeline", "")), "Клуб закрылся в 01:00. Виктор остался…", "truth_timeline"))
	_help_button(box, "TruthHelp", "Игрок видит на экране победы. ИИ этот текст не получает")
	box.add_child(_killer())
	box.add_child(_choices("method"))
	box.add_child(_choices("motive"))
	box.add_child(UiWidgets.label("Нужно назвать убийцу, способ и мотив"))
	return _scroll


func _people() -> Control:
	var page := HBoxContainer.new()
	page.name = "People"
	var list := VBoxContainer.new()
	list.name = "AgentList"
	list.custom_minimum_size = Vector2(220, 0)
	page.add_child(list)
	var agents: Array = _doc.raw.get("agents", [])
	for index in agents.size():
		var agent: Dictionary = agents[index]
		var button := UiWidgets.button(str(agent.get("name", agent.get("id", ""))), "Agent_%d" % index)
		var picked := index
		button.pressed.connect(func() -> void: _select_agent(picked))
		list.add_child(button)
	var controls := HBoxContainer.new()
	list.add_child(controls)
	var up := UiWidgets.button(UiStrings.MOVE_UP, "AgentUp")
	up.pressed.connect(func() -> void: _move_agent(-1))
	controls.add_child(up)
	var down := UiWidgets.button(UiStrings.MOVE_DOWN, "AgentDown")
	down.pressed.connect(func() -> void: _move_agent(1))
	controls.add_child(down)
	var add := UiWidgets.button(UiStrings.ADD_PERSON, "AddAgent")
	add.pressed.connect(_add_agent)
	list.add_child(add)
	var card := VBoxContainer.new()
	card.name = "AgentCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(UiWidgets.scrolling(card))
	_fill_card(card)
	return page


func _fill_card(card: VBoxContainer) -> void:
	for child in card.get_children():
		child.free()
	var agents: Array = _doc.raw.get("agents", [])
	if agents.is_empty() or _agent >= agents.size():
		return
	var agent: Dictionary = agents[_agent]
	card.add_child(_agent_line("Имя", "NameEdit", "name", str(agent.get("name", "")), "Ирина Морозова"))
	card.add_child(_agent_line("Роль в деле", "RoleEdit", "role", str(agent.get("role", "")), "Жена жертвы"))
	card.add_child(_gender(agent))
	card.add_child(_voice(agent))
	card.add_child(_agent_line("Интонация голоса", "VoiceStyleEdit", "voice_style", str(agent.get("voice_style", "")), "сдержанно, неторопливо"))
	_help_button(card, "VoiceStyleHelp", "Как читать вслух. Без тембра, возраста, пола, акцента. Работает при включённой интонации и озвучке Gemini/Chirp")
	card.add_child(_agent_line("Первая фраза", "GreetingEdit", "greeting", str(agent.get("greeting", "")), "Следователь. Наконец-то."))
	_help_button(card, "GreetingHelp", "Звучит, когда игрок впервые открывает диалог; персонаж помнит, что сказал её")
	card.add_child(UiWidgets.label("Междометия ожидания"))
	_help_button(card, "FillerHelp", "Короткие звуки, пока персонаж ещё не ответил. Если пусто — стандартные «Хм…», «Ну…», «Секунду…»")
	var fillers: Array = agent.get("filler_lines", [])
	for slot in 3:
		var current := str(fillers[slot]) if slot < fillers.size() else ""
		var samples := ["Хм…", "Ну что ж…", "Минутку."]
		card.add_child(_filler_line(slot, current, samples[slot]))
	card.add_child(_agent_area("Характер и манера речи", "PersonalityEdit", "personality", str(agent.get("personality", "")), "Холодная, говорит тихо, под давлением становится ядовитее"))
	_help_button(card, "PersonalityHelp", "ИИ получает это каждый ход — тайн не писать")
	card.add_child(_agent_area("Предыстория", "PromptBackgroundEdit", "prompt_background", str(agent.get("prompt_background", "")), "Жена Виктора, в браке семь лет."))
	_help_button(card, "BackgroundHelp", "Персонаж может сказать это вслух — тайны пишите в показания-ложь")
	card.add_child(_emotion(agent))
	card.add_child(_profanity(agent))
	card.add_child(_agent_area("Чего хочет", "WantsEdit", "wants", str(agent.get("wants", "")), "Закончить разговор быстро и на своих условиях"))
	card.add_child(_agent_area("Чего боится", "FearsEdit", "fears", str(agent.get("fears", "")), "Что начнут копаться в её личных делах и деньгах"))
	card.add_child(_agent_area("Своя версия", "OwnVersionEdit", "own_version", str(agent.get("own_version", "")), "Убийство связано с делами клуба"))
	card.add_child(_agent_area("Мелочи из жизни", "LifeEdit", "life_details", str(agent.get("life_details", "")), "Выросла в Петербурге, говорит «парадная»."))
	_living_samples(card, agent)
	_relationships(card, agent)
	EditorSheet.add_facts(card, self)


func _line(label: String, node_name: String, value: String, sample: String, key: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label(label))
	var edit := LineEdit.new()
	edit.name = node_name
	edit.text = value
	edit.placeholder_text = sample
	edit.custom_minimum_size = Vector2(0, 48)
	_watch(edit, func(text: String) -> void: _doc.set_field(key, text))
	box.add_child(edit)
	return box


func _area(label: String, node_name: String, value: String, sample: String, key: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label(label))
	var edit := TextEdit.new()
	edit.name = node_name
	edit.text = value
	edit.placeholder_text = sample
	edit.custom_minimum_size = Vector2(0, 96)
	edit.focus_entered.connect(func() -> void: _begin())
	edit.focus_exited.connect(func() -> void:
		if key == "editor":
			_doc.set_editor_note(edit.text)
		else:
			_doc.set_field(key, edit.text)
		_end()
	)
	edit.focus_entered.connect(func() -> void: _keep_visible(edit))
	box.add_child(edit)
	return box


func _agent_line(label: String, node_name: String, key: String, value: String, sample: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label(label))
	var edit := LineEdit.new()
	edit.name = node_name
	edit.text = value
	edit.placeholder_text = sample
	edit.custom_minimum_size = Vector2(0, 48)
	var field := key
	_watch(edit, func(text: String) -> void: _doc.set_agent_field(_agent, field, text))
	box.add_child(edit)
	return box


func _agent_area(label: String, node_name: String, key: String, value: String, sample: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label(label))
	var edit := TextEdit.new()
	edit.name = node_name
	edit.text = value
	edit.placeholder_text = sample
	edit.custom_minimum_size = Vector2(0, 80)
	var field := key
	edit.focus_entered.connect(func() -> void: _begin())
	edit.focus_exited.connect(func() -> void:
		_doc.set_agent_field(_agent, field, edit.text)
		_end()
	)
	edit.focus_entered.connect(func() -> void: _keep_visible(edit))
	box.add_child(edit)
	return box


func _filler_line(slot: int, value: String, sample: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = "Filler%d" % (slot + 1)
	edit.text = value
	edit.placeholder_text = sample
	edit.custom_minimum_size = Vector2(0, 48)
	var index := slot
	_watch(edit, func(_text: String) -> void: _store_fillers())
	edit.focus_entered.connect(func() -> void: _keep_visible(edit))
	return edit


func _store_fillers() -> void:
	var lines: Array = []
	for slot in 3:
		var edit := find_child("Filler%d" % (slot + 1), true, false) as LineEdit
		if edit != null:
			lines.append(edit.text)
	_doc.set_agent_field(_agent, "filler_lines", lines)


func _gender(agent: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label("Пол"))
	_help_button(box, "GenderHelp", "Только для подбора голоса, на текст ИИ не влияет")
	var choice := OptionButton.new()
	choice.name = "GenderChoice"
	choice.add_item("Не указан")
	choice.add_item("Мужской")
	choice.add_item("Женский")
	var gender := str(agent.get("gender", ""))
	choice.select(1 if gender == "male" else 2 if gender == "female" else 0)
	choice.item_selected.connect(func(index: int) -> void:
		var value := ""
		if index == 1:
			value = "male"
		elif index == 2:
			value = "female"
		_doc.set_agent_field(_agent, "gender", value)
		_schedule()
	)
	box.add_child(choice)
	return box


func _voice(agent: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label("Голос"))
	var choice := OptionButton.new()
	choice.name = "VoiceChoice"
	choice.add_item("")
	var gender := str(agent.get("gender", ""))
	var names: PackedStringArray = PackedStringArray()
	for voice in ChirpVoices.VOICES:
		if gender != "" and str(voice.get("gender", "")) != gender:
			continue
		var voice_name := str(voice.get("name", ""))
		names.append(voice_name)
		choice.add_item(voice_name)
	var current := str(agent.get("tts_voice", ""))
	var selected := names.find(current)
	choice.select(selected + 1 if selected >= 0 else 0)
	choice.item_selected.connect(func(index: int) -> void:
		var value := ""
		if index > 0:
			value = names[index - 1]
		_doc.set_agent_field(_agent, "tts_voice", value)
		_schedule()
	)
	box.add_child(choice)
	return box


func _emotion(agent: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label("Начальная эмоция"))
	var choice := OptionButton.new()
	choice.name = "EmotionChoice"
	var current := str(agent.get("starting_emotion", "neutral"))
	var selected := 0
	for index in Balance.EMOTIONS.size():
		var code := Balance.EMOTIONS[index]
		choice.add_item(UiStrings.emotion_word(code))
		if code == current:
			selected = index
	choice.select(selected)
	choice.item_selected.connect(func(index: int) -> void:
		_doc.set_agent_field(_agent, "starting_emotion", Balance.EMOTIONS[index])
		_schedule()
	)
	box.add_child(choice)
	return box


func _profanity(agent: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label(GameLanguage.text("profanity_field")))
	_help_button(box, "ProfanityHelp", GameLanguage.text("profanity_help"))
	var choice := OptionButton.new()
	choice.name = "ProfanityChoice"
	choice.add_item(GameLanguage.text("profanity_choice_never"))
	choice.add_item(GameLanguage.text("profanity_choice_sometimes"))
	choice.add_item(GameLanguage.text("profanity_choice_often"))
	var value := str(agent.get("profanity", "never"))
	choice.select(1 if value == "sometimes" else 2 if value == "often" else 0)
	choice.item_selected.connect(func(index: int) -> void:
		var code := "never"
		if index == 1:
			code = "sometimes"
		elif index == 2:
			code = "often"
		_doc.set_agent_field(_agent, "profanity", code)
		_schedule()
	)
	box.add_child(choice)
	return box


func _killer() -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiWidgets.label("Убийца"))
	var choice := OptionButton.new()
	choice.name = "KillerChoice"
	choice.add_item("—")
	var ids: PackedStringArray = PackedStringArray()
	var agents: Array = _doc.raw.get("agents", [])
	for agent in agents:
		if agent is Dictionary:
			var agent_id := str((agent as Dictionary).get("id", ""))
			ids.append(agent_id)
			choice.add_item(str((agent as Dictionary).get("name", agent_id)))
	var current := str(_doc.raw.get("killer_id", ""))
	var found := ids.find(current)
	choice.select(found + 1 if found >= 0 else 0)
	choice.item_selected.connect(func(index: int) -> void:
		_doc.set_field("killer_id", "" if index == 0 else ids[index - 1])
		_schedule()
	)
	box.add_child(choice)
	return box


func _living_samples(card: VBoxContainer, agent: Dictionary) -> void:
	card.add_child(UiWidgets.label("Примеры фраз"))
	var samples: Array = agent.get("sample_lines", [])
	for slot in 3:
		var edit := LineEdit.new()
		edit.name = "Sample%d" % (slot + 1)
		edit.placeholder_text = "Задавайте вопросы. Я не располагаю вечностью."
		edit.text = str(samples[slot]) if slot < samples.size() else ""
		edit.custom_minimum_size = Vector2(0, 48)
		_watch(edit, func(_text: String) -> void: _store_samples())
		card.add_child(edit)


func _store_samples() -> void:
	var lines: Array = []
	for slot in 3:
		var edit := find_child("Sample%d" % (slot + 1), true, false) as LineEdit
		if edit != null and edit.text.strip_edges() != "":
			lines.append(edit.text.strip_edges())
	_doc.set_agent_field(_agent, "sample_lines", lines)


func _relationships(card: VBoxContainer, agent: Dictionary) -> void:
	card.add_child(UiWidgets.label("Отношения"))
	_help_button(card, "RelationsHelp", "ИИ получает это каждый ход — тайн не писать")
	var links: Dictionary = agent.get("relationships", {})
	var agents: Array = _doc.raw.get("agents", [])
	for other in agents:
		if other is not Dictionary:
			continue
		var other_id := str((other as Dictionary).get("id", ""))
		if other_id == str(agent.get("id", "")):
			continue
		var edit := LineEdit.new()
		edit.name = "Rel_%s" % other_id
		edit.placeholder_text = "держит его за слабого дельца, не верит ни одному его слову"
		edit.text = str(links.get(other_id, ""))
		edit.custom_minimum_size = Vector2(0, 48)
		var who := other_id
		_watch(edit, func(text: String) -> void:
			var fresh: Dictionary = {}
			var current: Array = _doc.raw.get("agents", [])
			if _agent < current.size() and current[_agent] is Dictionary:
				fresh = (current[_agent] as Dictionary).get("relationships", {})
			fresh[who] = text
			_doc.set_agent_field(_agent, "relationships", fresh)
		)
		card.add_child(edit)


func _watch(edit: LineEdit, apply: Callable) -> void:
	edit.focus_entered.connect(func() -> void:
		_begin()
		_keep_visible(edit)
	)
	edit.focus_exited.connect(func() -> void:
		apply.call(edit.text)
		_end()
	)


func _begin() -> void:
	if _undo_open or _read_only:
		return
	_undo_open = true


func _end() -> void:
	_undo_open = false
	_schedule()
	_show_errors()


func _schedule() -> void:
	if _read_only or _timer == null:
		return
	_timer.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		flush_autosave()


func _help_button(parent: Node, node_name: String, text: String) -> void:
	var button := UiWidgets.button("?", node_name)
	button.custom_minimum_size = Vector2(48, 48)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void: _show_help(text))
	var row := HBoxContainer.new()
	if parent.get_child_count() > 0 and parent.get_child(parent.get_child_count() - 1) is Label:
		var label := parent.get_child(parent.get_child_count() - 1)
		parent.remove_child(label)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(button)
		parent.add_child(row)
		return
	var last := parent.get_child(parent.get_child_count() - 1) if parent.get_child_count() > 0 else null
	if last is VBoxContainer and last.get_child_count() > 0 and last.get_child(0) is Label:
		var title := last.get_child(0)
		last.remove_child(title)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		row.add_child(button)
		last.add_child(row)
		last.move_child(row, 0)
		return
	row.add_child(button)
	parent.add_child(row)


func _show_help(text: String) -> void:
	var label := _help.find_child("HelpText", true, false) as Label
	if label != null:
		label.text = text
	_help.visible = true


func _overlay(node_name: String) -> Control:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	UiWidgets.fill(center)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.name = "%sBox" % node_name
	center.add_child(box)
	return panel


func _popup(node_name: String) -> Control:
	var panel := _overlay(node_name)
	var box := panel.get_child(0).get_child(0)
	box.add_child(UiWidgets.label("", "HelpText"))
	var close := UiWidgets.button(UiStrings.DISMISS, "CloseHelp")
	close.pressed.connect(func() -> void: panel.visible = false)
	box.add_child(close)
	return panel


func _fail_popup() -> Control:
	var panel := _overlay("SaveFailed")
	var box := panel.get_child(0).get_child(0)
	var label := UiWidgets.label(UiStrings.SAVE_FAILED, "SaveFailedText")
	box.add_child(label)
	var retry := UiWidgets.button(UiStrings.RETRY, "RetrySave")
	retry.pressed.connect(_retry_save)
	box.add_child(retry)
	var leave := UiWidgets.button(UiStrings.EXIT_UNSAVED, "ExitWithoutSaving")
	leave.pressed.connect(func() -> void:
		panel.visible = false
		leave_pressed.emit()
	)
	box.add_child(leave)
	return panel


func _delete_popup() -> Control:
	var panel := _overlay("DeleteConfirm")
	var box := panel.get_child(0).get_child(0)
	var label := UiWidgets.label("", "DeleteText")
	label.custom_minimum_size = Vector2(420, 0)
	box.add_child(label)
	box.custom_minimum_size = Vector2(420, 0)
	var row := HBoxContainer.new()
	box.add_child(row)
	var yes := UiWidgets.button("Удалить вместе со ссылками", "ConfirmDelete")
	yes.pressed.connect(func() -> void:
		panel.visible = false
		_doc.remove_item(_remove_kind, _remove_id)
		_build()
		_schedule()
	)
	row.add_child(yes)
	var no := UiWidgets.button(UiStrings.CANCEL, "CancelDelete")
	no.pressed.connect(func() -> void: panel.visible = false)
	row.add_child(no)
	return panel


func _warn_popup() -> Control:
	var panel := _overlay("PublishWarn")
	var box := panel.get_child(0).get_child(0)
	var label := UiWidgets.label(UiStrings.SAVE_RESET, "HelpText")
	label.custom_minimum_size = Vector2(420, 0)
	box.add_child(label)
	box.custom_minimum_size = Vector2(420, 0)
	var row := HBoxContainer.new()
	box.add_child(row)
	var yes := UiWidgets.button(UiStrings.PUBLISH, "ConfirmPublish")
	yes.pressed.connect(func() -> void:
		panel.visible = false
		_publish(true)
	)
	row.add_child(yes)
	var no := UiWidgets.button(UiStrings.CANCEL, "CancelPublish")
	no.pressed.connect(func() -> void: panel.visible = false)
	row.add_child(no)
	return panel


func _choices(kind: String) -> Control:
	var method := kind == "method"
	var box := VBoxContainer.new()
	box.name = "MethodOptions" if method else "MotiveOptions"
	box.add_child(UiWidgets.label("Варианты способа" if method else "Варианты мотива"))
	var key := "method_options" if method else "motive_options"
	var true_key := "true_method_id" if method else "true_motive_id"
	var sample := "Кухонный нож из клуба" if method else "Деньги / долг и унижение"
	var options: Array = _doc.raw.get(key, [])
	var marked := str(_doc.raw.get(true_key, ""))
	for index in options.size():
		if options[index] is not Dictionary:
			continue
		var option: Dictionary = options[index]
		var row := HBoxContainer.new()
		box.add_child(row)
		var edit := LineEdit.new()
		edit.name = "%sText%d" % [kind, index]
		edit.text = str(option.get("text", ""))
		edit.placeholder_text = sample
		edit.custom_minimum_size = Vector2(0, 48)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var slot := index
		_watch(edit, func(text: String) -> void: _set_option_text(kind, slot, text))
		row.add_child(edit)
		var mark := CheckBox.new()
		mark.name = "%sTrue%d" % [kind, index]
		mark.text = "верный"
		mark.button_pressed = str(option.get("id", "")) == marked
		mark.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_mark_option(kind, slot)
		)
		row.add_child(mark)
	var add := UiWidgets.button("Добавить", "Add%s" % ("Method" if method else "Motive"))
	add.pressed.connect(func() -> void: _add_option(kind))
	box.add_child(add)
	return box


func _set_option_text(kind: String, index: int, text: String) -> void:
	var key := "method_options" if kind == "method" else "motive_options"
	var options: Array = _doc.raw.get(key, [])
	if index < 0 or index >= options.size() or options[index] is not Dictionary:
		return
	_doc._snapshot()
	(options[index] as Dictionary)["text"] = text
	_doc.changed.emit()
	_schedule()


func _mark_option(kind: String, index: int) -> void:
	var key := "method_options" if kind == "method" else "motive_options"
	var true_key := "true_method_id" if kind == "method" else "true_motive_id"
	var options: Array = _doc.raw.get(key, [])
	if index < 0 or index >= options.size() or options[index] is not Dictionary:
		return
	_doc.set_field(true_key, str((options[index] as Dictionary).get("id", "")))
	_build()


func _add_option(kind: String) -> void:
	var key := "method_options" if kind == "method" else "motive_options"
	var prefix := "method" if kind == "method" else "motive"
	var options: Array = _doc.raw.get(key, [])
	var ids := {}
	for option in options:
		if option is Dictionary:
			ids[str((option as Dictionary).get("id", ""))] = true
	var number := options.size() + 1
	var option_id := "%s_%d" % [prefix, number]
	while ids.has(option_id):
		number += 1
		option_id = "%s_%d" % [prefix, number]
	_doc._snapshot()
	options.append({"id": option_id, "text": ""})
	_doc.raw[key] = options
	_doc.changed.emit()
	_build()
	_schedule()


func _select_agent(index: int) -> void:
	_apply_open_fields()
	_agent = index
	var card := find_child("AgentCard", true, false) as VBoxContainer
	if card != null:
		_fill_card(card)
		_lock_if_needed()


func _move_agent(delta: int) -> void:
	if _read_only:
		return
	_doc.move_agent(_agent, delta)
	_agent = clampi(_agent + delta, 0, _doc.raw.get("agents", []).size() - 1)
	_build()
	_schedule()


func _add_agent() -> void:
	if _read_only:
		return
	_doc.add_agent()
	_agent = _doc.raw.get("agents", []).size() - 1
	_build()
	_schedule()


func _undo() -> void:
	_doc.undo()
	_agent = mini(_agent, maxi(0, _doc.raw.get("agents", []).size() - 1))
	_build()


func _publish(force: bool = false) -> void:
	if _read_only:
		return
	_apply_open_fields()
	var raw := _doc.export_raw()
	var blocked := false
	for issue in EditorChecks.collect(_doc.raw):
		if str(issue.get("level", "")) == "error":
			blocked = true
	if blocked or not CaseValidator.validate(raw).is_empty() or not CaseValidator.publish_errors(raw).is_empty():
		_show_errors()
		return
	var result := CaseLibrary.publish(case_id, raw, force)
	if result.get("warn", false):
		_warn.visible = true
		return
	var notice := str(result.get("notice", ""))
	if notice != "":
		_show_help(notice)


func _copy() -> void:
	var fresh := CaseLibrary.copy_case(case_id)
	if fresh != "":
		copied.emit(fresh)


func _try_leave() -> void:
	if consume_back():
		return
	leave_pressed.emit()


func _retry_save() -> void:
	if flush_autosave():
		_failed.visible = false
		leave_pressed.emit()


func _apply_open_fields() -> void:
	if _doc == null:
		return
	var title := find_child("TitleEdit", true, false) as LineEdit
	if title != null:
		_doc.raw["title"] = title.text
	var name := find_child("NameEdit", true, false) as LineEdit
	if name != null:
		_doc.set_agent_field(_agent, "name", name.text)
		_undo_open = true
		_store_fillers()
		_undo_open = false


func _show_errors() -> void:
	var box := find_child("EditorIssues", true, false) as VBoxContainer
	if box == null or _doc == null:
		return
	for child in box.get_children():
		child.free()
	for issue in EditorChecks.collect(_doc.raw):
		var row := HBoxContainer.new()
		var label := UiWidgets.label(str(issue.get("text", "")))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var jump := UiWidgets.button("Перейти", "GotoIssue")
		var payload: Dictionary = issue
		jump.pressed.connect(func() -> void: goto_issue(payload))
		row.add_child(jump)
		box.add_child(row)


func _lock_if_needed() -> void:
	if not _read_only:
		return
	for child in find_children("*", "LineEdit", true, false):
		(child as LineEdit).editable = false
	for child in find_children("*", "TextEdit", true, false):
		(child as TextEdit).editable = false
	for child in find_children("*", "OptionButton", true, false):
		(child as OptionButton).disabled = true
	for child in find_children("*", "CheckBox", true, false):
		(child as CheckBox).disabled = true
	for button in find_children("*", "Button", true, false):
		var node_name := str(button.name)
		if node_name.ends_with("Help") or node_name == "BackButton" or node_name == "CopyButton" or node_name == "CloseHelp" or node_name == "GotoIssue":
			continue
		if node_name == "CancelPublish" or node_name == "CancelDelete" or node_name == "ConfirmNo":
			continue
		(button as Button).disabled = true


func _keep_visible(control: Control) -> void:
	var scroll := _scroll
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			scroll = parent
			break
		parent = parent.get_parent()
	if scroll == null:
		return
	var keyboard := keyboard_inset
	if keyboard < 0:
		keyboard = DisplayServer.virtual_keyboard_get_height()
	var top := control.position.y
	if keyboard > 0:
		top = maxi(0.0, control.position.y + control.size.y + float(keyboard) - scroll.size.y)
	scroll.scroll_vertical = int(top)
