extends Node
## Сессия партии: ход, сигналы для UI, блокнот. Экранов здесь нет.

signal agent_replied(agent_id: String, text: String, remark: String)
signal case_opened
signal events(list: Array)
signal llm_error(kind: String, message: String)
signal save_failed(message: String)
signal busy_changed(is_busy: bool)
signal dialogue_sent(agent_id: String)

var case_data: CaseData = null
var state: GameState = null
var notebook: Notebook = null
var case_path: String = ""

var _engine: RulesEngine = null
var _dialogues: Dictionary = {}
var last_turn_line: String = ""
var last_turn_stats: Dictionary = {}
## Интонация последней реплики для синтеза. В текст реплики не входит.
var speech_style: String = ""
## Текст для синтеза. На экране и в истории остаётся ответ без меток.
var speech_line: String = ""
var is_busy: bool = false
## Текст игрока, который ход принял. Лента берёт его не раньше ответа.
var accepted_player_line: String = ""
## Подмена распознавания для запасного пути. Пусто — облачный STT.
var fallback_stt: SttBackend = null
const MODEL_CAP := 5
var _runner := TurnSession.new()
var _turn_token: int = 0
## Снимок партии до present_evidence / note_question. Пока ход не закончен, сворачивание пишет его.
var _turn_snapshot: Dictionary = {}


func open_case(path: String) -> CaseLoader.Result:
	_drop_turn()
	var loaded := CaseLoader.load_case(path)
	if not loaded.ok:
		case_data = null
		state = null
		notebook = null
		case_path = ""
		_engine = null
		_dialogues = {}
		return loaded
	case_data = loaded.case_data
	case_path = path
	state = GameState.new()
	state.case_id = case_data.id
	state.case_version_hash = SaveState.file_hash(path)
	_engine = RulesEngine.new(case_data, state)
	_engine.start_new()
	_dialogues = {}
	for agent in case_data.agents:
		_dialogues[agent.id] = DialogueState.new()
		state.dialogues[agent.id] = (_dialogues[agent.id] as DialogueState).to_dict()
	notebook = Notebook.new(case_data, state)
	case_opened.emit()
	return loaded


func mentioned_evidence(text: String) -> Array[String]:
	if case_data == null or state == null:
		return []
	var open: Array = []
	for evidence in case_data.evidence:
		if state.unlocked_evidence.has(evidence.id):
			open.append(evidence)
	return EvidenceMatcher.find_mentioned(text, open)


func ask(agent_id: String, player_text: String, wav: PackedByteArray = PackedByteArray()) -> void:
	if is_busy:
		return
	await _turn(agent_id, player_text, "", "", "", wav)


func confront(agent_id: String, statement_id: String, evidence_id: String, player_text: String = "", wav: PackedByteArray = PackedByteArray()) -> void:
	if is_busy:
		return
	var question := player_text.strip_edges()
	if question == "" and wav.is_empty():
		question = "Что скажете?"
	await _turn(agent_id, question, "", evidence_id, statement_id, wav)


func present(agent_id: String, evidence_id: String, player_text: String = "", wav: PackedByteArray = PackedByteArray()) -> void:
	if is_busy:
		return
	var question := player_text.strip_edges()
	if question == "" and wav.is_empty():
		question = "Что скажете?"
	var note := ""
	if case_data != null and case_data.evidence_by_id.has(evidence_id):
		var evidence: CaseData.EvidenceItem = case_data.evidence_by_id[evidence_id]
		note = "Следователь предъявляет улику «%s»: %s" % [evidence.title, evidence.full_text]
	await _turn(agent_id, question, note, evidence_id, "", wav)


func accuse(killer_id: String, motive_id: String, method_id: String) -> Dictionary:
	if _engine == null:
		return {"killer_ok": false, "motive_ok": false, "method_ok": false, "solved": false}
	var report := _engine.check_accusation(killer_id, motive_id, method_id)
	_autosave()
	return report


func continue_case(path: String) -> Dictionary:
	var case_id := SaveState.case_id_from_path(path)
	if case_id == "":
		return {"ok": false, "reason": "case"}
	var saved := SaveState.read(case_id)
	if not saved.ok:
		return saved
	var current_hash := SaveState.file_hash(path)
	if str(saved.get("hash", "")) != current_hash or str(saved.get("case_id", "")) != case_id:
		return {"ok": false, "reason": "hash"}
	var loaded := open_case(path)
	if not loaded.ok:
		return {"ok": false, "reason": "case"}
	_replace_state(saved.get("state", {}))
	return {"ok": true, "reason": ""}


## Первая фраза персонажа. Не ход: talked_to и turn не меняются.
func add_greeting(agent_id: String) -> String:
	if is_busy or case_data == null or state == null or not _dialogues.has(agent_id):
		return ""
	var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
	if agent == null or agent.greeting.strip_edges() == "":
		return ""
	var dialogue: DialogueState = _dialogues[agent_id]
	if not dialogue.messages.is_empty():
		return ""
	var text := agent.greeting.strip_edges()
	dialogue.append_message("agent", text, state.turn)
	_sync_dialogues()
	_autosave()
	return text


func links_speaker() -> bool:
	return true


func write_save() -> bool:
	return _autosave()


func _turn(agent_id: String, player_text: String, event_note: String, evidence_id: String, statement_id: String = "", wav: PackedByteArray = PackedByteArray()) -> void:
	await _runner.perform(self, agent_id, player_text, event_note, evidence_id, statement_id, wav)



func _autosave() -> bool:
	if state == null:
		return false
	return SaveState.write_state(state)


func _replace_state(data: Variant) -> void:
	_drop_turn()
	if data is not Dictionary:
		return
	state = GameState.from_dict(data)
	state.case_id = case_data.id
	state.case_version_hash = SaveState.file_hash(case_path)
	_engine = RulesEngine.new(case_data, state)
	_dialogues = {}
	for agent in case_data.agents:
		var saved: Variant = state.dialogues.get(agent.id, {})
		if saved is Dictionary:
			_dialogues[agent.id] = DialogueState.from_dict(saved)
		else:
			_dialogues[agent.id] = DialogueState.new()
		state.dialogues[agent.id] = (_dialogues[agent.id] as DialogueState).to_dict()
	notebook = Notebook.new(case_data, state)



func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		Speaker.suspend_playback()
		_save_for_suspend()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		Speaker.resume_playback()


func _save_for_suspend() -> void:
	if state == null or state.case_id.strip_edges() == "":
		return
	var saved := false
	if is_busy and not _turn_snapshot.is_empty():
		var frozen := GameState.from_dict(_turn_snapshot)
		frozen.case_id = state.case_id
		frozen.case_version_hash = state.case_version_hash
		saved = SaveState.write_state(frozen)
	else:
		_sync_dialogues()
		saved = _autosave()
	if not saved:
		save_failed.emit("Не удалось записать сохранение.")


func _sync_dialogues() -> void:
	if state == null:
		return
	for agent_id in _dialogues:
		state.dialogues[agent_id] = (_dialogues[agent_id] as DialogueState).to_dict()



func _spend_model(tally: Dictionary, kind: String, reason: String) -> bool:
	return _runner._spend_model(tally, kind, reason)


func _statement_text(statement_id: String) -> String:
	return _runner._statement_text(self, statement_id)


func _drop_turn() -> void:
	_runner.drop(self)


func _fallback_transcript(wav: PackedByteArray, agent_id: String, tally: Dictionary) -> Dictionary:
	return await _runner.fallback_transcript(self, wav, agent_id, tally)


func _restore(snapshot: Dictionary) -> void:
	_runner.restore(self, snapshot)
