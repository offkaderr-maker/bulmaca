extends Control

const SAVE_PATH  := "user://save_data.cfg"
const GAME_SCENE := "res://node_2d.tscn"

@onready var play_button:  Button = $UI/OrtaPanel/VBox/PlayButton
@onready var level_label:  Label  = $UI/OrtaPanel/VBox/LevelLabel

func _ready() -> void:
	var level_id := _load_saved_level_id()

	if FileAccess.file_exists(SAVE_PATH) and level_id > 1:
		play_button.text  = "KALDIĞIN YERDEN DEVAM ET"
		level_label.text  = "%d. Bölümden devam ediliyor" % level_id
	else:
		play_button.text  = "OYUNA BAŞLA"
		level_label.text  = "500 bölüm · Kelime bulmaca"

func _load_saved_level_id() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 1
	return int(cfg.get_value("progress", "level_id", 1))

func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
