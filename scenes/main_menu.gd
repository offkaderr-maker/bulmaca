extends Control

const SAVE_PATH := "user://save_data.cfg"
const GAME_SCENE := "res://node_2d.tscn"
const FALLBACK_NEXT_SCENE := "res://scenes/bolum_2.tscn"

@onready var play_button: Button = $Center/VBox/PlayButton

func _ready() -> void:
	var level_id := _load_saved_level_id()
	if FileAccess.file_exists(SAVE_PATH) and level_id > 1:
		play_button.text = "KALDIĞIN YERDEN DEVAM ET"
	else:
		play_button.text = "OYUNA BAŞLA"

func _load_saved_level_id() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 1
	return int(cfg.get_value("progress", "level_id", 1))

func _scene_for_level(level_id: int) -> String:
	if level_id <= 1:
		return GAME_SCENE
	var numbered := "res://bulmaca_cikisi_%d.json" % level_id
	if FileAccess.file_exists(numbered):
		return GAME_SCENE
	return FALLBACK_NEXT_SCENE

func _on_play_button_pressed() -> void:
	var level_id := _load_saved_level_id()
	var target := _scene_for_level(level_id)
	get_tree().change_scene_to_file(target)
