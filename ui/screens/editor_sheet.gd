class_name EditorSheet
extends RefCounted
## Показания на карточке персонажа и вкладка улик.


static func add_facts(card: VBoxContainer, editor: CaseEditor) -> void:
	card.add_child(editor._section_label("Показания"))
	editor._help_button(card, "FactsHelp", "Правда без условий открыта сразу. Ложь ломается, когда собран любой набор из «Чем можно сломать». Пока набор собран частично, ложь под сомнением и правду не выдаёт.")
	var agents: Array = editor._doc.raw.get("agents", [])
	if editor._agent < 0 or editor._agent >= agents.size() or agents[editor._agent] is not Dictionary:
		return
	var who := agents[editor._agent] as Dictionary
	var facts: Array = who.get("facts", [])
	for index in facts.size():
		if facts[index] is Dictionary:
			card.add_child(_fact(editor, index, facts[index] as Dictionary))
	if not editor._read_only:
		var add := UiWidgets.button("Добавить показание", "AddFact")
		add.pressed.connect(func() -> void:
			editor._doc.add_fact(editor._agent)
			editor.rebuild_editor()
		)
		card.add_child(add)


static func evidence_page(editor: CaseEditor) -> Control:
	var box := VBoxContainer.new()
	box.name = "EvidenceTab"
	var evidence: Array = editor._doc.raw.get("evidence", [])
	for index in evidence.size():
		if evidence[index] is Dictionary:
			box.add_child(_evidence(editor, index, evidence[index] as Dictionary))
	if not editor._read_only:
		var add := UiWidgets.button("Добавить улику", "AddEvidence")
		add.pressed.connect(func() -> void:
			editor._doc.add_evidence()
			editor.rebuild_editor()
		)
		box.add_child(add)
	var scroll := UiWidgets.scrolling(box)
	scroll.name = "EvidenceScroll"
	return scroll


