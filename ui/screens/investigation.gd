extends Control

signal menu_pressed
signal accuse_pressed

var _body: HBoxContainer
var _side: TabContainer
var _drawer: Control
var _top_accuse: Button
var _bottom: HBoxContainer
var _suspects: Control
var _chat: Control
var _evidence: Control
var _notebook: Control
var _mode: String = ""
var _keyboard: int = -1
var _seen_evidence: Dictionary = {}
var _seen_contradictions: Dictionary = {}


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.name = "SafeMargin"
	UiWidgets.fill(margin)
	add_child(margin)
	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(column)
	_top_accuse = UiWidgets.button(UiStrings.ACCUSE, "TopAccuseButton")
	_top_accuse.pressed.connect(func() -> void: accuse_pressed.emit())
	column.add_child(_top_accuse)
	_body = HBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)
	_suspects = preload("res://ui/screens/suspects.tscn").instantiate()
	_suspects.custom_minimum_size = Vector2(280, 0)
	_suspects.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat = preload("res://ui/screens/interrogation.tscn").instantiate()
	_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_evidence = preload("res://ui/screens/evidence_board.tscn").instantiate()
	_notebook = preload("res://ui/screens/notebook.tscn").instantiate()
	_side = TabContainer.new()
	_side.name = "SideTabs"
	_side.custom_minimum_size = Vector2(320, 0)
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_child(_evidence)
	_side.add_child(_notebook)
	_body.add_child(_suspects)
	_body.add_child(_chat)
	_body.add_child(_side)
	_bottom = HBoxContainer.new()
	_bottom.name = "BottomBar"
	column.add_child(_bottom)
	var accuse := UiWidgets.button(UiStrings.ACCUSE, "AccuseButton")
	accuse.pressed.connect(func() -> void: accuse_pressed.emit())
	_bottom.add_child(accuse)
	var menu := UiWidgets.button(UiStrings.MENU, "MenuButton")
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	_bottom.add_child(menu)
	_drawer = PanelContainer.new()
	_drawer.name = "Drawer"
	_drawer.visible = false
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	stack.add_child(_drawer)
	var drawer_box := VBoxContainer.new()
	drawer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drawer.add_child(drawer_box)
	var close := UiWidgets.button(UiStrings.TO_CHAT, "CloseDrawerButton")
	close.pressed.connect(func() -> void: _drawer.visible = false)
	drawer_box.add_child(close)
	_suspects.agent_chosen.connect(_on_agent)
	_chat.evidence_requested.connect(func() -> void: _show_tab(_evidence))
	_chat.notebook_requested.connect(func() -> void: _show_tab(_notebook))
	_chat.suspects_requested.connect(func() -> void: _show_tab(_suspects))
	_evidence.present_requested.connect(_present_from_board)
	_notebook.confront_chosen.connect(_confront_from_notebook)
	Game.events.connect(_on_events)
	_select_initial_agent()
	call_deferred("_apply_layout")


func _process(_delta: float) -> void:
	var keyboard := _keyboard_height()
	if keyboard != _keyboard:
		_keyboard = keyboard
		_apply_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func _apply_layout() -> void:
	if _body == null:
		return
	var mode := UiLayout.mode_for_size(Vector2(DisplayServer.window_get_size()))
	var keyboard := maxi(_keyboard_height(), 0)
	_apply_safe_area(keyboard)
	var wide := mode == "wide" and keyboard < 80
	if wide:
		_drawer.visible = false
		_top_accuse.visible = false
		_bottom.visible = true
		_side.custom_minimum_size = Vector2(320, 0)
		_side.size_flags_horizontal = Control.SIZE_FILL
		_suspects.visible = true
		_side.visible = true
		_park(_suspects, _body, 0)
		_park(_side, _body, 99)
		_chat.set_back_visible(false)
	else:
		if _mode != "medium":
			_drawer.visible = false
		_top_accuse.visible = true
		_bottom.visible = false
		_side.custom_minimum_size = Vector2(0, 0)
		_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_side.visible = true
		_park(_suspects, _side, 0)
		var drawer_box := _drawer.get_child(0)
		_park(_side, drawer_box, 99)
		_chat.set_back_visible(true)
	if _side.get_tab_count() > 0:
		_retitle_side()
	_mode = "wide" if wide else "medium"


func _retitle_side() -> void:
	for index in _side.get_tab_count():
		var child := _side.get_child(index)
		if child == _suspects:
			_side.set_tab_title(index, "Подозреваемые")
		elif child == _evidence:
			_side.set_tab_title(index, UiStrings.EVIDENCE)
		elif child == _notebook:
			_side.set_tab_title(index, UiStrings.NOTEBOOK)


