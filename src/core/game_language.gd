class_name GameLanguage
extends RefCounted
## Язык новых строк. Сейчас только русский. Старые строки игры здесь не дублируются.


const CODE := "ru"

const LINES := {
	"ru": {
		"stt_label": "Распознавание речи",
		"stt_cloud": "Облако (Gemini)",
		"stt_device": "На устройстве (Parakeet, бета)",
		"model_download": "Скачать модель (~640 МБ)",
		"model_delete": "Удалить модель",
		"model_cancel": "Отмена",
		"model_wifi": "≈640 МБ, лучше по Wi-Fi",
		"model_space": "Не хватает места. Нужно около 0,8 ГБ.",
		"model_corrupt": "Файл повреждён, скачайте ещё раз",
		"model_load_failed": "Модель не загрузилась",
		"model_ready": "Модель скачана",
		"model_stopped": "Загрузка прервана. Нажмите ещё раз — скачивание продолжится.",
		"stt_repeat": "Не расслышал, повторите",
		"stt_prompt": "Дословно расшифруй русскую речь. Верни только текст. Если речи нет или слышен только шум, верни пустой ответ: без цифр, времени, пояснений и знаков.",
		"stt_hint": "Возможные имена и слова из дела. Используй их написание, только если они действительно звучат в записи; не добавляй их, если их не произнесли: ",
		"model_license": "Модель NVIDIA Parakeet TDT 0.6B v3, лицензия CC-BY-4.0. Экспорт sherpa-onnx — Apache-2.0. NVIDIA не поддерживает этот продукт.",
	},
}


static func text(key: String) -> String:
	var table: Dictionary = LINES.get(CODE, {})
	return str(table.get(key, key))
