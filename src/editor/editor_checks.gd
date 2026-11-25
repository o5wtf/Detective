class_name EditorChecks
extends RefCounted
## Правила раздела 7: русский текст и куда ведёт «Перейти».


static func collect(raw: Dictionary) -> Array:
	var issues: Array = []
	var agents: Array = raw.get("agents", [])
	var evidence: Array = raw.get("evidence", [])
	var contradictions: Array = raw.get("contradictions", [])
	if str(raw.get("title", "")).strip_edges() == "":
		issues.append(_issue("error", "Нет названия", "overview", -1, "TitleEdit"))
	if str(raw.get("briefing", "")).strip_edges() == "":
		issues.append(_issue("error", "Нет брифинга", "overview", -1, "BriefingEdit"))
	if str(raw.get("truth_timeline", "")).strip_edges() == "":
		issues.append(_issue("warning", "Пустое «Как всё было»", "overview", -1, "TruthEdit"))
	if agents.is_empty():
		issues.append(_issue("error", "Нет персонажей", "people", -1, "AddAgent"))
	elif agents.size() < 2:
		issues.append(_issue("error", "Меньше 2 персонажей", "people", 0, "AddAgent"))
	if evidence.is_empty():
		issues.append(_issue("warning", "В деле нет улик", "evidence", -1, "AddEvidence"))
	_options(raw, "method", "способа", "MethodOptions", issues)
	_options(raw, "motive", "мотива", "MotiveOptions", issues)
	var agent_ids := {}
	var fact_owner := {}
	var facts := {}
	var agent_index := {}
	for index in agents.size():
		if agents[index] is Dictionary:
			agent_ids[str((agents[index] as Dictionary).get("id", ""))] = true
	for index in agents.size():
		if agents[index] is not Dictionary:
			continue
		var who := agents[index] as Dictionary
		var agent_id := str(who.get("id", ""))
		agent_index[agent_id] = index
		if agent_id == "":
			issues.append(_issue("error", "Повторяющийся или пустой id", "people", index, "NameEdit"))
		_agent(who, index, agent_ids, issues)
		var rows: Array = who.get("facts", [])
		if rows.is_empty():
			issues.append(_issue("warning", "Персонаж без показаний", "people", index, "AddFact"))
		for fact in rows:
			if fact is not Dictionary:
				continue
			var fact_id := str((fact as Dictionary).get("id", ""))
			if fact_id == "" or facts.has(fact_id):
				issues.append(_issue("error", "Повторяющийся или пустой id", "people", index, "Fact_%s" % fact_id))
			facts[fact_id] = fact
			fact_owner[fact_id] = agent_id
	if not agent_ids.has(str(raw.get("killer_id", ""))):
		issues.append(_issue("error", "Убийца не выбран", "overview", -1, "KillerChoice"))
	var killer := str(raw.get("killer_id", ""))
	var killer_lies := 0
	var any_breaks := false
	for fact_id in facts:
		var fact: Dictionary = facts[fact_id]
		var owner := str(fact_owner.get(fact_id, ""))
		var index := int(agent_index.get(owner, 0))
		_fact(fact, index, facts, evidence, fact_owner, contradictions, issues)
		if owner == killer and fact.get("is_lie", false):
			killer_lies += 1
		var sets := _sets(fact, contradictions)
		if fact.get("is_lie", false) and not sets.is_empty():
			any_breaks = true
	if killer != "" and killer_lies == 0:
		issues.append(_issue("warning", "У убийцы нет ни одной лжи", "overview", -1, "KillerChoice"))
	if not any_breaks:
		issues.append(_issue("warning", "Ни у одной лжи нет наборов «Чем можно сломать»", "people", 0, "AddFact"))
	_reach(facts, fact_owner, agent_index, contradictions, issues)
	var evidence_ids := {}
	var contradiction_ids := {}
	for row in contradictions:
		if row is Dictionary:
			var cid := str((row as Dictionary).get("id", ""))
			if cid == "" or contradiction_ids.has(cid):
				issues.append(_issue("error", "Повторяющийся или пустой id", "people", 0, "AddFact"))
			contradiction_ids[cid] = true
			_contradiction(row as Dictionary, facts, fact_owner, agent_index, issues)
	for index in evidence.size():
		if evidence[index] is not Dictionary:
			continue
		var body := evidence[index] as Dictionary
		var evidence_id := str(body.get("id", ""))
		if evidence_id == "" or evidence_ids.has(evidence_id):
			issues.append(_issue("error", "Повторяющийся или пустой id", "evidence", -1, "Ev_%s" % evidence_id))
		evidence_ids[evidence_id] = true
	for index in evidence.size():
		if evidence[index] is not Dictionary:
			continue
		_evidence(evidence[index] as Dictionary, agent_ids, facts, evidence_ids, contradiction_ids, issues)
	return issues


