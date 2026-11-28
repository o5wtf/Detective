# Архитектура прототипа

Документ описывает, **как** реализовать правила из `Дизайн документ Игры` (дальше — «диздок»). Если этот документ и диздок расходятся, прав диздок; расхождение нужно исправить в одном из них.

## 1. Платформа

- **Движок:** Godot 4.7 (последняя стабильная на ноябрь 2026 — 4.7.2). Стандартная сборка, не .NET.
- **Язык:** GDScript со статической типизацией (`var x: int`, `-> Array[String]`) везде, где это возможно.
- **Платформы:** Android (arm64; основное тестовое устройство — планшет) и Windows (x86_64). Linux и macOS не поддерживаются. Один проект, один интерфейс с адаптивной вёрсткой под сенсор и мышь (docs/UI_PROTOTYPE.md).
- **Модель:** Gemini через REST (`generateContent`), подробности — `docs/LLM_PROTOCOL.md`.
- **Без сторонних аддонов** на этапе прототипа (тесты — свой маленький раннер, см. раздел 8).

## 2. Структура папок

Проект Godot лежит в корне репозитория, чтобы дело открывалось как `res://cases/<дело>.json`.

```
project.godot
.gitignore
README.md
Дизайн документ Игры
docs/                     # документы (в папке лежит .gdignore — Godot её не импортирует)
tools/                    # Python-инструменты авторов (.gdignore)
cases/                    # дела в JSON (*.json) и заметки авторов (*_NOTES.md)
config/
  config.example.cfg      # пример настроек без ключа (в git)
src/
  core/                   # чистая логика, без Node и без UI
    case_data.gd          # CaseData: разобранное дело (типизированные словари/классы)
    case_loader.gd        # CaseLoader: чтение JSON → CaseData
    case_validator.gd     # CaseValidator: правила раздела 7 диздока (порт tools/validate_case.py)
    conditions.gd         # Conditions: вычисление unlock_condition (раздел 15)
    balance.gd            # Balance: числа давления (раздел 11)
    game_state.gd         # GameState: всё изменяемое состояние партии (сериализуемое)
    rules_engine.gd       # RulesEngine: раскрытие фактов, ложь, давление, противоречия, улики, обвинение
    accusation.gd         # Accusation: проверка обвинения (раздел 4)
  dialogue/
    dialogue_state.gd     # DialogueState: история и резюме разговора с одним агентом
    prompt_builder.gd     # PromptBuilder: системный промпт, промпт хода, схема ответа
    response_validator.gd # ResponseValidator: проверка ответа модели (утечки, формат)
    notebook.gd           # Notebook: журнал услышанных утверждений (для игрока и противоречий)
    evidence_matcher.gd   # EvidenceMatcher: локальный поиск упоминаний улик в вопросе
    summarizer.gd         # Summarizer: резюме старой части истории
  llm/
    llm_client.gd         # LLMClient: абстрактный интерфейс
    gemini_client.gd      # GeminiClient: реализация через HTTPRequest
    mock_llm_client.gd    # MockLLMClient: заранее заданные ответы (тесты, офлайн-отладка)
    llm_config.gd         # LLMConfig: ключ, модели, таймауты (из user://config.cfg)
  save/
    save_state.gd         # SaveState: сохранение и загрузка партии
  voice/                  # этап O1: системная озвучка, без микрофона (раздел 3.12)
    speech_backend.gd     # SpeechBackend: сменный синтез
    system_tts_backend.gd # SystemTtsBackend: DisplayServer.tts_speak
    speech_queue.gd       # SpeechQueue: одна реплика один раз, по порядку
    speech_text.gd        # SpeechText: очистка текста перед озвучкой
    speaker.gd            # автозагрузка Speaker: очередь, сигнал is_speaking
  autoload/
    game.gd               # автозагрузка Game: сессия, порядок хода, сигналы для UI
    llm.gd                # автозагрузка LLM: создаёт и отдаёт клиента по настройкам
ui/
  theme/                  # общая тема (шрифты, цвета)
  screens/                # сцены экранов (docs/UI_PROTOTYPE.md)
  components/             # переиспользуемые элементы (карточка улики, реплика и т. п.)
tests/
  run_tests.gd            # раннер тестов (headless)
  test_*.gd               # наборы тестов
  fixtures/               # маленькие дела для тестов, в том числе заведомо сломанные
  golden/                 # эталоны (например, результат tools/validate_case.py --simulate --json)
```

