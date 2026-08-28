extends Control

const SAVE_PATH := "user://save_data.cfg"
const GAME_SCENE := "res://node_2d.tscn"

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

func _on_play_button_pressed() -> void:
	# Hangi bölümde olursa olsun her zaman ana oyun sahnesine git.
	# node_2d.gd save'den level_id'yi okuyup doğru bölümü yükler.
	get_tree().change_scene_to_file(GAME_SCENE)
