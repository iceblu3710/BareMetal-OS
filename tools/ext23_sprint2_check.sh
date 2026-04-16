#!/usr/bin/env bash
set -euo pipefail

SERIAL_LOG="${EXT23_SERIAL_LOG:-sys/serial.log}"
LOOKUP_REGEX="${EXT23_S2_LOOKUP_REGEX:-vfs_lookup|ext2_readdir|/bmtest/smoke/probe.txt}"
READ_REGEX="${EXT23_S2_READ_REGEX:-ext2_read_file|vfs_read|probe.txt}"

strict=0
if [ "${1:-}" = "--strict" ]; then
	strict=1
fi

echo "Running host-side probe payload verification..."
if [ -f "sys/ext_data_fixture_manifest.tsv" ]; then
	echo "Fixture manifest detected; running suite verification..."
	bash ./baremetal.sh datafs-suite-verify
else
	bash ./baremetal.sh datafs-verify-probe
fi

if [ ! -f "$SERIAL_LOG" ]; then
	echo "WARN: serial log missing ($SERIAL_LOG), skipping read-path log checks."
	[ "$strict" -eq 1 ] && exit 1
	exit 0
fi

lookup_ok=0
read_ok=0

if rg -n -e "$LOOKUP_REGEX" "$SERIAL_LOG" >/dev/null 2>&1; then
	lookup_ok=1
fi

if rg -n -e "$READ_REGEX" "$SERIAL_LOG" >/dev/null 2>&1; then
	read_ok=1
fi

if [ "$lookup_ok" -eq 1 ]; then
	echo "lookup_path_signal=pass"
else
	echo "lookup_path_signal=warn (regex not found: $LOOKUP_REGEX)"
fi

if [ "$read_ok" -eq 1 ]; then
	echo "read_path_signal=pass"
else
	echo "read_path_signal=warn (regex not found: $READ_REGEX)"
fi

if [ "$strict" -eq 1 ] && { [ "$lookup_ok" -ne 1 ] || [ "$read_ok" -ne 1 ]; }; then
	echo "FAIL: strict mode requires both Sprint-2 serial-log checks to pass."
	exit 1
fi
