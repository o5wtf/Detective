class_name EditorHome
extends Control
## Список дел редактора.

signal open_pressed(case_id: String)
signal menu_pressed


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
	column.add_child(UiWidgets.label(UiStrings.MY_CASES, "EditorHomeTitle"))
	var back := UiWidgets.button(UiStrings.BACK, "BackButton")
	back.pressed.connect(func() -> void: menu_pressed.emit())
	column.add_child(back)
	var create := UiWidgets.button(UiStrings.CREATE_CASE, "CreateCaseButton")
	create.pressed.connect(_create)
	column.add_child(create)
	var box := VBoxContainer.new()
	box.name = "EditorList"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UiWidgets.scrolling(box))
	var restore := UiWidgets.button(UiStrings.RESTORE_EXAMPLE, "RestoreExampleButton")
	restore.pressed.connect(_restore)
	column.add_child(restore)
	refresh()


func refresh() -> void:
	var box := find_child("EditorList", true, false) as VBoxContainer
	if box == null:
		return
	for child in box.get_children():
		child.free()
	for case_id in CaseLibrary.list_ids():
		box.add_child(_row(case_id))


func _row(case_id: String) -> Control:
	var row := VBoxContainer.new()
	row.name = "Row_%s" % case_id
	var raw := CaseLibrary.read_source(case_id)
	var title := str(raw.get("title", case_id))
	row.add_child(UiWidgets.label("%s — %s" % [title, _badge(CaseLibrary.status(case_id))]))
	var buttons := HBoxContainer.new()
	row.add_child(buttons)
	var open := UiWidgets.button(UiStrings.OPEN_CASE, "Open_%s" % case_id)
	open.pressed.connect(func() -> void: open_pressed.emit(case_id))
	buttons.add_child(open)
	var copy := UiWidgets.button(UiStrings.COPY_CASE, "Copy_%s" % case_id)
	copy.pressed.connect(func() -> void: _copy(case_id))
	buttons.add_child(copy)
	if CaseLibrary.is_example(case_id):
		var restore := UiWidgets.button(UiStrings.RESTORE_EXAMPLE, "Restore_%s" % case_id)
		restore.pressed.connect(_restore)
		buttons.add_child(restore)
	else:
		var delete := UiWidgets.button(UiStrings.DELETE_CASE, "Delete_%s" % case_id)
		delete.pressed.connect(func() -> void: _delete(case_id))
		buttons.add_child(delete)
	return row


func _badge(status: String) -> String:
	match status:
		"example":
			return UiStrings.EXAMPLE_BADGE
		"draft":
			return UiStrings.DRAFT_BADGE
		"dirty":
			return UiStrings.PUBLISHED_DIRTY
		_:
			return UiStrings.PUBLISHED_BADGE


func _create() -> void:
	var raw := CaseLibrary.new_case()
	CaseLibrary.write_draft(str(raw.get("id", "")), raw)
	refresh()
	open_pressed.emit(str(raw.get("id", "")))


func _copy(case_id: String) -> void:
	var fresh := CaseLibrary.copy_case(case_id)
	refresh()
	if fresh != "":
		open_pressed.emit(fresh)


func _delete(case_id: String) -> void:
	CaseLibrary.delete_case(case_id)
	refresh()


func _restore() -> void:
	CaseLibrary.restore_example()
	refresh()
