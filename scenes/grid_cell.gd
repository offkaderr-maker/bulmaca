extends Control

const CELL_SIZE := Vector2(64, 64)

func _ready() -> void:
	custom_minimum_size = CELL_SIZE
	size = CELL_SIZE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rect_node: ColorRect = $ColorRect
	rect_node.position = Vector2.ZERO
	rect_node.size = CELL_SIZE
	rect_node.z_index = 0
	rect_node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cell_label: Label = $Label
	cell_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cell_label.position = Vector2.ZERO
	cell_label.size = CELL_SIZE
	cell_label.z_index = 1
	cell_label.z_as_relative = true
	cell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func reveal_letter() -> void:
	$ColorRect.color = Color("#2ecc71")
	var cell_label: Label = $Label
	cell_label.z_index = 1
	if cell_label.label_settings:
		cell_label.label_settings = cell_label.label_settings.duplicate()
		cell_label.label_settings.font_color = Color.WHITE
	else:
		cell_label.add_theme_color_override("font_color", Color.WHITE)
	cell_label.text = str(get_meta("char"))