static func _fact(editor: CaseEditor, index: int, fact: Dictionary) -> Control:
	var fact_id := str(fact.get("id", ""))
	var card := VBoxContainer.new()
	card.name = "Fact_%s" % fact_id
	var bar := HBoxContainer.new()
	card.add_child(bar)
	bar.add_child(UiWidgets.label("Показание"))
	if not editor._read_only:
		var up := UiWidgets.button(UiStrings.MOVE_UP, "FactUp_%s" % fact_id)
		var down := UiWidgets.button(UiStrings.MOVE_DOWN, "FactDown_%s" % fact_id)
		var remove := UiWidgets.button(UiStrings.DELETE_CASE, "FactDelete_%s" % fact_id)
		var at := index
		up.pressed.connect(func() -> void:
			editor._doc.move_fact(editor._agent, at, -1)
			editor.rebuild_editor()
		)
		down.pressed.connect(func() -> void:
			editor._doc.move_fact(editor._agent, at, 1)
			editor.rebuild_editor()
		)
		remove.pressed.connect(func() -> void: editor.ask_remove("fact", fact_id))
		bar.add_child(up)
		bar.add_child(down)
		bar.add_child(remove)
	var kind := OptionButton.new()
	kind.name = "FactKind_%s" % fact_id
	kind.add_item("Правда")
	kind.add_item("Всегда врёт")
	kind.add_item("Может соврать")
	var lie := str(fact.get("lie_type", "cannot_lie"))
	kind.select(1 if lie == "must_lie" else 2 if lie == "can_lie" else 0)
	kind.item_selected.connect(func(picked: int) -> void:
		var code := "cannot_lie"
		if picked == 1:
			code = "must_lie"
		elif picked == 2:
			code = "can_lie"
		var had := fact.get("breaks_with") is Array and not (fact.get("breaks_with") as Array).is_empty()
		editor._doc.set_fact_kind(editor._agent, index, code)
		if code == "cannot_lie" and had:
			editor._show_help("Противоречия и наборы этой лжи удалены")
		editor.rebuild_editor()
	)
	card.add_child(kind)
	card.add_child(_area(editor, "Что он расскажет", "FactFull_%s" % fact_id, str(fact.get("content_full", "")), "Должен Виктору 2,5 млн.", index, "content_full"))
	var basic_label := "Оговорка" if lie == "can_lie" else "Неполное признание"
	card.add_child(_area(editor, basic_label, "FactBasic_%s" % fact_id, str(fact.get("content_basic", "")), "Был должен Виктору крупную сумму.", index, "content_basic"))
	if lie == "can_lie":
		editor._help_button(card, "BasicHelp_%s" % fact_id, "ИИ знает её с первого хода и может сказать в любой момент. Сказанная, она засчитывается как правда для противоречий")
	card.add_child(UiWidgets.label("Связанные улики"))
	if lie != "cannot_lie":
		editor._help_button(card, "EvidenceHelp_%s" % fact_id, "От них зависит «Полностью — только после показа улики» и тема лжи. Ломают ложь только наборы из «Чем можно сломать»")
	var box := VBoxContainer.new()
	box.name = "FactEvidence_%s" % fact_id
	card.add_child(box)
	var selected: Array = fact.get("related_evidence_ids", []) if fact.get("related_evidence_ids") is Array else []
	for item in editor._doc.raw.get("evidence", []):
		if item is not Dictionary:
			continue
		var evidence_id := str((item as Dictionary).get("id", ""))
		var toggle := CheckBox.new()
		toggle.text = str((item as Dictionary).get("title", evidence_id))
		toggle.button_pressed = selected.has(evidence_id)
		toggle.custom_minimum_size = Vector2(48, 48)
		var linked := evidence_id
		toggle.toggled.connect(func(on: bool) -> void:
			var current := _fact_now(editor, index)
			var ids: Array = current.get("related_evidence_ids", []) if current.get("related_evidence_ids") is Array else []
			var next: Array = []
			for one in ids:
				if str(one) != linked:
					next.append(one)
			if on:
				next.append(linked)
			editor._doc.set_fact_field(editor._agent, index, "related_evidence_ids", next)
			editor._schedule()
		)
		box.add_child(toggle)
	var requires := CheckBox.new()
	requires.name = "FactRequires_%s" % fact_id
	requires.text = "Полностью — только после показа улики"
	requires.button_pressed = fact.get("requires_evidence", false) == true
	requires.disabled = selected.is_empty()
	requires.custom_minimum_size = Vector2(48, 48)
	requires.toggled.connect(func(on: bool) -> void:
		editor._doc.set_fact_field(editor._agent, index, "requires_evidence", on)
		editor._schedule()
	)
	card.add_child(requires)
	card.add_child(UiWidgets.label("Только после того, как сломана ложь…"))
	var search := LineEdit.new()
	search.name = "FactSearch_%s" % fact_id
	search.placeholder_text = "поиск: персонаж или показание"
	search.custom_minimum_size = Vector2(0, 48)
	var broken := OptionButton.new()
	broken.name = "FactBroken_%s" % fact_id
	card.add_child(search)
	card.add_child(broken)
	_fill_broken(editor, broken, fact_id, "")
	search.text_changed.connect(func(text: String) -> void:
		broken.set_block_signals(true)
		_fill_broken(editor, broken, fact_id, text)
		broken.set_block_signals(false)
	)
	broken.item_selected.connect(func(picked: int) -> void:
		var priors: Array = []
		var chosen := str(broken.get_item_metadata(picked))
		if chosen != "":
			priors.append(chosen)
		editor._doc.set_fact_field(editor._agent, index, "requires_broken_lies", priors)
		editor._schedule()
	)
	if lie == "cannot_lie":
		return card
	card.add_child(_area(editor, "Что он говорит вместо правды", "FactLie_%s" % fact_id, str(fact.get("lie_text", "")), "Долгов нет.", index, "lie_text"))
	card.add_child(UiWidgets.label("Чем можно сломать"))
	editor._help_button(card, "BreaksHelp_%s" % fact_id, "Ложь ломается, когда собран целиком любой набор. Пока набор собран частично, ложь под сомнением: персонаж защищается, но не признаётся")
	card.add_child(_breaks(editor, index, fact))
	card.add_child(UiWidgets.label("Противоречит показанию…"))
	editor._help_button(card, "ContraHelp_%s" % fact_id, "Противоречие засчитывается, когда игрок услышал обе стороны. Ложь оно не ломает — для этого «Чем можно сломать»")
	card.add_child(_contradictions(editor, fact_id))
	return card


static func _breaks(editor: CaseEditor, index: int, fact: Dictionary) -> Control:
	var fact_id := str(fact.get("id", ""))
	var box := VBoxContainer.new()
	box.name = "FactBreaks_%s" % fact_id
	var sets: Array = fact.get("breaks_with", []) if fact.get("breaks_with") is Array else []
	for set_index in sets.size():
		if sets[set_index] is not Array:
			continue
		var row := VBoxContainer.new()
		row.name = "BreakSet_%s_%d" % [fact_id, set_index]
		box.add_child(row)
		if set_index > 0:
			row.add_child(UiWidgets.label("или"))
		var items: Array = sets[set_index]
		for item_index in items.size():
			if items[item_index] is Dictionary:
				row.add_child(_break_item(editor, index, set_index, item_index, items[item_index] as Dictionary))
		if not editor._read_only:
			var add_item := UiWidgets.button("И ещё пункт", "BreakAddItem_%s_%d" % [fact_id, set_index])
			var set_at := set_index
			add_item.pressed.connect(func() -> void:
				var current := _fact_now(editor, index)
				var fresh: Array = current.get("breaks_with", [])
				if set_at < fresh.size() and fresh[set_at] is Array:
					(fresh[set_at] as Array).append({"type": "evidence_shown", "evidence_id": ""})
					editor._doc.set_fact_field(editor._agent, index, "breaks_with", fresh)
					editor.rebuild_editor()
			)
			row.add_child(add_item)
	if not editor._read_only:
		var add_set := UiWidgets.button("Добавить набор", "BreakAddSet_%s" % fact_id)
		add_set.pressed.connect(func() -> void:
			editor._doc.add_break_set(editor._agent, index)
			editor.rebuild_editor()
		)
		box.add_child(add_set)
	return box


