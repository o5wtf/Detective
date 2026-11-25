extends TestCase
## Сверка CaseValidator с tools/validate_case.py.
## manifest.json заполнен запуском Python-скрипта: число ошибок и их тексты.

const FIXTURES := "res://tests/fixtures"
const REAL_CASE := "res://cases/rain_over_shadow.json"

const EXPECTED_CODE := {
	"broken_killer_missing.json": "killer_missing",
	"broken_motive_missing.json": "true_motive_missing",
	"broken_lie_text_missing.json": "lie_text_missing",
	"broken_cannot_lie_with_text.json": "lie_text_forbidden",
	"broken_pressure_order.json": "pressure_order",
	"broken_unknown_evidence.json": "fact_unknown_evidence",
	"broken_unknown_agent_condition.json": "cond_unknown_agent",
	"broken_empty_or.json": "cond_group_invalid",
	"broken_unknown_contradiction_fact.json": "contradiction_unknown_fact",
	"broken_lie_form_without_lie.json": "contradiction_lie_without_lie",
	"broken_contradiction_break_without_pair.json": "breaks_lie_no_contradiction",
	"broken_emotion.json": "emotion_unknown",
	"broken_no_prompt_background.json": "agent_field_missing",
}


func test_fixtures_match_python_manifest() -> void:
	var manifest: Dictionary = _read_json("%s/manifest.json" % FIXTURES)
	var broken_on_disk := 0
	for file_name in DirAccess.get_files_at(FIXTURES):
		if file_name.begins_with("broken_") and file_name.ends_with(".json"):
			broken_on_disk += 1
			assert_true(manifest.has(file_name), "нет записи manifest для %s" % file_name)
	assert_true(broken_on_disk >= 12 and broken_on_disk <= 15, "файлов broken_*: %d" % broken_on_disk)
	assert_eq(broken_on_disk, EXPECTED_CODE.size(), "код ожидания не покрывает все broken_*")
	for file_name in manifest:
		var entry: Dictionary = manifest[file_name]
		var raw: Dictionary = _read_json("%s/%s" % [FIXTURES, file_name])
		var errors := CaseValidator.validate(raw)
		assert_eq(errors.size(), int(entry["errors"]), file_name)
		var messages: Array = entry["messages"]
		assert_eq(errors.size(), messages.size(), file_name)
		for index in errors.size():
			assert_eq(errors[index]["message"], messages[index], "%s #%d" % [file_name, index])
		if EXPECTED_CODE.has(file_name):
			assert_eq(errors.size(), 1, file_name)
			assert_eq(errors[0]["code"], EXPECTED_CODE[file_name], file_name)
			var loaded := CaseLoader.load_case("%s/%s" % [FIXTURES, file_name])
			assert_false(loaded.ok, file_name)
			assert_true(loaded.case_data == null, file_name)
			assert_eq(loaded.errors[0]["code"], EXPECTED_CODE[file_name], file_name)


func test_valid_minimal_loads() -> void:
	var loaded := CaseLoader.load_case("%s/valid_minimal.json" % FIXTURES)
	assert_true(loaded.ok)
	assert_eq(loaded.errors.size(), 0)
	var data := loaded.case_data
	assert_eq(data.id, "minimal")
	assert_eq(data.killer_id, "a")
	assert_eq(data.agents.size(), 1)
	assert_eq(data.agents[0].facts.size(), 1)
	assert_eq(data.agents[0].facts[0].pressure_for_full, 10)
	assert_false(data.agents[0].facts[0].is_lie)
	assert_eq(data.agents[0].starting_emotion, "neutral")
	assert_eq(data.agents[0].greeting, "")
	assert_eq(data.agents[0].profanity, "never")
	assert_eq(data.agents[0].wants, "")
	assert_eq(data.agents[0].sample_lines.size(), 0)
	assert_eq(data.evidence.size(), 1)
	assert_true(data.evidence[0].unlock_condition == null)
	assert_eq(data.victory_condition, "correct_accusation")
	assert_eq(CaseValidator.warning_messages(_read_json("%s/valid_minimal.json" % FIXTURES)).size(), 0)


