extends Control

const SAVE_PATH  := "user://save_data.cfg"
const GAME_SCENE := "res://node_2d.tscn"

# ---------------------------------------------------------------------------
# Ana menü node'ları
# ---------------------------------------------------------------------------
@onready var play_button  : Button = $UI/OrtaPanel/VBox/PlayButton
@onready var level_label  : Label  = $UI/OrtaPanel/VBox/LevelLabel
@onready var cark_ac_buton: Button = $UI/OrtaPanel/VBox/CarkButonAlani/CarkAcButon

# ---------------------------------------------------------------------------
# Çark popup node'ları
# ---------------------------------------------------------------------------
@onready var cark_layer   : CanvasLayer = $CarkLayer
@onready var cark_node                  = $CarkLayer/PopupPanel/IcVBox/CarkNode
@onready var cevir_buton  : Button      = $CarkLayer/PopupPanel/IcVBox/CevirButon
@onready var hak_label    : Label       = $CarkLayer/PopupPanel/IcVBox/HakLabel
@onready var sonuc_label  : Label       = $CarkLayer/PopupPanel/IcVBox/SonucLabel

# ===========================================================================
# HAZIRLIK
# ===========================================================================

func _ready() -> void:
	_uygula_pastel_cark_rengi()

	# Çark node'una referansları enjekte et
	cark_node.cevirme_butonu = cevir_buton
	cark_node.hak_label      = hak_label
	cark_node.sonuc_label    = sonuc_label

	# Ödül sinyalini bağla
	cark_node.odul_kazanildi.connect(_on_odul_kazanildi)

	# Popup başta gizli
	cark_layer.visible = false

	# Ana menü metinlerini ayarla
	_ana_menu_guncelle()

	# Çark açma butonunu günlük hak durumuna göre güncelle
	_cark_ac_buton_guncelle()

func _uygula_pastel_cark_rengi() -> void:
	if not cark_node or not cark_node.has_method("_draw"):
		return

	var pastel_dilimler := [
		[2, 35, Color(0.94, 0.72, 0.76, 1.0)],
		[4, 30, Color(0.70, 0.83, 0.97, 1.0)],
		[6, 20, Color(0.71, 0.92, 0.81, 1.0)],
		[8, 10, Color(0.97, 0.89, 0.68, 1.0)],
		[10, 5, Color(0.81, 0.71, 0.95, 1.0)],
	]

	var toplam_aci: float = 0.0
	cark_node._dilim_acilari.clear()
	for dilim in pastel_dilimler:
		var oran: float = float(dilim[1]) / 100.0
		var aciklik: float = oran * TAU
		cark_node._dilim_acilari.append({
			"baslangic": toplam_aci,
			"bitis": toplam_aci + aciklik,
			"odul": int(dilim[0]),
			"renk": Color(dilim[2]),
		})
		toplam_aci += aciklik

	cark_node.queue_redraw()

func _ana_menu_guncelle() -> void:
	var level_id := _load_saved_level_id()
	if FileAccess.file_exists(SAVE_PATH) and level_id > 1:
		play_button.text = "KALDIĞIN YERDEN DEVAM ET"
		level_label.text = "%d. Bölümden devam ediliyor" % level_id
	else:
		play_button.text = "OYUNA BAŞLA"
		level_label.text = "500 bölüm · Kelime bulmaca"

func _cark_ac_buton_guncelle() -> void:
	var kalan : int = cark_node.kalan_hak()
	if kalan > 0:
		cark_ac_buton.text     = "🎡 Günlük Çarkı Çevir  (%d hak)" % kalan
		cark_ac_buton.disabled = false
	else:
		cark_ac_buton.text     = "🎡 Çark — Yarın Yenilenir 🌙"
		cark_ac_buton.disabled = true

# ===========================================================================
# ANA MENÜ SİNYALLERİ
# ===========================================================================

func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_cark_ac_pressed() -> void:
	sonuc_label.text   = ""
	cark_layer.visible = true

# ===========================================================================
# ÇARK POPUP SİNYALLERİ
# ===========================================================================

func _on_cark_kapat_pressed() -> void:
	cark_layer.visible = false
	# Popup kapanınca ana menü butonunu güncelle
	_cark_ac_buton_guncelle()

func _on_cevir_pressed() -> void:
	cark_node.cevir()

# Çark durduğunda spin_wheel.gd bu sinyali emit eder
func _on_odul_kazanildi(miktar: int) -> void:
	_altin_ekle(miktar)
	_cark_ac_buton_guncelle()

# ===========================================================================
# ALTIN — save_data.cfg'ye yaz (node_2d.gd ile aynı key yapısı)
# ===========================================================================

func _altin_ekle(miktar: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var mevcut : int = int(cfg.get_value("progress", "altin", 0))
	cfg.set_value("progress", "altin", mevcut + miktar)
	cfg.save(SAVE_PATH)
	print("Çark ödülü eklendi: +%d altın (toplam: %d)" % [miktar, mevcut + miktar])

# ===========================================================================
# YARDIMCI
# ===========================================================================

func _load_saved_level_id() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 1
	return int(cfg.get_value("progress", "level_id", 1))