static func _break_item(editor: CaseEditor, fact_index: int, set_index: int, item_index: int, item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var kind := OptionButton.new()
	kind.add_item("Показана улика")
	kind.add_item("Пересказаны слова")
	kind.select(1 if str(item.get("type", "")) == "testimony_retold" else 0)
	var target := OptionButton.new()
	target.name = "BreakTarget_%d_%d_%d" % [fact_index, set_index, item_index]
	var full := CheckBox.new()
	full.text = "только полная правда"
	full.button_pressed = str(item.get("form", "")) == "truth_full"
	full.custom_minimum_size = Vector2(48, 48)
	_fill_break_target(editor, target, item)
	var fact_at := fact_index
	var set_at := set_index
	var item_at := item_index
	kind.item_selected.connect(func(picked: int) -> void:
		var point := {"type": "testimony_retold" if picked == 1 else "evidence_shown"}
		if picked == 1:
			point["fact_id"] = ""
		else:
			point["evidence_id"] = ""
		_write_break(editor, fact_at, set_at, item_at, point)
	)
	target.item_selected.connect(func(picked: int) -> void:
		var point := item.duplicate(true)
		var meta := str(target.get_item_metadata(picked))
		if str(point.get("type", "")) == "testimony_retold":
			point["fact_id"] = meta
		else:
			point["type"] = "evidence_shown"
			point["evidence_id"] = meta
		_write_break(editor, fact_at, set_at, item_at, point)
	)
	full.toggled.connect(func(on: bool) -> void:
		var point := item.duplicate(true)
		point["type"] = "testimony_retold"
		if on:
			point["form"] = "truth_full"
		else:
			point.erase("form")
		_write_break(editor, fact_at, set_at, item_at, point)
	)
	var full_title := _break_full(editor, item)
	target.tooltip_text = full_title
	var shown := Label.new()
	shown.name = "BreakFull_%d_%d_%d" % [fact_index, set_index, item_index]
	shown.text = full_title
	shown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kind)
	row.add_child(target)
	row.add_child(full)
	var host := VBoxContainer.new()
	host.add_child(row)
	host.add_child(shown)
	return host


static func _contradictions(editor: CaseEditor, fact_id: String) -> Control:
	var box := VBoxContainer.new()
	box.name = "FactContra_%s" % fact_id
	var rows: Array = editor._doc.raw.get("contradictions", [])
	for row_index in rows.size():
		if rows[row_index] is not Dictionary:
			continue
		var body := rows[row_index] as Dictionary
		if str(body.get("fact_a_id", "")) != fact_id or str(body.get("fact_a_form", "")) != "lie":
			continue
		if str(body.get("fact_b_form", "")) == "lie":
			continue
		var other := str(body.get("fact_b_id", ""))
		var block := VBoxContainer.new()
		box.add_child(block)
		block.add_child(UiWidgets.label(_fact_label(editor, other)))
		var full := CheckBox.new()
		full.text = "Только после его полной правды"
		full.button_pressed = str(body.get("fact_b_form", "")) == "truth_full"
		full.custom_minimum_size = Vector2(48, 48)
		var at := row_index
		full.toggled.connect(func(on: bool) -> void:
			var list: Array = editor._doc.raw.get("contradictions", [])
			if at < list.size() and list[at] is Dictionary:
				editor._doc._snapshot()
				(list[at] as Dictionary)["fact_b_form"] = "truth_full" if on else "truth"
				editor._doc.changed.emit()
				editor._schedule()
		)
		block.add_child(full)
		var edit := TextEdit.new()
		edit.name = "ContraText_%s" % str(body.get("id", ""))
		edit.text = str(body.get("description", ""))
		edit.placeholder_text = "Аркадий говорит, что ушёл домой в 00:30, но Павел видел его в клубе после закрытия в 01:00"
		edit.custom_minimum_size = Vector2(0, 80)
		edit.focus_exited.connect(func() -> void:
			var list: Array = editor._doc.raw.get("contradictions", [])
			if at < list.size() and list[at] is Dictionary:
				editor._doc._snapshot()
				(list[at] as Dictionary)["description"] = edit.text
				editor._doc.changed.emit()
				editor._schedule()
		)
		block.add_child(edit)
	var both := VBoxContainer.new()
	both.name = "OtherContras_%s" % fact_id
	box.add_child(both)
	for row in rows:
		if row is not Dictionary:
			continue
		var body := row as Dictionary
		var sides_truth := str(body.get("fact_a_form", "")) != "lie" and str(body.get("fact_b_form", "")) != "lie"
		var mentions := str(body.get("fact_a_id", "")) == fact_id or str(body.get("fact_b_id", "")) == fact_id
		if sides_truth and mentions:
			var note := UiWidgets.label("Прочие противоречия: %s" % str(body.get("description", "")))
			note.name = "ReadOnlyContra_%s" % str(body.get("id", ""))
			both.add_child(note)
	if not editor._read_only:
		var other := OptionButton.new()
		other.name = "ContraPick_%s" % fact_id
		other.add_item("—")
		other.set_item_metadata(0, "")
		var cursor := 1
		for agent in editor._doc.raw.get("agents", []):
			if agent is not Dictionary:
				continue
			if str((agent as Dictionary).get("id", "")) == _owner(editor, fact_id):
				continue
			for fact in (agent as Dictionary).get("facts", []):
				if fact is not Dictionary:
					continue
				var other_id := str((fact as Dictionary).get("id", ""))
				other.add_item(_fact_label(editor, other_id))
				other.set_item_metadata(cursor, other_id)
				cursor += 1
		var add := UiWidgets.button("Добавить противоречие", "ContraAdd_%s" % fact_id)
		add.pressed.connect(func() -> void:
			var picked := str(other.get_item_metadata(other.selected))
			if picked == "":
				return
			editor._doc.add_contradiction(fact_id, picked, false, "")
			editor.rebuild_editor()
		)
		box.add_child(other)
		box.add_child(add)
	return box