Правило зависимостей: `src/core` ничего не знает о `dialogue`, `llm`, `ui`. `dialogue` знает о `core`. `autoload/game.gd` склеивает всё. UI общается только с автозагрузкой `Game` (сигналы и методы), а не с движком правил напрямую.

## 3. Модули и интерфейсы

Сигнатуры ниже — договорённость, а не готовый код. Имена методов можно уточнять при реализации, но смысл и разделение ответственности менять нельзя без правки документа.

### 3.1 CaseLoader и CaseValidator — диздок, разделы 2, 7, 8, 13, 14, 15

```
class_name CaseLoader
static func load_case(path: String) -> CaseLoadResult   # {ok: bool, case: CaseData, errors: Array[String]}

class_name CaseValidator
static func validate(raw: Dictionary) -> Array[ValidationError]   # {code: String, message: String}
```

- Правила **точно те же**, что в `tools/validate_case.py`. Каждой ошибке даётся код (например `killer_missing`, `lie_text_missing`, `cond_unknown_agent`), чтобы тесты сверяли коды, а не текст.
- При любой ошибке дело не запускается: UI показывает список ошибок (это экран для автора, не для игрока).

### 3.2 RulesEngine — диздок, разделы 3, 4, 8, 11, 14, 15

Чистая логика: без Node, без сети, без UI. Всё состояние лежит в `GameState`, поэтому движок легко тестировать и сохранять.

```
class_name RulesEngine
func _init(case_data: CaseData, state: GameState) -> void
func start_new() -> Array[GameEvent]                       # стартовые значения агентов, улики без условия
func get_packet(agent_id: String) -> Array[PacketEntry]   # что модели разрешено знать сейчас (раздел 8)
func note_question(agent_id: String) -> Array[GameEvent]  # dialogue_with
func register_statements(agent_id: String, statements: Array[Statement]) -> Array[GameEvent]
func present_evidence(agent_id: String, evidence_id: String) -> Array[GameEvent]
func apply_tone(agent_id: String, tone: int) -> Array[GameEvent]
func set_emotion(agent_id: String, emotion: String) -> void
func check_accusation(killer_id: String, motive_id: String, method_id: String) -> AccusationResult
func pressure_band(agent_id: String) -> String            # calm 0–24 | tense 25–49 | nervous 50–74 | breaking 75–100
```

- `PacketEntry`: `{key: "k1", fact_id, mode, lie_text, content}`. `mode` — одно из `lie`, `lie_or_basic` (can_lie с оговоркой), `basic`, `full`. Ключи `k1…kn` назначаются при каждой сборке пакета, модель видит только их.
- `Statement`: `{fact_id, form}`, где `form` — `lie | basic | full`.
- `GameEvent`: `{type, ...}`, где `type` — одно из `evidence_unlocked`, `lie_broken`, `fact_level_changed`, `contradiction_registered`, `pressure_changed`, `heard`.
- **Каскад.** После любого действия движок вызывает внутренний `_resolve()` и повторяет проход, пока что-то меняется. Внутри каждого шага всё перебирается в порядке файла дела.
  1. Открыть улики, чьи условия выполнены (раздел 15 диздока).
  2. Для каждого факта (агенты и их факты по порядку):
     - если это несломанная ложь — проверить `breaks_lie_on` (список — «любое из»). Если ложь сломалась — отметить; уровень этого факта пересчитывается на следующем проходе;
     - иначе пересчитать уровень: Full, если требование улики выполнено или его нет; Basic, если ложь сломана, а улика ещё нужна. Пороги давления уровень не поднимают.
  3. Для каждого противоречия по порядку: если обе стороны услышаны — зафиксировать и сразу применить давление (раздел 11).

  Давление за предъявление улики применяется в момент предъявления. Этот порядок совпадает с `tools/validate_case.py --simulate`, на этом держится тест на совпадение с эталоном (этап 3 плана).
- Давление всегда 0–100. Каждая пара «улика — агент» даёт давление один раз. Каждое противоречие фиксируется один раз.

### 3.3 GameState — диздок, разделы 5, 8, 11, 14

Только данные, без логики. Метод `to_dict()` / `from_dict()` для сохранения.
Поля:
- `pressure{agent: int}`, `emotion{agent: String}`;
- `unlocked_evidence[]`, `shown{evidence_id: [agent_id]}`, `broken_lies[]`, `fact_levels{fact_id: closed|basic|full}`;
- `heard[]` (`{agent_id, fact_id, form, turn}`), `contradictions[]`, `talked_to[]`;
- `accusation{killer_ok, motive_ok, method_ok, attempts}`;
- `dialogues{agent_id: DialogueState.to_dict()}`, `turn: int`, `case_id`, `case_version_hash`.

