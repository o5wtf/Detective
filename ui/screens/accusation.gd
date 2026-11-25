extends Control

signal menu_pressed
signal back_pressed

var _killer: OptionButton
var _motive: OptionButton
var _method: OptionButton
var _result: Label
var _victory: PanelContainer
var _timeline: Label


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var margin := MarginContainer.new()
	UiWidgets.fill(margin)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "AccusationScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(UiWidgets.label(UiStrings.ACCUSE, "TitleLabel"))
	column.add_child(UiWidgets.label("Кто"))
	_killer = _options("KillerOption")
	column.add_child(_killer)
	column.add_child(UiWidgets.label("Мотив"))
	_motive = _options("MotiveOption")
	column.add_child(_motive)
	column.add_child(UiWidgets.label("Способ"))
	_method = _options("MethodOption")
	column.add_child(_method)
	var back := UiWidgets.button(UiStrings.BACK, "BackButton")
	back.pressed.connect(func() -> void: back_pressed.emit())
	column.add_child(back)
	var accuse := UiWidgets.button(UiStrings.ACCUSE, "AccuseButton")
	accuse.pressed.connect(_accuse)
	column.add_child(accuse)
	_result = UiWidgets.label("", "ResultLabel")
	column.add_child(_result)
	_victory = PanelContainer.new()
	_victory.name = "VictoryPanel"
	_victory.visible = false
	column.add_child(_victory)
	var victory_box := VBoxContainer.new()
	_victory.add_child(victory_box)
	victory_box.add_child(UiWidgets.label(UiStrings.VICTORY))
	victory_box.add_child(UiWidgets.label(UiStrings.HOW_IT_ENDED))
	_timeline = UiWidgets.label("", "TimelineLabel")
	victory_box.add_child(_timeline)
	var menu := UiWidgets.button(UiStrings.TO_MENU, "VictoryMenuButton")
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	victory_box.add_child(menu)
	refresh()


func refresh() -> void:
	if _killer == null or Game.case_data == null or Game.state == null:
		return
	_fill_agents(_killer)
	_fill_options(_motive, Game.case_data.motive_options)
	_fill_options(_method, Game.case_data.method_options)
	_apply_locks()
	if bool(Game.state.accusation.get("killer_ok", false)) and bool(Game.state.accusation.get("motive_ok", false)) and bool(Game.state.accusation.get("method_ok", false)):
		_show_victory()


func _options(node_name: String) -> OptionButton:
	var control := OptionButton.new()
	control.name = node_name
	control.custom_minimum_size = Vector2(0, 48)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control


func _fill_agents(control: OptionButton) -> void:
	control.clear()
	control.add_item(UiStrings.CHOOSE, -1)
	var index := 1
	for agent in Game.case_data.agents:
		var prefix := "✓ " if bool(Game.state.accusation.get("killer_ok", false)) and agent.id == Game.case_data.killer_id else ""
		control.add_item("%s%s" % [prefix, agent.name], index)
		control.set_item_metadata(index, agent.id)
		index += 1
	_select_known(control, Game.case_data.killer_id if bool(Game.state.accusation.get("killer_ok", false)) else "")


func _fill_options(control: OptionButton, options: Array) -> void:
	control.clear()
	control.add_item(UiStrings.CHOOSE, -1)
	var index := 1
	for option in options:
		control.add_item(option.text, index)
		control.set_item_metadata(index, option.id)
		index += 1


func _select_known(control: OptionButton, id_value: String) -> void:
	if id_value == "":
		control.select(0)
		return
	for index in control.item_count:
		if str(control.get_item_metadata(index)) == id_value:
			control.select(index)
			return


func _apply_locks() -> void:
	var killer_ok := bool(Game.state.accusation.get("killer_ok", false))
	var motive_ok := bool(Game.state.accusation.get("motive_ok", false))
	var method_ok := bool(Game.state.accusation.get("method_ok", false))
	_killer.disabled = killer_ok
	_motive.disabled = motive_ok
	_method.disabled = method_ok
	if motive_ok:
		_select_known(_motive, Game.case_data.true_motive_id)
	if method_ok:
		_select_known(_method, Game.case_data.true_method_id)


func _accuse() -> void:
	var killer_id := _meta(_killer)
	var motive_id := _meta(_motive)
	var method_id := _meta(_method)
	if killer_id == "" or motive_id == "" or method_id == "":
		_result.text = UiStrings.PICK_ALL
		return
	var report := Game.accuse(killer_id, motive_id, method_id)
	refresh()
	if report.get("solved", false):
		_result.text = ""
		_show_victory()
		return
	if not report.get("killer_match", false) and not report.get("killer_ok", false):
		_result.text = UiStrings.WRONG_KILLER
		return
	var parts: PackedStringArray = PackedStringArray()
	if report.get("motive_evaluated", false) and not report.get("motive_match", false):
		parts.append(UiStrings.WRONG_MOTIVE)
	if report.get("method_evaluated", false) and not report.get("method_match", false):
		parts.append(UiStrings.WRONG_METHOD)
	_result.text = ". ".join(parts)


func _show_victory() -> void:
	_victory.visible = true
	_timeline.text = Game.case_data.truth_timeline if Game.case_data != null else ""


func _meta(control: OptionButton) -> String:
	if control.selected <= 0:
		return ""
	return str(control.get_item_metadata(control.selected))
