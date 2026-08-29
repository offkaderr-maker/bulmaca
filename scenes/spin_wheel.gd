extends Control

# ===========================================================================
# GÜNLÜK ŞANS ÇARKI
# ===========================================================================

signal odul_kazanildi(miktar: int)

const SAVE_PATH     : String  = "user://save_data.cfg"
const GUNLUK_HAK    : int     = 5
const CARK_YARI_CAP : float   = 140.0
const MERKEZ        : Vector2 = Vector2(200, 210)

# ---------------------------------------------------------------------------
# Dilim tanımları: [ödül_altın, ihtimal_yüzdesi, renk]
# ---------------------------------------------------------------------------
const DILIMLER = [
	[2,  35, Color(0.95, 0.35, 0.35, 1.0)],
	[4,  30, Color(0.25, 0.55, 0.95, 1.0)],
	[6,  20, Color(0.25, 0.78, 0.42, 1.0)],
	[8,  10, Color(0.98, 0.78, 0.12, 1.0)],
	[10,  5, Color(0.75, 0.25, 0.95, 1.0)],
]

var _dilim_acilari: Array = []   # Array of Dictionary

# ---------------------------------------------------------------------------
# Animasyon durumu
# ---------------------------------------------------------------------------
var _aci_rad   : float = 0.0
var _hedef_aci : float = 0.0
var _hiz       : float = 0.0
var _doniyor   : bool  = false
var _kazanilan : int   = 0

# Günlük hak
var _bugun_kullanilan : int    = 0
var _son_tarih        : String = ""

# Node referansları — main_menu.gd tarafından set edilir
var cevirme_butonu : Button = null
var hak_label      : Label  = null
var sonuc_label    : Label  = null

# ===========================================================================
# HAZIRLIK
# ===========================================================================

func _ready() -> void:
	_dilim_acilerini_hesapla()
	_gunluk_durum_yukle()
	queue_redraw()

func _dilim_acilerini_hesapla() -> void:
	_dilim_acilari.clear()
	var toplam_aci: float = 0.0
	for d in DILIMLER:
		var oran    : float = float(d[1]) / 100.0
		var aciklik : float = oran * TAU
		_dilim_acilari.append({
			"baslangic": toplam_aci,
			"bitis"    : toplam_aci + aciklik,
			"odul"     : int(d[0]),
			"renk"     : Color(d[2]),
		})
		toplam_aci += aciklik

# ===========================================================================
# SAVE / LOAD
# ===========================================================================

func _bugun_tarih() -> String:
	var t: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [t["year"], t["month"], t["day"]]

func _gunluk_durum_yukle() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	_son_tarih        = str(cfg.get_value("cark", "son_tarih", ""))
	_bugun_kullanilan = int(cfg.get_value("cark", "bugun_kullanilan", 0))
	if _son_tarih != _bugun_tarih():
		_bugun_kullanilan = 0
		_son_tarih        = _bugun_tarih()
		_gunluk_durum_kaydet()
	_hak_etiketini_guncelle()

func _gunluk_durum_kaydet() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("cark", "son_tarih",        _son_tarih)
	cfg.set_value("cark", "bugun_kullanilan", _bugun_kullanilan)
	cfg.save(SAVE_PATH)

func kalan_hak() -> int:
	return max(0, GUNLUK_HAK - _bugun_kullanilan)

func _hak_etiketini_guncelle() -> void:
	if hak_label:
		if kalan_hak() > 0:
			hak_label.text = "Günlük hak: %d / %d" % [kalan_hak(), GUNLUK_HAK]
		else:
			hak_label.text = "Yarın yenilenir 🌙"
	if cevirme_butonu:
		cevirme_butonu.disabled = (_doniyor or kalan_hak() <= 0)
		cevirme_butonu.text     = "Yarın Gel" if kalan_hak() <= 0 else "ÇEVİR"

# ===========================================================================
# ÇARKI DÖNDÜR
# ===========================================================================

