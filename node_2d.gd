extends Node2D

@export var cell_scene: PackedScene = preload("res://scenes/grid_cell.tscn")
@export var letter_button_scene: PackedScene = preload("res://scenes/letter_button.tscn")

var circle_center_pos: Vector2 = Vector2(270, 750) 
var circle_radius: float = 130.0 

# --- DEĞİŞKENLER ---
@onready var line_node: Line2D = $Line2D 
@onready var preview_label: Label = $PreviewLabel 
@onready var win_panel: Control = $WinLayer/WinPanel 
var is_dragging: bool = false 
var selected_buttons: Array = [] 
var current_word: String = "" 
var valid_words: Array = [] 

var word_cells_map: Dictionary = {}
var discovered_words: Array = []
var letter_buttons: Array = []
var last_drag_pos: Vector2 = Vector2.ZERO
const LETTER_HIT_RADIUS: float = 48.0
const SAVE_PATH: String = "user://save_data.cfg"
var current_level_id: int = 1

func _ready() -> void:
	current_level_id = _load_saved_level_id()
	var next_scene := _scene_path_for_level(current_level_id)
	if next_scene != "" and next_scene != scene_file_path:
		get_tree().change_scene_to_file(next_scene)
		return
	load_and_build_puzzle()

func _json_path_for_level(level_id: int) -> String:
	if level_id <= 1:
		return "res://bulmaca_cikisi.json"
	var numbered := "res://bulmaca_cikisi_%d.json" % level_id
	if FileAccess.file_exists(numbered):
		return numbered
	return "res://bulmaca_cikisi.json"

func _scene_path_for_level(level_id: int) -> String:
	if level_id <= 1:
		return ""
	var numbered := "res://bulmaca_cikisi_%d.json" % level_id
	if FileAccess.file_exists(numbered):
		return ""
	return "res://scenes/bolum_2.tscn"

