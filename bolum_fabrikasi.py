"""
bolum_fabrikasi.py
==================
Kelime havuzunu okur, 500 benzersiz crossword bölümü üretir ve
bolumler_listesi.json dosyasını yazar.

Kullanım:
    python bolum_fabrikasi.py

Gereksinim: Sadece Python standart kütüphanesi.

Optimizasyonlar (v3 — 500 bölüm):
  - CrosswordGrid: harf→hücre ters indeksi ile O(1) eşleşme arama
  - Alt kelime cache: aynı ana kelimeye tekrar sorulmaz
  - Ana kelime unique, alt kelimeler bölümler arası reuse edilebilir
  - 10 zorluk bandı, kademeli güçleşme
  - Fallback zinciri: bant gevşetme → sıfır kısıt → placeholder
"""

import json
import math
import random
import os
import re
import sys
from collections import Counter, defaultdict

# ---------------------------------------------------------------------------
# AYARLAR
# ---------------------------------------------------------------------------

KELIME_HAVUZU_DOSYASI = os.path.join(os.path.dirname(__file__), "kelime_havuzu.txt.txt")
CIKTI_DOSYASI         = os.path.join(os.path.dirname(__file__), "bolumler_listesi.json")
TOPLAM_BOLUM          = 500
RANDOM_SEED           = 2024

# 500 bölümü 10 banda yay — her band 50 bölüm
# (bas, son, ana_min, ana_max, hedef_kelime)
ZORLUK_BANTLARI = [
    (  1,  50,  3,  4,   6),   # Band 1 — kolay
    ( 51, 100,  3,  5,   8),   # Band 2
    (101, 150,  4,  5,  10),   # Band 3
    (151, 200,  4,  6,  11),   # Band 4
    (201, 250,  5,  6,  12),   # Band 5 — orta
    (251, 300,  5,  6,  13),   # Band 6
    (301, 350,  5,  7,  13),   # Band 7
    (351, 400,  5,  7,  14),   # Band 8
    (401, 450,  6,  7,  14),   # Band 9
    (451, 500,  6,  7,  15),   # Band 10 — zor
]

CIRCLE_RADIUS = 200.0

# ---------------------------------------------------------------------------
# 1. Türkçe büyük harf
# ---------------------------------------------------------------------------

TR_BUYUK = str.maketrans(
    "abcçdefgğhıijklmnoöprsştuüvyz",
    "ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ"
)

def turkce_upper(s: str) -> str:
    return s.translate(TR_BUYUK)

# ---------------------------------------------------------------------------
# 2. Kelime havuzu okuma + hızlı indeks
# ---------------------------------------------------------------------------

def kelime_havuzunu_oku(dosya: str):
    kelimeler = set()
    try:
        with open(dosya, encoding="utf-8") as f:
            for satir in f:
                k = satir.strip()
                if not k:
                    continue
                k = turkce_upper(k)
                if 3 <= len(k) <= 7 and re.fullmatch(r"[A-ZÇĞIİÖŞÜ]+", k):
                    kelimeler.add(k)
    except FileNotFoundError:
        print(f"HATA: {dosya} bulunamadı!")
        sys.exit(1)

    havuz = sorted(kelimeler)

    # harf → bu harfi içeren kelimeler kümesi
    harf_indeks: dict[str, set] = defaultdict(set)
    for k in havuz:
        for h in set(k):
            harf_indeks[h].add(k)

    print(f"Kelime havuzu: {len(havuz)} benzersiz kelime (3-7 harf)")
    return havuz, harf_indeks

# ---------------------------------------------------------------------------
# 3. Alt kelime arama — sonuçlar cache'lenir
# ---------------------------------------------------------------------------

_alt_cache: dict[str, list] = {}

def alt_kelimeleri_bul(ana: str, havuz: list, harf_indeks: dict) -> list:
    if ana in _alt_cache:
        return _alt_cache[ana]

    ana_sayac = Counter(ana)
    # En nadir harfi bul → aday setini küçült
    en_nadir = min(ana_sayac, key=lambda h: len(harf_indeks.get(h, set())))
    adaylar  = harf_indeks.get(en_nadir, set())

    sonuc = []
    for k in adaylar:
        if k == ana:
            continue
        kc = Counter(k)
        if all(kc[h] <= ana_sayac[h] for h in kc):
            sonuc.append(k)

    _alt_cache[ana] = sonuc
    return sonuc