static func _evidence(editor: CaseEditor, index: int, body: Dictionary) -> Control:
	var evidence_id := str(body.get("id", ""))
	var card := VBoxContainer.new()
	card.name = "Ev_%s" % evidence_id
	var bar := HBoxContainer.new()
	card.add_child(bar)
	bar.add_child(UiWidgets.label("Улика"))
	if not editor._read_only:
		var remove := UiWidgets.button(UiStrings.DELETE_CASE, "EvDelete_%s" % evidence_id)
		var up := UiWidgets.button(UiStrings.MOVE_UP, "EvUp_%s" % evidence_id)
		var down := UiWidgets.button(UiStrings.MOVE_DOWN, "EvDown_%s" % evidence_id)
		var at := index
		up.pressed.connect(func() -> void:
			editor._doc.move_evidence(at, -1)
			editor.rebuild_editor()
		)
		down.pressed.connect(func() -> void:
			editor._doc.move_evidence(at, 1)
			editor.rebuild_editor()
		)
		remove.pressed.connect(func() -> void: editor.ask_remove("evidence", evidence_id))
		bar.add_child(up)
		bar.add_child(down)
		bar.add_child(remove)
	card.add_child(_ev_line(editor, index, "Название", "EvTitle_%s" % evidence_id, "title", str(body.get("title", "")), "Журнал охраны"))
	editor._help_button(card, "EvTitleHelp_%s" % evidence_id, "Нужны узнаваемые слова — по ним игра понимает, что игрок назвал улику")
	var types := OptionButton.new()
	types.name = "EvType_%s" % evidence_id
	types.add_item("Место")
	types.add_item("Предмет")
	types.add_item("Документ")
	var kind := str(body.get("type", "object"))
	if kind == "scene" or kind == "location":
		kind = "place"
	elif kind == "item":
		kind = "object"
	types.select(0 if kind == "place" else 2 if kind == "document" else 1)
	types.item_selected.connect(func(picked: int) -> void:
		var code := "object"
		if picked == 0:
			code = "place"
		elif picked == 2:
			code = "document"
		editor._doc.set_evidence_field(index, "type", code)
		editor._schedule()
	)
	card.add_child(types)
	card.add_child(_ev_line(editor, index, "Подпись на доске улик", "EvShort_%s" % evidence_id, "short_description", str(body.get("short_description", "")), "Записи выходов из клуба в ночь убийства."))
	card.add_child(_ev_area(editor, index, "Содержание улики", "EvFull_%s" % evidence_id, "full_text", str(body.get("full_text", "")), "Журнал показывает выход Аркадия в 01:18."))
	editor._help_button(card, "EvFullHelp_%s" % evidence_id, "Читает игрок; знает персонаж, которому улику показали")
	card.add_child(UiWidgets.label("Касается персонажей"))
	editor._help_button(card, "EvAgentsHelp_%s" % evidence_id, "При показе у них появляется значок «новое»")
	var people := VBoxContainer.new()
	people.name = "EvAgents_%s" % evidence_id
	card.add_child(people)
	var owners := _evidence_owners(editor, evidence_id)
	var marked: Array = body.get("related_agent_ids", []) if body.get("related_agent_ids") is Array else []
	for agent in editor._doc.raw.get("agents", []):
		if agent is not Dictionary:
			continue
		var agent_id := str((agent as Dictionary).get("id", ""))
		var toggle := CheckBox.new()
		toggle.text = str((agent as Dictionary).get("name", agent_id))
		toggle.button_pressed = owners.has(agent_id) or marked.has(agent_id)
		toggle.disabled = owners.has(agent_id)
		toggle.custom_minimum_size = Vector2(48, 48)
		var who := agent_id
		toggle.toggled.connect(func(on: bool) -> void:
			if owners.has(who):
				return
			var list: Array = editor._doc.raw.get("evidence", [])
			if index >= list.size() or list[index] is not Dictionary:
				return
			var current: Array = (list[index] as Dictionary).get("related_agent_ids", [])
			var next: Array = []
			for one in current:
				if str(one) != who:
					next.append(one)
			if on:
				next.append(who)
			editor._doc.set_evidence_field(index, "related_agent_ids", next)
			editor._schedule()
		)
		people.add_child(toggle)
	card.add_child(UiWidgets.label("Когда появляется"))
	card.add_child(_condition(editor, index, evidence_id, body.get("unlock_condition")))
	return card


