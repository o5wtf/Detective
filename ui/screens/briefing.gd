extends Control

signal start_pressed


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var margin := MarginContainer.new()
	UiWidgets.fill(margin)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	var title := UiWidgets.label("", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var briefing := UiWidgets.label("", "BriefingLabel")
	briefing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(briefing)
	var start := UiWidgets.button(UiStrings.START, "StartButton")
	start.pressed.connect(func() -> void: start_pressed.emit())
	box.add_child(start)
	refresh()


func refresh() -> void:
	if Game.case_data == null:
		return
	var title := get_node_or_null("TitleLabel") as Label
	if title == null:
		title = find_child("TitleLabel", true, false) as Label
	var briefing := find_child("BriefingLabel", true, false) as Label
	if title != null:
		title.text = Game.case_data.title
	if briefing != null:
		briefing.text = Game.case_data.briefing
