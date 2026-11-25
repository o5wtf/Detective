extends TestCase

const SECRET := "unit-test-key"


func test_config_key_order() -> void:
	var user_key := LLMConfig.from_sources(_cfg("user-key", "model-from-user"), "env-key", _cfg("dev-key", "model-from-dev"), true)
	assert_eq(user_key.key_source, "user")
	assert_true(user_key.api_key == "user-key", "ключ из user://")
	assert_eq(user_key.dialogue_model, "model-from-user")
	var env_key := LLMConfig.from_sources(_cfg("", "model-from-user"), "env-key", _cfg("dev-key", "model-from-dev"), true)
	assert_eq(env_key.key_source, "env")
	assert_true(env_key.api_key == "env-key", "ключ из окружения")
	assert_eq(env_key.dialogue_model, "model-from-user")
	var dev_key := LLMConfig.from_sources("", "", _cfg("dev-key", "model-from-dev"), true)
	assert_eq(dev_key.key_source, "dev")
	assert_true(dev_key.api_key == "dev-key", "ключ из dev.cfg")
	assert_eq(dev_key.dialogue_model, "model-from-dev")
	var release := LLMConfig.from_sources("", "", _cfg("dev-key", "model-from-dev"), false)
	assert_eq(release.key_source, "none")
	assert_eq(release.api_key, "")
	assert_eq(release.dialogue_model, LLMConfig.DEFAULT_DIALOGUE_MODEL)
	var gemini := LLMConfig.create_client(user_key)
	assert_true(gemini is GeminiClient)
	gemini.free()
	user_key.provider = "mock"
	var mock := LLMConfig.create_client(user_key)
	assert_true(mock is MockLLMClient)
	mock.free()


func test_request_body_uses_config_models_and_schema() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"да\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "да")
	assert_eq(transport.seen.size(), 1)
	var call: Dictionary = transport.seen[0]
	assert_true(str(call["url"]).contains("/dialogue-model:generateContent"), "адрес модели")
	assert_false(str(call["url"]).contains(SECRET), "ключ в адресе")
	var headers: Dictionary = call["headers"]
	assert_eq(headers["Content-Type"], "application/json")
	assert_true(headers["x-goog-api-key"] == SECRET, "заголовок ключа")
	var body: Dictionary = JSON.parse_string(call["body"])
	assert_true(body.has("systemInstruction"))
	assert_eq(body["systemInstruction"]["parts"][0]["text"], "система")
	assert_eq(body["contents"][0]["role"], "user")
	assert_eq(body["contents"][0]["parts"][0]["text"], "вопрос")
	var generation: Dictionary = body["generationConfig"]
	assert_eq(generation["responseMimeType"], "application/json")
	assert_true(generation.has("responseJsonSchema"))
	assert_eq(generation["responseJsonSchema"]["required"], ["reply"])
	assert_eq(generation["thinkingConfig"]["thinkingLevel"], "MINIMAL")
	assert_eq(generation["temperature"], 0.9)
	assert_eq(generation["maxOutputTokens"], 2048)
	var safety: Array = body["safetySettings"]
	assert_eq(safety.size(), 4)
	assert_eq(safety[0]["threshold"], "BLOCK_ONLY_HIGH")
	assert_false(JSON.stringify(result).contains(SECRET), "ключ попал в результат")
	client.free()


func test_summary_model_and_thought_parts() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"кратко\"}", true))
	var request := _request("summary")
	var result: Dictionary = await client.generate(request)
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "кратко")
	assert_false(result["raw_text"].contains("скрытые рассуждения"))
	assert_true(str(transport.seen[0]["url"]).contains("/dialogue-model:generateContent"))
	client.free()