### 3.4 DialogueState — диздок, раздел 9

```
class_name DialogueState
var messages: Array[Dictionary]   # {role: "player"|"agent", text, remark, turn}
var summary: String
var summarized_count: int         # сколько первых сообщений уже свёрнуто в summary
func recent(n := 6) -> Array      # последние 6 реплик (реплика = одно сообщение)
func needs_summary() -> bool      # true, если вне окна 6 реплик лежит ≥ 6 ещё не свёрнутых
```

### 3.5 PromptBuilder — диздок, разделы 8, 9

```
class_name PromptBuilder
static func build_turn(case_data, state, agent_id, packet, dialogue, player_text, event_note) -> LLMRequest
static func build_summary(case_data, agent_id, old_summary, messages) -> LLMRequest
```

- Собирает системную инструкцию, текст хода и схему ответа **точно** по `docs/LLM_PROTOCOL.md`.
- Никогда не кладёт в промпт `background`, `truth_timeline`, `killer_id`, закрытые факты и правду по несломанной лжи.

### 3.6 LLMClient и GeminiClient — диздок, раздел 12

```
class_name LLMClient extends Node     # абстрактный
signal finished(result: LLMResult)
func generate(request: LLMRequest) -> LLMResult   # корутина: var r = await client.generate(req)

LLMRequest { system: String, user: String, schema: Dictionary, model_role: "dialogue"|"summary",
             temperature: float, max_output_tokens: int }
LLMResult  { ok: bool, json: Dictionary, raw_text: String,
             error: "" | "offline" | "timeout" | "rate_limited" | "auth" | "blocked" | "bad_response" | "server",
             retry_after_s: float }
```

- `GeminiClient` использует узел `HTTPRequest`. Запрос: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`, заголовки `x-goog-api-key` и `Content-Type: application/json`. Тело — в `docs/LLM_PROTOCOL.md`.
- Ключ и модели читаются из `LLMConfig`. Порядок поиска:
  1. `user://config.cfg` — сюда пишет экран настроек.
  2. Переменная окружения `GEMINI_API_KEY` (удобно для разработки на Windows).
  3. Только в отладочной сборке — `res://config/dev.cfg`. Этот файл в `.gitignore` и исключён из экспорта.
- Обработка ошибок:
  - нет сети или DNS → `offline`;
  - нет ответа за отведённое время, 429, 502, 503 и 504 → повтор той же модели (пауза из `RetryInfo`, не больше двух повторов). Ход не длиннее 25 с, затем `timeout` / `rate_limited` / `overloaded` и кнопка «Повторить»;
  - 401, 403 и 400 с `API_KEY_INVALID` → `auth`; прочий 400 ключом не считается;
  - 404 → модель недоступна, другой модели нет;
  - прочий 5xx → `server`: один повтор той же модели;
  - `finishReason` `SAFETY` или блокировка промпта → `blocked`;
  - `MAX_TOKENS` или оборванный JSON → одна повторная попытка с большим лимитом;
  - JSON не разобрался → `bad_response`.
- При любой ошибке движок правил **не меняет** состояние: ход считается несостоявшимся, игрок может повторить.
- Паузы в 1 с между запросами нет. В полёте по-прежнему один запрос, а `Game.is_busy` отсекает второй тап по отправке.
- `MockLLMClient` возвращает ответы из очереди или по правилу. С ним работают все автоматические тесты, и игру можно запустить без сети (`llm/provider=mock` в настройках).

### 3.7 ResponseValidator — диздок, разделы 8, 9

```
class_name ResponseValidator
static func validate(resp: Dictionary, packet: Array[PacketEntry], context: ValidatorContext) -> ValidationReport
# report: {ok, violations: Array[String], statements: Array[Statement], tone: int, emotion: String, ...}
```

Правила — в `docs/LLM_PROTOCOL.md`, раздел 6. Валидатор ещё и переводит ключи пакета (`k1`) в `fact_id`.

### 3.8 Notebook — диздок, раздел 14

