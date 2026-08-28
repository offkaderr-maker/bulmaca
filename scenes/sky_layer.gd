extends CanvasLayer

# ===========================================================================
# GÖKYÜZÜ KATMANI — Gradient arka plan + süzülen bulutlar
# Tamamen kod ile üretilir, dışarıdan texture gerekmez.
# ===========================================================================

const EKRAN_EN:    float = 540.0
const EKRAN_BOY:   float = 960.0

# Bulut tanımları: [başlangıç_x, y, genişlik, yükseklik, hız, alpha]
const BULUT_TANIMLARI = [
	# x_baslangic  y      en     boy   hiz    alpha
	[  -260.0,   90.0, 260.0,  55.0,  18.0,  0.18 ],
	[  -120.0,  200.0, 180.0,  40.0,  11.0,  0.13 ],
	[  -400.0,  330.0, 320.0,  65.0,  22.0,  0.15 ],
	[  -200.0,  470.0, 220.0,  45.0,  14.0,  0.11 ],
]

var _bulutlar: Array = []   # [{rect: ColorRect, hiz: float}]

func _ready() -> void:
	_arkaplan_olustur()
	_bulutlari_olustur()

# ---------------------------------------------------------------------------
# ARKA PLAN — GradientTexture2D ile dikey renk geçişi
# ---------------------------------------------------------------------------
func _arkaplan_olustur() -> void:
	# Gradient tanımla: üst = derin gökyüzü mavisi, alt = pastel açık mavi/turkuaz
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.133, 0.420, 0.776, 1.0),   # #2269C6 — derin gökyüzü mavisi
		Color(0.608, 0.847, 0.918, 1.0),   # #9BD8EA — ufuk turkuazı
	])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = gradient
	grad_tex.fill_from = Vector2(0.5, 0.0)
	grad_tex.fill_to   = Vector2(0.5, 1.0)
	grad_tex.width  = 4
	grad_tex.height = 64

	var bg := TextureRect.new()
	bg.texture              = grad_tex
	bg.stretch_mode         = TextureRect.STRETCH_SCALE
	bg.size                 = Vector2(EKRAN_EN, EKRAN_BOY)
	bg.position             = Vector2.ZERO
	bg.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

# ---------------------------------------------------------------------------
# BULUTLAR — Elips benzeri yuvarlak dikdörtgenler (StyleBoxFlat ile)
# ---------------------------------------------------------------------------
func _bulutlari_olustur() -> void:
	for tanim in BULUT_TANIMLARI:
		var x:     float = tanim[0]
		var y:     float = tanim[1]
		var en:    float = tanim[2]
		var boy:   float = tanim[3]
		var hiz:   float = tanim[4]
		var alpha: float = tanim[5]

		# Panel kullanarak yuvarlak köşeli "bulut" şekli yapıyoruz
		var panel := PanelContainer.new()
		panel.size            = Vector2(en, boy)
		panel.position        = Vector2(x, y)
		panel.mouse_filter    = Control.MOUSE_FILTER_IGNORE

		var style := StyleBoxFlat.new()
		style.bg_color          = Color(1.0, 1.0, 1.0, alpha)
		style.corner_radius_top_left     = int(boy * 0.5)
		style.corner_radius_top_right    = int(boy * 0.5)
		style.corner_radius_bottom_left  = int(boy * 0.5)
		style.corner_radius_bottom_right = int(boy * 0.5)
		style.shadow_color      = Color(0.8, 0.9, 1.0, alpha * 0.4)
		style.shadow_size       = 6
		panel.add_theme_stylebox_override("panel", style)

		add_child(panel)
		_bulutlar.append({"rect": panel, "hiz": hiz})

# ---------------------------------------------------------------------------
# BULUT HAREKETİ — Sağa süzülür, ekrandan çıkınca soldan yeniden doğar
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	for bulut in _bulutlar:
		var panel: PanelContainer = bulut["rect"]
		var hiz:   float          = bulut["hiz"]
		panel.position.x += hiz * delta

		# Bulut tamamen sağdan çıktıysa sol kenara reset
		if panel.position.x > EKRAN_EN + 20.0:
			panel.position.x = -panel.size.x - 10.0
