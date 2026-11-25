class_name BreakSets
extends RefCounted
## Наборы breaks_with: перевод старых дел, проверка «И/ИЛИ», сомнение.
## Движок подставляет лжеца сам. Слом решает RulesEngine, не модель.


const DEFENSE := "Защищайся в своей манере: если это сказал тот, к кому ты плохо относишься (см. отношения), — он наговаривает; если свидетель сам врёт — «а вы ему верите?». Правду не признавай."
const HOLD := "Это тебя не опровергает: держись своей версии, можешь оспорить, объяснить или уйти от ответа. Ничего сверх блока ЧТО ТЫ МОЖЕШЬ СКАЗАТЬ не признавай."


static func sets_of(case_data: CaseData, fact: CaseData.Fact) -> Array:
	if fact == null:
		return []
	if fact.breaks_with_explicit:
		return fact.breaks_with
	return translate(fact, case_data.contradictions if case_data != null else [])


static func translate(fact: CaseData.Fact, contradictions: Array) -> Array:
	var sets: Array = []
	if fact == null:
		return sets
	var modes := _modes(fact.breaks_lie_on)
	if modes.has("evidence"):
		for evidence_id in fact.related_evidence_ids:
			sets.append([{"type": "evidence_shown", "evidence_id": evidence_id}])
	if modes.has("contradiction"):
		for contradiction in contradictions:
			if contradiction == null:
				continue
			var partner := _partner(contradiction, fact.id)
			if partner.is_empty():
				continue
			var item := {"type": "testimony_retold", "fact_id": str(partner["fact_id"])}
			if str(partner["form"]) == "truth_full":
				item["form"] = "truth_full"
			sets.append([item])
	return sets


static func set_met(case_data: CaseData, state: GameState, fact: CaseData.Fact, items: Array) -> bool:
	if items.is_empty():
		return false
	return Conditions.evaluate({"AND": items}, state, ctx_for(case_data, state, fact))


static func holds(case_data: CaseData, state: GameState, fact: CaseData.Fact) -> bool:
	var sets := sets_of(case_data, fact)
	var arms: Array = []
	for items in sets:
		if items is not Array or (items as Array).is_empty():
			continue
		arms.append({"AND": items})
	if arms.is_empty():
		return false
	return Conditions.evaluate({"OR": arms}, state, ctx_for(case_data, state, fact))


static func ctx_for(case_data: CaseData, state: GameState, fact: CaseData.Fact) -> Dictionary:
	var liar := ""
	if case_data != null:
		liar = str(case_data.fact_owner.get(fact.id, ""))
	var counted: Array = []
	if state != null:
		for key in state.retold:
			var parts := str(key).split("|")
			if parts.size() < 3 or parts[0] != liar:
				continue
			if not witness_counts(case_data, state, fact, parts[1]):
				continue
			counted.append({"fact_id": parts[1], "form": parts[2]})
	return {"agent_id": liar, "retold": counted}


static func witness_counts(case_data: CaseData, state: GameState, target: CaseData.Fact, witness_fact_id: String) -> bool:
	if target == null or target.related_evidence_ids.is_empty() or case_data == null:
		return true
	var owner := str(case_data.fact_owner.get(witness_fact_id, ""))
	var agent: CaseData.Agent = case_data.agent_by_id.get(owner) as CaseData.Agent
	if agent == null:
		return true
	for fact in agent.facts:
		if fact.id == witness_fact_id or not fact.is_lie:
			continue
		if state != null and state.broken_lies.has(fact.id):
			continue
		if fact.related_evidence_ids.is_empty():
			continue
		for evidence_id in fact.related_evidence_ids:
			if target.related_evidence_ids.has(evidence_id):
				return false
	return true