- Хранит услышанные утверждения (`heard` в `GameState`). Для игрока показывает: агент, ход, текст утверждения. Текст — это `content_basic`, `content_full` или `lie_text`, в зависимости от формы.
- Две вкладки: записи и уже найденные противоречия. Фильтр подозреваемого действует на обе. Противоречия находятся сами, когда обе стороны попали в журнал.

### 3.9 EvidenceMatcher — диздок, раздел 10

- Локально, без модели: ищет в вопросе игрока слова из `title` открытых улик (без учёта регистра, по основе слова — первые 5 букв слов длиннее 4 букв).
- Нашёл — UI показывает подсказку «Предъявить: <улика>?». Предъявление происходит только по кнопке. Модель дополнительно возвращает `mentioned_evidence`, это тоже лишь подсказка.

### 3.10 SaveState — без раздела в диздоке (прототип)

- Автосохранение после каждого состоявшегося хода и обвинения в `user://saves/<case_id>.json`: версия формата `1`, id дела, SHA-256 файла дела и `GameState.to_dict()`. Поле `contradiction_turns` необязательное: старое сохранение со списком `contradictions` загружается без него.
- Ключ API в сохранение не пишется.
- Если хэш дела не совпал, формат чужой или файл повреждён, сохранение не загружается, игра предлагает начать заново.
- Кнопки «Продолжить» (если файл есть) и «Начать заново».

### 3.11 Автозагрузка Game

```
signal agent_replied(agent_id, text, remark)
signal events(list: Array[GameEvent])
signal llm_error(kind: String, message: String)
signal busy_changed(is_busy: bool)
func open_case(path: String) -> CaseLoadResult
func ask(agent_id: String, player_text: String) -> void
func present(agent_id: String, evidence_id: String) -> void
func accuse(killer_id, motive_id, method_id) -> AccusationResult
```

### 3.12 Озвучка (этап O1) — только системный голос

Игра по-прежнему ведёт ход текстом. Озвучка читает уже показанную реплику и не влияет на правила. Микрофона и распознавания речи в этом этапе нет.

```
class_name SpeechBackend extends Node
signal started(line_id)
signal finished(line_id)
signal speech_error(line_id, kind)
func speak(line_id, text, voice_hint) -> void
func stop() -> void

# Автозагрузка Speaker
signal is_speaking(active: bool)
func speak_reply(agent_id, reply) -> void
func stop_and_clear() -> void
func reset_for_case() -> void
```

