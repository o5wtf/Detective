@tool
extends EditorPlugin
## Кладёт в APK официальный sherpa-onnx arm64 и тонкий плагин Godot.
## Сами .so в git нет: их собирает tools/fetch_sherpa_android.py перед экспортом.


var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = _SherpaExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	if _export != null:
		remove_export_plugin(_export)
		_export = null


class _SherpaExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "SherpaOnnx"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		var paths := PackedStringArray([
			"sherpa_onnx/bin/sherpa-onnx-2.0.3-arm64.aar",
			"sherpa_onnx/bin/sherpa_godot-release.aar",
		])
		for relative in paths:
			if not FileAccess.file_exists("res://addons/%s" % relative):
				push_error("Нет addons/%s. Перед экспортом Android: python3 tools/fetch_sherpa_android.py" % relative)
		return paths

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["org.jetbrains.kotlin:kotlin-stdlib:2.1.21"])
