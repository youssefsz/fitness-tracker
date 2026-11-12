"""Resize the brand masters and generate the native launch assets."""
import json
import plistlib
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageColor

root = Path(__file__).resolve().parents[1]
brand = json.loads((root / "tool/brand.json").read_text())
name = brand["name"]
masters = root / "tool/brand_sources"
ios = root / "ios/Runner"
catalog = ios / "Assets.xcassets"
res = root / "android/app/src/main/res"
icon = Image.open(masters / "app-icon.png").convert("RGB")
mark = Image.open(masters / "mark.png").convert("RGBA")
alpha = mark.getchannel("A")
resample = Image.Resampling.LANCZOS


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def metadata(path, images=None, colors=None):
    payload = {"info": {"version": 1, "author": "xcode"}}
    payload["images" if images is not None else "colors"] = images if images is not None else colors
    write(path / "Contents.json", json.dumps(payload, indent=2) + "\n")


def tint(hex_color):
    ink = Image.new("RGBA", mark.size, hex_color)
    ink.putalpha(alpha)
    return ink


def place(canvas, image, side, center):
    resized = image.resize((side, side), resample)
    canvas.alpha_composite(resized, (round(center[0] - side / 2), round(center[1] - side / 2)))


save(mark.resize((144, 144), resample), root / "assets/brand/mark.png")

# Apple's square source stays opaque. Each catalog slot keeps its original scale.
app_icons = catalog / "AppIcon.appiconset"
for slot in json.loads((app_icons / "Contents.json").read_text())["images"]:
    size = round(float(slot["size"].split("x")[0]) * int(slot["scale"][0]))
    save(icon.resize((size, size), resample), app_icons / slot["filename"])

launch_mark_name = "FitnessTrackerLaunchMark"
launch_images = catalog / f"{launch_mark_name}.imageset"
variants = []
backdrops = []
colors = []
for dark in (False, True):
    suffix = "-dark" if dark else ""
    appearance = {"appearances": [{"appearance": "luminosity", "value": "dark"}]} if dark else {}
    ink = brand["darkInk" if dark else "ink"]
    bg = brand["darkBackground" if dark else "lightBackground"]
    components = {
        channel: f"{n / 255:.6f}" for channel, n in
        zip(("red", "green", "blue"), ImageColor.getrgb(bg))
    }
    colors.append({"idiom": "universal", **appearance,
                   "color": {"color-space": "srgb", "components": {"alpha": "1", **components}}})
    backdrop = f"LaunchBackdrop{suffix}.png"
    save(Image.new("RGB", (1, 1), bg), catalog / "LaunchBackdrop.imageset" / backdrop)
    backdrops.append({"idiom": "universal", "filename": backdrop, **appearance})
    ink_image = tint(ink)
    for scale in (1, 2, 3):
        file = f"{launch_mark_name}{suffix}@{scale}x.png"
        save(ink_image.resize((78 * scale, 78 * scale), resample), launch_images / file)
        variants.append({"idiom": "universal", "filename": file, "scale": f"{scale}x", **appearance})
    qualifier = "-night" if dark else ""
    save(ink_image.resize((312, 312), resample), res / f"drawable{qualifier}-xxxhdpi/launch_mark.png")
    splash = Image.new("RGBA", (1152, 1152))
    # Android's splash masks a 192 dp safe circle inside the 288 dp viewport.
    place(splash, ink_image, 596, (576, 576))
    save(splash, res / f"drawable{qualifier}-xxxhdpi/splash_mark.png")
    write(res / f"values{qualifier}/colors.xml", f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="launch_background">{bg}</color>
    <color name="launcher_green">{brand['accent']}</color>
</resources>
""")
metadata(launch_images, images=variants)
metadata(catalog / "LaunchBackground.colorset", colors=colors)
metadata(catalog / "LaunchBackdrop.imageset", images=backdrops)

for density, scale in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
    legacy = round(48 * scale)
    save(icon.resize((legacy, legacy), resample), res / f"mipmap-{density}/ic_launcher.png")
    adaptive = round(108 * scale)
    foreground = Image.new("RGBA", (adaptive, adaptive))
    place(foreground, tint(brand["ink"]), round(63 * scale), (adaptive / 2, adaptive / 2))
    save(foreground, res / f"mipmap-{density}/ic_launcher_foreground.png")
write(res / "mipmap-anydpi-v26/ic_launcher.xml", """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_green" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
""")
for variation in ("", "-v21"):
    write(res / f"drawable{variation}/launch_background.xml", """<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/launch_background" />
    <item>
        <bitmap android:gravity="center" android:src="@drawable/launch_mark" />
    </item>
</layer-list>
""")
for dark in (False, True):
    for modern in (False, True):
        q = ("-night" if dark else "") + ("-v31" if modern else "")
        parent = "@android:style/Theme.Black.NoTitleBar" if dark else "@android:style/Theme.Light.NoTitleBar"
        flags = f'        <item name="android:windowLightStatusBar">{str(not dark).lower()}</item>'
        modern_items = """
        <item name="android:windowSplashScreenBackground">@color/launch_background</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_mark</item>""" if modern else ""
        launch_window = "@color/launch_background" if modern else "@drawable/launch_background"
        write(res / f"values{q}/styles.xml", f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="{parent}">
        <item name="android:windowBackground">{launch_window}</item>
        <item name="android:statusBarColor">@color/launch_background</item>
        <item name="android:navigationBarColor">@color/launch_background</item>
{flags}{modern_items}
    </style>
    <style name="NormalTheme" parent="{parent}">
        <item name="android:windowBackground">@color/launch_background</item>
        <item name="android:statusBarColor">@color/launch_background</item>
        <item name="android:navigationBarColor">@color/launch_background</item>
{flags}
    </style>
</resources>
""")

strings = ET.Element("resources")
ET.SubElement(strings, "string", name="app_name").text = name
ET.indent(strings, space="    ")
ET.ElementTree(strings).write(res / "values/strings.xml", encoding="utf-8", xml_declaration=True)
plist = ios / "Info.plist"
info = plistlib.loads(plist.read_bytes())
info["CFBundleDisplayName"] = info["CFBundleName"] = name
plist.write_bytes(plistlib.dumps(info, sort_keys=False))

write(root / "lib/app/branding.dart", f"""// Generated by tool/generate_brand_assets.py.
abstract final class Branding {{
  static const name = '{name}';
  static const mark = 'assets/brand/mark.png';
}}
""")