- Сейчас подключён `SystemTtsBackend`: `DisplayServer.tts_speak`. Голоса читаются в момент фразы, не на старте. Пустой список на Android повторяется около 5 с: движок поднимается не сразу. Сначала русский голос, иначе любой, иначе пустой id (голос по умолчанию). `no_voice` пишется только если за это время список так и пуст. В APK есть `<queries>` на `android.intent.action.TTS_SERVICE`, иначе Android 11+ не показывает системные голоса. Фрагмент добавляет экспортный плагин `addons/tts_query` при Gradle-сборке. Каталог `android/build` не в git: CI распаковывает его из `android_source.zip` шаблона Godot.
- `GeminiTtsBackend` — второй синтез за тем же `SpeechBackend`: только `gemini-3.8-flash-lite-tts`, поток `streamGenerateContent?alt=sse`. События Google разделены `\r\n\r\n` и разбираются по мере чтения тела, без накопления всего ответа. PCM 24 кГц копится в своей очереди и уходит в `AudioStreamGenerator` (буфер около 1 с) только пока в нём есть место, поэтому быстрый поток не выбрасывает кадры. Воспроизведение начинается с первого куска, после короткого запаса около 0.15 с. `finished` приходит, когда ответ уже скачан, очередь пуста и буфер доиграл. «Стоп» очищает очередь сразу. Нечётный байт переносится на следующий кусок. Голос берётся из `tts_voice` персонажа, иначе по полу. В `reply` модель может редко поставить `<sigh>`, `<laugh>`, `<gasp>` или `<short pause>`. Чужие метки снимаются, остаётся не больше двух. На экране, в истории, в резюме и в следующем промпте меток нет, в том числе незакрытого `<` в конце куска. В Gemini TTS метки остаются, если «Интонация» включена. Системный голос и выключенная «Интонация» их убирают. Поле `voice_style` у персонажа — короткая манера («сдержанно, неторопливо»), без тембра, возраста, пола и акцента; код его не заполняет. Необязательный `pace` (`slow` / `normal` / `fast`) добавляется к стилю; `normal` и пустой стиль не отправляются. Ключ кэша по-прежнему включает текст и стиль, поэтому метки и манера различают записи. Поле ответа `tone` — короткая интонация из фиксированного списка. Незнакомое значение отбрасывается. При включённой «Интонации» оно уходит в `contents[].parts[].speechMetadata.style` и не читается вслух. Готовый PCM лежит в `user://tts-cache` (хеш модели, голоса, тона и текста, не больше 50 МБ, старые записи вытесняются). Попадание в кэш не делает запрос и не пишет расход. Если у персонажа заполнено `greeting`, а озвучка Gemini включена, эта строка готовится в кэш, пока игрок читает материалы; живая реплика идёт раньше, общий предел 10 запросов в минуту. «Стоп» эту подготовку прекращает. Не больше 10 запросов в минуту; 429, 503 и таймаут повторяются. После неудачи системный голос не подменяет Gemini: у реплики появляется «Повторить озвучку». Строка ошибки показывает вид и код HTTP (`bad_response http=400`, `no_audio http=200`, если звука в ответе нет). Ключ в эту строку не попадает. Расход TTS: $0.50 / $6 за миллион входных и аудио-токенов.
- Очередь говорит каждую реплику один раз (id дела, агента и хода). `speak` всегда заканчивается `finished` или `speech_error`, и очередь после этого берёт следующую. «Стоп» и уход с экрана снимают кнопку повтора, но не оставляют id заблокированным. Готовый `speech_style` уходит в синтез как есть. Журнал последних событий виден под «Проверить голос». Новая реплика встаёт в хвост и не перебивает текущую. «Стоп», скрытие допроса и смена экрана останавливают звук и очищают очередь. Новая партия забывает уже сказанные id.
- В синтез уходит только очищенный текст реплики: без ремарки, тона, эмоции, звёздочек, скобок и служебных слов.
- Настройка «Озвучка» выключена по умолчанию и лежит в `user://config.cfg` как `voice/enabled`. При миграции настроек до `settings_version=3` отсутствующий флаг записывается как `false`.
- Журнал: `voice start|finish|error id=… len=…` без текста реплики. `audio/general/text_to_speech` включён.
- Голосовой ввод (настройка «Голосовой ввод», по умолчанию выключен): удержание кнопки на допросе. Захват — `AudioServer.get_input_frames` Godot 4.7, запасной путь `AudioStreamMicrophone` и `AudioEffectCapture` на приглушённой шине. В распознавание уходит моно PCM 16 кГц, с 300 мс предзаписи. Удержание короче 300 мс или без энергии отбрасывается. На 60 с запись отправляется. Расшифровка — отдельный `generateContent`, модель `gemini-3.5-flash-lite`, тот же ключ, что у диалога, без смены модели. Распознавание только облачное, через сменный `SttBackend`. Соединение с generativelanguage.googleapis.com для обычных запросов держится и переиспользуется; поток озвучки берёт отдельное соединение и закрывает его. `audio/driver/enable_input` включён. Android: `RECORD_AUDIO` в манифесте; захват стартует только после `on_request_permissions_result`. Если `get_input_frames` не открылся или за удержание молчит около 400 мс, используется запасной путь. Пункт «Постоянное прослушивание» в списке есть и выключен.

## 4. Ход игрока: поток данных

Вопрос агенту `A`:

1. UI → `Game.ask(A, text)`. UI блокирует ввод (`busy_changed(true)`).
2. `EvidenceMatcher` проверяет текст. Если нашлась улика, UI уже показал подсказку до отправки, и игрок мог её предъявить (тогда сначала идёт поток «Предъявление», ниже).
3. `RulesEngine.note_question(A)` → отметка «был диалог» → каскад (могли открыться улики с `dialogue_with`).
4. `RulesEngine.get_packet(A)` → пакет фактов с ключами `k1…kn`.
5. `PromptBuilder.build_turn(...)` → системная инструкция, текст хода, схема с перечнем ключей пакета и `propertyOrdering`.
6. `LLM.client.generate(request)`. Ошибка сети или лимита → `llm_error`, состояние откатывается, конец хода. Повторный `ask` во время `is_busy` ничего не делает.
7. `ResponseValidator.validate(...)`. Мелкие ошибки (форма `stated`, лишние предложения, длина) правятся на месте. Повторная генерация только при пустой реплике, служебном слове или утечке. Снова не вышло → нейтральная уклончивая реплика, `statements = []`, тон 0.
8. `RulesEngine.register_statements(A, statements)` → журнал услышанного → автоматические противоречия → каскад.
9. `RulesEngine.apply_tone(A, tone)` → каскад. Тон влияет на давление со следующего хода (диздок, раздел 11).
10. `RulesEngine.set_emotion(A, emotion)`, если эмоция из списка.
11. `DialogueState` записывает реплику игрока и ответ (с ремаркой).
12. `Game` шлёт `agent_replied` и `events`. UI показывает ответ, ремарку состояния, всплывашки («Открыта улика», «Найдено противоречие»).
13. Если резюме пора обновить, `Summarizer` вызывается уже после показанной реплики, той же моделью. Ошибка не прячет реплику: берётся `Summarizer.apply_fallback`. После отката состояния диалог берётся заново из карты сессии, затем синхронизация и автосохранение.
14. `SaveState` — автосохранение. `busy_changed(false)`.

