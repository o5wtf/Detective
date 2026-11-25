extends TestCase


func test_greeting_is_once_and_does_not_count_as_a_turn() -> void:
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var turn := Game.state.turn
	var text := Game.add_greeting("irina_morozova")
	assert_eq(text, "Следователь. Наконец-то. Давайте без соболезнований, у меня мало времени")
	assert_eq(Game.state.turn, turn)
	assert_false(Game.state.talked_to.has("irina_morozova"))
	assert_false(Conditions.evaluate({"type": "dialogue_with", "agent_id": "irina_morozova"}, Game.state))
	var dialogue: DialogueState = Game._dialogues["irina_morozova"]
	assert_eq(dialogue.messages.size(), 1)
	assert_eq(str(dialogue.messages[0]["role"]), "agent")
	assert_eq(str(dialogue.messages[0]["text"]), text)
	assert_eq(Game.add_greeting("irina_morozova"), "")
	var continued := Game.continue_case("res://cases/rain_over_shadow.json")
	assert_true(continued.ok, str(continued.get("reason", "")))
	var kept: DialogueState = Game._dialogues["irina_morozova"]
	assert_eq(kept.messages.size(), 1)
	assert_eq(Game.add_greeting("irina_morozova"), "")
	assert_false(Game.state.talked_to.has("irina_morozova"))
	Game.is_busy = true
	assert_eq(Game.add_greeting("arkady_volkov"), "")
	assert_false(Game.state.talked_to.has("arkady_volkov"))
	Game.is_busy = false
	assert_eq(Game.add_greeting("arkady_volkov"), "Здравствуйте. Ну, давайте, спрашивайте. Мне скрывать нечего, ну вы понимаете")


func test_greeting_is_in_the_feed_and_uses_the_prefetch_voice() -> void:
	assert_true(Game.open_case("res://cases/rain_over_shadow.json").ok)
	var was_enabled := Speaker.enabled
	Speaker.enabled = false
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/interrogation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	screen.open_agent("mira_belova")
	var feed: Array = screen._feeds["mira_belova"]
	assert_eq(feed.size(), 1)
	assert_eq(str(feed[0]["text"]), "Следователь… Садитесь. Я так и думала, что вы начнёте с меня")
	assert_false(Game.state.talked_to.has("mira_belova"))
	var agent: CaseData.Agent = Game.case_data.agent_by_id["mira_belova"]
	var jobs := GreetingPlan.jobs(Game.case_data, true, true)
	var expected: Dictionary = {}
	for job in jobs:
		if str(job.get("text", "")) == SpeechText.clean(agent.greeting):
			expected = job
	assert_false(expected.is_empty())
	assert_eq(str(expected.get("style", "missing")), "")
	var previous: Node = Speaker.backend
	var spy := _Spy.new()
	Speaker.backend = spy
	Speaker.enabled = true
	Game.speech_style = "angry"
	Speaker.speak_greeting("mira_belova", agent.greeting)
	assert_eq(spy.line_id, "greet:%s:mira_belova" % Game.state.case_id)
	assert_eq(spy.text, str(expected["text"]))
	assert_eq(spy.voice, str(expected["voice"]))
	assert_eq(spy.style, "")
	Speaker._on_started(spy.line_id)
	assert_true(Speaker.speaking)
	Speaker._remember_retry(spy.line_id, spy.text, spy.voice, "")
	assert_eq(str(Speaker.retry_line.get("agent_id", "")), "mira_belova")
	assert_eq(Speaker._agent_from_line("case:arkady_volkov:3"), "arkady_volkov")
	Speaker.enabled = was_enabled
	Speaker.backend = previous
	Speaker.stop_and_clear()
	Speaker.dismiss_retry()
	Game.speech_style = ""
	spy.free()
	screen.free()


class _Spy:
	extends SpeechBackend

	var line_id: String = ""
	var text: String = ""
	var voice: String = ""
	var style: String = ""

	func speak(next_id: String, next_text: String, voice_hint: String = "", next_style: String = "") -> void:
		line_id = next_id
		text = next_text
		voice = voice_hint
		style = next_style

	func stop() -> void:
		pass
