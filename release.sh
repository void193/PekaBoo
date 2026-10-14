#!/usr/bin/env bash
# Builds the public downloads of PekaBoo (no Arijit songs - those stay in the private build):
#   build/public/PekaBoo-v1.0-android.apk, PekaBoo-v1.0-windows.zip, PekaBoo-v1.0-linux.tar.gz
set -euo pipefail
cd "$(dirname "$0")"
T=$HOME/gamedev-tools
VER=v1.0
export JAVA_HOME=$T/jdk PATH=$T/jdk/bin:$PATH
KS=$PWD/rubinbastakoti-release.keystore
KS_PASS=$(grep "^Password" KEYSTORE-README.txt | awk '{print $3}')
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$KS GODOT_ANDROID_KEYSTORE_RELEASE_USER=pekaboo GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$KS_PASS
rm -rf build/public && mkdir -p build/public/windows build/public/linux
# The private build hangs the couple's own photos; the public build gets neutral illustrated pictures
# (same sizes, so the baked frames still fit). The private photos are put back when this script exits.
PH=game/assets/photos
rm -rf build/photos_private && mkdir -p build/photos_private
cp $PH/photo*.jpg build/photos_private/
trap 'cp build/photos_private/photo*.jpg '"$PH"'/ 2>/dev/null || true' EXIT
python3 - <<'PY'
from PIL import Image, ImageOps
import os
src = os.path.expanduser("~/pekaboo-site/samples")
pairs = {"photo1.jpg": ("memory6_home.jpg", (506, 900)), "photo2.jpg": ("memory1_first_trip.jpg", (900, 675)),
         "photo3.jpg": ("memory3_movie_night.jpg", (675, 900)), "photo4.jpg": ("memory2_sunday.jpg", (675, 900))}
for dst, (name, size) in pairs.items():
    im = Image.open(os.path.join(src, name)).convert("RGB")
    ImageOps.fit(im, size, Image.LANCZOS).save("game/assets/photos/" + dst, quality=90)
PY
"$T/godot" --headless --import --path game > /dev/null 2>&1 || true
for preset in "Android Public" "Windows" "Linux"; do
  echo "exporting $preset..."
  "$T/godot" --headless --path game --export-release "$preset" > "build/public/export-${preset// /_}.log" 2>&1 || true
done
BT=$T/android-sdk/build-tools/34.0.0
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$KS_PASS" --ks-key-alias pekaboo --out build/public/PekaBoo-$VER-android.apk build/public/PekaBoo-android-unsigned.apk
rm -f build/public/PekaBoo-android-unsigned.apk build/public/*.idsig
cat > build/public/windows/HOW-TO-PLAY.txt <<'TXT'
PekaBoo - by RubinBastakoti
Double-click PekaBoo.exe to play.
If Windows says "Windows protected your PC", click "More info" then "Run anyway"
(the game isn't signed with a paid Microsoft certificate, that's all).
Keys: WASD move, mouse look, Space jump, C crouch, Shift run, E action, 1-9 tools, Esc frees the mouse, F11 fullscreen.

Make it yours: put your own pictures (jpg/png) in  Pictures\PekaBoo  and TV videos (.ogv) in  Videos\PekaBoo,
then open Settings in the game and tap Reload. Your pictures hang in the frames around the house.
TXT
(cd build/public/windows && rm -f ../PekaBoo-$VER-windows.zip && python3 -m zipfile -c ../PekaBoo-$VER-windows.zip PekaBoo.exe HOW-TO-PLAY.txt)
cat > build/public/linux/HOW-TO-PLAY.txt <<'TXT'
PekaBoo - by RubinBastakoti
Extract, then run:  ./PekaBoo.x86_64   (or double-click it)
Keys: WASD move, mouse look, Space jump, C crouch, Shift run, E action, 1-9 tools, Esc frees the mouse, F11 fullscreen.

Make it yours: put your own pictures (jpg/png) in  ~/Pictures/PekaBoo  and TV videos (.ogv) in  ~/Videos/PekaBoo,
then open Settings in the game and tap Reload. Your pictures hang in the frames around the house.
TXT
chmod +x build/public/linux/PekaBoo.x86_64
tar -C build/public -czf build/public/PekaBoo-$VER-linux.tar.gz --transform 's,^linux,PekaBoo,' linux
ls -la build/public/PekaBoo-$VER-*
