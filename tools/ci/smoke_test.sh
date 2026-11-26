#!/usr/bin/env bash
# Launch a packaged CarRacing build without a display for a few hundred frames.
# Fails if it crashes, exits non-zero, never starts the engine, or logs a
# script error. On macOS it also checks the binary's CPU architecture.
#
# usage: tools/ci/smoke_test.sh <game executable> [expected macOS architecture]
set -euo pipefail

executable=$1
expected_arch=${2:-}
log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/carracing-smoke.log"
rm -f "$log" "$log.stdout"

if [ -n "$expected_arch" ]; then
	actual=$(lipo -archs "$executable")
	echo "binary architectures: $actual (machine: $(uname -m))"
	if [ "$actual" != "$expected_arch" ]; then
		echo "expected only $expected_arch" >&2
		exit 1
	fi
fi

set +e
"$executable" --headless --quit-after 600 --log-file "$log" >"$log.stdout" 2>&1
status=$?
set -e

echo "--- exit status: $status ---"
cat "$log.stdout" "$log" 2>/dev/null | tail -n 60

if [ "$status" -ne 0 ]; then
	echo "game exited with status $status" >&2
	exit 1
fi
if ! cat "$log.stdout" "$log" 2>/dev/null | grep -q "Godot Engine v"; then
	echo "engine start banner not found in the log" >&2
	exit 1
fi
if cat "$log.stdout" "$log" 2>/dev/null | grep -E "SCRIPT ERROR|Parse Error|handle_crash|Failed to load"; then
	echo "errors found in the log" >&2
	exit 1
fi
echo "smoke test passed"