func test_finish_and_block_reasons() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_candidate("{\"reply\":\"x\"}", "MAX_TOKENS"))
	transport.push(_candidate("{\"reply\":\"после лимита\"}", "STOP"))
	var truncated: Dictionary = await client.generate(_request("dialogue"))
	assert_true(truncated["ok"])
	assert_eq(truncated["json"]["reply"], "после лимита")
	assert_eq(transport.seen.size(), 2)
	transport.push(_candidate("{\"reply\":\"x\"}", "SAFETY"))
	var safety: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(safety["error"], "blocked")
	transport.push(_blocked_prompt())
	var blocked: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(blocked["error"], "blocked")
	client.free()


func test_malformed_json_and_schema_fallback() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push({"ok": true, "status": 200, "body": "not-json", "headers": {}, "error": ""})
	var broken: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(broken["error"], "bad_response")
	transport.push(_candidate("not-json-object", "STOP"))
	var broken_text: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(broken_text["error"], "bad_response")
	transport.push(_status(400, "{\"error\":{\"message\":\"Invalid JSON payload. Unknown name responseJsonSchema\"}}"))
	transport.push(_ok("{\"reply\":\"через старую схему\"}"))
	var switched: Dictionary = await client.generate(_request("dialogue"))
	assert_true(switched["ok"])
	var first: Dictionary = JSON.parse_string(transport.seen[2]["body"])
	var second: Dictionary = JSON.parse_string(transport.seen[3]["body"])
	assert_true(first["generationConfig"].has("responseJsonSchema"))
	assert_false(first["generationConfig"].has("responseSchema"))
	assert_true(second["generationConfig"].has("responseSchema"))
	assert_false(second["generationConfig"].has("responseJsonSchema"))
	client.free()


func test_invalid_key_statuses() -> void:
	for status in [400, 401, 403]:
		var client := await _client()
		var transport: FakeTransport = client._transport
		transport.push(_status(status, "{\"error\":{\"status\":\"API_KEY_INVALID\",\"message\":\"API key not valid. Please pass a valid API key.\"}}"))
		var result: Dictionary = await client.generate(_request("dialogue"))
		assert_false(result["ok"], "статус %d" % status)
		assert_eq(result["error"], "auth", "статус %d" % status)
		assert_true(str(result["message"]).contains("Ключ"), "понятный текст")
		assert_false(JSON.stringify(result).contains(SECRET), "ключ попал в результат")
		assert_eq(transport.seen.size(), 1, "без повторов")
		client.free()


func test_missing_key_does_not_call_network() -> void:
	var client := await _client("")
	var transport: FakeTransport = client._transport
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "auth")
	assert_true(str(result["message"]).contains("Не задан ключ"))
	assert_eq(transport.seen.size(), 0)
	client.free()


func test_rate_limit_retries_the_same_model() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(429, "{\"error\":{\"message\":\"quota\",\"details\":[{\"@type\":\"type.googleapis.com/google.rpc.RetryInfo\",\"retryDelay\":\"0.4s\"}]}}"))
	transport.push(_ok("{\"reply\":\"та же модель\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "та же модель")
	assert_eq(result["model"], "dialogue-model")
	assert_eq(client.waits, [0.4])
	assert_eq(transport.seen.size(), 2)
	assert_true(str(transport.seen[0]["url"]).contains("/dialogue-model:"))
	assert_true(str(transport.seen[1]["url"]).contains("/dialogue-model:"))
	assert_false(str(transport.seen[1]["url"]).contains("gemini-3.5-flash:"))
	client.free()


func test_rate_limit_exhausted_is_rate_limited() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	for _i in 3:
		transport.push(_status(429, "{}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "rate_limited")
	assert_eq(transport.seen.size(), 3)
	assert_true(str(result["message"]).contains("dialogue-model"))
	client.free()


func test_server_error_retries_twice() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(500, ""))
	transport.push(_status(500, ""))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "server")
	assert_eq(transport.seen.size(), 2)
	assert_eq(client.waits, [GeminiClient.SERVER_PAUSE_S])
	assert_true(str(transport.seen[1]["url"]).contains("/dialogue-model:"))
	transport.push(_status(500, ""))
	transport.push(_ok("{\"reply\":\"после сбоя\"}"))
	var recovered: Dictionary = await client.generate(_request("dialogue"))
	assert_true(recovered["ok"])
	client.free()


func test_timeout_and_offline() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"})
	transport.push(_ok("{\"reply\":\"успел\"}"))
	var timed_out: Dictionary = await client.generate(_request("dialogue"))
	assert_true(timed_out["ok"])
	assert_eq(timed_out["model"], "dialogue-model")
	assert_eq(transport.seen.size(), 2)
	assert_true(str(transport.seen[1]["url"]).contains("/dialogue-model:"))
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"})
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"})
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"})
	var offline: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(offline["error"], "offline")
	assert_eq(str(offline["message"]), UiStrings.NO_LINK)
	assert_eq(transport.seen.size(), 5)
	assert_eq(client.waits, [1.0, 1.0, 3.0])
	client.free()


func test_no_pause_between_requests() -> void:
	var client := await _client()
	client.min_interval_s = 5.0
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"раз\"}"))
	transport.push(_ok("{\"reply\":\"два\"}"))
	var first: Dictionary = await client.generate(_request("dialogue"))
	var second: Dictionary = await client.generate(_request("dialogue"))
	assert_true(first["ok"] and second["ok"])
	assert_eq(client.waits.size(), 0)
	client.free()