func _park(node: Control, parent: Node, index: int) -> void:
	if node.get_parent() != parent:
		node.reparent(parent)
	var last := parent.get_child_count() - 1
	var target := mini(index, last)
	if target < 0:
		target = 0
	if node.get_index() != target:
		parent.move_child(node, target)


func _show_tab(node: Control) -> void:
	_apply_layout()
	if node.get_parent() != _side:
		return
	var portrait := _mode != "wide"
	if portrait and _drawer.visible and _side.current_tab == node.get_index():
		_drawer.visible = false
		return
	_side.current_tab = node.get_index()
	if portrait:
		_drawer.visible = true


func _confront_from_notebook(agent_id: String, statement_id: String, evidence_id: String) -> void:
	_on_agent(agent_id)
	if _mode != "wide":
		_drawer.visible = false
	_chat.begin_confront(statement_id, evidence_id)


func _present_from_board(evidence_id: String) -> void:
	if _chat.agent_id == "":
		return
	if _mode != "wide":
		_drawer.visible = false
	await _chat._confirm_from_board(evidence_id)


func _on_agent(agent_id: String) -> void:
	_acknowledge(agent_id)
	_chat.open_agent(agent_id)
	_evidence.agent_id = agent_id
	_evidence.refresh()
	_suspects.refresh(agent_id, _news_map())
	if _mode != "wide":
		_drawer.visible = false


func _select_initial_agent() -> void:
	if Game.case_data == null or Game.case_data.agents.is_empty():
		return
	var agent_id := Game.case_data.starting_agent_id
	if agent_id == "" or not Game.case_data.agent_by_id.has(agent_id):
		agent_id = Game.case_data.agents[0].id
	_on_agent(agent_id)


func _on_events(_list: Array) -> void:
	_suspects.refresh(_chat.agent_id, _news_map())
	_evidence.refresh()
	_notebook.refresh()


func _news_map() -> Dictionary:
	var news := {}
	if Game.case_data == null:
		return news
	for agent in Game.case_data.agents:
		news[agent.id] = _has_news(agent.id)
	return news


func _has_news(agent_id: String) -> bool:
	for evidence in Game.case_data.evidence:
		if not Game.state.unlocked_evidence.has(evidence.id):
			continue
		if not evidence.related_agent_ids.has(agent_id):
			continue
		if not _seen_list(agent_id, _seen_evidence).has(evidence.id):
			return true
	for contradiction in Game.case_data.contradictions:
		if not Game.state.contradictions.has(contradiction.id):
			continue
		if not _touches(contradiction, agent_id):
			continue
		if not _seen_list(agent_id, _seen_contradictions).has(contradiction.id):
			return true
	return false


func _acknowledge(agent_id: String) -> void:
	var evidence_seen := _seen_list(agent_id, _seen_evidence)
	for evidence in Game.case_data.evidence:
		if Game.state.unlocked_evidence.has(evidence.id) and evidence.related_agent_ids.has(agent_id):
			if not evidence_seen.has(evidence.id):
				evidence_seen.append(evidence.id)
	var contradiction_seen := _seen_list(agent_id, _seen_contradictions)
	for contradiction in Game.case_data.contradictions:
		if Game.state.contradictions.has(contradiction.id) and _touches(contradiction, agent_id):
			if not contradiction_seen.has(contradiction.id):
				contradiction_seen.append(contradiction.id)


func _seen_list(agent_id: String, bag: Dictionary) -> Array:
	if not bag.has(agent_id):
		bag[agent_id] = []
	return bag[agent_id]


func _touches(contradiction: CaseData.Contradiction, agent_id: String) -> bool:
	for fact_id in [contradiction.fact_a_id, contradiction.fact_b_id]:
		if str(Game.case_data.fact_owner.get(fact_id, "")) == agent_id:
			return true
	return false


func _keyboard_height() -> int:
	if OS.get_name() != "Android":
		return 0
	return DisplayServer.virtual_keyboard_get_height()


func _apply_safe_area(keyboard: int) -> void:
	var margin := get_node_or_null("SafeMargin") as MarginContainer
	if margin == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var left := 12
	var top := 12
	var right := 12
	var bottom := 12 + keyboard
	if screen.x > 0 and screen.y > 0:
		left = maxi(left, safe.position.x)
		top = maxi(top, safe.position.y)
		right = maxi(right, screen.x - (safe.position.x + safe.size.x))
		bottom = maxi(bottom, screen.y - (safe.position.y + safe.size.y) + keyboard)
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