func _save_level_id(level_id: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("progress", "level_id", level_id)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		print("Kayıt yazılamadı: ", SAVE_PATH, " hata=", err)
	else:
		print("İlerleme kaydedildi (telefon/user://): level_id=", level_id)

func _load_saved_level_id() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 1
	return int(cfg.get_value("progress", "level_id", 1))

func load_and_build_puzzle() -> void:
	var file = FileAccess.open(_json_path_for_level(current_level_id), FileAccess.READ)
	if not file:
		print("Hata: JSON dosyası bulunamadı kanka!")
		return
		
	var json_text = file.get_as_text()
	file.close()
	
	var puzzle_data = JSON.parse_string(json_text)
	valid_words = puzzle_data["valid_word_list"] 
	
	var box = puzzle_data["bounding_box"]
	var grid_width_cells = (box["max_x"] - box["min_x"]) + 1
	var grid_height_cells = (box["max_y"] - box["min_y"]) + 1
	
	var max_allowed_width: float = 460.0
	var max_allowed_height: float = 380.0
	
	var scale_x = max_allowed_width / (grid_width_cells * 64.0)
	var scale_y = max_allowed_height / (grid_height_cells * 64.0)
	var final_scale_factor = min(scale_x, scale_y)
	
	final_scale_factor = clamp(final_scale_factor, 0.4, 0.9)
	var dynamic_cell_spacing = 64.0 * final_scale_factor + (6.0 * final_scale_factor)
	
	var total_grid_pixel_width = grid_width_cells * dynamic_cell_spacing
	var total_grid_pixel_height = grid_height_cells * dynamic_cell_spacing
	
	var start_x = (540.0 - total_grid_pixel_width) / 2.0 + (32.0 * final_scale_factor)
	var start_y = 120.0 + ((max_allowed_height - total_grid_pixel_height) / 2.0) + (32.0 * final_scale_factor)
	
	var grid_start_pos = Vector2(start_x, start_y)
	var created_cells: Dictionary = {}
	
	var placed_words = puzzle_data["words_on_board"]
	for word_data in placed_words:
		var w_string = word_data["word"]
		word_cells_map[w_string] = [] 
		
		var cells = word_data["cells"]
		for cell_info in cells:
			var gx = cell_info["x"]
			var gy = cell_info["y"]
			var char_text = cell_info["char"]
			var coord_key = Vector2(gx, gy)
			
			var cell_instance: Node
			
			if not created_cells.has(coord_key):
				cell_instance = cell_scene.instantiate()
				add_child(cell_instance)
				
				var pixel_x = grid_start_pos.x + (gx * dynamic_cell_spacing)
				var pixel_y = grid_start_pos.y + (gy * dynamic_cell_spacing)
				
				cell_instance.global_position = Vector2(pixel_x, pixel_y) - Vector2(32, 32) * final_scale_factor
				cell_instance.scale = Vector2(final_scale_factor, final_scale_factor)
				
				var cell_label = find_label_recursive(cell_instance)
				if cell_label:
					cell_label.text = "" 
				
				cell_instance.set_meta("char", char_text)
				created_cells[coord_key] = cell_instance
			else:
				cell_instance = created_cells[coord_key]
			
			word_cells_map[w_string].append(cell_instance)
			
	var circle_layout = puzzle_data["circle_layout"]
	for letter_data in circle_layout:
		spawn_letter_on_circle(letter_data["char"], letter_data["angle_rad"])

func spawn_letter_on_circle(char_text: String, angle_rad: float) -> void:
	var letter_instance = letter_button_scene.instantiate()
	add_child(letter_instance)
	
	var spawn_pos = Vector2(
		circle_center_pos.x + cos(angle_rad) * circle_radius,
		circle_center_pos.y + sin(angle_rad) * circle_radius
	)
	
	var btn_node = letter_instance.get_node("Button")
	var half_size = btn_node.size / 2.0
	letter_instance.global_position = spawn_pos - half_size
	
	var btn_label = find_label_recursive(letter_instance)
	if btn_label:
		btn_label.text = char_text
		
	letter_instance.set_meta("char", char_text)
	letter_buttons.append(letter_instance)

func _letter_center(button_node: Node) -> Vector2:
	var btn_node = button_node.get_node("Button")
	return button_node.global_position + (btn_node.size / 2.0)

func _pick_letters_along_segment(from_pos: Vector2, to_pos: Vector2) -> void:
	var hits: Array = []
	for button_node in letter_buttons:
		if selected_buttons.has(button_node):
			continue
		var center = _letter_center(button_node)
		var closest = Geometry2D.get_closest_point_to_segment(center, from_pos, to_pos)
		if closest.distance_to(center) <= LETTER_HIT_RADIUS:
			hits.append([from_pos.distance_to(closest), button_node])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	for hit in hits:
		_on_letter_entered(hit[1])

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_W:
		_show_level_complete_panel()
		return
	if win_panel.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			preview_label.text = ""
			last_drag_pos = get_global_mouse_position()
			_pick_letters_along_segment(last_drag_pos, last_drag_pos)
		else:
			is_dragging = false
			check_final_word()
	elif event is InputEventMouseMotion and is_dragging:
		var now = get_global_mouse_position()
		_pick_letters_along_segment(last_drag_pos, now)
		last_drag_pos = now

func _on_letter_entered(button_node: Node) -> void:
	if not is_dragging:
		return 
		
	if not selected_buttons.has(button_node):
		selected_buttons.append(button_node)
		
		var char_val = button_node.get_meta("char")
		current_word += char_val
		preview_label.text = current_word
		
		line_node.add_point(_letter_center(button_node))

func _process(_delta: float) -> void:
	if is_dragging and selected_buttons.size() > 0:
		var mouse_pos = get_global_mouse_position()
		
		if line_node.points.size() > selected_buttons.size():
			line_node.set_point_position(line_node.points.size() - 1, mouse_pos)
		else:
			line_node.add_point(mouse_pos)

# --- SÜPER KATMAN DESTEKLİ KONTROL MOTORU ---
func check_final_word() -> void:
	if discovered_words.has(current_word):
		print("Bu kelimeyi zaten buldun kanka!")
	elif word_cells_map.has(current_word):
		print("Tebrikler kanka! Şerit açılıyor: ", current_word)
		discovered_words.append(current_word)
		
		var cells_to_open = word_cells_map[current_word]
		for cell in cells_to_open:
			cell.reveal_letter()
			
		if discovered_words.size() == word_cells_map.size():
			print("BÖLÜM BİTTİ KANKA! 🎉")
			_show_level_complete_panel()
	else:
		print("Yanlış kelime!")
		
	current_word = ""
	preview_label.text = "" 
	selected_buttons.clear()
	line_node.clear_points()

func _show_level_complete_panel() -> void:
	is_dragging = false
	win_panel.visible = true

func _on_next_level_pressed() -> void:
	current_level_id += 1
	_save_level_id(current_level_id)
	var next_scene := _scene_path_for_level(current_level_id)
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)
	else:
		get_tree().reload_current_scene()

func find_label_recursive(node: Node) -> Label:
	if node is Label:
		return node
	for child in node.get_children():
		var res = find_label_recursive(child)
		if res: return res
	return null

func find_color_rect_recursive(node: Node) -> ColorRect:
	if node is ColorRect:
		return node
	for child in node.get_children():
		var res = find_color_rect_recursive(child)
		if res: return res
	return null
