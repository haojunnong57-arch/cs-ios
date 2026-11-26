#!/bin/bash
# 组装 CS 1.6 iOS .ipa
# 输入：
#   engine.ipa            FWGS 官方 xash3d-fwgs-ios-arm64.ipa（含 libxash/SDL3/GLES 渲染器）
#   stage/cstrike         cs16-client 交叉编译产物（client/menu/cs/yapb dylib + extras.pk3）
#   assets/cstrike        HLDS(cstrike) 游戏资源（地图/模型/音效）
# 输出： out/CS16-unsigned.ipa
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/dist"
OUT="${ROOT}/out"
APP="${WORK}/Payload/Launcher.app"
BUNDLE_ID="${BUNDLE_ID:-com.haojunnong.cs16}"
APP_NAME="${APP_NAME:-CS 1.6}"
VERSION="${VERSION:-1.6.0}"

log() { echo "[package] $*"; }

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

log "解包官方引擎 ipa"
python3 - "$ROOT/engine.ipa" "$WORK" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
test -d "$APP" || { echo "缺少 $APP"; exit 1; }

log "合并游戏资源"
if [ -d "${ROOT}/assets/cstrike" ]; then
  cp -R "${ROOT}/assets/cstrike" "$APP/cstrike"
else
  echo "警告：没有 assets/cstrike，仅打包模组"
  mkdir -p "$APP/cstrike"
fi
mkdir -p "$APP/cstrike/cl_dlls" "$APP/cstrike/dlls"

log "安装 mod dylib（引擎查找后缀：_ios_arm64）"
for f in "${ROOT}"/stage/cstrike/cl_dlls/*.dylib; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .dylib)"
  base="${base%_arm64}"
  cp "$f" "$APP/cstrike/cl_dlls/${base}_ios_arm64.dylib"
done
for f in "${ROOT}"/stage/cstrike/dlls/*.dylib; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .dylib)"
  base="${base%_arm64}"
  cp "$f" "$APP/cstrike/dlls/${base}_ios_arm64.dylib"
done
[ -e "${ROOT}/stage/cstrike/extras.pk3" ] && cp "${ROOT}/stage/cstrike/extras.pk3" "$APP/cstrike/"

log "写 liblist.gam"
cat > "$APP/cstrike/liblist.gam" <<EOF
game "Counter-Strike"
title "Counter-Strike 1.6"
version "1.6"
type "multiplayer_only"
gamedll "dlls/cs_ios_arm64.dylib"
gamedll_osx "dlls/cs_ios_arm64.dylib"
EOF

log "清掉非 iOS 的库，避免误加载"
rm -rf "$APP/cstrike/dlls/"*.so "$APP/cstrike/cl_dlls/"*.so 2>/dev/null || true
rm -rf "$APP/cstrike/dlls/"*_arm64.dylib "$APP/cstrike/cl_dlls/"*_arm64.dylib 2>/dev/null || true

log "改 Info.plist"
python3 - "$APP/Info.plist" "$BUNDLE_ID" "$APP_NAME" "$VERSION" <<'PY'
import plistlib, sys
path, bid, name, ver = sys.argv[1:5]
d = plistlib.load(open(path, "rb"))
d["CFBundleIdentifier"] = bid
d["CFBundleDisplayName"] = name
d["CFBundleName"] = "cstrike"
d["CFBundleShortVersionString"] = ver
d["CFBundleVersion"] = "1"
d["UIFileSharingEnabled"] = True
d["LSSupportsOpeningDocumentsInPlace"] = True
land = ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
d["UISupportedInterfaceOrientations"] = land
d["UISupportedInterfaceOrientations~ipad"] = land
d.pop("UISupportsDocumentBrowser", None)
plistlib.dump(d, open(path, "wb"))
print("bundle id:", bid)
PY

log "编译启动器"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -mios-version-min=12.0 -O2 \
  -fobjc-arc -isysroot "$SDK" \
  -framework UIKit -framework Foundation \
  -o "$APP/Launcher" "${ROOT}/ci/launcher/main.m"
cp "${ROOT}/ci/launcher/main.m" "$APP/launcher_main.m.txt" 2>/dev/null || true
rm -f "$APP/launcher_main.m.txt"

log "静态校验：架构 / 依赖"
fail=0
while IFS= read -r -d '' f; do
  arch="$(lipo -archs "$f" 2>/dev/null || echo unknown)"
  echo "  $(basename "$f") -> $arch"
  case "$arch" in
    *arm64*) ;;
    *) echo "    !! 不是 arm64"; fail=1 ;;
  esac
  while read -r dep; do
    case "$dep" in
      /usr/lib/*|/System/*|@rpath/*|@executable_path/*|@loader_path/*|"") ;;
      *) if [ ! -e "$dep" ] && [ ! -e "$APP/$(basename "$dep")" ]; then
           echo "    !! 缺失依赖 $dep"; fail=1
         fi ;;
    esac
  done < <(otool -L "$f" | tail -n +2 | awk '{print $1}')
done < <(find "$APP" -maxdepth 1 -name '*.dylib' -print0; find "$APP/cstrike" -name '*.dylib' -print0)
[ "$fail" -eq 0 ] || { echo "校验失败"; exit 1; }

log "临时签名"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | tail -3 || true

log "打包 ipa"
(cd "$WORK" && zip -qry "${OUT}/CS16-unsigned.ipa" Payload)
ls -lh "${OUT}/CS16-unsigned.ipa"
python3 - "${OUT}/CS16-unsigned.ipa" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
bad = z.testzip()
names = z.namelist()
print("条目:", len(names), "损坏:", bad or "无")
print("含 DLL:", sum(1 for n in names if n.endswith(".dylib")))
print("含地图:", sum(1 for n in names if "/maps/" in n and n.endswith(".bsp")))
PY