static func _condition(editor: CaseEditor, index: int, evidence_id: String, cond: Variant) -> Control:
	var box := VBoxContainer.new()
	box.name = "EvCond_%s" % evidence_id
	var mode := OptionButton.new()
	mode.name = "EvMode_%s" % evidence_id
	mode.add_item("Доступна сразу")
	mode.add_item("Персонаж упомянул её")
	mode.add_item("Сломана ложь…")
	mode.add_item("После разговора с персонажем")
	mode.add_item("После показа другой улики")
	mode.add_item("После найденного противоречия")
	mode.add_item("И")
	mode.add_item("ИЛИ")
	mode.add_item("Неподдерживаемое условие")
	mode.select(_cond_mode(cond, evidence_id))
	mode.item_selected.connect(func(picked: int) -> void:
		editor._doc.set_unlock(index, _cond_template(editor, evidence_id, picked))
		editor.rebuild_editor()
	)
	box.add_child(mode)
	if cond is Dictionary:
		var body := cond as Dictionary
		if body.has("AND") or body.has("OR"):
			var op := "AND" if body.has("AND") else "OR"
			var items: Array = body[op]
			for sub_index in items.size():
				var nested := _condition(editor, index, "%s_%d" % [evidence_id, sub_index], items[sub_index])
				box.add_child(nested)
		elif str(body.get("type", "")) == "evidence_mentioned":
			box.add_child(_agent_pick(editor, index, evidence_id, "agent_id", str(body.get("agent_id", ""))))
			box.add_child(UiWidgets.label("Тема"))
			editor._help_button(box, "MentionHelp_%s" % evidence_id, "Откроется, когда разговор с этим персонажем дважды коснётся темы или игрок прямо спросит")
			var topic := LineEdit.new()
			topic.name = "EvTopic_%s" % evidence_id
			topic.text = str(body.get("topic", ""))
			topic.placeholder_text = "кто входил и выходил"
			topic.custom_minimum_size = Vector2(0, 48)
			topic.focus_exited.connect(func() -> void:
				var next := (body as Dictionary).duplicate(true)
				next["topic"] = topic.text
				editor._doc.set_unlock(index, next)
				editor._schedule()
			)
			box.add_child(topic)
		elif str(body.get("type", "")) == "lie_broken":
			box.add_child(_fact_pick(editor, index, evidence_id, str(body.get("fact_id", ""))))
		elif str(body.get("type", "")) == "dialogue_with":
			box.add_child(_agent_pick(editor, index, evidence_id, "agent_id", str(body.get("agent_id", ""))))
		elif str(body.get("type", "")) == "evidence_shown":
			box.add_child(_evidence_pick(editor, index, evidence_id, str(body.get("evidence_id", ""))))
		elif str(body.get("type", "")) == "inconsistency_created":
			box.add_child(_contradiction_pick(editor, index, evidence_id, str(body.get("contradiction_id", ""))))
			editor._help_button(box, "InconHelp_%s" % evidence_id, "Откроется, когда игрок услышал обе стороны этого противоречия")
		elif str(body.get("type", "")) == "pressure_on_agent" or str(body.get("type", "")) == "":
			var note := UiWidgets.label("Неподдерживаемое условие")
			note.name = "Unsupported_%s" % evidence_id
			box.add_child(note)
	return box


