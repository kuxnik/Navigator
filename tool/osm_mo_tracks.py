"""Грунтовки OpenStreetMap по Московской области (и Москве) в GPX-файлы,
нарезанные на куски, чтобы их открывали Компас 55 и другие навигаторы.

Запуск: python3 tool/osm_mo_tracks.py out_dir
Только стандартная библиотека Python. Данные © участники OpenStreetMap, ODbL.
"""
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request
import zipfile

SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]
UA = "ru.kuxnik.navigator (+https://github.com/kuxnik/Navigator) mo-tracks export"

# Сетка поверх МО: шаг 0.4° по широте и 0.65° по долготе (~45 × 40 км)
LAT0, LAT1, DLAT = 54.20, 57.00, 0.40
LON0, LON1, DLON = 35.10, 40.30, 0.65
MAX_FILE_BYTES = 6 * 1024 * 1024  # больше — режем лист ещё на 4 части
SIMPLIFY_M = 4.0  # упрощение линий, метров

GRADES = [
    ("good", "любая машина", "Green"),
    ("medium", "кроссовер", "Yellow"),
    ("hard", "джип", "Red"),
    ("unknown", "класс не указан", "DarkGray"),
]


def classify(tags):
    tt = tags.get("tracktype")
    sm = tags.get("smoothness")
    if tags.get("4wd_only") == "yes" or tt in ("grade4", "grade5") or sm in (
        "horrible", "very_horrible", "impassable"):
        return "hard"
    if tt == "grade3" or sm in ("bad", "very_bad"):
        return "medium"
    if tt in ("grade1", "grade2") or sm in ("good", "intermediate", "excellent"):
        return "good"
    return "unknown"


def query(s, w, n, e):
    q = (
        '[out:json][timeout:300];'
        'area["ISO3166-2"~"^RU-(MOS|MOW)$"]->.a;'
        f'(way["highway"="track"](area.a)({s},{w},{n},{e});'
        f'way["4wd_only"="yes"](area.a)({s},{w},{n},{e}););'
        'out tags geom;'
    )
    body = urllib.parse.urlencode({"data": q}).encode()
    last = None
    for attempt in range(6):
        url = SERVERS[attempt % len(SERVERS)]
        try:
            req = urllib.request.Request(url, data=body, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=400) as r:
                j = json.loads(r.read().decode("utf-8"))
            rem = j.get("remark")
            if rem and not j.get("elements") and "error" in rem.lower():
                raise RuntimeError(rem)
            return j.get("elements", [])
        except Exception as ex:  # noqa: BLE001
            last = ex
            print(f"   попытка {attempt + 1} ({url}): {ex}", flush=True)
            time.sleep(20 + attempt * 20)
    raise RuntimeError(f"Overpass не ответил: {last}")


def simplify(pts, eps_m):
    """Рамер — Дуглас — Пейкер в локальной проекции (метры)."""
    if len(pts) < 3:
        return pts
    lat0 = math.radians(pts[0][0])
    kx = 111320.0 * math.cos(lat0)
    ky = 110540.0
    xy = [((p[1]) * kx, (p[0]) * ky) for p in pts]
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = xy[a]
        bx, by = xy[b]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy) or 1e-9
        best, bi = 0.0, -1
        for i in range(a + 1, b):
            px, py = xy[i]
            d = abs(dy * px - dx * py + bx * ay - by * ax) / L
            if d > best:
                best, bi = d, i
        if best > eps_m and bi > 0:
            keep[bi] = True
            stack.append((a, bi))
            stack.append((bi, b))
    return [p for p, k in zip(pts, keep) if k]


def gpx(title, ways_by_grade):
    out = [
        '<?xml version="1.0" encoding="UTF-8"?>\n',
        '<gpx version="1.1" creator="Navigator (kuxnik/Navigator)" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3">\n',
        f'<metadata><name>{title}</name><copyright author="OpenStreetMap contributors">'
        '<license>https://opendatacommons.org/licenses/odbl/</license></copyright></metadata>\n',
    ]
    for key, label, color in GRADES:
        ways = ways_by_grade.get(key) or []
        if not ways:
            continue
        out.append(f"<trk><name>Грунтовки OSM · {label}</name>"
                   f"<extensions><gpxx:TrackExtension><gpxx:DisplayColor>{color}</gpxx:DisplayColor>"
                   "</gpxx:TrackExtension></extensions>\n")
        for pts in ways:
            out.append("<trkseg>")
            out.extend(f'<trkpt lat="{la:.6f}" lon="{lo:.6f}"/>' for la, lo in pts)
            out.append("</trkseg>\n")
        out.append("</trk>\n")
    out.append("</gpx>\n")
    return "".join(out).encode("utf-8")