func test_real_case_loads() -> void:
	var loaded := CaseLoader.load_case(REAL_CASE)
	var codes: PackedStringArray = PackedStringArray()
	for item in loaded.errors:
		codes.append(str(item["code"]))
	assert_true(loaded.ok, "коды: %s" % ", ".join(codes))
	assert_eq(loaded.errors.size(), 0)
	var raw: Dictionary = _read_json(REAL_CASE)
	var data := loaded.case_data
	assert_eq(data.agents.size(), (raw["agents"] as Array).size())
	assert_eq(data.evidence.size(), (raw["evidence"] as Array).size())
	assert_eq(data.contradictions.size(), (raw["contradictions"] as Array).size())
	assert_eq(data.motive_options.size(), (raw["motive_options"] as Array).size())
	assert_eq(data.method_options.size(), (raw["method_options"] as Array).size())
	var raw_facts := 0
	for agent in raw["agents"]:
		raw_facts += (agent["facts"] as Array).size()
	var parsed_facts := 0
	for agent in data.agents:
		assert_false(agent.id.is_empty())
		parsed_facts += agent.facts.size()
		for fact in agent.facts:
			assert_false(fact.id.is_empty())
			assert_false(fact.content_basic.is_empty())
			assert_false(fact.content_full.is_empty())
	assert_eq(parsed_facts, raw_facts)
	assert_eq(data.fact_by_id.size(), raw_facts)
	assert_eq(CaseValidator.validate(raw).size(), 0)
	var by_id := {}
	for agent in data.agents:
		by_id[agent.id] = agent
	assert_eq((by_id["irina_morozova"] as CaseData.Agent).greeting, "Следователь. Наконец-то. Давайте без соболезнований, у меня мало времени")
	assert_eq((by_id["arkady_volkov"] as CaseData.Agent).profanity, "sometimes")
	assert_eq((by_id["alina_kuznetsova"] as CaseData.Agent).profanity, "sometimes")
	assert_eq((by_id["mira_belova"] as CaseData.Agent).profanity, "never")
	assert_eq((by_id["pavel_sokolov"] as CaseData.Agent).sample_lines.size(), 3)
	assert_eq(CaseValidator.warning_messages(raw).size(), 0)


func test_broken_json_is_reported() -> void:
	var loaded := CaseLoader.load_case("%s/invalid_syntax.json" % FIXTURES)
	assert_false(loaded.ok)
	assert_true(loaded.case_data == null)
	assert_eq(loaded.errors.size(), 1)
	assert_eq(loaded.errors[0]["code"], "json_parse")
	var message := str(loaded.errors[0]["message"])
	assert_true(message.contains("JSON"), message)
	assert_true(message.contains("строка"), message)


func test_json_array_is_reported() -> void:
	var loaded := CaseLoader.load_case("%s/not_an_object.json" % FIXTURES)
	assert_false(loaded.ok)
	assert_eq(loaded.errors[0]["code"], "json_not_object")
	assert_true(str(loaded.errors[0]["message"]).contains("объектом"))


func test_missing_file_is_reported() -> void:
	var loaded := CaseLoader.load_case("%s/no_such_case.json" % FIXTURES)
	assert_false(loaded.ok)
	assert_true(loaded.case_data == null)
	assert_eq(loaded.errors[0]["code"], "file_not_found")


func test_more_rules_and_warnings() -> void:
	var minimal: Dictionary = _read_json("%s/valid_minimal.json" % FIXTURES)
	var self_ref: Dictionary = minimal.duplicate(true)
	self_ref["evidence"][0]["unlock_condition"] = {"type": "evidence_shown", "evidence_id": "e1"}
	_expect_code(self_ref, "cond_self_evidence")
	var bad_gte: Dictionary = minimal.duplicate(true)
	bad_gte["evidence"][0]["unlock_condition"] = {
		"type": "pressure_on_agent", "agent_id": "a", "gte": 140,
	}
	assert_eq(CaseValidator.validate(bad_gte).size(), 0)
	var unknown_type: Dictionary = minimal.duplicate(true)
	unknown_type["evidence"][0]["unlock_condition"] = {"type": "phase_of_moon"}
	_expect_code(unknown_type, "cond_unknown_type")
	var unknown_evidence: Dictionary = minimal.duplicate(true)
	unknown_evidence["evidence"][0]["unlock_condition"] = {
		"type": "evidence_shown", "evidence_id": "missing", "agent_id": "ghost",
	}
	var unknown_errors := CaseValidator.validate(unknown_evidence)
	assert_eq(unknown_errors.size(), 2)
	assert_eq(unknown_errors[0]["code"], "cond_unknown_evidence")
	assert_eq(unknown_errors[1]["code"], "cond_unknown_agent")
	var valid_condition: Dictionary = minimal.duplicate(true)
	valid_condition["evidence"][0]["unlock_condition"] = {
		"OR": [
			{"type": "dialogue_with", "agent_id": "a"},
			{"AND": [
				{"type": "pressure_on_agent", "agent_id": "a", "gte": 0},
				{"type": "inconsistency_created"},
			]},
		],
	}
	assert_eq(CaseValidator.validate(valid_condition).size(), 0)
	var one_way: Dictionary = minimal.duplicate(true)
	one_way["evidence"][0]["related_fact_ids"] = ["f1"]
	assert_eq(CaseValidator.validate(one_way).size(), 0)
	var bad_profanity: Dictionary = minimal.duplicate(true)
	bad_profanity["agents"][0]["profanity"] = "always"
	_expect_code(bad_profanity, "agent_profanity")
	var warnings := CaseValidator.warning_messages(one_way)
	assert_eq(warnings.size(), 1)
	assert_true(warnings[0].contains("не ссылается"), warnings[0])


