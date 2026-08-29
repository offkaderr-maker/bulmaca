extends Node2D

@export var cell_scene: PackedScene = preload("res://scenes/grid_cell.tscn")
@export var letter_button_scene: PackedScene = preload("res://scenes/letter_button.tscn")

# Başlangıç değerleri — _ready()'de viewport'a göre yeniden hesaplanır
var circle_center_pos: Vector2 = Vector2(270, 750)
var circle_radius: float = 130.0

# Viewport'tan türetilen grid kısıtları — load_and_build_puzzle() bunları kullanır
var _vp_grid_max_w: float  = 460.0
var _vp_grid_max_h: float  = 380.0
var _vp_grid_start_y: float = 120.0

# --- TEMEL DEĞİŞKENLER ---
@onready var line_node: Line2D = $Line2D
@onready var preview_label: Label = $PreviewLabel
@onready var win_panel: Control = $WinLayer/WinPanel
@onready var altin_label: Label = $HudLayer/AltinLabel
@onready var ipucu_button: Button = $HudLayer/IpucuButton

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
const ALTIN_KELIME_ODULU: int = 3      # her doğru kelime için
const ALTIN_BOLUM_ODULU: int = 5       # bölüm tamamen bitince bonus
const ALTIN_IPUCU_MALIYETI: int = 10   # ipucu için gereken altın

var current_level_id: int = 1
var altin: int = 0

# Henüz açılmamış tüm hücreleri hızlıca bulmak için tutuyoruz
# key = Vector2(gx,gy)  →  value = cell node
var tum_hucreler: Dictionary = {}

# ===========================================================================
# BAŞLANGIÇ
# ===========================================================================

func _ready() -> void:
	# --- Viewport'a göre dinamik konumlandırma ---
	# stretch/aspect="keep" ile viewport her zaman 540×960 oranında gelir;
	# ama güvenli taraf için her zaman gerçek görünür boyutu sorguluyoruz.
	var vp := get_viewport().get_visible_rect().size
	var vw := vp.x   # örn. 540
	var vh := vp.y   # örn. 960

	# Harf çemberi: yatay orta, alt %22'sinin ortasında
	circle_center_pos = Vector2(vw * 0.5, vh * 0.78)
	# Çember yarıçapı: genişliğin %24'ü (540'ta 130px)
	circle_radius = vw * 0.24

	# Grid kısıtları: ekranın %85 genişliği, üst %50'si yüksekliği
	_vp_grid_max_w    = vw * 0.852    # 540×0.852 ≈ 460
	_vp_grid_max_h    = vh * 0.396    # 960×0.396 ≈ 380
	_vp_grid_start_y  = vh * 0.125    # 960×0.125 = 120

	# --- Normal başlangıç akışı ---
	current_level_id = _load_saved_level_id()
	altin = _load_saved_altin()
	_altin_guncelle()
	load_and_build_puzzle()

# ===========================================================================
# ALTIN SİSTEMİ
# ===========================================================================

func _altin_kazan(miktar: int) -> void:
	altin += miktar
	_altin_kaydet()
	_altin_guncelle()

func _altin_harca(miktar: int) -> bool:
	if altin < miktar:
		return false
	altin -= miktar
	_altin_kaydet()
	_altin_guncelle()
	return true

func _altin_guncelle() -> void:
	if altin_label:
		altin_label.text = "🪙 %d" % altin
	# İpucu butonunu aktif/pasif et
	if ipucu_button:
		ipucu_button.disabled = (altin < ALTIN_IPUCU_MALIYETI)

func _altin_kaydet() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("progress", "altin", altin)
	cfg.save(SAVE_PATH)

func _load_saved_altin() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0
	return int(cfg.get_value("progress", "altin", 0))

# ===========================================================================
# KAYIT / YÜKLEME
# ===========================================================================

