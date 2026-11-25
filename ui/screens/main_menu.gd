extends Control

signal new_case_pressed
signal settings_pressed
signal continue_pressed
signal restart_pressed
signal editor_pressed

var _continue: Button
var _restart: Button
var _problem: Label


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var center := CenterContainer.new()
	UiWidgets.fill(center)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)
	var title := UiWidgets.label("Детектив")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	box.add_child(_spacer(24))
	var new_case := UiWidgets.button(UiStrings.NEW_CASE, "NewCaseButton")
	new_case.pressed.connect(func() -> void: new_case_pressed.emit())
	box.add_child(new_case)
	_continue = UiWidgets.button(UiStrings.CONTINUE, "ContinueButton")
	_continue.visible = false
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.pressed.connect(func() -> void: continue_pressed.emit())
	box.add_child(_continue)
	_restart = UiWidgets.button(UiStrings.RESTART, "RestartButton")
	_restart.visible = false
	_restart.pressed.connect(func() -> void: restart_pressed.emit())
	box.add_child(_restart)
	_problem = UiWidgets.label("", "SaveProblemLabel")
	_problem.visible = false
	box.add_child(_problem)
	var editor := UiWidgets.button(UiStrings.EDITOR, "EditorButton")
	editor.pressed.connect(func() -> void: editor_pressed.emit())
	box.add_child(editor)
	var settings := UiWidgets.button(UiStrings.SETTINGS, "SettingsButton")
	settings.pressed.connect(func() -> void: settings_pressed.emit())
	box.add_child(settings)
	for child in box.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2(280, 48)


func refresh_for(case_path: String) -> void:
	var case_id := SaveState.case_id_from_path(case_path)
	var present := SaveState.exists(case_id)
	if _continue != null:
		_continue.visible = present
	if _restart != null:
		_restart.visible = present
	if _problem != null and not present:
		_problem.visible = false
	var editor := find_child("EditorButton", true, false) as Button
	if editor != null:
		editor.visible = SettingsStore.load_current().developer


func show_save_problem(reason: String) -> void:
	if _problem == null:
		return
	match reason:
		"hash":
			_problem.text = UiStrings.SAVE_HASH
		"version":
			_problem.text = UiStrings.SAVE_VERSION
		_:
			_problem.text = UiStrings.SAVE_CORRUPT
	_problem.visible = true
	if _restart != null:
		_restart.visible = true


func _spacer(height: float) -> Control:
	var control := Control.new()
	control.custom_minimum_size = Vector2(0, height)
	return control