def write_piece(out_dir, name, title, ways, index, depth=0):
    """ways: список (grade, pts). Если файл слишком большой — делим на 4 по середине."""
    by = {}
    for g, pts in ways:
        by.setdefault(g, []).append(pts)
    data = gpx(title, by)
    if len(data) > MAX_FILE_BYTES and len(ways) > 50 and depth < 4:
        lats = sorted(p[len(p) // 2][0] for _, p in ways)
        lons = sorted(p[len(p) // 2][1] for _, p in ways)
        mlat, mlon = lats[len(lats) // 2], lons[len(lons) // 2]
        parts = {"a": [], "b": [], "c": [], "d": []}
        for g, p in ways:
            la, lo = p[len(p) // 2]
            k = ("a" if la >= mlat else "c") if lo < mlon else ("b" if la >= mlat else "d")
            parts[k].append((g, p))
        for k, sub in parts.items():
            if sub:
                write_piece(out_dir, f"{name}{k}", f"{title}{k}", sub, index, depth + 1)
        return
    path = os.path.join(out_dir, f"{name}.gpx")
    with open(path, "wb") as f:
        f.write(data)
    counts = {g: len(v) for g, v in by.items()}
    index.append((name, len(data), counts))
    print(f"   → {name}.gpx {len(data) / 1e6:.1f} МБ, дорог: {sum(counts.values())}", flush=True)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "mo_tracks"
    os.makedirs(out_dir, exist_ok=True)
    index = []
    seen = set()
    rows = int(round((LAT1 - LAT0) / DLAT))
    cols = int(round((LON1 - LON0) / DLON))
    for r in range(rows):
        for c in range(cols):
            s = LAT0 + r * DLAT
            n = s + DLAT
            w = LON0 + c * DLON
            e = w + DLON
            name = f"mo_{s:.2f}N_{w:.2f}E"
            print(f"Лист {r + 1}-{c + 1}: {s:.2f}–{n:.2f}N, {w:.2f}–{e:.2f}E", flush=True)
            els = query(s, w, n, e)
            ways = []
            for el in els:
                if el.get("type") != "way" or el["id"] in seen:
                    continue
                geom = el.get("geometry") or []
                pts = [(g["lat"], g["lon"]) for g in geom if "lat" in g]
                if len(pts) < 2:
                    continue
                seen.add(el["id"])
                ways.append((classify(el.get("tags") or {}), simplify(pts, SIMPLIFY_M)))
            if ways:
                write_piece(out_dir, name, f"Грунтовки МО {s:.2f}N {w:.2f}E ", ways, index)
            else:
                print("   пусто", flush=True)
            time.sleep(5)

    lines = [
        "Грунтовки OpenStreetMap — Московская область и Москва",
        "Данные © участники OpenStreetMap, лицензия ODbL (https://www.openstreetmap.org/copyright)",
        "",
        "Каждый файл — квадрат примерно 45×40 км (большие поделены на части a–d).",
        "Имя файла — юго-западный угол квадрата: широта N, долгота E.",
        "В каждом файле до 4 треков по проходимости: любая машина / кроссовер / джип / класс не указан.",
        "",
        "файл | размер | любая машина | кроссовер | джип | не указан",
    ]
    for name, size, cnt in sorted(index):
        lines.append(f"{name}.gpx | {size / 1e6:.1f} МБ | {cnt.get('good', 0)} | "
                     f"{cnt.get('medium', 0)} | {cnt.get('hard', 0)} | {cnt.get('unknown', 0)}")
    with open(os.path.join(out_dir, "СПИСОК.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with zipfile.ZipFile("mo_tracks.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for fn in sorted(os.listdir(out_dir)):
            z.write(os.path.join(out_dir, fn), fn)
    print(f"Готово: файлов {len(index)}, дорог {len(seen)}", flush=True)


if __name__ == "__main__":
    main()