func _save_level_id(level_id: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("progress", "level_id", level_id)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		print("Kayıt yazılamadı: ", err)
	else:
		print("Kaydedildi: level_id=", level_id)

func _load_saved_level_id() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 1
	return int(cfg.get_value("progress", "level_id", 1))

# Mevcut bölümde bulunan kelimeleri anlık kaydet.
# Her doğru kelimede çağrılır.
func _discovered_words_kaydet() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var key := "bolum_%d" % current_level_id
	cfg.set_value("words", key, discovered_words)
	cfg.save(SAVE_PATH)

# Bölüm yüklendikten sonra, kaydedilmiş kelimeleri oku ve
# ilgili hücreleri otomatik olarak aç (yeşil/reveal).
func _discovered_words_yukle() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var key  := "bolum_%d" % current_level_id
	var kayitli = cfg.get_value("words", key, [])
	if kayitli.is_empty():
		return

	for kelime in kayitli:
		if word_cells_map.has(kelime) and not discovered_words.has(kelime):
			discovered_words.append(kelime)
			for cell in word_cells_map[kelime]:
				cell.reveal_letter()
				cell.set_meta("revealed", true)

	print("Kaldığın yerden devam: ", discovered_words.size(), " kelime geri yüklendi.")

# Bölüm tamamlandığında o bölümün kelime kaydını sil — artık gerek yok.
func _bolum_kelime_kaydi_temizle(level_id: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var key := "bolum_%d" % level_id
	cfg.erase_section_key("words", key)
	cfg.save(SAVE_PATH)

# ===========================================================================
# BÖLÜM VERİSİ
# ===========================================================================

func _bolum_verisini_getir(level_id: int) -> Dictionary:
	var dosya_yolu := "res://bolumler_listesi.json"
	var file = FileAccess.open(dosya_yolu, FileAccess.READ)
	if not file:
		print("Hata: bolumler_listesi.json bulunamadı!")
		return {}
	var json_text = file.get_as_text()
	file.close()

	var liste_verisi = JSON.parse_string(json_text)
	if liste_verisi == null or not liste_verisi.has("bolumler"):
		print("Hata: bolumler_listesi.json geçersiz format!")
		return {}

	var bolumler: Array = liste_verisi["bolumler"]
	for bolum in bolumler:
		if int(bolum.get("level_id", -1)) == level_id:
			return bolum

	print("Uyarı: level_id=", level_id, " bulunamadı, bölüm 1'e dönülüyor.")
	if bolumler.size() > 0:
		return bolumler[0]
	return {}

# ===========================================================================
# ÇEMBER ARKA PLAN ÇİZİMİ (draw API — gökyüzü temasıyla uyumlu)
# ===========================================================================

func _draw() -> void:
	# Harf çemberinin altına yarı şeffaf disk çiz
	var disk_radius: float = circle_radius + 52.0
	# Dış parlak halka
	draw_circle(circle_center_pos, disk_radius,       Color(1.0, 1.0, 1.0, 0.10))
	# İç dolgu
	draw_circle(circle_center_pos, disk_radius - 6.0, Color(1.0, 1.0, 1.0, 0.14))
	# İnce border çemberi
	var border_segments := 64
	var pts := PackedVector2Array()
	for i in range(border_segments + 1):
		var a := (2.0 * PI / border_segments) * i
		pts.append(circle_center_pos + Vector2(cos(a), sin(a)) * (disk_radius - 2.0))
	draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.40), 2.0, true)

# ===========================================================================
# BÖLÜM YÜKLEME / İNŞA
# ===========================================================================

func load_and_build_puzzle() -> void:
	var puzzle_data: Dictionary = _bolum_verisini_getir(current_level_id)
	if puzzle_data.is_empty():
		print("Hata: Bölüm verisi alınamadı! level_id=", current_level_id)
		return

	valid_words = puzzle_data["valid_word_list"]

	var box = puzzle_data["bounding_box"]
	var grid_width_cells  = (box["max_x"] - box["min_x"]) + 1
	var grid_height_cells = (box["max_y"] - box["min_y"]) + 1

	var max_allowed_width:  float = _vp_grid_max_w
	var max_allowed_height: float = _vp_grid_max_h

	var scale_x = max_allowed_width  / (grid_width_cells  * 64.0)
	var scale_y = max_allowed_height / (grid_height_cells * 64.0)
	var final_scale_factor = clamp(min(scale_x, scale_y), 0.4, 0.9)
	var dynamic_cell_spacing = 64.0 * final_scale_factor + (6.0 * final_scale_factor)

	var total_grid_pixel_width  = grid_width_cells  * dynamic_cell_spacing
	var total_grid_pixel_height = grid_height_cells * dynamic_cell_spacing

	var vw := get_viewport().get_visible_rect().size.x
	var start_x = (vw - total_grid_pixel_width)  / 2.0 + (32.0 * final_scale_factor)
	var start_y = _vp_grid_start_y + ((max_allowed_height - total_grid_pixel_height) / 2.0) + (32.0 * final_scale_factor)

	var grid_start_pos = Vector2(start_x, start_y)
	var created_cells: Dictionary = {}

	var placed_words = puzzle_data["words_on_board"]
	for word_data in placed_words:
		var w_string = word_data["word"]
		word_cells_map[w_string] = []

		for cell_info in word_data["cells"]:
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
				cell_instance.set_meta("revealed", false)
				created_cells[coord_key] = cell_instance
				tum_hucreler[coord_key] = cell_instance
			else:
				cell_instance = created_cells[coord_key]

			word_cells_map[w_string].append(cell_instance)

	var circle_layout = puzzle_data["circle_layout"]
	for letter_data in circle_layout:
		spawn_letter_on_circle(letter_data["char"], letter_data["angle_rad"])

	# Grid ve harf çemberi hazır — kaydedilmiş kelimeleri geri yükle
	_discovered_words_yukle()

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

