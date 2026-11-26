#!/bin/sh
# Split a Godot universal macOS export into separate Apple Silicon (arm64)
# and Intel (x86_64) apps. Godot's official export templates only ship a
# universal binary, so the release build thins it with lipo and re-signs it
# ad hoc (hardened runtime, same as Godot's own ad-hoc signing).
#
# usage: tools/split_macos_app.sh <universal CarRacing.app> <output dir>
# result: <output dir>/arm64/CarRacing.app and <output dir>/x86_64/CarRacing.app
set -eu

source_app=$1
output=$2

for arch in arm64 x86_64; do
	dest="$output/$arch/CarRacing.app"
	rm -rf "$dest"
	mkdir -p "$output/$arch"
	ditto "$source_app" "$dest"
	find "$dest/Contents" -type f | while IFS= read -r file; do
		if file -b "$file" | grep -q "Mach-O universal"; then
			lipo "$file" -thin "$arch" -output "$file.thin"
			mv "$file.thin" "$file"
		fi
	done
	rm -rf "$dest/Contents/_CodeSignature"
	codesign --force --deep --options runtime --sign - "$dest"
	codesign --verify --deep --strict "$dest"
	echo "$arch: $(lipo -archs "$dest/Contents/MacOS/CarRacing")"
done