func test_only_one_request_in_flight() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"после очереди\"}"))
	client._busy = true
	var waiting: Variant = client.call("generate", _request("dialogue"))
	assert_eq(transport.calls, 0, "второй запрос не стартовал, пока первый в полёте")
	client._busy = false
	(Engine.get_main_loop() as SceneTree).process_frame.connect(func() -> void: client._released.emit(), CONNECT_ONE_SHOT)
	var result: Dictionary = await waiting
	assert_true(result["ok"])
	assert_eq(transport.calls, 1)
	assert_false(JSON.stringify(result).contains(SECRET), "ключ попал в результат")
	await (Engine.get_main_loop() as SceneTree).process_frame
	client.free()


func test_lite_shape_is_accepted() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	var fenced := "```json\n{\"player_tone\": \"1\", \"reply\": \"Я ничего не видел.\", \"remark\": \"отводит взгляд\", \"emotion\": \"Neutral\"}\n```"
	var parts: Array = [
		{"thought": true, "text": "скрытые рассуждения"},
		{"text": fenced, "thoughtSignature": "sig"},
	]
	var payload := {"candidates": [{"content": {"parts": parts}, "finishReason": "MAX_TOKENS"}]}
	var scripted := {"ok": true, "status": 200, "body": JSON.stringify(payload), "headers": {}, "error": ""}
	transport.push(scripted)
	transport.push(scripted.duplicate(true))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "Я ничего не видел.")
	assert_eq(result["json"]["player_tone"], 1)
	assert_eq(result["json"]["emotion"], "neutral")
	assert_false(str(result["raw_text"]).contains("скрытые рассуждения"))
	client.free()