# ===========================================================================
# İPUCU / HARF SATIN ALMA
# ===========================================================================

func _on_ipucu_pressed() -> void:
	# Henüz açılmamış hücreleri topla
	var kapali_hucreler: Array = []
	for coord in tum_hucreler:
		var cell = tum_hucreler[coord]
		if is_instance_valid(cell) and not cell.get_meta("revealed", false):
			kapali_hucreler.append(cell)

	if kapali_hucreler.is_empty():
		print("Tüm harfler zaten açık!")
		return

	# Altın yeterli mi?
	if not _altin_harca(ALTIN_IPUCU_MALIYETI):
		print("Yeterli altın yok! Gereken: ", ALTIN_IPUCU_MALIYETI, " Mevcut: ", altin)
		return

	# Rastgele bir kapalı hücreyi aç
	kapali_hucreler.shuffle()
	var hedef_hucre = kapali_hucreler[0]
	hedef_hucre.reveal_letter()
	hedef_hucre.set_meta("revealed", true)

	print("İpucu kullanıldı! -", ALTIN_IPUCU_MALIYETI, " altın")

	# Eğer tüm bölüm bu açılmayla tamamlandıysa bölüm bitişini tetikle
	_ipucu_sonrasi_bitis_kontrol()
	# İpucu sonrası güncel kelime listesini kaydet
	_discovered_words_kaydet()

func _ipucu_sonrasi_bitis_kontrol() -> void:
	# Her kelimede en az bir kapalı hücre var mı kontrol et
	for kelime in word_cells_map:
		if discovered_words.has(kelime):
			continue
		# Bu kelimeye ait tüm hücreler açıldıysa kelimeyi keşfedilmiş say
		var hepsi_acik = true
		for cell in word_cells_map[kelime]:
			if not cell.get_meta("revealed", false):
				hepsi_acik = false
				break
		if hepsi_acik and not discovered_words.has(kelime):
			discovered_words.append(kelime)

	if discovered_words.size() == word_cells_map.size():
		print("İpucuyla bölüm tamamlandı!")
		_show_level_complete_panel()

# ===========================================================================
# SÜRÜKLEME / GİRİŞ
# ===========================================================================

func _letter_center(button_node: Node) -> Vector2:
	var btn_node = button_node.get_node("Button")
	return button_node.global_position + (btn_node.size / 2.0)

func _pick_letters_along_segment(from_pos: Vector2, to_pos: Vector2) -> void:
	# Sadece anlık parmak pozisyonunu kullan — segment yakınlığı değil,
	# harf merkezine doğrudan mesafe kontrolü yapar. Bu sayede çizgi
	# harfin iç alanına girildiğinde tetiklenir, dışarıdan geçerken tetiklenmez.
	var hits: Array = []
	for button_node in letter_buttons:
		if selected_buttons.has(button_node):
			continue
		var center = _letter_center(button_node)
		# to_pos = anlık parmak konumu; from_pos eski konum (geri dönüş için saklanır)
		if to_pos.distance_to(center) <= LETTER_HIT_RADIUS:
			hits.append([to_pos.distance_to(center), button_node])
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
		# Önce geri dönüş kontrolü yap, sonra yeni harf eklemeye bak
		_geri_don_kontrol(now)
		_pick_letters_along_segment(last_drag_pos, now)
		last_drag_pos = now

