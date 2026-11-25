extends Control

var _screen: Control = null
var _place := "menu"
var _exit: Control
var _scale_factor := -1.0


func _ready() -> void:
	UiWidgets.fill(self)
	if OS.get_name() == "Windows":
		DisplayServer.window_set_min_size(Vector2i(1024, 640))
	get_window().size_changed.connect(_apply_content_scale)
	_apply_content_scale()
	_apply_theme()
	_build_exit()
	show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()


func handle_back() -> void:
	if _exit != null and _exit.visible:
		_exit.visible = false
		return
	if _screen != null and _screen.has_method("consume_back") and _screen.consume_back():
		return
	match _place:
		"accusation":
			show_investigation()
		"editor":
			show_editor_home()
		"picker", "editor_home", "settings", "briefing", "damaged", "investigation":
			show_menu()
		_:
			if _exit != null:
				_exit.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F11:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()


func show_menu() -> void:
	_place = "menu"
	var screen := preload("res://ui/screens/main_menu.tscn").instantiate()
	_swap(screen)
	screen.new_case_pressed.connect(show_picker)
	screen.editor_pressed.connect(show_editor_home)
	screen.settings_pressed.connect(func() -> void: show_settings(false))
	screen.continue_pressed.connect(_on_continue)
	screen.restart_pressed.connect(_on_restart)
	CaseLibrary.ensure_example()
	screen.refresh_for(CaseLibrary.published_path(CaseLibrary.example_id()))


func show_settings(explain_key: bool) -> void:
	_place = "settings"
	var screen := preload("res://ui/screens/settings.tscn").instantiate()
	screen.explain_key = explain_key
	screen.back_pressed.connect(show_menu)
	screen.saved.connect(_apply_theme)
	_swap(screen)


func show_briefing() -> void:
	_place = "briefing"
	var screen := preload("res://ui/screens/briefing.tscn").instantiate()
	screen.start_pressed.connect(show_investigation)
	_swap(screen)


func show_investigation() -> void:
	_place = "investigation"
	var screen := preload("res://ui/screens/investigation.tscn").instantiate()
	screen.menu_pressed.connect(show_menu)
	screen.accuse_pressed.connect(show_accusation)
	_swap(screen)


func show_accusation() -> void:
	_place = "accusation"
	var screen := preload("res://ui/screens/accusation.tscn").instantiate()
	screen.menu_pressed.connect(show_menu)
	screen.back_pressed.connect(show_investigation)
	_swap(screen)


func show_picker() -> void:
	_place = "picker"
	CaseLibrary.ensure_example()
	var screen := CasePicker.new()
	screen.menu_pressed.connect(show_menu)
	screen.play_pressed.connect(_on_play)
	screen.damaged_pressed.connect(func(case_id: String) -> void:
		var loaded := CaseLoader.load_case(CaseLibrary.published_path(case_id))
		show_damaged(loaded.errors)
	)
	_swap(screen)


func show_editor_home() -> void:
	_place = "editor_home"
	CaseLibrary.ensure_example()
	var screen := EditorHome.new()
	screen.menu_pressed.connect(show_menu)
	screen.open_pressed.connect(show_editor)
	_swap(screen)


func show_editor(case_id: String) -> void:
	_place = "editor"
	var screen := CaseEditor.new()
	screen.leave_pressed.connect(show_editor_home)
	screen.copied.connect(show_editor)
	_swap(screen)
	screen.open_id(case_id)


func _on_play(case_id: String, mode: String) -> void:
	var path := CaseLibrary.published_path(case_id)
	Speaker.reset_for_case()
	if mode == "restart":
		SaveState.discard(case_id)
	if mode == "continue":
		var result := Game.continue_case(path)
		if result.get("ok", false):
			show_investigation()
			return
		if _screen != null and _screen.has_method("show_save_problem"):
			_screen.show_save_problem(str(result.get("reason", "")))
		return
	if not SettingsStore.has_playable_key():
		show_settings(true)
		return
	var loaded := Game.open_case(path)
	if not loaded.ok:
		show_damaged(loaded.errors)
		return
	show_briefing()


func _on_continue() -> void:
	Speaker.reset_for_case()
	var result := Game.continue_case(CaseLibrary.published_path(CaseLibrary.example_id()))
	if result.get("ok", false):
		show_investigation()
		return
	if _screen != null and _screen.has_method("show_save_problem"):
		_screen.show_save_problem(str(result.get("reason", "")))


func _on_restart() -> void:
	SaveState.discard(CaseLibrary.example_id())
	_on_new_case()


func show_damaged(errors: Array) -> void:
	_place = "damaged"
	var screen := preload("res://ui/screens/damaged_case.tscn").instantiate()
	screen.errors = errors
	screen.back_pressed.connect(show_menu)
	_swap(screen)


func _on_new_case() -> void:
	Speaker.reset_for_case()
	if not SettingsStore.has_playable_key():
		show_settings(true)
		return
	CaseLibrary.ensure_example()
	var loaded := Game.open_case(CaseLibrary.published_path(CaseLibrary.example_id()))
	if not loaded.ok:
		show_damaged(loaded.errors)
		return
	show_briefing()


func _apply_content_scale() -> void:
	var window := get_window()
	var factor := UiLayout.content_scale_factor_for(Vector2(window.size))
	if is_equal_approx(factor, _scale_factor):
		return
	_scale_factor = factor
	window.content_scale_factor = factor


func _apply_theme() -> void:
	theme = NoirTheme.make(SettingsStore.load_current().text_scale)


func _build_exit() -> void:
	_exit = PanelContainer.new()
	_exit.name = "ExitConfirm"
	_exit.visible = false
	_exit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_exit.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_exit)
	var center := CenterContainer.new()
	UiWidgets.fill(center)
	_exit.add_child(center)
	var box := VBoxContainer.new()
	center.add_child(box)
	box.add_child(UiWidgets.label(UiStrings.EXIT_TITLE, "ExitTitle"))
	var yes := UiWidgets.button(UiStrings.EXIT_YES, "ExitYes")
	yes.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(yes)
	var no := UiWidgets.button(UiStrings.EXIT_NO, "ExitNo")
	no.pressed.connect(func() -> void: _exit.visible = false)
	box.add_child(no)


func _swap(screen: Control) -> void:
	Speaker.stop_and_clear(false)
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = screen
	UiWidgets.fill(screen)
	add_child(screen)