static func _area(editor: CaseEditor, label: String, node_name: String, value: String, sample: String, fact_index: int, key: String) -> Control:
	var host := VBoxContainer.new()
	host.add_child(UiWidgets.label(label))
	var edit := TextEdit.new()
	edit.name = node_name
	edit.text = value
	edit.placeholder_text = sample
	edit.custom_minimum_size = Vector2(0, 80)
	edit.focus_exited.connect(func() -> void:
		editor._doc.set_fact_field(editor._agent, fact_index, key, edit.text)
		editor._schedule()
	)
	host.add_child(edit)
	return host


static func _ev_line(editor: CaseEditor, index: int, label: String, node_name: String, key: String, value: String, sample: String) -> Control:
	var host := VBoxContainer.new()
	host.add_child(UiWidgets.label(label))
	var edit := LineEdit.new()
	edit.name = node_name
	edit.text = value
	edit.placeholder_text = sample
	edit.custom_minimum_size = Vector2(0, 48)
	edit.focus_exited.connect(func() -> void:
		editor._doc.set_evidence_field(index, key, edit.text)
		editor._schedule()
	)
	host.add_child(edit)
	return host


static func _ev_area(editor: CaseEditor, index: int, label: String, node_name: String, key: String, value: String, sample: String) -> Control:
	var host := VBoxContainer.new()
	host.add_child(UiWidgets.label(label))
	var edit := TextEdit.new()
	edit.name = node_name
	edit.text = value
	edit.placeholder_text = sample
	edit.custom_minimum_size = Vector2(0, 96)
	edit.focus_exited.connect(func() -> void:
		editor._doc.set_evidence_field(index, key, edit.text)
		editor._schedule()
	)
	host.add_child(edit)
	return host


static func _fill_broken(editor: CaseEditor, broken: OptionButton, fact_id: String, query: String) -> void:
	broken.clear()
	broken.add_item("—")
	broken.set_item_metadata(0, "")
	var needle := query.strip_edges().to_lower()
	var cursor := 1
	for agent in editor._doc.raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is not Dictionary or not (fact as Dictionary).get("is_lie", false):
				continue
			var other := str((fact as Dictionary).get("id", ""))
			if other == fact_id:
				continue
			var label := _fact_label(editor, other)
			if needle != "" and not label.to_lower().contains(needle):
				continue
			broken.add_item(label)
			broken.set_item_metadata(cursor, other)
			cursor += 1
	var current := ""
	var found := _find_fact(editor, fact_id)
	var priors: Array = found.get("requires_broken_lies", []) if found.get("requires_broken_lies") is Array else []
	if not priors.is_empty():
		current = str(priors[0])
	broken.set_block_signals(true)
	for item_index in broken.item_count:
		if str(broken.get_item_metadata(item_index)) == current:
			broken.select(item_index)
			broken.set_block_signals(false)
			return
	broken.select(0)
	broken.set_block_signals(false)


static func _fill_break_target(editor: CaseEditor, target: OptionButton, item: Dictionary) -> void:
	target.clear()
	var selected := str(item.get("evidence_id", item.get("fact_id", "")))
	var cursor := 0
	var pick := 0
	if str(item.get("type", "")) == "testimony_retold":
		for agent in editor._doc.raw.get("agents", []):
			if agent is not Dictionary:
				continue
			for fact in (agent as Dictionary).get("facts", []):
				if fact is not Dictionary:
					continue
				var fact_id := str((fact as Dictionary).get("id", ""))
				target.add_item(_fact_label(editor, fact_id))
				target.set_item_metadata(cursor, fact_id)
				if fact_id == selected:
					pick = cursor
				cursor += 1
	else:
		for evidence in editor._doc.raw.get("evidence", []):
			if evidence is not Dictionary:
				continue
			var evidence_id := str((evidence as Dictionary).get("id", ""))
			target.add_item(str((evidence as Dictionary).get("title", evidence_id)))
			target.set_item_metadata(cursor, evidence_id)
			if evidence_id == selected:
				pick = cursor
			cursor += 1
	target.set_block_signals(true)
	if target.item_count == 0:
		target.add_item("—")
		target.set_item_metadata(0, "")
	else:
		target.select(pick)
	target.set_block_signals(false)


static func _write_break(editor: CaseEditor, fact_index: int, set_index: int, item_index: int, point: Dictionary) -> void:
	var current := _fact_now(editor, fact_index)
	var sets: Array = current.get("breaks_with", []) if current.get("breaks_with") is Array else []
	if set_index >= sets.size() or sets[set_index] is not Array:
		return
	var items: Array = sets[set_index]
	if item_index >= items.size():
		return
	items[item_index] = point
	editor._doc.set_fact_field(editor._agent, fact_index, "breaks_with", sets)
	editor.rebuild_editor()