# Parmak son seçili harften uzaklaşıp bir öncekine yaklaşıyorsa son harfi iptal et.
# Birden fazla harf aynı harekette iptal edilebilir (hızlı geri çekilme için döngü).
func _geri_don_kontrol(parmak_pos: Vector2) -> void:
	# En az 2 harf seçili olmalı; tek harfle geri dönüş anlamsız
	while selected_buttons.size() >= 2:
		var son_btn    = selected_buttons[selected_buttons.size() - 1]
		var onceki_btn = selected_buttons[selected_buttons.size() - 2]

		var son_merkez    = _letter_center(son_btn)
		var onceki_merkez = _letter_center(onceki_btn)

		# Parmak son harften mi yoksa önceki harften mi uzakta?
		# Öncekine daha yakınsa → son harfi geri al
		if parmak_pos.distance_to(onceki_merkez) < parmak_pos.distance_to(son_merkez):
			# Son harfi seçim listesinden çıkar
			selected_buttons.pop_back()
			# current_word'ün son karakterini sil
			current_word = current_word.left(current_word.length() - 1)
			preview_label.text = current_word
			# Line2D: _process'in eklediği fare-takip noktası + son harf noktasını kaldır.
			# Nokta sayısı: [harf_1, harf_2, ..., harf_N, takip_noktası]
			# Takip noktası varsa onu sil, ardından son harf noktasını sil.
			var pc := line_node.get_point_count()
			if pc > selected_buttons.size() + 1:
				# Takip noktası mevcut — önce onu kaldır
				line_node.remove_point(pc - 1)
				pc -= 1
			if pc > 0:
				line_node.remove_point(pc - 1)
		else:
			# Geri dönüş yok, döngüyü kır
			break

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

# ===========================================================================
# KELİME KONTROL MOTORU
# ===========================================================================

func check_final_word() -> void:
	if discovered_words.has(current_word):
		print("Bu kelimeyi zaten buldun!")
	elif word_cells_map.has(current_word):
		print("Doğru! Şerit açılıyor: ", current_word)
		discovered_words.append(current_word)

		var cells_to_open = word_cells_map[current_word]
		for cell in cells_to_open:
			cell.reveal_letter()
			cell.set_meta("revealed", true)

		# Her doğru kelime için altın ödülü ve anlık kayıt
		_altin_kazan(ALTIN_KELIME_ODULU)
		_discovered_words_kaydet()

		if discovered_words.size() == word_cells_map.size():
			print("BÖLÜM BİTTİ! 🎉")
			_show_level_complete_panel()
	else:
		print("Yanlış kelime!")

	current_word = ""
	preview_label.text = ""
	selected_buttons.clear()
	line_node.clear_points()

# ===========================================================================
# BÖLÜM BİTİŞ PANELİ
# ===========================================================================

func _show_level_complete_panel() -> void:
	is_dragging = false

	# Bölüm tamamlama bonusu
	_altin_kazan(ALTIN_BOLUM_ODULU)

	# Sonraki bölüm numarası
	var sonraki = current_level_id + 1
	if sonraki > 500:
		sonraki = 1

	var btn = get_node_or_null("WinLayer/WinPanel/Box/VBox/NextLevelButton")
	if btn:
		btn.text = "%d. Bölüme Başla" % sonraki

	# Bonus yazısını güncelle
	var bonus_lbl = get_node_or_null("WinLayer/WinPanel/Box/VBox/BonusLabel")
	if bonus_lbl:
		bonus_lbl.text = "+%d Altın Kazandın! 🪙" % ALTIN_BOLUM_ODULU

	win_panel.visible = true

# ===========================================================================
# SONRAKI BÖLÜM
# ===========================================================================

func _on_next_level_pressed() -> void:
	# Tamamlanan bölümün ara kelime kaydını temizle (artık gereksiz)
	_bolum_kelime_kaydi_temizle(current_level_id)
	current_level_id += 1
	if current_level_id > 500:
		current_level_id = 1
	_save_level_id(current_level_id)
	_sahneyi_sifirla()
	load_and_build_puzzle()

func _sahneyi_sifirla() -> void:
	for btn in letter_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	letter_buttons.clear()

	for key in word_cells_map:
		for cell in word_cells_map[key]:
			if is_instance_valid(cell):
				cell.queue_free()
	word_cells_map.clear()
	tum_hucreler.clear()

	discovered_words.clear()
	selected_buttons.clear()
	current_word = ""
	is_dragging = false
	line_node.clear_points()
	preview_label.text = ""
	win_panel.visible = false
	queue_redraw()

# ===========================================================================
# YARDIMCI FONKSİYONLAR
# ===========================================================================

func find_label_recursive(node: Node) -> Label:
	if node is Label:
		return node
	for child in node.get_children():
		var res = find_label_recursive(child)
		if res:
			return res
	return null

func find_color_rect_recursive(node: Node) -> ColorRect:
	if node is ColorRect:
		return node
	for child in node.get_children():
		var res = find_color_rect_recursive(child)
		if res:
			return res
	return null
