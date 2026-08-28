"""
bolum_fabrikasi.py
==================
Kelime havuzunu okur, 100 benzersiz crossword bölümü üretir ve
bolumler_listesi.json dosyasını yazar.

Kullanım:
    python bolum_fabrikasi.py

Gereksinim: Sadece Python standart kütüphanesi (json, math, random, os, re)
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
CIKTI_DOSYASI        = os.path.join(os.path.dirname(__file__), "bolumler_listesi.json")
TOPLAM_BOLUM         = 100
RANDOM_SEED          = 42

# Bölüm zorluk bantları: (bolum_bas, bolum_son, ana_min_harf, ana_max_harf, hedef_kelime_sayisi)
ZORLUK_BANTLARI = [
    (  1,  20,  3,  4,   7),
    ( 21,  40,  4,  5,   9),
    ( 41,  60,  5,  6,  11),
    ( 61,  80,  5,  7,  13),
    ( 81, 100,  6,  7,  14),
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
    """
    Döner:
      havuz_liste : sıralı kelime listesi
      harf_indeks : harf -> o harfi içeren kelimeler seti  (hızlı arama için)
      sayac_indeks: Counter(kelime) -> kelimeler listesi    (alt kelime arama için)
    """
    kelimeler = set()
    try:
        with open(dosya, encoding="utf-8") as f:
            for satir in f:
                kelime = satir.strip()
                if not kelime:
                    continue
                kelime = turkce_upper(kelime)
                if 3 <= len(kelime) <= 7 and re.fullmatch(r"[A-ZÇĞIİÖŞÜ]+", kelime):
                    kelimeler.add(kelime)
    except FileNotFoundError:
        print(f"HATA: {dosya} bulunamadı!")
        sys.exit(1)

    havuz_liste = sorted(kelimeler)

    # harf → kelimeler seti
    harf_indeks: dict[str, set[str]] = defaultdict(set)
    for k in havuz_liste:
        for h in set(k):
            harf_indeks[h].add(k)

    print(f"Kelime havuzu yüklendi: {len(havuz_liste)} benzersiz kelime (3-7 harf)")
    return havuz_liste, harf_indeks

# ---------------------------------------------------------------------------
# 3. Alt kelime arama (önceden hesaplanmış Counter ile)
# ---------------------------------------------------------------------------

def alt_kelimeleri_bul(ana_kelime: str, havuz_liste: list, harf_indeks: dict) -> list:
    """
    ana_kelime harflerinin alt kümesinden oluşan havuz kelimelerini döner.
    harf_indeks ile başlangıç adayını küçük tutarak hız kazanır.
    """
    ana_sayac = Counter(ana_kelime)
    # Ana kelimenin en az sık harfini bul → aday kümesini küçült
    en_nadir_harf = min(ana_sayac, key=lambda h: len(harf_indeks.get(h, set())))
    adaylar = harf_indeks.get(en_nadir_harf, set())

    sonuc = []
    for kelime in adaylar:
        if kelime == ana_kelime:
            continue
        kc = Counter(kelime)
        if all(kc[h] <= ana_sayac[h] for h in kc):
            sonuc.append(kelime)
    return sonuc

# ---------------------------------------------------------------------------
# 4. CrosswordGrid motoru
# ---------------------------------------------------------------------------

class CrosswordGrid:
    def __init__(self):
        self.grid: dict[tuple, str] = {}
        self.yerlesik: list[dict] = []

    def _al(self, x, y):
        return self.grid.get((x, y))

    def _koy(self, x, y, ch):
        self.grid[(x, y)] = ch

    def _gecerli(self, kelime: str, x: int, y: int, yatay: bool) -> bool:
        dx, dy = (1, 0) if yatay else (0, 1)
        n = len(kelime)

        # Baş ve son boşluk
        if self._al(x - dx, y - dy) is not None:
            return False
        if self._al(x + dx * n, y + dy * n) is not None:
            return False

        kesisim = False
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
        """Mevcut grid hücrelerinden kesişim adayı üret."""
        sonuc = []
        # Kelimedeki her harfin grid'deki eşleşme noktalarına bak
        for i, ch in enumerate(kelime):
            for (gx, gy), gch in self.grid.items():
                if gch != ch:
                    continue
                for yatay in (True, False):
                    dx, dy = (1, 0) if yatay else (0, 1)
                    sx = gx - dx * i
                    sy = gy - dy * i
                    if self._gecerli(kelime, sx, sy, yatay):
                        sonuc.append((sx, sy, yatay))
        return sonuc

    def bounding_box(self) -> dict:
        if not self.grid:
            return {"min_x": 0, "max_x": 0, "min_y": 0, "max_y": 0}
        xs = [p[0] for p in self.grid]
        ys = [p[1] for p in self.grid]
        return {"min_x": min(xs), "max_x": max(xs), "min_y": min(ys), "max_y": max(ys)}

    def normalize(self):
        bb = self.bounding_box()
        ox, oy = bb["min_x"], bb["min_y"]
        if ox == 0 and oy == 0:
            return
        self.grid = {(x - ox, y - oy): ch for (x, y), ch in self.grid.items()}
        for kd in self.yerlesik:
            kd["start_x"] -= ox
            kd["start_y"] -= oy
            for c in kd["cells"]:
                c["x"] -= ox
                c["y"] -= oy

    def olustur(self, kelime_listesi: list, hedef: int) -> bool:
        if not kelime_listesi:
            return False
        # İlk kelime yatay (0,0)
        self._yerles(kelime_listesi[0], 0, 0, True)

        for kelime in kelime_listesi[1:]:
            if len(self.yerlesik) >= hedef:
                break
            if any(k["word"] == kelime for k in self.yerlesik):
                continue
            adaylar = self._adaylar(kelime)
            if adaylar:
                random.shuffle(adaylar)
                self._yerles(kelime, *adaylar[0])

        self.normalize()
        return len(self.yerlesik) >= max(3, hedef // 2)

# ---------------------------------------------------------------------------
# 5. Circle layout
# ---------------------------------------------------------------------------

def circle_layout_hesapla(harfler: list) -> list:
    n = len(harfler)
    layout = []
    for i, ch in enumerate(harfler):
        aci = (2 * math.pi / n) * i
        layout.append({
            "char":      ch,
            "index":     i,
            "angle_rad": round(aci, 4),
            "offset_x":  round(CIRCLE_RADIUS * math.cos(aci), 2),
            "offset_y":  round(CIRCLE_RADIUS * math.sin(aci), 2),
        })
    return layout

# ---------------------------------------------------------------------------
# 6. Tek bölüm oluştur
# ---------------------------------------------------------------------------

def bolum_olustur_tek(level_id, havuz_liste, harf_indeks,
                      min_len, max_len, hedef, rng, deneme=30):
    adaylar = [k for k in havuz_liste if min_len <= len(k) <= max_len]
    if not adaylar:
        return None

    for _ in range(deneme):
        ana = rng.choice(adaylar)
        altlar = alt_kelimeleri_bul(ana, havuz_liste, harf_indeks)

        min_alt = 2 if min_len <= 3 else 4
        if len(altlar) < min_alt:
            continue

        rng.shuffle(altlar)
        kelime_listesi = [ana] + altlar

        g = CrosswordGrid()
        if not g.olustur(kelime_listesi, hedef):
            continue

        yerlesik_kelimeler = [k["word"] for k in g.yerlesik]
        valid_set = set(yerlesik_kelimeler)
        # Kısa alt kelimeler de geçerli listeye gir
        for k in altlar[:hedef + 4]:
            valid_set.add(k)
        valid_word_list = sorted(valid_set)

        circle_harfler = list(ana)
        bb = g.bounding_box()

        return {
            "level_id":        level_id,
            "target_letters":  circle_harfler,
            "circle_layout":   circle_layout_hesapla(circle_harfler),
            "bounding_box":    bb,
            "islands_count":   1,
            "words_on_board":  g.yerlesik,
            "bonus_words":     [],
            "valid_word_list": valid_word_list,
        }
    return None

# ---------------------------------------------------------------------------
# 7. 100 bölüm üret
# ---------------------------------------------------------------------------

def yuz_bolum_uret(havuz_liste, harf_indeks) -> list:
    rng = random.Random(RANDOM_SEED)
    bolumler = []
    kullanilan: set = set()

    bant_plan = []
    for (bas, son, mn, mx, hf) in ZORLUK_BANTLARI:
        for lid in range(bas, son + 1):
            bant_plan.append((lid, mn, mx, hf))

    for (level_id, mn, mx, hf) in bant_plan:
        basarili = False

        # Normal bant denemesi (ana kelime tekrarı olmadan)
        for _ in range(80):
            bolum = bolum_olustur_tek(level_id, havuz_liste, harf_indeks,
                                      mn, mx, hf, rng, deneme=25)
            if bolum is None:
                break
            ana = bolum["words_on_board"][0]["word"]
            if ana not in kullanilan:
                kullanilan.add(ana)
                bolumler.append(bolum)
                print(f"  Bölüm {level_id:>3} ✓  ana={ana:<10}  "
                      f"grid={len(bolum['words_on_board']):<3}  "
                      f"valid={len(bolum['valid_word_list'])}")
                basarili = True
                break

        if not basarili:
            # Fallback: tüm uzunluklar açık
            print(f"  Bölüm {level_id:>3} ⚠  fallback...")
            for _ in range(120):
                bolum = bolum_olustur_tek(level_id, havuz_liste, harf_indeks,
                                          3, 7, max(4, hf - 3), rng, deneme=25)
                if bolum is None:
                    break
                ana = bolum["words_on_board"][0]["word"]
                if ana not in kullanilan:
                    kullanilan.add(ana)
                    bolumler.append(bolum)
                    print(f"           ↳ OK: ana={ana}")
                    basarili = True
                    break

        if not basarili:
            print(f"  Bölüm {level_id:>3} ✗  placeholder eklendi")
            bolumler.append(_placeholder(level_id))

    return bolumler

def _placeholder(level_id):
    return {
        "level_id": level_id,
        "target_letters": ["A", "R", "A"],
        "circle_layout": circle_layout_hesapla(["A", "R", "A"]),
        "bounding_box": {"min_x": 0, "max_x": 2, "min_y": 0, "max_y": 0},
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

def yaz(bolumler, cikti):
    with open(cikti, "w", encoding="utf-8") as f:
        json.dump({"bolumler": bolumler}, f, ensure_ascii=False, indent=2)
    kb = os.path.getsize(cikti) / 1024
    print(f"\nDosya : {cikti}")
    print(f"Bölüm : {len(bolumler)}")
    print(f"Boyut : {kb:.1f} KB")

# ---------------------------------------------------------------------------
# 9. Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("  BÖLÜM FABRİKASI  —  100 Bölüm Üretici")
    print("=" * 60)

    havuz_liste, harf_indeks = kelime_havuzunu_oku(KELIME_HAVUZU_DOSYASI)

    print("\nBölümler üretiliyor...\n")
    bolumler = yuz_bolum_uret(havuz_liste, harf_indeks)

    if len(bolumler) < TOPLAM_BOLUM:
        print(f"\n⚠  {len(bolumler)}/{TOPLAM_BOLUM} bölüm üretildi.")
    else:
        print(f"\n✓  {len(bolumler)} bölüm başarıyla üretildi.")

    yaz(bolumler, CIKTI_DOSYASI)
    print("\nHazır!")

if __name__ == "__main__":
    main()