static func _options(raw: Dictionary, kind: String, word: String, node_name: String, issues: Array) -> void:
	var key := "%s_options" % kind
	var true_key := "true_%s_id" % kind
	var options: Array = raw.get(key, []) if raw.get(key) is Array else []
	var filled := 0
	var ids := {}
	for option in options:
		if option is not Dictionary:
			continue
		var option_id := str((option as Dictionary).get("id", ""))
		if option_id == "" or ids.has(option_id):
			issues.append(_issue("error", "Повторяющийся или пустой id", "overview", -1, node_name))
		ids[option_id] = true
		if str((option as Dictionary).get("text", "")).strip_edges() != "":
			filled += 1
	if filled == 0:
		issues.append(_issue("error", "Нет вариантов %s" % word, "overview", -1, node_name))
	elif filled == 1:
		issues.append(_issue("warning", "У способа или мотива только один вариант", "overview", -1, node_name))
	if not ids.has(str(raw.get(true_key, ""))):
		issues.append(_issue("error", "Не отмечен верный %s" % ("способ" if kind == "method" else "мотив"), "overview", -1, node_name))


static func _agent(who: Dictionary, index: int, agent_ids: Dictionary, issues: Array) -> void:
	if str(who.get("name", "")).strip_edges() == "":
		issues.append(_issue("error", "Пусто имя", "people", index, "NameEdit"))
	if str(who.get("role", "")).strip_edges() == "":
		issues.append(_issue("error", "Пусто роль", "people", index, "RoleEdit"))
	if str(who.get("personality", "")).strip_edges() == "":
		issues.append(_issue("error", "Пусто характер", "people", index, "PersonalityEdit"))
	if str(who.get("prompt_background", "")).strip_edges() == "":
		issues.append(_issue("error", "Пусто предыстория", "people", index, "PromptBackgroundEdit"))
	var emotion := str(who.get("starting_emotion", "neutral"))
	if not CaseValidator.EMOTIONS.has(emotion):
		issues.append(_issue("error", "Эмоция не из списка", "people", index, "EmotionChoice"))
	var gender := str(who.get("gender", ""))
	if gender != "" and gender != "male" and gender != "female":
		issues.append(_issue("error", "Неверный пол", "people", index, "GenderChoice"))
	var voice := str(who.get("tts_voice", "")).strip_edges()
	if voice != "" and not _voice_ok(voice):
		issues.append(_issue("error", "Неверное имя голоса", "people", index, "VoiceChoice"))
	var profanity := str(who.get("profanity", "never"))
	if profanity != "never" and profanity != "sometimes" and profanity != "often":
		issues.append(_issue("error", "Неверное значение «Ругается»", "people", index, "ProfanityChoice"))
	var links: Variant = who.get("relationships", {})
	if links is Dictionary:
		for other in links:
			if str(other) == str(who.get("id", "")) or not agent_ids.has(str(other)):
				issues.append(_issue("error", "В отношениях удалённый персонаж или он сам", "people", index, "RelationsHelp"))
	var blob := ""
	for key in ["wants", "fears", "own_version", "life_details"]:
		blob += str(who.get(key, ""))
	for line in who.get("sample_lines", []):
		blob += str(line)
	if _looks_like_fact(blob):
		issues.append(_issue("warning", "В полях «Живого персонажа» есть время или числа", "people", index, "WantsEdit"))


