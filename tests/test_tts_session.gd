extends TestCase


func test_second_phrase_reuses_the_client() -> void:
	var made: Array = []
	var transport := GeminiTtsBackend.GeminiTtsTransport.new()
	transport.http_factory = func() -> Object:
		var link := _Link.new()
		made.append(link)
		return link
	(Engine.get_main_loop() as SceneTree).root.add_child(transport)
	assert_true(_run(transport))
	assert_eq(made.size(), 1)
	assert_true(_run(transport))
	assert_eq(made.size(), 1)
	transport.cancel()
	assert_eq(made.size(), 1)
	assert_true(_run(transport))
	assert_eq(made.size(), 2)
	transport.free()


func test_reused_client_that_drops_before_a_status_is_replaced() -> void:
	var made: Array = []
	var transport := GeminiTtsBackend.GeminiTtsTransport.new()
	transport.http_factory = func() -> Object:
		var link := _Link.new()
		made.append(link)
		return link
	(Engine.get_main_loop() as SceneTree).root.add_child(transport)
	assert_true(_run(transport))
	made[0].fail_request = true
	assert_true(_run(transport))
	assert_eq(made.size(), 2)
	transport.free()


func test_parked_client_older_than_the_idle_limit_is_dropped() -> void:
	var now := {"ms": 0}
	var made: Array = []
	var transport := GeminiTtsBackend.GeminiTtsTransport.new()
	transport.clock_ms = func() -> int: return int(now.ms)
	transport.http_factory = func() -> Object:
		var link := _Link.new()
		made.append(link)
		return link
	(Engine.get_main_loop() as SceneTree).root.add_child(transport)
	assert_true(_run(transport))
	now.ms = int(HttpSession.IDLE_REUSE_S * 1000.0) + 5
	assert_true(_run(transport))
	assert_eq(made.size(), 2)
	transport.free()


func _run(transport: GeminiTtsBackend.GeminiTtsTransport) -> bool:
	var pcm := PackedByteArray([0, 0, 0, 0])
	var event := "data: {\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"%s\"}}]}}]}\r\n\r\n" % Marshalls.raw_to_base64(pcm)
	var pending: Variant = transport.call("stream", {"path": "/x", "body": {}, "api_key": "k", "on_chunk": func(_chunk: PackedByteArray) -> void: pass})
	for _step in 3:
		if transport._done:
			break
		var http: Object = transport._http
		if http == null:
			return false
		http.mode = "connected"
		transport._tick()
		if transport._http != http:
			continue
		http.chunks = [event.to_utf8_buffer()]
		http.mode = "body"
		transport._tick()
		transport._tick()
		http.mode = "done"
		transport._tick()
	if pending is Dictionary:
		return bool((pending as Dictionary).get("ok", false))
	return bool(transport._result.get("ok", false))


class _Link:
	extends RefCounted

	var mode: String = "connecting"
	var chunks: Array = []
	var fail_request: bool = false

	func connect_to_host(_host: String, _port: int, _tls: TLSOptions = null) -> int:
		mode = "connected"
		return OK

	func get_status() -> int:
		match mode:
			"connecting":
				return HTTPClient.STATUS_CONNECTING
			"body":
				return HTTPClient.STATUS_BODY
			"dead":
				return HTTPClient.STATUS_CONNECTION_ERROR
			_:
				return HTTPClient.STATUS_CONNECTED

	func poll() -> void:
		pass

	func request(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> int:
		if fail_request:
			fail_request = false
			mode = "dead"
			return OK
		mode = "body"
		return OK

	func get_response_code() -> int:
		return 200

	func read_response_body_chunk() -> PackedByteArray:
		if chunks.is_empty():
			mode = "done"
			return PackedByteArray()
		return chunks.pop_front()

	func close() -> void:
		mode = "connecting"
