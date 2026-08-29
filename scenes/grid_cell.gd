extends Control

const CELL_SIZE := Vector2(64, 64)

# Kapalı hücre stili: yarı şeffaf beyaz, yuvarlatılmış köşeler
var _style_kapali: StyleBoxFlat
# Açık hücre stili: yeşil ton, yuvarlatılmış köşeler
var _style_acik: StyleBoxFlat

func _ready() -> void:
	custom_minimum_size = CELL_SIZE
	size = CELL_SIZE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Panel node (tscn'de ColorRect'in yerini aldı)
	var panel_node: Panel = $Panel
	panel_node.position     = Vector2.ZERO
	panel_node.size         = CELL_SIZE
	panel_node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Kapalı kutu stili
	_style_kapali = StyleBoxFlat.new()
	_style_kapali.bg_color                      = Color(1.0, 1.0, 1.0, 0.28)
	_style_kapali.border_color                  = Color(1.0, 1.0, 1.0, 0.55)
	_style_kapali.set_border_width_all(1)
	_style_kapali.set_corner_radius_all(10)
	_style_kapali.shadow_color                  = Color(0.0, 0.15, 0.35, 0.18)
	_style_kapali.shadow_size                   = 4

	# Açık kutu stili (reveal sonrası)
	_style_acik = StyleBoxFlat.new()
	_style_acik.bg_color                        = Color(0.18, 0.78, 0.45, 0.92)
	_style_acik.border_color                    = Color(0.10, 0.65, 0.35, 1.0)
	_style_acik.set_border_width_all(1)
	_style_acik.set_corner_radius_all(10)
	_style_acik.shadow_color                    = Color(0.0, 0.30, 0.15, 0.25)
	_style_acik.shadow_size                     = 5

	panel_node.add_theme_stylebox_override("panel", _style_kapali)

	# Label
	var cell_label: Label = $Label
	cell_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cell_label.position     = Vector2.ZERO
	cell_label.size         = CELL_SIZE
	cell_label.z_index      = 2
	cell_label.z_as_relative = true
	cell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

func reveal_letter() -> void:
	var panel_node: Panel = $Panel
	panel_node.add_theme_stylebox_override("panel", _style_acik)

	var cell_label: Label = $Label
	cell_label.z_index = 2
	# Açık hücrede harf siyah ve net
	if cell_label.label_settings:
		cell_label.label_settings = cell_label.label_settings.duplicate()
		cell_label.label_settings.font_color = Color(0.0, 0.0, 0.0, 1.0)
	else:
		cell_label.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
	cell_label.text = str(get_meta("char"))
