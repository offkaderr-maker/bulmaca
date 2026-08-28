extends Node2D

@export var cell_scene: PackedScene = preload("res://scenes/grid_cell.tscn")
@export var letter_button_scene: PackedScene = preload("res://scenes/letter_button.tscn")

var circle_center_pos: Vector2 = Vector2(270, 750) 
var circle_radius: float = 130.0 

# --- DEĞİŞKENLER ---
@onready var line_node: Line2D = $Line2D 
@onready var preview_label: Label = $PreviewLabel 
var is_dragging: bool = false 
var selected_buttons: Array = [] 
var current_word: String = "" 
var valid_words: Array = [] 

var word_cells_map: Dictionary = {}
var discovered_words: Array = []

func _ready() -> void:
	load_and_build_puzzle()

func load_and_build_puzzle() -> void:
	var file = FileAccess.open("res://bulmaca_cikisi.json", FileAccess.READ)
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
	
	var area_node = letter_instance.get_node("Area2D")
	area_node.connect("mouse_entered", Callable(self, "_on_letter_entered").bind(letter_instance))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			preview_label.text = "" 
		else:
			is_dragging = false
			check_final_word()

func _on_letter_entered(button_node: Node) -> void:
	if not is_dragging:
		return 
		
	if not selected_buttons.has(button_node):
		selected_buttons.append(button_node)
		
		var char_val = button_node.get_meta("char")
		current_word += char_val
		preview_label.text = current_word
		
		var btn_node = button_node.get_node("Button")
		var btn_center = button_node.global_position + (btn_node.size / 2.0)
		line_node.add_point(btn_center)

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
			var cell_label = find_label_recursive(cell)
			var rect_node = find_color_rect_recursive(cell)
			
			# Önce kutuyu yeşile boyuyoruz
			if rect_node:
				rect_node.color = Color("#2ecc71")
				rect_node.z_index = 0 # Kutunun katmanını arkaya kilitle 🧱
				
			if cell_label:
				# KATMAN MUCİZESİ: Harf kutunun neresinde olursa olsun onu en ön katmana zorla! 🚀
				cell_label.z_index = 1 
				cell_label.add_theme_color_override("font_color", Color.WHITE) # Rengi beyaz yap
				cell_label.text = cell.get_meta("char") # Harfi bas
			
		if discovered_words.size() == word_cells_map.size():
			print("BÖLÜM BİTTİ KANKA! 🎉")
	else:
		print("Yanlış kelime!")
		
	current_word = ""
	preview_label.text = "" 
	selected_buttons.clear()
	line_node.clear_points()

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
