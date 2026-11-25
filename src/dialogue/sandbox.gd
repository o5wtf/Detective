class_name Sandbox
extends Node
## Пробный допрос черновика. Своё состояние, без сигналов партии и без сохранения.


signal agent_replied(agent_id: String, text: String, remark: String)
signal llm_error(kind: String, message: String)
signal events(list: Array)
signal save_failed(message: String)
signal busy_changed(is_busy: bool)
signal dialogue_sent(agent_id: String)

var case_data: CaseData = null
var state: GameState = null
var notebook: Notebook = null
var _engine: RulesEngine = null
var _dialogues: Dictionary = {}
var is_busy: bool = false
var _turn_token: int = 0
var _turn_snapshot: Dictionary = {}
var speech_style: String = ""
var speech_line: String = ""
var accepted_player_line: String = ""
var last_turn_line: String = ""
var last_turn_stats: Dictionary = {}
var fallback_stt: SttBackend = null
var log_lines: PackedStringArray = PackedStringArray()
var _runner := TurnSession.new()


func open_draft(raw: Dictionary) -> bool:
	_runner.drop(self)
	var parsed := CaseLoader.parse(raw)
	if not parsed.ok:
		case_data = null
		state = null
		notebook = null
		_engine = null
		_dialogues = {}
		return false
	case_data = parsed.case_data
	state = GameState.new()
	state.case_id = case_data.id
	_engine = RulesEngine.new(case_data, state)
	_engine.start_new()
	_dialogues = {}
	for agent in case_data.agents:
		_dialogues[agent.id] = DialogueState.new()
		state.dialogues[agent.id] = (_dialogues[agent.id] as DialogueState).to_dict()
	notebook = Notebook.new(case_data, state)
	return true


func ask(agent_id: String, player_text: String) -> void:
	if is_busy:
		return
	await _runner.perform(self, agent_id, player_text, "", "", "", PackedByteArray())


func links_speaker() -> bool:
	return false


func write_save() -> bool:
	return true


func note_line(line: String) -> void:
	log_lines.append(line)


func _sync_dialogues() -> void:
	if state == null:
		return
	for agent_id in _dialogues:
		state.dialogues[agent_id] = (_dialogues[agent_id] as DialogueState).to_dict()