func test_parse_matches_load_and_keeps_hidden_keys() -> void:
	var raw := _read_json(REAL_CASE)
	var loaded := CaseLoader.load_case(REAL_CASE)
	var parsed := CaseLoader.parse(raw)
	assert_true(parsed.ok)
	assert_eq(parsed.case_data.id, loaded.case_data.id)
	assert_eq(parsed.case_data.agents.size(), loaded.case_data.agents.size())
	assert_eq(parsed.case_data.fact_by_id.size(), loaded.case_data.fact_by_id.size())
	var saved := CaseLoader.save_document(raw)
	assert_eq(CaseValidator.validate(saved).size(), 0)
	for key in ["background", "is_key", "starting_pressure", "tags", "breaks_with", "breaks_lie_on", "editor"]:
		assert_eq(_key_count(saved, key), _key_count(raw, key), key)
	assert_true(_key_count(raw, "background") > 0)
	assert_true(_key_count(raw, "breaks_with") > 0)
	assert_true(_key_count(raw, "is_key") > 0)


func test_background_and_unlinked_key_evidence_load() -> void:
	var minimal: Dictionary = _read_json("%s/valid_minimal.json" % FIXTURES)
	minimal["agents"][0].erase("background")
	assert_eq(CaseValidator.validate(minimal).size(), 0)
	assert_true(CaseLoader.parse(minimal).ok)
	var unlinked := CaseLoader.load_case("%s/valid_unlinked_key.json" % FIXTURES)
	assert_true(unlinked.ok, str(unlinked.errors))
	assert_true(unlinked.case_data.evidence[0].is_key)


func test_filler_lines_and_profanity_survive_the_round_trip() -> void:
	var raw: Dictionary = _read_json("%s/valid_minimal.json" % FIXTURES).duplicate(true)
	raw["agents"][0]["filler_lines"] = ["Раз", "Два", "Три", "Лишняя"]
	raw["agents"][0]["profanity"] = "sometimes"
	raw["secret_note"] = "не для движка"
	var saved := CaseLoader.save_document(raw)
	assert_eq(str(saved.get("secret_note", "")), "не для движка")
	assert_eq((saved["agents"][0]["filler_lines"] as Array).size(), 4)
	var loaded := CaseLoader.parse(saved)
	assert_true(loaded.ok)
	var agent: CaseData.Agent = loaded.case_data.agents[0]
	assert_eq(agent.filler_lines.size(), 3)
	assert_eq(agent.filler_lines[0], "Раз")
	assert_eq(agent.filler_lines[2], "Три")
	assert_eq(FillerBank.lines_for(agent)[0], "Раз")
	assert_eq(agent.profanity, "sometimes")
	for value in ["never", "sometimes", "often"]:
		var again: Dictionary = saved.duplicate(true)
		again["agents"][0]["profanity"] = value
		var back := CaseLoader.parse(CaseLoader.save_document(again))
		assert_true(back.ok, value)
		assert_eq(back.case_data.agents[0].profanity, value)
	var cleared: Dictionary = saved.duplicate(true)
	(cleared["agents"][0] as Dictionary).erase("filler_lines")
	(cleared["agents"][0] as Dictionary).erase("profanity")
	var plain := CaseLoader.parse(CaseLoader.save_document(cleared))
	assert_eq(plain.case_data.agents[0].profanity, "never")
	assert_eq(plain.case_data.agents[0].filler_lines.size(), 0)
	assert_eq(FillerBank.lines_for(plain.case_data.agents[0]), FillerBank.standard_lines())
	var empty_lines: Dictionary = saved.duplicate(true)
	empty_lines["agents"][0]["filler_lines"] = []
	var empty_agent := CaseLoader.parse(CaseLoader.save_document(empty_lines)).case_data.agents[0]
	assert_eq(FillerBank.lines_for(empty_agent), FillerBank.standard_lines())
	var bad: Dictionary = saved.duplicate(true)
	bad["agents"][0]["profanity"] = "always"
	var rejected := CaseLoader.parse(bad)
	assert_false(rejected.ok)
	assert_eq(rejected.errors[0]["code"], "agent_profanity")
	assert_true(rejected.case_data == null)


func _key_count(value: Variant, key: String) -> int:
	var count := 0
	if value is Dictionary:
		var body := value as Dictionary
		if body.has(key):
			count += 1
		for child in body.values():
			count += _key_count(child, key)
	elif value is Array:
		for child in value:
			count += _key_count(child, key)
	return count


func _expect_code(raw: Dictionary, code: String) -> void:
	var errors := CaseValidator.validate(raw)
	assert_eq(errors.size(), 1, code)
	assert_eq(errors[0]["code"], code)


func _read_json(path: String) -> Dictionary:
	var parser := JSON.new()
	var parse_code := parser.parse(FileAccess.get_file_as_string(path))
	assert_eq(parse_code, OK, path)
	return parser.data as Dictionary
