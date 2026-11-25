extends Control

signal confront_chosen(agent_id: String, statement_id: String, evidence_id: String)

var _rows: VBoxContainer
var _filter: OptionButton
var _tabs: TabBar
var _tab: int = 0
var _picker: VBoxContainer
var _pending_agent: String = ""
var _pending_statement: String = ""


func _ready() -> void:
	UiWidgets.fill(self)
	var column := VBoxContainer.new()
	UiWidgets.fill(column)
	add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	_tabs = TabBar.new()
	_tabs.name = "NotebookTabs"
	_tabs.custom_minimum_size = Vector2(0, 48)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_tab(UiStrings.NOTES_TAB)
	_tabs.add_tab(UiStrings.CONTRADICTIONS_TAB)
	_tabs.add_tab(UiStrings.PRESENTATIONS_TAB)
	_tabs.tab_changed.connect(_on_tab)
	top.add_child(_tabs)
	_filter = OptionButton.new()
	_filter.name = "FilterButton"
	_filter.custom_minimum_size = Vector2(140, 48)
	_filter.item_selected.connect(func(_index: int) -> void: refresh())
	top.add_child(_filter)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UiWidgets.scrolling(_rows))
	_picker = VBoxContainer.new()
	_picker.name = "EvidencePicker"
	_picker.visible = false
	column.add_child(_picker)
	refresh()


func refresh() -> void:
	if _filter == null:
		return
	var current := _filter.get_selected_id()
	_filter.clear()
	_filter.add_item(UiStrings.ALL_AGENTS, 0)
	if Game.case_data != null:
		var index := 1
		for agent in Game.case_data.agents:
			_filter.add_item(agent.name, index)
			_filter.set_item_metadata(index, agent.id)
			index += 1
	if current >= 0 and current < _filter.item_count:
		_filter.select(current)
	else:
		_filter.select(0)
	for child in _rows.get_children():
		child.queue_free()
	_picker.visible = false
	if _tab == 0:
		_fill_notes(_agent_filter())
	elif _tab == 1:
		_fill_contradictions(_agent_filter())
	else:
		_fill_presentations(_agent_filter())


func _on_tab(index: int) -> void:
	_tab = index
	refresh()


func _agent_filter() -> String:
	if _filter.selected <= 0:
		return ""
	return str(_filter.get_item_metadata(_filter.selected))


func _fill_notes(agent_filter: String) -> void:
	if Game.notebook == null:
		_rows.add_child(_plain(UiStrings.NO_NOTES))
		return
	var any := false
	for entry in Game.notebook.entries():
		if agent_filter != "" and str(entry.get("agent_id", "")) != agent_filter:
			continue
		any = true
		_rows.add_child(_note_row(entry))
	if not any:
		_rows.add_child(_plain(UiStrings.NO_NOTES))


func _fill_contradictions(agent_filter: String) -> void:
	var rows: Array[Dictionary] = []
	if Game.notebook != null:
		rows = Game.notebook.found_contradictions(agent_filter)
	if rows.is_empty():
		_rows.add_child(_plain("—"))
		return
	for row in rows:
		_rows.add_child(_contradiction_row(row))


func _fill_presentations(agent_filter: String) -> void:
	var rows: Array[Dictionary] = []
	if Game.notebook != null:
		rows = Game.notebook.confrontations(agent_filter)
	if rows.is_empty():
		_rows.add_child(_plain("—"))
		return
	for row in rows:
		var agent_name := _agent_name(str(row.get("agent_id", "")))
		var title := _evidence_title(str(row.get("evidence_id", "")))
		var text := "%s, ход %s: «%s» — %s" % [agent_name, str(row.get("turn", 0)), title, str(row.get("player_verdict", ""))]
		var also: Variant = row.get("also_broken", [])
		if also is Array and not (also as Array).is_empty():
			text += " (%s)" % UiStrings.also_broken(_also_names(also))
		var line := _plain(text)
		line.name = "Presentation_%s_%s" % [str(row.get("statement_id", "")).replace("|", "_"), str(row.get("evidence_id", ""))]
		_rows.add_child(line)


func _note_row(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var agent_name := _agent_name(str(entry.get("agent_id", "")))
	var text := "%s, ход %s:  «%s»" % [agent_name, str(entry.get("turn", 0)), str(entry.get("text", ""))]
	if bool(entry.get("broken", false)):
		text = "%s  %s" % [text, UiStrings.EXPOSED]
		box.add_child(_plain(text))
		return box
	box.add_child(_plain(text))
	var button := UiWidgets.button(UiStrings.CONFRONT, "Confront_%s" % str(entry.get("statement_id", "")).replace("|", "_"))
	var agent_id := str(entry.get("agent_id", ""))
	var statement_id := str(entry.get("statement_id", ""))
	button.pressed.connect(func() -> void: _open_picker(agent_id, statement_id))
	box.add_child(button)
	return box


func _open_picker(agent_id: String, statement_id: String) -> void:
	_pending_agent = agent_id
	_pending_statement = statement_id
	for child in _picker.get_children():
		child.queue_free()
	_picker.visible = true
	_picker.add_child(_plain(UiStrings.CONFRONT))
	var any := false
	if Game.case_data != null and Game.state != null:
		for evidence in Game.case_data.evidence:
			if not Game.state.unlocked_evidence.has(evidence.id):
				continue
			any = true
			var button := UiWidgets.button(evidence.title, "Pick_%s" % evidence.id)
			var evidence_id := evidence.id
			button.pressed.connect(func() -> void:
				_picker.visible = false
				confront_chosen.emit(_pending_agent, _pending_statement, evidence_id)
			)
			_picker.add_child(button)
	if not any:
		_picker.add_child(_plain(UiStrings.NO_EVIDENCE))


func _agent_name(agent_id: String) -> String:
	if Game.case_data != null and Game.case_data.agent_by_id.has(agent_id):
		return (Game.case_data.agent_by_id[agent_id] as CaseData.Agent).name
	return agent_id


func _evidence_title(evidence_id: String) -> String:
	if Game.case_data != null and Game.case_data.evidence_by_id.has(evidence_id):
		return (Game.case_data.evidence_by_id[evidence_id] as CaseData.EvidenceItem).title
	return evidence_id


func _also_names(fact_ids: Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for fact_id in fact_ids:
		var fact: CaseData.Fact = null
		if Game.case_data != null:
			fact = Game.case_data.fact_by_id.get(str(fact_id)) as CaseData.Fact
		names.append(fact.lie_text if fact != null and fact.lie_text != "" else str(fact_id))
	return ", ".join(names)


func _contradiction_row(row: Dictionary) -> Label:
	var text := "✓ %s" % str(row.get("description", ""))
	var turn := int(row.get("turn", -1))
	if turn >= 0:
		text = "%s, ход %d" % [text, turn]
	var line := _plain(text)
	line.add_theme_color_override("font_color", NoirTheme.GOOD)
	return line


func _plain(text: String) -> Label:
	var line := UiWidgets.label(text)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