static func _fact_now(editor: CaseEditor, index: int) -> Dictionary:
	var agents: Array = editor._doc.raw.get("agents", [])
	if editor._agent >= agents.size() or agents[editor._agent] is not Dictionary:
		return {}
	var facts: Array = (agents[editor._agent] as Dictionary).get("facts", [])
	if index >= facts.size() or facts[index] is not Dictionary:
		return {}
	return facts[index]


static func _find_fact(editor: CaseEditor, fact_id: String) -> Dictionary:
	for agent in editor._doc.raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is Dictionary and str((fact as Dictionary).get("id", "")) == fact_id:
				return fact
	return {}


static func _owner(editor: CaseEditor, fact_id: String) -> String:
	for agent in editor._doc.raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is Dictionary and str((fact as Dictionary).get("id", "")) == fact_id:
				return str((agent as Dictionary).get("id", ""))
	return ""


static func _fact_full(editor: CaseEditor, fact_id: String) -> String:
	var owner := ""
	var text := fact_id
	for agent in editor._doc.raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is Dictionary and str((fact as Dictionary).get("id", "")) == fact_id:
				owner = str((agent as Dictionary).get("name", (agent as Dictionary).get("id", "")))
				text = str((fact as Dictionary).get("content_full", fact_id)).replace("\n", " ")
	return "%s: %s" % [owner, text]


static func _fact_label(editor: CaseEditor, fact_id: String) -> String:
	return _ellipsize(_fact_full(editor, fact_id))


static func _break_full(editor: CaseEditor, item: Dictionary) -> String:
	if str(item.get("type", "")) == "testimony_retold":
		return _fact_full(editor, str(item.get("fact_id", "")))
	var evidence_id := str(item.get("evidence_id", ""))
	for evidence in editor._doc.raw.get("evidence", []):
		if evidence is Dictionary and str((evidence as Dictionary).get("id", "")) == evidence_id:
			return str((evidence as Dictionary).get("title", evidence_id))
	return evidence_id


static func _ellipsize(text: String) -> String:
	if text.length() <= 42:
		return text
	return text.substr(0, 41) + "…"


static func _evidence_owners(editor: CaseEditor, evidence_id: String) -> Dictionary:
	var owners := {}
	for agent in editor._doc.raw.get("agents", []):
		if agent is not Dictionary:
			continue
		var agent_id := str((agent as Dictionary).get("id", ""))
		for fact in (agent as Dictionary).get("facts", []):
			if fact is not Dictionary:
				continue
			var related: Array = (fact as Dictionary).get("related_evidence_ids", []) if (fact as Dictionary).get("related_evidence_ids") is Array else []
			if related.has(evidence_id):
				owners[agent_id] = true
	return owners


static func _cond_mode(cond: Variant, evidence_id: String) -> int:
	if cond == null or cond is not Dictionary:
		return 0
	var body := cond as Dictionary
	if body.has("AND"):
		return 6
	if body.has("OR"):
		return 7
	var kind := str(body.get("type", ""))
	if kind == "evidence_mentioned":
		return 1
	if kind == "lie_broken":
		return 2
	if kind == "dialogue_with":
		return 3
	if kind == "evidence_shown":
		return 4
	if kind == "inconsistency_created":
		return 5
	if kind == "pressure_on_agent":
		return 8
	return 8 if evidence_id != "" else 0


static func _cond_template(editor: CaseEditor, evidence_id: String, mode: int) -> Variant:
	var agent_id := ""
	var fact_id := ""
	var other_evidence := ""
	var contradiction_id := ""
	for agent in editor._doc.raw.get("agents", []):
		if agent is Dictionary and agent_id == "":
			agent_id = str((agent as Dictionary).get("id", ""))
			for fact in (agent as Dictionary).get("facts", []):
				if fact is Dictionary and fact_id == "":
					fact_id = str((fact as Dictionary).get("id", ""))
	for evidence in editor._doc.raw.get("evidence", []):
		if evidence is Dictionary and str((evidence as Dictionary).get("id", "")) != evidence_id and other_evidence == "":
			other_evidence = str((evidence as Dictionary).get("id", ""))
	for row in editor._doc.raw.get("contradictions", []):
		if row is Dictionary and contradiction_id == "":
			contradiction_id = str((row as Dictionary).get("id", ""))
	if mode == 0:
		return null
	if mode == 1:
		return {"type": "evidence_mentioned", "agent_id": agent_id, "evidence_id": evidence_id, "topic": ""}
	if mode == 2:
		return {"type": "lie_broken", "fact_id": fact_id}
	if mode == 3:
		return {"type": "dialogue_with", "agent_id": agent_id}
	if mode == 4:
		return {"type": "evidence_shown", "evidence_id": other_evidence}
	if mode == 5:
		return {"type": "inconsistency_created", "contradiction_id": contradiction_id}
	if mode == 6:
		return {"AND": [{"type": "dialogue_with", "agent_id": agent_id}]}
	if mode == 7:
		return {"OR": [{"type": "dialogue_with", "agent_id": agent_id}, {"type": "lie_broken", "fact_id": fact_id}]}
	return {"type": "pressure_on_agent", "agent_id": agent_id, "min": 1}