func cevir() -> void:
	if _doniyor or kalan_hak() <= 0:
		return

	var hedef_dilim_idx : int        = _odul_sec()
	var hedef_dilim     : Dictionary = _dilim_acilari[hedef_dilim_idx]
	_kazanilan = int(hedef_dilim["odul"])

	var dilim_ortasi : float = (float(hedef_dilim["baslangic"]) + float(hedef_dilim["bitis"])) / 2.0
	var kac_tur      : float = 5.0 + randf() * 3.0
	_hedef_aci = _aci_rad + kac_tur * TAU + _normalize_aci((-PI / 2.0) - dilim_ortasi - _aci_rad)

	_hiz     = 18.0
	_doniyor = true
	if sonuc_label:
		sonuc_label.text = ""
	if cevirme_butonu:
		cevirme_butonu.disabled = true

func _normalize_aci(a: float) -> float:
	while a < 0.0:
		a += TAU
	while a >= TAU:
		a -= TAU
	return a

func _odul_sec() -> int:
	var r   : float = randf() * 100.0
	var kum : float = 0.0
	for i in range(DILIMLER.size()):
		kum += float(DILIMLER[i][1])
		if r < kum:
			return i
	return DILIMLER.size() - 1

# ===========================================================================
# ANİMASYON
# ===========================================================================

func _process(delta: float) -> void:
	if not _doniyor:
		return
	var kalan : float = _hedef_aci - _aci_rad
	if kalan <= 0.0:
		_aci_rad = _hedef_aci
		_doniyor = false
		_donus_bitti()
		queue_redraw()
		return
	_hiz      = clamp(kalan * 4.0, 0.5, 18.0)
	_aci_rad += _hiz * delta
	queue_redraw()

func _donus_bitti() -> void:
	_bugun_kullanilan += 1
	_gunluk_durum_kaydet()
	_hak_etiketini_guncelle()
	if sonuc_label:
		sonuc_label.text = "+%d Altın Kazandın! 🪙" % _kazanilan
	odul_kazanildi.emit(_kazanilan)

# ===========================================================================
# ÇİZİM
# ===========================================================================

func _draw() -> void:
	var r      : float   = CARK_YARI_CAP
	var merkez : Vector2 = MERKEZ
	var seg    : int     = 60

	for dilim in _dilim_acilari:
		var renk  : Color = Color(dilim["renk"])
		var bas   : float = float(dilim["baslangic"]) + _aci_rad
		var bitis : float = float(dilim["bitis"])     + _aci_rad
		var pts   : PackedVector2Array = PackedVector2Array()
		pts.append(merkez)
		for j in range(seg + 1):
			var a : float = bas + (bitis - bas) * float(j) / float(seg)
			pts.append(merkez + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, renk)
		draw_line(merkez, merkez + Vector2(cos(bas), sin(bas)) * r,
			Color(1, 1, 1, 0.5), 1.5)

	draw_arc(merkez, r, 0.0, TAU, 80, Color(1, 1, 1, 0.85), 3.0)

	for dilim in _dilim_acilari:
		var bas      : float   = float(dilim["baslangic"]) + _aci_rad
		var bitis    : float   = float(dilim["bitis"])     + _aci_rad
		var orta     : float   = (bas + bitis) / 2.0
		var yazi_pos : Vector2 = merkez + Vector2(cos(orta), sin(orta)) * (r * 0.62)
		var metin    : String  = "%d🪙" % int(dilim["odul"])
		draw_string(ThemeDB.fallback_font,
			yazi_pos - Vector2(18, 10), metin,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 1))

	draw_circle(merkez, 34.0, Color(0.12, 0.12, 0.20, 0.95))
	draw_arc(merkez, 34.0, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 2.0)

	var ok_pts : PackedVector2Array = PackedVector2Array([
		merkez + Vector2(-10.0, -r - 6.0),
		merkez + Vector2( 10.0, -r - 6.0),
		merkez + Vector2(  0.0, -r + 14.0),
	])
	draw_colored_polygon(ok_pts, Color(1.0, 0.9, 0.1, 1.0))
	draw_polyline(ok_pts, Color(0.6, 0.4, 0.0, 1.0), 1.5, true)
