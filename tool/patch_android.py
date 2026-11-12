"""Дополняет сгенерированный `flutter create` Android-проект:
разрешения, название приложения, минимальные версии Gradle/AGP для плагинов."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent / "android"

# --- AndroidManifest: разрешения и название ---
manifest = root / "app" / "src" / "main" / "AndroidManifest.xml"
m = manifest.read_text(encoding="utf-8")
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
]
lines = "".join(
    f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m
)
m = re.sub(r"(<manifest[^>]*>\n)", lambda x: x.group(1) + lines, m, count=1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Навигатор"', m, count=1)
manifest.write_text(m, encoding="utf-8")
print("manifest patched")


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v)[:3])


# --- Android Gradle Plugin >= 8.12.1 (нужно свежим плагинам) ---
for name in ("settings.gradle.kts", "settings.gradle"):
    f = root / name
    if not f.exists():
        continue
    s = f.read_text(encoding="utf-8")

    def bump(mt):
        cur = mt.group(2)
        return mt.group(1) + ("8.12.1" if vtuple(cur) < (8, 12, 1) else cur) + mt.group(3)

    s = re.sub(r'(id\("com\.android\.application"\) version ")([\d.]+)(")', bump, s)
    s = re.sub(r"(id 'com\.android\.application' version ')([\d.]+)(')", bump, s)
    f.write_text(s, encoding="utf-8")
    print(name, "AGP checked")

# --- Gradle wrapper >= 8.13 ---
wp = root / "gradle" / "wrapper" / "gradle-wrapper.properties"
if wp.exists():
    s = wp.read_text(encoding="utf-8")
    mt = re.search(r"gradle-([\d.]+)-(all|bin)\.zip", s)
    if mt and vtuple(mt.group(1)) < (8, 13):
        s = s.replace(mt.group(0), "gradle-8.13-all.zip")
        wp.write_text(s, encoding="utf-8")
    print("gradle wrapper checked")
