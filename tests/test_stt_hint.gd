extends TestCase

const FIXTURE := "res://tests/fixtures/turn_flow.json"


func test_hint_uses_known_words_and_skips_hidden_ones() -> void:
	var loaded := CaseLoader.load_case(FIXTURE)
	assert_true(loaded.ok)
	var case_data: CaseData = loaded.case_data
	var state := GameState.new()
	var hint := SttHint.build(case_data, state, "a", "Я видел его там поздно вечером и ещё много лишних слов " + "x".repeat(300))
	assert_true(hint.contains("только если они действительно звучат"))
	assert_true(hint.contains("Аня"))
	assert_true(hint.contains("Борис"))
	assert_true(hint.contains("Учебный ход"))
	assert_false(hint.contains("Записка"))
	assert_false(hint.contains("Заметки автора"))
	assert_false(hint.contains("Меня там не было"))
	assert_false(hint.contains("truth_timeline"))
	state.unlocked_evidence.append("ev")
	var open_hint := SttHint.build(case_data, state, "a", "")
	assert_true(open_hint.contains("Записка"))
	assert_true(open_hint.contains("документ"))
	assert_eq(SttHint.for_turn("parakeet", case_data, state, "a", "Записка"), "")
	assert_eq(SttHint.build(null, state, "a", ""), "")


func test_empty_hint_leaves_the_request_body_unchanged() -> void:
	var wav := VoiceAudio.wav_bytes(VoiceAudio.tone(160, 1000), 16000)
	var plain := JSON.stringify(GeminiStt.build_body(wav, "MINIMAL"))
	var hinted := JSON.stringify(GeminiStt.build_body(wav, "MINIMAL", "Аня, Борис"))
	assert_false(plain.contains("Аня"))
	assert_true(hinted.contains("Аня, Борис"))
	assert_true(hinted.contains(GameLanguage.text("stt_prompt")))
	var secret := "СекретнаяПодсказка"
	var line := GeminiStt.log_line("gemini-3.5-flash-lite", 200, "{\"usageMetadata\":{\"promptTokenCount\":3,\"candidatesTokenCount\":1}}")
	assert_false(line.contains(secret))
	assert_true(line.contains("prompt_tokens=3"))