func test_truncated_json_retries_without_thinking() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_candidate("{", "MAX_TOKENS"))
	transport.push(_ok("{\"reply\":\"после повтора\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "после повтора")
	var retry: Dictionary = JSON.parse_string(transport.seen[1]["body"])
	assert_eq(retry["generationConfig"]["thinkingConfig"]["thinkingLevel"], "MINIMAL")
	assert_true(int(retry["generationConfig"]["maxOutputTokens"]) >= LLMConfig.REPLY_MAX_OUTPUT_TOKENS)
	client.free()


func test_overloaded_retries_same_model_and_missing_model_stops() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(503, "{\"error\":{\"message\":\"high demand\",\"status\":\"UNAVAILABLE\",\"details\":[{\"@type\":\"type.googleapis.com/google.rpc.RetryInfo\",\"retryDelay\":\"0.2s\"}]}}"))
	transport.push(_ok("{\"reply\":\"есть\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["model"], "dialogue-model")
	assert_true(str(transport.seen[0]["url"]).contains("/dialogue-model:"))
	assert_true(str(transport.seen[1]["url"]).contains("/dialogue-model:"))
	transport.push(_status(404, "{\"error\":{\"message\":\"no longer available to new users\",\"status\":\"NOT_FOUND\"}}"))
	var missing: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(missing["error"], "unavailable")
	assert_eq(transport.seen.size(), 3)
	client.free()


func test_plain_400_is_not_an_auth_error() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(400, "{\"error\":{\"status\":\"INVALID_ARGUMENT\",\"message\":\"thinkingLevel is not supported\"}}"))
	transport.push(_ok("{\"reply\":\"без рассуждений\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	var retry: Dictionary = JSON.parse_string(transport.seen[1]["body"])
	assert_eq(retry["generationConfig"]["thinkingConfig"]["thinkingLevel"], "LOW")
	assert_eq(transport.seen.size(), 2)
	client.free()


func test_timeout_names_the_model() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	for _i in 3:
		transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"})
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "timeout")
	assert_eq(transport.seen.size(), 3)
	assert_eq(str(result["message"]), UiStrings.NO_LINK)
	assert_false(str(result["message"]).contains("Пробовали"))
	assert_eq(client.waits, [1.0, 3.0])
	assert_eq(float(transport.seen[0]["timeout"]), GeminiClient.ATTEMPT_TIMEOUT_S)
	client.free()


func test_minimal_thinking_falls_back_to_low_and_is_remembered() -> void:
	var client := await _client()
	client.thinking_level = "MINIMAL"
	client.accepted_thinking = {}
	var transport: FakeTransport = client._transport
	transport.push(_status(400, "{\"error\":{\"status\":\"INVALID_ARGUMENT\",\"message\":\"thinking level MINIMAL is not supported\"}}"))
	transport.push(_ok("{\"reply\":\"на low\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	var first: Dictionary = JSON.parse_string(transport.seen[0]["body"])
	var second: Dictionary = JSON.parse_string(transport.seen[1]["body"])
	assert_eq(first["generationConfig"]["thinkingConfig"]["thinkingLevel"], "MINIMAL")
	assert_eq(second["generationConfig"]["thinkingConfig"]["thinkingLevel"], "LOW")
	transport.push(_ok("{\"reply\":\"снова\"}"))
	var again: Dictionary = await client.generate(_request("dialogue"))
	assert_true(again["ok"])
	var third: Dictionary = JSON.parse_string(transport.seen[2]["body"])
	assert_eq(third["generationConfig"]["thinkingConfig"]["thinkingLevel"], "LOW")
	client.free()


func test_turn_deadline_stops_the_request() -> void:
	var client := await _client()
	client.turn_deadline_ms = 0
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"не должен уйти\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "timeout")
	assert_eq(transport.seen.size(), 0)
	client.free()


func test_probe_uses_a_short_timeout_without_thinking() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"ok\":\"да\"}"))
	var request := _request("dialogue")
	request["probe"] = true
	request["timeout_s"] = 12.0
	var result: Dictionary = await client.generate(request)
	assert_true(result["ok"])
	assert_eq(transport.seen[0]["timeout"], 12.0)
	var body: Dictionary = JSON.parse_string(transport.seen[0]["body"])
	assert_false(body["generationConfig"].has("thinkingConfig"))
	client.free()


func test_live_smoke_is_skipped_without_env_key() -> void:
	assert_false(LLMConfig.live_smoke_enabled(""))
	assert_false(LLMConfig.live_smoke_enabled("   "))
	assert_true(LLMConfig.live_smoke_enabled("present"))
	var env_key := OS.get_environment("GEMINI_API_KEY").strip_edges()
	if env_key == "":
		assert_false(LLMConfig.live_smoke_enabled(env_key), "без ключа живой тест не запускается")


func test_network_retries_do_not_spend_the_rate_limit_counter() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"})
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"})
	transport.push(_status(429, "{\"error\":{\"message\":\"busy\",\"status\":\"RESOURCE_EXHAUSTED\"}}"))
	transport.push(_ok("{\"reply\":\"после сети\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(transport.seen.size(), 4)
	assert_eq(client.waits[0], 1.0)
	assert_eq(client.waits[1], 3.0)
	client.free()


func test_summary_thinking_does_not_replace_the_reply_level() -> void:
	var client := await _client()
	client.thinking_level = "MINIMAL"
	client.accepted_thinking = {}
	var transport: FakeTransport = client._transport
	transport.push(_status(400, "{\"error\":{\"status\":\"INVALID_ARGUMENT\",\"message\":\"thinking level MINIMAL is not supported\"}}"))
	transport.push(_ok("{\"reply\":\"сводка\"}"))
	var summary: Dictionary = await client.generate(_request("summary"))
	assert_true(summary["ok"])
	transport.push(_ok("{\"reply\":\"реплика\"}"))
	var reply: Dictionary = await client.generate(_request("dialogue"))
	assert_true(reply["ok"])
	var body: Dictionary = JSON.parse_string(transport.seen[2]["body"])
	assert_eq(body["generationConfig"]["thinkingConfig"]["thinkingLevel"], "MINIMAL")
	var stored := SettingsStore.load_thinking()
	assert_false(stored.has("dialogue-model"))
	assert_true(stored.has("dialogue-model|summary"))
	client.free()


func _client(key: String = SECRET) -> GeminiClient:
	var config := LLMConfig.new()
	config.api_key = key
	config.dialogue_model = "dialogue-model"
	config.summary_model = "summary-model"
	config.thinking_level = "LOW"
	config.timeout_s = 30.0
	config.min_interval_s = 0.0
	var client := GeminiClient.new()
	client.apply_config(config)
	client.accepted_thinking = {}
	client._instant_wait = true
	var transport := FakeTransport.new()
	client.set_transport(transport)
	(Engine.get_main_loop() as SceneTree).root.add_child(client)
	return client


func _request(role: String) -> Dictionary:
	return {
		"system": "система",
		"user": "вопрос",
		"schema": {"type": "object", "properties": {"reply": {"type": "string"}}, "required": ["reply"]},
		"model_role": role,
		"temperature": 0.9,
		"max_output_tokens": 2048,
	}


func _ok(text: String, with_thought: bool = false) -> Dictionary:
	return _candidate(text, "STOP", with_thought)


func _candidate(text: String, finish: String, with_thought: bool = false) -> Dictionary:
	var parts: Array = []
	if with_thought:
		parts.append({"thought": true, "text": "скрытые рассуждения"})
	parts.append({"text": text})
	var payload := {
		"candidates": [{
			"content": {"parts": parts},
			"finishReason": finish,
		}],
	}
	return {"ok": true, "status": 200, "body": JSON.stringify(payload), "headers": {}, "error": ""}


func _blocked_prompt() -> Dictionary:
	var payload := {"promptFeedback": {"blockReason": "SAFETY"}}
	return {"ok": true, "status": 200, "body": JSON.stringify(payload), "headers": {}, "error": ""}


func _status(code: int, body: String, headers: Dictionary = {}) -> Dictionary:
	return {"ok": true, "status": code, "body": body, "headers": headers, "error": ""}


func _cfg(key: String, model: String) -> String:
	return "[llm]\napi_key=\"%s\"\ndialogue_model=\"%s\"\nsummary_model=\"summary-model\"\nfallback_model=\"fallback-model\"\nthinking_level=\"LOW\"\ntimeout_s=30\nmin_interval_s=1.0\n" % [key, model]


class FakeTransport:
	extends RefCounted

	var scripted: Array = []
	var seen: Array = []
	var calls: int = 0

	func push(outcome: Dictionary) -> void:
		scripted.append(outcome)

	func request(url: String, headers: Dictionary, body: String, timeout_s: float, _byte_mark: String = "") -> Dictionary:
		calls += 1
		seen.append({"url": url, "headers": headers, "body": body, "timeout": timeout_s})
		if scripted.is_empty():
			return {"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"}
		return scripted.pop_front()
