class_name CaseData
extends RefCounted
## Разобранное дело. Только данные, без правил раскрытия.

var id: String = ""
var title: String = ""
var briefing: String = ""
var intro_atmosphere: String = ""
var killer_id: String = ""
var true_motive_id: String = ""
var true_method_id: String = ""
var motive_options: Array[Option] = []
var method_options: Array[Option] = []
var truth_timeline: String = ""
var victory_condition: String = "correct_accusation"
var starting_agent_id: String = ""
var agents: Array[Agent] = []
var evidence: Array[EvidenceItem] = []
var contradictions: Array[Contradiction] = []
var agent_by_id: Dictionary = {}
var fact_by_id: Dictionary = {}
var evidence_by_id: Dictionary = {}
var contradiction_by_id: Dictionary = {}
var fact_owner: Dictionary = {}


class Option:
	extends RefCounted
	var id: String = ""
	var text: String = ""


class Fact:
	extends RefCounted
	var id: String = ""
	var content_basic: String = ""
	var content_full: String = ""
	var is_lie: bool = false
	var lie_type: String = ""
	var lie_text: String = ""
	var tags: Array[String] = []
	var related_evidence_ids: Array[String] = []
	var pressure_for_basic: int = 0
	var pressure_for_full: int = 0
	var requires_evidence: bool = false
	## Ложь открывается только после того, как сломаны эти факты.
	var requires_broken_lies: Array[String] = []
	## null, строка или список: pressure | evidence | contradiction.
	## Если breaks_with задан в файле, движок это поле не читает.
	var breaks_lie_on: Variant = null
	## Наборы слома. Пусто и breaks_with_explicit — ложь без наборов.
	var breaks_with: Array = []
	## false: поля в файле не было, наборы переводятся из breaks_lie_on.
	var breaks_with_explicit: bool = false


class Agent:
	extends RefCounted
	var id: String = ""
	var name: String = ""
	var role: String = ""
	var personality: String = ""
	var prompt_background: String = ""
	var background: String = ""
	var starting_pressure: int = 0
	var starting_emotion: String = "neutral"
	## male | female | пусто. Нужен только как запасной выбор голоса.
	var gender: String = ""
	## Имя заранее заданного голоса Gemini TTS. Пусто — выбор по gender.
	var tts_voice: String = ""
	## Постоянная манера речи для speechMetadata.style, например «сдержанно, неторопливо».
	## Не описывать тембр, возраст, пол и акцент: из-за этого голос плывёт между репликами.
	## Пусто — стиль только из интонации реплики. Значение заполняет автор дела, не код.
	var voice_style: String = ""
	## Короткое приветствие. Пусто — заранее ничего не готовим и первая фраза не звучит.
	var greeting: String = ""
	## never | sometimes | often. Пусто читается как never.
	var profanity: String = "never"
	var wants: String = ""
	var fears: String = ""
	var own_version: String = ""
	var life_details: String = ""
	var sample_lines: Array[String] = []
	## До трёх коротких междометий. Пусто — стандартные «Хм…», «Ну…», «Секунду…».
	var filler_lines: Array[String] = []
	var relationships: Dictionary = {}
	var facts: Array[Fact] = []


class EvidenceItem:
	extends RefCounted
	var id: String = ""
	var title: String = ""
	var short_description: String = ""
	var full_text: String = ""
	var type: String = ""
	var related_fact_ids: Array[String] = []
	var related_agent_ids: Array[String] = []
	var is_key: bool = false
	## null либо объект условия (раздел 15). Здесь только хранение.
	var unlock_condition: Variant = null


class Contradiction:
	extends RefCounted
	var id: String = ""
	var fact_a_id: String = ""
	var fact_a_form: String = ""
	var fact_b_id: String = ""
	var fact_b_form: String = ""
	var description: String = ""