static func doubt_report(case_data: CaseData, state: GameState, fact: CaseData.Fact) -> Dictionary:
	var report := {"active": false, "line": "", "evidence": [], "retells": []}
	if fact == null or state == null or state.broken_lies.has(fact.id):
		return report
	var liar := str(case_data.fact_owner.get(fact.id, "")) if case_data != null else ""
	var evidence_ids := {}
	var retell_ids := {}
	for items in sets_of(case_data, fact):
		if items is not Array:
			continue
		for item in items:
			if item is not Dictionary:
				continue
			var body := item as Dictionary
			if str(body.get("type", "")) == "evidence_shown":
				evidence_ids[str(body.get("evidence_id", ""))] = true
			elif str(body.get("type", "")) == "testimony_retold":
				retell_ids[str(body.get("fact_id", ""))] = true
	var bits: PackedStringArray = PackedStringArray()
	var retells: Array = []
	for key in state.retold:
		var parts := str(key).split("|")
		if parts.size() < 3 or parts[0] != liar or not retell_ids.has(parts[1]):
			continue
		var counted := witness_counts(case_data, state, fact, parts[1])
		var witness: CaseData.Fact = case_data.fact_by_id.get(parts[1]) as CaseData.Fact
		var text := Notebook.text_for(witness, parts[2])
		var speaker := _speaker(case_data, str(case_data.fact_owner.get(parts[1], "")))
		retells.append({"speaker": speaker, "text": text, "counted": counted, "fact_id": parts[1], "form": parts[2]})
		bits.append("слова %s «%s»" % [speaker, text])
	var titles: Array = []
	for evidence_id in evidence_ids:
		if not _shown(state, str(evidence_id), liar):
			continue
		var title := str(evidence_id)
		if case_data != null and case_data.evidence_by_id.has(evidence_id):
			title = (case_data.evidence_by_id[evidence_id] as CaseData.EvidenceItem).title
		titles.append(title)
		bits.append("улику «%s»" % title)
	var stored_blocked := false
	for row in retells:
		if row.get("counted") != true:
			stored_blocked = true
	var any_done := false
	for items in sets_of(case_data, fact):
		if items is not Array:
			continue
		for item in items:
			if item is Dictionary and Conditions.evaluate(item, state, ctx_for(case_data, state, fact)):
				any_done = true
	report["evidence"] = titles
	report["retells"] = retells
	report["active"] = any_done or stored_blocked
	if report["active"] and not bits.is_empty():
		report["line"] = "Тебе уже предъявили: %s." % "; ".join(bits)
	elif report["active"]:
		report["line"] = "Тебе уже предъявили улику или слова, но набор ещё не собран."
	return report


static func evidence_in_set(case_data: CaseData, fact: CaseData.Fact, evidence_id: String) -> bool:
	for items in sets_of(case_data, fact):
		if items is not Array:
			continue
		for item in items:
			if item is Dictionary and str((item as Dictionary).get("type", "")) == "evidence_shown" and str((item as Dictionary).get("evidence_id", "")) == evidence_id:
				return true
	return false


static func evidence_completes(case_data: CaseData, state: GameState, fact: CaseData.Fact, evidence_id: String) -> bool:
	if not evidence_in_set(case_data, fact, evidence_id):
		return false
	for items in sets_of(case_data, fact):
		if items is not Array or (items as Array).is_empty():
			continue
		var uses := false
		var ready := true
		for item in items:
			if item is not Dictionary:
				ready = false
				continue
			var body := item as Dictionary
			if str(body.get("type", "")) == "evidence_shown" and str(body.get("evidence_id", "")) == evidence_id:
				uses = true
			elif not Conditions.evaluate(body, state, ctx_for(case_data, state, fact)):
				ready = false
		if uses and ready:
			return true
	return false


static func event_note(title: String, quote: String, verdict: String) -> String:
	var head := "Следователь предъявляет улику «%s» против твоих слов «%s». Итог проверки: %s." % [title, quote, verdict]
	if verdict == "refuted" or verdict == "completed":
		return head + " Признай только то, что теперь есть в блоке ЧТО ТЫ МОЖЕШЬ СКАЗАТЬ."
	return head + " " + HOLD


static func retell_key(agent_id: String, fact_id: String, form: String) -> String:
	return "%s|%s|%s" % [agent_id, fact_id, form]


static func _speaker(case_data: CaseData, agent_id: String) -> String:
	if case_data == null:
		return agent_id
	var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
	if agent == null or agent.name == "":
		return agent_id
	return agent.name


static func _shown(state: GameState, evidence_id: String, agent_id: String) -> bool:
	var agents: Array = state.shown.get(evidence_id, [])
	return agents.has(agent_id)


static func _partner(contradiction: CaseData.Contradiction, fact_id: String) -> Dictionary:
	var pairs := [
		[contradiction.fact_a_id, contradiction.fact_a_form, contradiction.fact_b_id, contradiction.fact_b_form],
		[contradiction.fact_b_id, contradiction.fact_b_form, contradiction.fact_a_id, contradiction.fact_a_form],
	]
	for pair in pairs:
		if str(pair[0]) != fact_id or str(pair[1]) != "lie":
			continue
		var form := str(pair[3])
		if form != "truth" and form != "truth_full":
			continue
		return {"fact_id": str(pair[2]), "form": form}
	return {}


static func _modes(value: Variant) -> Dictionary:
	var found := {}
	if value == null:
		return found
	if value is String:
		found[value] = true
		return found
	if value is Array or value is PackedStringArray:
		for item in value:
			found[str(item)] = true
	return found