static func _agent_pick(editor: CaseEditor, index: int, evidence_id: String, key: String, current: String) -> Control:
	var choice := OptionButton.new()
	choice.name = "EvAgentPick_%s" % evidence_id
	var cursor := 0
	var pick := 0
	for agent in editor._doc.raw.get("agents", []):
		if agent is not Dictionary:
			continue
		var agent_id := str((agent as Dictionary).get("id", ""))
		choice.add_item(str((agent as Dictionary).get("name", agent_id)))
		choice.set_item_metadata(cursor, agent_id)
		if agent_id == current:
			pick = cursor
		cursor += 1
	choice.set_block_signals(true)
	if choice.item_count > 0:
		choice.select(pick)
	choice.set_block_signals(false)
	choice.item_selected.connect(func(picked: int) -> void:
		var list: Array = editor._doc.raw.get("evidence", [])
		if index >= list.size() or list[index] is not Dictionary:
			return
		var cond: Variant = (list[index] as Dictionary).get("unlock_condition")
		if cond is Dictionary:
			var next := (cond as Dictionary).duplicate(true)
			next[key] = str(choice.get_item_metadata(picked))
			editor._doc.set_unlock(index, next)
			editor._schedule()
	)
	return choice


static func _fact_pick(editor: CaseEditor, index: int, evidence_id: String, current: String) -> Control:
	var choice := OptionButton.new()
	choice.name = "EvFactPick_%s" % evidence_id
	var cursor := 0
	var pick := 0
	for agent in editor._doc.raw.get("agents", []):
		if agent is not Dictionary:
			continue
		for fact in (agent as Dictionary).get("facts", []):
			if fact is not Dictionary:
				continue
			var fact_id := str((fact as Dictionary).get("id", ""))
			choice.add_item(_fact_label(editor, fact_id))
			choice.set_item_metadata(cursor, fact_id)
			if fact_id == current:
				pick = cursor
			cursor += 1
	choice.set_block_signals(true)
	if choice.item_count > 0:
		choice.select(pick)
	choice.set_block_signals(false)
	choice.item_selected.connect(func(picked: int) -> void:
		editor._doc.set_unlock(index, {"type": "lie_broken", "fact_id": str(choice.get_item_metadata(picked))})
		editor._schedule()
	)
	return choice


static func _evidence_pick(editor: CaseEditor, index: int, evidence_id: String, current: String) -> Control:
	var choice := OptionButton.new()
	choice.name = "EvShownPick_%s" % evidence_id
	var cursor := 0
	var pick := 0
	for evidence in editor._doc.raw.get("evidence", []):
		if evidence is not Dictionary:
			continue
		var other := str((evidence as Dictionary).get("id", ""))
		if other == evidence_id:
			continue
		choice.add_item(str((evidence as Dictionary).get("title", other)))
		choice.set_item_metadata(cursor, other)
		if other == current:
			pick = cursor
		cursor += 1
	choice.set_block_signals(true)
	if choice.item_count == 0:
		choice.add_item("—")
		choice.set_item_metadata(0, "")
	else:
		choice.select(pick)
	choice.set_block_signals(false)
	choice.item_selected.connect(func(picked: int) -> void:
		var shown := str(choice.get_item_metadata(picked))
		editor._doc.set_unlock(index, {"type": "evidence_shown", "evidence_id": shown})
		editor._schedule()
	)
	return choice


static func _contradiction_pick(editor: CaseEditor, index: int, evidence_id: String, current: String) -> Control:
	var choice := OptionButton.new()
	choice.name = "EvContraPick_%s" % evidence_id
	choice.add_item("—")
	choice.set_item_metadata(0, "")
	var cursor := 1
	var pick := 0
	for row in editor._doc.raw.get("contradictions", []):
		if row is not Dictionary:
			continue
		var contradiction_id := str((row as Dictionary).get("id", ""))
		choice.add_item(contradiction_id)
		choice.set_item_metadata(cursor, contradiction_id)
		if contradiction_id == current:
			pick = cursor
		cursor += 1
	choice.set_block_signals(true)
	choice.select(pick)
	choice.set_block_signals(false)
	choice.item_selected.connect(func(picked: int) -> void:
		editor._doc.set_unlock(index, {"type": "inconsistency_created", "contradiction_id": str(choice.get_item_metadata(picked))})
		editor._schedule()
	)
	return choice