static func _fact(fact: Dictionary, index: int, facts: Dictionary, evidence: Array, owners: Dictionary, contradictions: Array, issues: Array) -> void:
	var fact_id := str(fact.get("id", ""))
	var node := "FactFull_%s" % fact_id
	if str(fact.get("content_full", "")).strip_edges() == "":
		issues.append(_issue("error", "Пусто «Что он расскажет»", "people", index, node))
	var kind := str(fact.get("lie_type", ""))
	var lie: bool = fact.get("is_lie", false) == true
	var basic := str(fact.get("content_basic", "")).strip_edges()
	var full := str(fact.get("content_full", "")).strip_edges()
	if lie and kind == "can_lie" and basic == "":
		issues.append(_issue("error", "Пустая «Оговорка»", "people", index, "FactBasic_%s" % fact_id))
	var related: Array = fact.get("related_evidence_ids", []) if fact.get("related_evidence_ids") is Array else []
	var evidence_ids := {}
	for item in evidence:
		if item is Dictionary:
			evidence_ids[str((item as Dictionary).get("id", ""))] = true
	for evidence_id in related:
		if not evidence_ids.has(str(evidence_id)):
			issues.append(_issue("error", "Улика ссылается на удалённого персонажа или показание", "people", index, "FactEvidence_%s" % fact_id))
	if fact.get("requires_evidence", false) and related.is_empty():
		issues.append(_issue("error", "«Полностью — только после показа улики» включено без связанных улик", "people", index, "FactRequires_%s" % fact_id))
	if lie and str(fact.get("lie_text", "")).strip_edges() == "":
		issues.append(_issue("error", "У лжи пустой текст лжи", "people", index, "FactLie_%s" % fact_id))
	if not lie and str(fact.get("lie_text", "")).strip_edges() != "":
		issues.append(_issue("error", "У правды заполнен текст лжи", "people", index, "FactFull_%s" % fact_id))
	var priors: Array = fact.get("requires_broken_lies", []) if fact.get("requires_broken_lies") is Array else []
	for prior in priors:
		if str(prior) == "" or not facts.has(str(prior)):
			var text := "Показание лишилось условия “после сломанной лжи”" if str(prior) == "" else "Ссылка на удалённое показание в «Только после того, как сломана ложь…»"
			issues.append(_issue("error", text, "people", index, "FactBroken_%s" % fact_id))
	if lie and fact.get("requires_evidence", false) and (basic == "" or basic == full):
		issues.append(_issue("warning", "«Неполное признание» пустое или совпадает с «Что он расскажет»", "people", index, "FactBasic_%s" % fact_id))
	if lie and kind == "can_lie" and basic != "" and basic == full:
		issues.append(_issue("warning", "«Оговорка» совпадает с «Что он расскажет»", "people", index, "FactBasic_%s" % fact_id))
	var sets := _sets(fact, contradictions)
	if lie and kind == "must_lie" and sets.is_empty():
		issues.append(_issue("error", "У «Всегда врёт» нет ни одного набора", "people", index, "FactBreaks_%s" % fact_id))
	if lie and kind == "can_lie" and sets.is_empty():
		issues.append(_issue("warning", "«Может соврать» без наборов «Чем можно сломать»", "people", index, "FactBreaks_%s" % fact_id))
	var used_evidence := {}
	for raw_set in sets:
		if raw_set is not Array or (raw_set as Array).is_empty():
			issues.append(_issue("error", "Пустой набор", "people", index, "FactBreaks_%s" % fact_id))
			continue
		for item in raw_set:
			if item is not Dictionary:
				issues.append(_issue("error", "Неизвестный вид пункта", "people", index, "FactBreaks_%s" % fact_id))
				continue
			var point := item as Dictionary
			var point_kind := str(point.get("type", ""))
			if point_kind == "evidence_shown":
				var evidence_id := str(point.get("evidence_id", ""))
				used_evidence[evidence_id] = true
				if not evidence_ids.has(evidence_id):
					issues.append(_issue("error", "В наборе удалённая улика или показание", "people", index, "FactBreaks_%s" % fact_id))
			elif point_kind == "testimony_retold":
				var told := str(point.get("fact_id", ""))
				if not facts.has(told):
					issues.append(_issue("error", "В наборе удалённая улика или показание", "people", index, "FactBreaks_%s" % fact_id))
				elif str(owners.get(told, "")) == str(owners.get(fact_id, "")):
					issues.append(_issue("error", "Пересказ своего показания", "people", index, "FactBreaks_%s" % fact_id))
			else:
				issues.append(_issue("error", "Неизвестный вид пункта", "people", index, "FactBreaks_%s" % fact_id))
	if lie:
		for evidence_id in related:
			if not used_evidence.has(str(evidence_id)):
				issues.append(_issue("warning", "Связанная улика лжи не входит ни в один набор", "people", index, "FactEvidence_%s" % fact_id))