Предъявление улики `E` агенту `A`: `RulesEngine.present_evidence(A, E)` → каскад → затем обычный ход с шага 3, где вместо текста игрока стоит пометка события «Игрок предъявляет улику: <title> — <full_text>», чтобы агент отреагировал уже с новым пакетом.

Обвинение: `RulesEngine.check_accusation` → `AccusationResult` с галочками (диздок, раздел 4) → автосохранение.

## 5. Соответствие разделам диздока

| Раздел диздока | Модули |
|---|---|
| 1–2 Структура дела | CaseData, CaseLoader |
| 3 Улики и открытие | RulesEngine, Conditions |
| 4 Обвинение | Accusation, RulesEngine, экран обвинения |
| 5 Стартовое состояние | RulesEngine.start_new, GameState |
| 6 Связи | CaseValidator |
| 7 Валидация | CaseValidator (= tools/validate_case.py) |
| 8 Раскрытие фактов и ложь | RulesEngine.get_packet, ResponseValidator |
| 9 Контекст и промпт | PromptBuilder, DialogueState, Summarizer, ResponseValidator |
| 10 UX допроса | экраны UI, EvidenceMatcher, Notebook |
| 11 Давление и эмоция | Balance, RulesEngine |
| 12 Платформа и ИИ | LLMClient, GeminiClient, LLMConfig, SpeechBackend, экспорт |
| 13 Схема агента | CaseData, CaseValidator, PromptBuilder |
| 14 Противоречия | RulesEngine, Notebook |
| 15 Условия открытия | Conditions |

## 6. Сеть, Android и Windows

- В экспорте Android нужно включить разрешение `INTERNET`.
- HTTPS работает встроенными сертификатами Godot. Проверять на реальном устройстве (этап 9 плана).
- Настройки проекта для экрана: `display/window/stretch/mode = canvas_items`, `aspect = expand`, базовый размер 1280×800, ориентация Android — `sensor` (альбомная и книжная).
- Windows: `user://` — это `%APPDATA%\Godot\app_userdata\Detective` (или своя папка при `use_custom_user_dir`). Ключ хранится там же в `config.cfg`.
- На Android `user://` — личная папка приложения: ключ не виден другим приложениям, но доступен на рутованном устройстве. Для прототипа это приемлемо, для релиза нужен свой сервер (диздок, раздел 12).

## 7. Что не входит в прототип

Голос (этап 10 плана, модуль из раздела 3.12) и 3D-модели (этап 11) — следующие этапы после текстового прототипа, см. `docs/IMPLEMENTATION_PLAN.md`. Архитектура к ним готова: эмоция и ремарка в ответе модели — это данные для интонации и анимации.

## 8. Тесты

- **Свой минимальный раннер** `tests/run_tests.gd`, без GUT. Запуск: `godot --headless --path . -s res://tests/run_tests.gd`. Код выхода 0 — всё прошло, 1 — есть падения.
- Почему не GUT:
  - тестируется в основном чистая логика (`src/core`), для неё хватает `assert_eq` и `assert_true`;
  - нет внешней зависимости, которую надо обновлять вместе с Godot;
  - облачному агенту проще: один файл, понятный вывод.

  Если тестов станет много или понадобятся тесты сцен и моков узлов, можно перейти на GUT (раннер оставит тот же интерфейс: `test_*` методы в классах `extends TestCase`).
- Каждый тестовый файл `tests/test_<модуль>.gd` наследует `tests/test_case.gd`. Методы, начинающиеся с `test_`, запускаются по очереди. Асинхронные тесты ждут `await`.
