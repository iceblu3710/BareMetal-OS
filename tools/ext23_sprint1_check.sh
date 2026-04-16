#!/usr/bin/env bash
set -euo pipefail

SERIAL_LOG="${EXT23_SERIAL_LOG:-sys/serial.log}"
DATA_IMG="${EXT23_DATA_IMG:-sys/ext_data.img}"

# Make these configurable because kernel-side log strings are still in flux.
NVS_COUNT_REGEX="${EXT23_NVS_COUNT_REGEX:-os_nvs_device_count[[:space:]]*[:=][[:space:]]*2}"
SUPERBLOCK_LOG_REGEX="${EXT23_SB_MAGIC_REGEX:-0xEF53|EF53|ef53}"

strict=0
if [ "${1:-}" = "--strict" ]; then
	strict=1
fi

if [ ! -f "$DATA_IMG" ]; then
	echo "Missing data image: $DATA_IMG"
	echo "Run 'bash ./baremetal.sh datafs' first."
	exit 1
fi

raw_magic="$(dd if="$DATA_IMG" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')"
magic_le="$(printf '0x%s%s' "${raw_magic:2:2}" "${raw_magic:0:2}" | tr '[:lower:]' '[:upper:]')"
echo "superblock_magic=$magic_le (expected 0xEF53)"

if [ "$(echo "$magic_le" | tr '[:lower:]' '[:upper:]')" != "0XEF53" ]; then
	echo "FAIL: ext superblock magic check failed for $DATA_IMG"
	exit 1
fi

if [ ! -f "$SERIAL_LOG" ]; then
	echo "WARN: serial log missing ($SERIAL_LOG), skipping kernel-log checks."
	[ "$strict" -eq 1 ] && exit 1
	exit 0
fi

nvs_ok=0
sb_ok=0

if rg -n -e "$NVS_COUNT_REGEX" "$SERIAL_LOG" >/dev/null 2>&1; then
	nvs_ok=1
fi

if rg -n -e "$SUPERBLOCK_LOG_REGEX" "$SERIAL_LOG" >/dev/null 2>&1; then
	sb_ok=1
fi

if [ "$nvs_ok" -eq 1 ]; then
	echo "nvs_device_count_check=pass"
else
	echo "nvs_device_count_check=warn (regex not found: $NVS_COUNT_REGEX)"
fi

if [ "$sb_ok" -eq 1 ]; then
	echo "superblock_probe_log_check=pass"
else
	echo "superblock_probe_log_check=warn (regex not found: $SUPERBLOCK_LOG_REGEX)"
fi

if [ "$strict" -eq 1 ] && { [ "$nvs_ok" -ne 1 ] || [ "$sb_ok" -ne 1 ]; }; then
	echo "FAIL: strict mode requires both serial-log checks to pass."
	exit 1
fi
