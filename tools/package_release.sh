#!/bin/sh
# Package a CarRacing release: Windows single EXE and full ZIP, separate
# Apple Silicon and Intel macOS ZIPs, the license pack, BUILD_INFO.json and
# SHA256SUMS.txt. Runs on macOS (needs lipo, codesign and ditto).
#
# usage: tools/package_release.sh <version, e.g. v0.2.7> <CarRacing.exe> <universal CarRacing.app> <output dir>
set -eu

version=$1
windows_exe=$2
universal_app=$3
mkdir -p "$4"
out=$(cd "$4" && pwd)
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Documents shipped in every package.
docs="$work/docs"
mkdir -p "$docs/LICENSES"
cp "$root/licenses/GODOT_LICENSE.txt" "$root/licenses/GODOT_THIRD_PARTY_COPYRIGHT.txt" "$docs/LICENSES/"
cp "$root/racing_prototype/fonts/OFL.txt" "$docs/LICENSES/FONT_OFL.txt"
cp "$root/racing_prototype/art/CREDITS.txt" "$docs/LICENSES/GAME_ASSETS_CREDITS.txt"
cp "$root/README.md" "$docs/README.md"
sed "s/{{VERSION}}/$version/g" "$root/tools/release/运行说明.txt" > "$docs/运行说明.txt"

add_docs() {
	cp -R "$docs/LICENSES" "$docs/README.md" "$docs/运行说明.txt" "$1/"
}

# macOS: Godot only ships a universal template, so thin it per architecture.
"$root/tools/split_macos_app.sh" "$universal_app" "$work/mac"
for pair in "AppleSilicon arm64" "Intel x86_64"; do
	set -- $pair
	name="CarRacing-macOS-$1"
	mkdir -p "$work/packages/$name"
	add_docs "$work/packages/$name"
	ditto "$work/mac/$2/CarRacing.app" "$work/packages/$name/CarRacing.app"
	(cd "$work/packages" && ditto -c -k --norsrc --noextattr --keepParent "$name" "$out/$name.zip")
done

# Windows: the EXE embeds the game pack; the ZIP adds the documents.
mkdir -p "$work/packages/Windows"
add_docs "$work/packages/Windows"
cp "$windows_exe" "$work/packages/Windows/CarRacing.exe"
(cd "$work/packages/Windows" && zip -q -r -X "$out/CarRacing-Windows-x64.zip" CarRacing.exe LICENSES README.md 运行说明.txt)
cp "$windows_exe" "$out/CarRacing-Windows-x64.exe"
(cd "$docs" && zip -q -r -X "$out/THIRD_PARTY_LICENSES.zip" LICENSES)

exe_sha=$(shasum -a 256 "$out/CarRacing-Windows-x64.exe" | cut -d' ' -f1)
godot_version=$("${GODOT:-godot}" --version 2>/dev/null | tail -n 1 | tr -d '\r')
cat > "$out/BUILD_INFO.json" <<EOF
{
  "version": "$version",
  "repository": "https://github.com/AmoseCP/car-racing",
  "commit": "$(git -C "$root" rev-parse HEAD)",
  "godot_version": "$godot_version",
  "export_templates": "official ${GODOT_VERSION:-4.7.2}-stable, SHA-512 verified",
  "built_by": "${BUILD_RUN_URL:-local build}",
  "targets": [
    "macOS Apple Silicon (arm64), thinned from the universal export",
    "macOS Intel (x86_64), thinned from the universal export",
    "Windows x86_64, embedded PCK (single EXE), custom icon and version resources"
  ],
  "macos_signing": "ad-hoc with hardened runtime, not notarized",
  "windows_exe_sha256": "$exe_sha"
}
EOF

(cd "$out" && shasum -a 256 CarRacing-Windows-x64.exe CarRacing-Windows-x64.zip \
	CarRacing-macOS-AppleSilicon.zip CarRacing-macOS-Intel.zip THIRD_PARTY_LICENSES.zip BUILD_INFO.json > SHA256SUMS.txt)
ls -l "$out"
