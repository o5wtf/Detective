class_name SherpaNative
extends RefCounted
## Заглушка нативной библиотеки sherpa-onnx.
## Сборки arm64 в этом PR нет: available() остаётся false, модель в память не грузится.
## Следующий PR подставляет реальную библиотеку и грузит её в фоновом потоке.


func available() -> bool:
	return false


func transcribe_wav(_wav: PackedByteArray) -> Dictionary:
	return {"text": "", "crash": false}
