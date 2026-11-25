extends TestCase


func test_turn_log_survives_other_voice_notes() -> void:
	TurnTiming.reset()
	for _index in 12:
		TurnTiming.begin("gemini")
		TurnTiming.mark("release")
		TurnTiming.publish()
	assert_eq(TurnTiming.lines().size(), 10)
	assert_eq(Speaker.turn_log.size(), 10)
	for index in 25:
		Speaker.note_line("mic noise %d" % index)
	assert_eq(TurnTiming.lines().size(), 10)
	assert_eq(Speaker.turn_log.size(), 10)
	assert_true(Speaker.voice_log.size() <= 20)
	TurnTiming.reset()


func test_gemini_stt_reuses_the_shared_session() -> void:
	var source := FileAccess.get_file_as_string("res://src/voice/gemini_stt.gd")
	assert_false(source.contains("HTTPRequest.new"))
	assert_true(source.contains("HttpSession.exchange"))
	HttpSession.reset()
	var made: Array = []
	HttpSession.maker = func(_host: String) -> ScriptedLink:
		var link := ScriptedLink.new()
		made.append(link)
		return link
	var host := Node.new()
	_attach(host)
	var transport := GeminiStt.GeminiSttTransport.new()
	host.add_child(transport)
	var headers := {"Content-Type": "application/json"}
	var first: Dictionary = await transport.request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", headers, "{}", 5.0)
	var second: Dictionary = await transport.request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", headers, "{}", 5.0)
	assert_eq(int(first.get("status", 0)), 200)
	assert_eq(int(second.get("status", 0)), 200)
	assert_true(HttpSession.last_reused)
	assert_eq(made.size(), 1)
	HttpSession.reset()
	HttpSession.maker = Callable()
	host.free()


func test_connection_is_reused_until_it_drops() -> void:
	HttpSession.reset()
	var made: Array = []
	HttpSession.maker = func(_host: String) -> FakeLink:
		var link := FakeLink.new()
		made.append(link)
		return link
	var first := HttpSession.checkout("generativelanguage.googleapis.com")
	assert_false(bool(first.get("reused", true)))
	HttpSession.checkin("generativelanguage.googleapis.com", first.get("client"), true)
	var second := HttpSession.checkout("generativelanguage.googleapis.com")
	assert_true(bool(second.get("reused", false)))
	assert_eq(second.get("client"), first.get("client"))
	var link: FakeLink = second.get("client")
	link.status = HTTPClient.STATUS_DISCONNECTED
	HttpSession.checkin("generativelanguage.googleapis.com", link, false)
	assert_true(link.closed)
	var third := HttpSession.checkout("generativelanguage.googleapis.com")
	assert_false(bool(third.get("reused", true)))
	assert_eq(made.size(), 2)
	var parts := HttpSession.split_url("https://generativelanguage.googleapis.com/v1beta/models/x:generateContent")
	assert_eq(str(parts.get("host", "")), "generativelanguage.googleapis.com")
	assert_eq(int(parts.get("port", 0)), 443)
	assert_true(bool(parts.get("tls", false)))
	assert_true(str(parts.get("path", "")).begins_with("/v1beta"))
	HttpSession.reset()
	HttpSession.maker = Callable()


func test_turn_log_keeps_ten_and_names_the_span() -> void:
	TurnTiming.reset()
	TurnTiming.begin("gemini")
	TurnTiming.mark("release")
	TurnTiming.note_reused(true)
	TurnTiming.mark("first_audio")
	var line := TurnTiming.format_row(TurnTiming.turns.back())
	assert_true(line.contains("backend=gemini"))
	assert_true(line.contains("reused=yes"))
	assert_true(line.contains("total="))
	TurnTiming.mark("dialogue_first_byte")
	TurnTiming.note_tts_reused(true)
	var marked := TurnTiming.format_row(TurnTiming.turns.back())
	assert_true(marked.contains("dialogue_first_byte="))
	assert_true(marked.contains("tts_reused=yes"))
	TurnTiming.reset()
	for _index in 12:
		TurnTiming.begin("gemini")
	assert_eq(TurnTiming.turns.size(), TurnTiming.LIMIT)