static func _contradiction(body: Dictionary, facts: Dictionary, owners: Dictionary, agent_index: Dictionary, issues: Array) -> void:
	var left := str(body.get("fact_a_id", ""))
	var right := str(body.get("fact_b_id", ""))
	var owner := str(owners.get(left, ""))
	var index := int(agent_index.get(owner, 0))
	var node := "FactContra_%s" % left
	if not facts.has(left) or not facts.has(right):
		issues.append(_issue("error", "Противоречие ссылается на удалённое показание", "people", index, node))
	if str(body.get("fact_a_form", "")) == "lie" and facts.has(left) and (facts[left] as Dictionary).get("is_lie", false) != true:
		issues.append(_issue("error", "Форма «Ложь» у правды", "people", index, "FactFull_%s" % left))
	if str(body.get("fact_b_form", "")) == "lie" and facts.has(right) and (facts[right] as Dictionary).get("is_lie", false) != true:
		var right_owner := str(owners.get(right, ""))
		issues.append(_issue("error", "Форма «Ложь» у правды", "people", int(agent_index.get(right_owner, 0)), "FactFull_%s" % right))
	if left == right and str(body.get("fact_a_form", "")) == str(body.get("fact_b_form", "")):
		issues.append(_issue("error", "Обе стороны противоречия одинаковы", "people", index, node))
	if str(body.get("description", "")).strip_edges() == "":
		issues.append(_issue("error", "Нет текста для блокнота", "people", index, node))
	if facts.has(left) and facts.has(right) and str(owners.get(left, "")) == str(owners.get(right, "")):
		issues.append(_issue("warning", "Противоречие между показаниями одного персонажа", "people", index, node))


static func _evidence(body: Dictionary, agent_ids: Dictionary, facts: Dictionary, evidence_ids: Dictionary, contradiction_ids: Dictionary, issues: Array) -> void:
	var evidence_id := str(body.get("id", ""))
	if str(body.get("title", "")).strip_edges() == "":
		issues.append(_issue("error", "У улики пусто название", "evidence", -1, "EvTitle_%s" % evidence_id))
	var kind := str(body.get("type", ""))
	if kind == "scene" or kind == "location":
		kind = "place"
	elif kind == "item":
		kind = "object"
	if kind == "":
		issues.append(_issue("error", "У улики пусто тип", "evidence", -1, "EvType_%s" % evidence_id))
	elif kind != "place" and kind != "object" and kind != "document":
		issues.append(_issue("error", "У улики пусто тип", "evidence", -1, "EvType_%s" % evidence_id))
	if str(body.get("short_description", "")).strip_edges() == "":
		issues.append(_issue("error", "У улики пусто подпись", "evidence", -1, "EvShort_%s" % evidence_id))
	if str(body.get("full_text", "")).strip_edges() == "":
		issues.append(_issue("error", "У улики пусто содержание", "evidence", -1, "EvFull_%s" % evidence_id))
	for fact_id in body.get("related_fact_ids", []):
		if not facts.has(str(fact_id)):
			issues.append(_issue("error", "Улика ссылается на удалённого персонажа или показание", "evidence", -1, "EvAgents_%s" % evidence_id))
	for agent_id in body.get("related_agent_ids", []):
		if not agent_ids.has(str(agent_id)):
			issues.append(_issue("error", "Улика ссылается на удалённого персонажа или показание", "evidence", -1, "EvAgents_%s" % evidence_id))
	var people: Array = body.get("related_agent_ids", []) if body.get("related_agent_ids") is Array else []
	var linked := false
	for fact_id in facts:
		var related: Array = (facts[fact_id] as Dictionary).get("related_evidence_ids", []) if (facts[fact_id] as Dictionary).get("related_evidence_ids") is Array else []
		if related.has(evidence_id):
			linked = true
	if people.is_empty() and not linked:
		issues.append(_issue("warning", "Улика без «Касается персонажей» и без связанных показаний", "evidence", -1, "EvAgents_%s" % evidence_id))
	_condition(body.get("unlock_condition"), evidence_id, agent_ids, facts, evidence_ids, contradiction_ids, issues, false)


