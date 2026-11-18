"""Дополняет сгенерированный `flutter create` iOS-проект: разрешения,
фоновая геопозиция, название, минимальная версия iOS."""
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parent.parent / "ios"

info = root / "Runner" / "Info.plist"
with info.open("rb") as f:
    p = plistlib.load(f)
p["CFBundleDisplayName"] = "Навигатор"
p["CFBundleName"] = "Навигатор"
p["NSLocationWhenInUseUsageDescription"] = "Показывать вашу позицию на карте и вести к точке."
p["NSLocationAlwaysAndWhenInUseUsageDescription"] = "Записывать трек, когда экран погашен."
p["NSLocationAlwaysUsageDescription"] = "Записывать трек, когда экран погашен."
p["NSMotionUsageDescription"] = "Гироскоп нужен для точного курса машины."
modes = set(p.get("UIBackgroundModes", []))
modes.add("location")
p["UIBackgroundModes"] = sorted(modes)
p["UIFileSharingEnabled"] = True
p["LSSupportsOpeningDocumentsInPlace"] = True
p["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait"]
p["UIRequiresFullScreen"] = True
with info.open("wb") as f:
    plistlib.dump(p, f)
print("Info.plist patched")

# Минимальная iOS 15 — нужна части плагинов.
podfile = root / "Podfile"
if podfile.exists():
    s = podfile.read_text(encoding="utf-8")
    s = re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '15.0'", s, count=1, flags=re.M)
    podfile.write_text(s, encoding="utf-8")
    print("Podfile: iOS 15")
pbx = root / "Runner.xcodeproj" / "project.pbxproj"
if pbx.exists():
    s = pbx.read_text(encoding="utf-8")
    s = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", s)
    pbx.write_text(s, encoding="utf-8")
    print("project: iOS 15")