func test_stale_reused_connection_is_replaced_once() -> void:
	HttpSession.reset()
	var made: Array = []
	HttpSession.maker = func(_host: String) -> DropLink:
		var link := DropLink.new()
		made.append(link)
		return link
	var host := Node.new()
	_attach(host)
	var first: Dictionary = await HttpSession.exchange(host, "https://generativelanguage.googleapis.com/v1/models/x:generateContent", PackedStringArray(), "{}", 5.0)
	assert_eq(int(first.get("status", 0)), 200)
	(made[0] as DropLink).fail_request = true
	var second: Dictionary = await HttpSession.exchange(host, "https://generativelanguage.googleapis.com/v1/models/x:generateContent", PackedStringArray(), "{}", 5.0)
	assert_eq(int(second.get("status", 0)), 200)
	assert_false(bool(second.get("reused", true)))
	assert_eq(made.size(), 2)
	HttpSession.reset()
	HttpSession.maker = Callable()
	host.free()


func test_idle_connection_older_than_the_limit_is_not_reused() -> void:
	HttpSession.reset()
	var now := {"ms": 1000}
	HttpSession.clock_ms = func() -> int: return int(now.ms)
	var made: Array = []
	HttpSession.maker = func(_host: String) -> FakeLink:
		var link := FakeLink.new()
		made.append(link)
		return link
	var first := HttpSession.checkout("generativelanguage.googleapis.com")
	HttpSession.checkin("generativelanguage.googleapis.com", first.get("client"), true)
	now.ms = 1000 + int(HttpSession.IDLE_REUSE_S * 1000.0) + 1
	var second := HttpSession.checkout("generativelanguage.googleapis.com")
	assert_false(bool(second.get("reused", true)))
	assert_eq(made.size(), 2)
	HttpSession.reset()
	HttpSession.maker = Callable()


func _attach(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


class ScriptedLink:
	extends RefCounted

	var status: int = HTTPClient.STATUS_DISCONNECTED
	var read_once: bool = false

	func get_status() -> int:
		return status

	func connect_to_host(_host: String, _port: int, _tls: TLSOptions = null) -> int:
		status = HTTPClient.STATUS_CONNECTED
		return OK

	func poll() -> void:
		pass

	func request(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> int:
		read_once = false
		status = HTTPClient.STATUS_BODY
		return OK

	func get_response_code() -> int:
		return 200

	func read_response_body_chunk() -> PackedByteArray:
		if read_once:
			status = HTTPClient.STATUS_CONNECTED
			return PackedByteArray()
		read_once = true
		return PackedByteArray([123, 125])

	func close() -> void:
		status = HTTPClient.STATUS_DISCONNECTED


class FakeLink:
	extends RefCounted

	var status: int = HTTPClient.STATUS_CONNECTED
	var closed: bool = false

	func get_status() -> int:
		return status

	func close() -> void:
		closed = true
		status = HTTPClient.STATUS_DISCONNECTED


class DropLink:
	extends RefCounted

	var status: int = HTTPClient.STATUS_DISCONNECTED
	var requests: int = 0
	var fail_request: bool = false

	func get_status() -> int:
		return status

	func connect_to_host(_host: String, _port: int, _tls: TLSOptions = null) -> int:
		status = HTTPClient.STATUS_CONNECTED
		return OK

	func poll() -> void:
		pass

	func request(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> int:
		requests += 1
		if fail_request:
			fail_request = false
			status = HTTPClient.STATUS_CONNECTION_ERROR
			return OK
		status = HTTPClient.STATUS_BODY
		return OK

	func get_response_code() -> int:
		return 200

	func read_response_body_chunk() -> PackedByteArray:
		status = HTTPClient.STATUS_CONNECTED
		return PackedByteArray([123, 125])

	func close() -> void:
		status = HTTPClient.STATUS_DISCONNECTED