# ---------------------------------------------------------------------------
# 4. CrosswordGrid — harf ters indeksi ile hızlı kesişim arama
# ---------------------------------------------------------------------------

class CrosswordGrid:
    def __init__(self):
        self.grid:    dict[tuple, str]  = {}   # (x,y) → char
        self.yerlesik: list[dict]        = []
        # harf → bu harfin bulunduğu koordinatlar kümesi (ters indeks)
        self._harf_konumlari: dict[str, list] = defaultdict(list)

    def _al(self, x, y):
        return self.grid.get((x, y))

    def _koy(self, x, y, ch):
        self.grid[(x, y)] = ch
        self._harf_konumlari[ch].append((x, y))

    def _gecerli(self, kelime: str, x: int, y: int, yatay: bool) -> bool:
        dx, dy = (1, 0) if yatay else (0, 1)
        n = len(kelime)

        if self._al(x - dx, y - dy) is not None:
            return False
        if self._al(x + dx * n, y + dy * n) is not None:
            return False

        kesisim  = False
        yan_dx, yan_dy = (0, 1) if yatay else (1, 0)

        for i, ch in enumerate(kelime):
            cx, cy = x + dx * i, y + dy * i
            mevcut = self._al(cx, cy)
            if mevcut is not None:
                if mevcut != ch:
                    return False
                kesisim = True
            else:
                if self._al(cx + yan_dx, cy + yan_dy) is not None:
                    return False
                if self._al(cx - yan_dx, cy - yan_dy) is not None:
                    return False

        if self.yerlesik and not kesisim:
            return False
        return True

    def _yerles(self, kelime: str, x: int, y: int, yatay: bool):
        dx, dy = (1, 0) if yatay else (0, 1)
        cells = []
        for i, ch in enumerate(kelime):
            cx, cy = x + dx * i, y + dy * i
            self._koy(cx, cy, ch)
            cells.append({"x": cx, "y": cy, "char": ch})
        self.yerlesik.append({
            "word":      kelime,
            "direction": "horizontal" if yatay else "vertical",
            "start_x":   x,
            "start_y":   y,
            "cells":     cells,
        })

    def _adaylar(self, kelime: str) -> list:
        """
        Harf ters indeksi kullanarak adayları üret.
        Eski O(n*m) yerine O(k*p): k=eşleşen harf sayısı, p=o harfin grid konumları.
        """
        sonuc = []
        goruldu = set()
        for i, ch in enumerate(kelime):
            for (gx, gy) in self._harf_konumlari.get(ch, []):
                for yatay in (True, False):
                    dx, dy = (1, 0) if yatay else (0, 1)
                    sx = gx - dx * i
                    sy = gy - dy * i
                    anahtar = (sx, sy, yatay)
                    if anahtar in goruldu:
                        continue
                    goruldu.add(anahtar)
                    if self._gecerli(kelime, sx, sy, yatay):
                        sonuc.append(anahtar)
        return sonuc

    def bounding_box(self) -> dict:
        if not self.grid:
            return {"min_x": 0, "max_x": 0, "min_y": 0, "max_y": 0}
        xs = [p[0] for p in self.grid]
        ys = [p[1] for p in self.grid]
        return {"min_x": min(xs), "max_x": max(xs),
                "min_y": min(ys), "max_y": max(ys)}

    def normalize(self):
        bb  = self.bounding_box()
        ox, oy = bb["min_x"], bb["min_y"]
        if ox == 0 and oy == 0:
            return
        self.grid = {(x - ox, y - oy): ch for (x, y), ch in self.grid.items()}
        # Ters indeksi de güncelle
        self._harf_konumlari = defaultdict(list)
        for (x, y), ch in self.grid.items():
            self._harf_konumlari[ch].append((x, y))
        for kd in self.yerlesik:
            kd["start_x"] -= ox
            kd["start_y"] -= oy
            for c in kd["cells"]:
                c["x"] -= ox
                c["y"] -= oy

    def olustur(self, kelime_listesi: list, hedef: int) -> bool:
        if not kelime_listesi:
            return False
        self._yerles(kelime_listesi[0], 0, 0, True)

        for kelime in kelime_listesi[1:]:
            if len(self.yerlesik) >= hedef:
                break
            if any(k["word"] == kelime for k in self.yerlesik):
                continue
            adaylar = self._adaylar(kelime)
            if adaylar:
                random.shuffle(adaylar)
                sx, sy, yatay = adaylar[0]
                self._yerles(kelime, sx, sy, yatay)

        self.normalize()
        return len(self.yerlesik) >= max(3, hedef // 2)

# ---------------------------------------------------------------------------
# 5. Circle layout
# ---------------------------------------------------------------------------

def circle_layout_hesapla(harfler: list) -> list:
    n = len(harfler)
    return [
        {
            "char":      ch,
            "index":     i,
            "angle_rad": round((2 * math.pi / n) * i, 4),
            "offset_x":  round(CIRCLE_RADIUS * math.cos((2 * math.pi / n) * i), 2),
            "offset_y":  round(CIRCLE_RADIUS * math.sin((2 * math.pi / n) * i), 2),
        }
        for i, ch in enumerate(harfler)
    ]

# ---------------------------------------------------------------------------
# 6. Tek bölüm oluştur
#    • Ana kelime her bölümde benzersiz (kullanilan_ana seti ile kontrol)
#    • Alt kelimeler farklı bölümlerde reuse edilebilir (tıkanma yok)
# ---------------------------------------------------------------------------

def bolum_olustur_tek(level_id, havuz, harf_indeks,
                      min_len, max_len, hedef,
                      rng, kullanilan_ana: set,
                      deneme=30) -> dict | None:
    adaylar = [k for k in havuz if min_len <= len(k) <= max_len
               and k not in kullanilan_ana]
    if not adaylar:
        # Tüm kelimeler kullanıldıysa kısıtı kaldır (reuse izni)
        adaylar = [k for k in havuz if min_len <= len(k) <= max_len]
    if not adaylar:
        return None

    rng.shuffle(adaylar)
    # Her denemede farklı aday seç
    deneme_adaylari = adaylar[:min(deneme * 3, len(adaylar))]

    for ana in deneme_adaylari:
        altlar = alt_kelimeleri_bul(ana, havuz, harf_indeks)
        min_alt = 2 if min_len <= 3 else 4
        if len(altlar) < min_alt:
            continue

        altlar_karisik = altlar[:]
        rng.shuffle(altlar_karisik)
        kelime_listesi = [ana] + altlar_karisik

        g = CrosswordGrid()
        if not g.olustur(kelime_listesi, hedef):
            continue

        yerlesik = [k["word"] for k in g.yerlesik]
        valid_set = set(yerlesik)
        for k in altlar_karisik[:hedef + 5]:
            valid_set.add(k)

        return {
            "level_id":        level_id,
            "target_letters":  list(ana),
            "circle_layout":   circle_layout_hesapla(list(ana)),
            "bounding_box":    g.bounding_box(),
            "islands_count":   1,
            "words_on_board":  g.yerlesik,
            "bonus_words":     [],
            "valid_word_list": sorted(valid_set),
        }
    return None

# ---------------------------------------------------------------------------
# 7. 500 bölüm üret
# ---------------------------------------------------------------------------

def bes_yuz_bolum_uret(havuz, harf_indeks) -> list:
    rng            = random.Random(RANDOM_SEED)
    bolumler       = []
    kullanilan_ana: set = set()

    # (level_id, min_len, max_len, hedef) listesi oluştur
    bant_plan = []
    for (bas, son, mn, mx, hf) in ZORLUK_BANTLARI:
        for lid in range(bas, son + 1):
            bant_plan.append((lid, mn, mx, hf))

    toplam = len(bant_plan)
    for idx, (level_id, mn, mx, hf) in enumerate(bant_plan):
        # İlerleme göster (her 10 bölümde bir)
        if level_id % 10 == 0 or level_id == 1:
            pct = (idx / toplam) * 100
            print(f"  [{pct:5.1f}%] Bölüm {level_id} işleniyor...")

        bolum = None

        # 1. Normal deneme
        bolum = bolum_olustur_tek(
            level_id, havuz, harf_indeks,
            mn, mx, hf, rng, kullanilan_ana, deneme=20
        )

        # 2. Fallback A: bant genişlet
        if bolum is None:
            bolum = bolum_olustur_tek(
                level_id, havuz, harf_indeks,
                max(3, mn - 1), min(7, mx + 1),
                max(4, hf - 2), rng, kullanilan_ana, deneme=20
            )

        # 3. Fallback B: tüm uzunluklar, reuse serbest
        if bolum is None:
            bolum = bolum_olustur_tek(
                level_id, havuz, harf_indeks,
                3, 7, max(3, hf - 3), rng,
                set(),   # kullanilan_ana'yı devre dışı bırak → reuse izni
                deneme=30
            )

        # 4. Son çare: placeholder
        if bolum is None:
            print(f"  Bölüm {level_id:>3} ✗  placeholder")
            bolumler.append(_placeholder(level_id))
            continue

        # Ana kelimeyi kullanılanlar setine ekle
        ana = bolum["words_on_board"][0]["word"]
        kullanilan_ana.add(ana)
        bolumler.append(bolum)

        # Detaylı log (her 50 bölümde bir veya hata varsa)
        if level_id % 50 == 0 or level_id <= 5:
            print(f"  Bölüm {level_id:>3} ✓  ana={ana:<12} "
                  f"grid={len(bolum['words_on_board']):<3} "
                  f"valid={len(bolum['valid_word_list'])}")

    return bolumler

def _placeholder(level_id: int) -> dict:
    return {
        "level_id": level_id,
        "target_letters": ["A", "R", "A"],
        "circle_layout": circle_layout_hesapla(["A", "R", "A"]),
        "bounding_box":  {"min_x": 0, "max_x": 2, "min_y": 0, "max_y": 0},
        "islands_count": 1,
        "words_on_board": [{
            "word": "ARA", "direction": "horizontal",
            "start_x": 0, "start_y": 0,
            "cells": [{"x": 0, "y": 0, "char": "A"},
                      {"x": 1, "y": 0, "char": "R"},
                      {"x": 2, "y": 0, "char": "A"}],
        }],
        "bonus_words": [],
        "valid_word_list": ["ARA"],
    }

# ---------------------------------------------------------------------------
# 8. Yaz
# ---------------------------------------------------------------------------

def yaz(bolumler: list, cikti: str):
    with open(cikti, "w", encoding="utf-8") as f:
        json.dump({"bolumler": bolumler}, f, ensure_ascii=False, indent=2)
    kb = os.path.getsize(cikti) / 1024
    mb = kb / 1024
    print(f"\nDosya : {cikti}")
    print(f"Bölüm : {len(bolumler)}")
    print(f"Boyut : {kb:.0f} KB  ({mb:.2f} MB)")

# ---------------------------------------------------------------------------
# 9. Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print(f"  BÖLÜM FABRİKASI  —  {TOPLAM_BOLUM} Bölüm Üretici  (v3)")
    print("=" * 60)
    print(f"Kelime havuzu : {KELIME_HAVUZU_DOSYASI}")
    print(f"Çıktı         : {CIKTI_DOSYASI}")
    print(f"Seed          : {RANDOM_SEED}")
    print("-" * 60)

    havuz, harf_indeks = kelime_havuzunu_oku(KELIME_HAVUZU_DOSYASI)

    print(f"\n{TOPLAM_BOLUM} bölüm üretiliyor...\n")
    import time
    t0 = time.time()

    bolumler = bes_yuz_bolum_uret(havuz, harf_indeks)

    sure = time.time() - t0
    print(f"\nSüre : {sure:.1f} saniye")

    placeholder_sayisi = sum(1 for b in bolumler
                             if b["valid_word_list"] == ["ARA"])
    if placeholder_sayisi:
        print(f"⚠  {placeholder_sayisi} bölüm placeholder ile dolduruldu.")

    if len(bolumler) < TOPLAM_BOLUM:
        print(f"⚠  {len(bolumler)}/{TOPLAM_BOLUM} bölüm üretildi.")
    else:
        print(f"✓  {len(bolumler)} bölüm başarıyla üretildi.")

    yaz(bolumler, CIKTI_DOSYASI)
    print("\nHazır! Oyunu başlatabilirsin.")

if __name__ == "__main__":
    main()