static func _condition(cond: Variant, evidence_id: String, agent_ids: Dictionary, facts: Dictionary, evidence_ids: Dictionary, contradiction_ids: Dictionary, issues: Array, inside_or: bool) -> void:
	var node := "EvCond_%s" % evidence_id
	if cond == null:
		return
	if cond is not Dictionary:
		issues.append(_issue("error", "Пустая группа «И»/«ИЛИ»", "evidence", -1, node))
		return
	var body := cond as Dictionary
	for op in ["AND", "OR"]:
		if not body.has(op):
			continue
		var items: Array = body[op] if body[op] is Array else []
		if items.is_empty():
			issues.append(_issue("error", "Улика осталась без условия", "evidence", -1, node))
			issues.append(_issue("error", "Пустая группа «И»/«ИЛИ»", "evidence", -1, node))
			return
		for sub in items:
			_condition(sub, evidence_id, agent_ids, facts, evidence_ids, contradiction_ids, issues, op == "OR" and items.size() >= 2)
		return
	var kind := str(body.get("type", ""))
	var unsupported := kind == "pressure_on_agent" or (kind == "inconsistency_created" and str(body.get("contradiction_id", "")) == "")
	if unsupported and inside_or:
		issues.append(_issue("warning", "Неподдерживаемое условие внутри «ИЛИ»", "evidence", -1, node))
	elif unsupported:
		issues.append(_issue("error", "Неподдерживаемое условие", "evidence", -1, node))
	if kind == "inconsistency_created" and str(body.get("contradiction_id", "")) != "" and not contradiction_ids.has(str(body.get("contradiction_id", ""))):
		issues.append(_issue("error", "«После найденного противоречия» с удалённым противоречием", "evidence", -1, node))
	if body.has("agent_id") and not agent_ids.has(str(body.get("agent_id", ""))):
		issues.append(_issue("error", "Условие ссылается на удалённое", "evidence", -1, node))
	if body.has("fact_id") and not facts.has(str(body.get("fact_id", ""))):
		issues.append(_issue("error", "Условие ссылается на удалённое", "evidence", -1, node))
	if body.has("evidence_id"):
		var other := str(body.get("evidence_id", ""))
		if other == evidence_id and kind == "evidence_shown":
			issues.append(_issue("error", "Улика ждёт показа самой себя", "evidence", -1, node))
		elif not evidence_ids.has(other):
			issues.append(_issue("error", "Условие ссылается на удалённое", "evidence", -1, node))


static func _reach(facts: Dictionary, owners: Dictionary, agent_index: Dictionary, contradictions: Array, issues: Array) -> void:
	var breakable := {}
	var guard := 0
	while guard < facts.size() + 2:
		guard += 1
		var grew := false
		for fact_id in facts:
			if breakable.has(fact_id):
				continue
			var fact: Dictionary = facts[fact_id]
			if not fact.get("is_lie", false):
				continue
			var priors: Array = fact.get("requires_broken_lies", []) if fact.get("requires_broken_lies") is Array else []
			var ready := true
			for prior in priors:
				if str(prior) != "" and not breakable.has(str(prior)):
					ready = false
			if not ready:
				continue
			for raw_set in _sets(fact, contradictions):
				if _collectable(raw_set, facts, breakable):
					breakable[fact_id] = true
					grew = true
					break
		if not grew:
			break
	for fact_id in facts:
		var fact: Dictionary = facts[fact_id]
		if str(fact.get("lie_type", "")) != "must_lie" or not fact.get("is_lie", false):
			continue
		var sets := _sets(fact, contradictions)
		if sets.is_empty() or breakable.has(fact_id):
			continue
		var owner := str(owners.get(fact_id, ""))
		issues.append(_issue("error", "Ни один набор не собрать", "people", int(agent_index.get(owner, 0)), "FactBreaks_%s" % fact_id))


static func _collectable(raw_set: Variant, facts: Dictionary, breakable: Dictionary) -> bool:
	if raw_set is not Array or (raw_set as Array).is_empty():
		return false
	for item in raw_set:
		if item is not Dictionary:
			return false
		var body := item as Dictionary
		var kind := str(body.get("type", ""))
		if kind == "evidence_shown":
			continue
		if kind != "testimony_retold" or not facts.has(str(body.get("fact_id", ""))):
			return false
		var told: Dictionary = facts[str(body.get("fact_id", ""))]
		if not told.get("is_lie", false) or str(told.get("lie_type", "")) == "cannot_lie":
			continue
		if str(told.get("lie_type", "")) == "can_lie" and str(body.get("form", "")) != "truth_full":
			continue
		if not breakable.has(str(body.get("fact_id", ""))):
			return false
	return true


static func _sets(fact: Dictionary, contradictions: Array) -> Array:
	if fact.has("breaks_with") and fact.get("breaks_with") is Array:
		return fact.get("breaks_with")
	return CaseValidator.effective_sets(fact, contradictions)


static func _voice_ok(voice: String) -> bool:
	for row in ChirpVoices.VOICES:
		if str(row.get("name", "")) == voice:
			return true
	return false


static func _looks_like_fact(text: String) -> bool:
	if text.find(":") >= 0:
		var pattern := RegEx.new()
		if pattern.compile("\\d{1,2}:\\d{2}") == OK and pattern.search(text) != null:
			return true
	var digits := RegEx.new()
	if digits.compile("\\d") == OK and digits.search(text) != null:
		return true
	return false


static func _issue(level: String, text: String, tab: String, agent: int, node_name: String) -> Dictionary:
	return {
		"level": level,
		"text": text,
		"target": {"tab": tab, "agent": agent, "node": node_name},
	}
