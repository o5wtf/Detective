class_name CasePicker
extends Control
## Опубликованные дела вместо одного «Новое дело».

signal play_pressed(case_id: String, mode: String)
signal menu_pressed
signal damaged_pressed(case_id: String)


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var margin := MarginContainer.new()
	UiWidgets.fill(margin)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	column.add_child(UiWidgets.label(UiStrings.CASE_PICK, "PickTitle"))
	var back := UiWidgets.button(UiStrings.BACK, "BackButton")
	back.pressed.connect(func() -> void: menu_pressed.emit())
	column.add_child(back)
	var box := VBoxContainer.new()
	box.name = "CaseList"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UiWidgets.scrolling(box))
	var restore := UiWidgets.button(UiStrings.RESTORE_EXAMPLE, "RestoreExampleButton")
	restore.pressed.connect(_restore)
	column.add_child(restore)
	refresh()


func refresh() -> void:
	var box := find_child("CaseList", true, false) as VBoxContainer
	if box == null:
		return
	for child in box.get_children():
		child.free()
	var ids := CaseLibrary.list_ids()
	var published: PackedStringArray = PackedStringArray()
	for case_id in ids:
		if FileAccess.file_exists(CaseLibrary.published_path(case_id)):
			published.append(case_id)
	if published.is_empty():
		box.add_child(UiWidgets.label(UiStrings.EMPTY_CASES, "EmptyCases"))
		return
	for case_id in published:
		box.add_child(_card(case_id))


func _card(case_id: String) -> Control:
	var raw := CaseLibrary._read_dict(CaseLibrary.published_path(case_id))
	var panel := VBoxContainer.new()
	panel.name = "Case_%s" % case_id
	var loaded := CaseLoader.parse(raw)
	if not loaded.ok:
		panel.add_child(UiWidgets.label("%s — %s" % [case_id, UiStrings.DAMAGED_CASE]))
		var open := UiWidgets.button(UiStrings.DAMAGED_CASE, "Damaged_%s" % case_id)
		open.pressed.connect(func() -> void: damaged_pressed.emit(case_id))
		panel.add_child(open)
		return panel
	var data := loaded.case_data
	panel.add_child(UiWidgets.label(data.title))
	var briefing := data.briefing.strip_edges()
	if briefing.length() > 120:
		briefing = briefing.substr(0, 120)
	panel.add_child(UiWidgets.label(briefing))
	var save := SaveState.exists(case_id)
	panel.add_child(UiWidgets.label("Персонажей: %d%s" % [data.agents.size(), " · есть сохранение" if save else ""]))
	var start := UiWidgets.button(UiStrings.NEW_CASE, "Start_%s" % case_id)
	start.pressed.connect(func() -> void: play_pressed.emit(case_id, "start"))
	panel.add_child(start)
	if save:
		var cont := UiWidgets.button(UiStrings.CONTINUE, "Continue_%s" % case_id)
		cont.pressed.connect(func() -> void: play_pressed.emit(case_id, "continue"))
		panel.add_child(cont)
		var again := UiWidgets.button(UiStrings.RESTART, "Restart_%s" % case_id)
		again.pressed.connect(func() -> void: play_pressed.emit(case_id, "restart"))
		panel.add_child(again)
	return panel


func _restore() -> void:
	CaseLibrary.restore_example()
	refresh()
