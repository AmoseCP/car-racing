#!/bin/sh
# Install the official Godot editor and the Windows/macOS export templates on
# a macOS machine, verifying both downloads against Godot's SHA-512 sums.
# Downloads are kept in $GODOT_CACHE so CI can cache them between runs.
#
# usage: tools/ci/install_godot.sh
# prints the path of the Godot binary on its last line
set -eu

version=${GODOT_VERSION:-4.7.2}
cache=${GODOT_CACHE:-$HOME/godot-cache}
base="https://github.com/godotengine/godot-builds/releases/download/${version}-stable"
editor="Godot_v${version}-stable_macos.universal.zip"
templates="Godot_v${version}-stable_export_templates.tpz"

mkdir -p "$cache"
cd "$cache"
curl -fsSL -o SHA512-SUMS.txt "$base/SHA512-SUMS.txt"
for file in "$editor" "$templates"; do
	if [ ! -f "$file" ] || ! grep " $file\$" SHA512-SUMS.txt | shasum -a 512 -c - >/dev/null 2>&1; then
		curl -fsSL --retry 3 -o "$file" "$base/$file"
	fi
	grep " $file\$" SHA512-SUMS.txt | shasum -a 512 -c - >&2
done

rm -rf Godot.app
unzip -q "$editor"

target="$HOME/Library/Application Support/Godot/export_templates/${version}.stable"
mkdir -p "$target"
unzip -q -o -j "$templates" templates/version.txt templates/macos.zip templates/windows_release_x86_64.exe -d "$target"

echo "$cache/Godot.app/Contents/MacOS/Godot"
