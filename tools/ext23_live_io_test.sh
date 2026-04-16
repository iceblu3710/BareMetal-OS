#!/usr/bin/env bash
set -euo pipefail

strict=0
if [ "${1:-}" = "--strict" ]; then
	strict=1
fi

MOUNT_REGEX="${EXT23_LIVE_MOUNT_REGEX:-ext2_mount|datafs mount|mount ok}"
READDIR_REGEX="${EXT23_LIVE_READDIR_REGEX:-/bmtest/smoke|probe.txt|alpha.txt}"
READ_REGEX="${EXT23_LIVE_READ_REGEX:-probe.txt|BareMetal ext3 payload|EXT23-LARGE-LINE-0001}"
WRITE_REGEX="${EXT23_LIVE_WRITE_REGEX:-write ok|host.txt|create ok}"

if [ ! -d src/BareMetal ]; then
	echo "Missing src/BareMetal. Run 'bash ./baremetal.sh setup' first."
	exit 1
fi

if [ ! -d sys ]; then
	echo "Missing sys directory. Run 'bash ./baremetal.sh setup' first."
	exit 1
fi

echo "[1/6] Prepare ext data image + fixture suite"
bash ./baremetal.sh datafs
bash ./baremetal.sh datafs-suite-populate

echo "[2/6] Apply kernel scaffolds"
bash ./baremetal.sh ext23-scaffold

echo "[3/6] Build"
bash ./baremetal.sh build

echo "[4/6] Boot bounded live run"
if command -v timeout >/dev/null 2>&1; then
	timeout 30s bash ./baremetal.sh run || true
else
	echo "Missing timeout command; skipping bounded run."
fi

if [ ! -f sys/serial.log ]; then
	echo "WARN: missing sys/serial.log"
	[ "$strict" -eq 1 ] && exit 1
	exit 0
fi

echo "[5/6] Evaluate live IO markers"
mount_ok=0
readdir_ok=0
read_ok=0
write_ok=0

rg -n -e "$MOUNT_REGEX" sys/serial.log >/dev/null 2>&1 && mount_ok=1
rg -n -e "$READDIR_REGEX" sys/serial.log >/dev/null 2>&1 && readdir_ok=1
rg -n -e "$READ_REGEX" sys/serial.log >/dev/null 2>&1 && read_ok=1
rg -n -e "$WRITE_REGEX" sys/serial.log >/dev/null 2>&1 && write_ok=1

report_check() {
	local name="$1" value="$2" regex="$3"
	if [ "$value" -eq 1 ]; then
		echo "$name=pass"
	else
		echo "$name=warn (regex not found: $regex)"
	fi
}

report_check "mount_signal" "$mount_ok" "$MOUNT_REGEX"
report_check "readdir_signal" "$readdir_ok" "$READDIR_REGEX"
report_check "read_signal" "$read_ok" "$READ_REGEX"
report_check "write_signal" "$write_ok" "$WRITE_REGEX"

echo "[6/6] Tail serial log"
tail -n 80 sys/serial.log

if [ "$strict" -eq 1 ] && { [ "$mount_ok" -ne 1 ] || [ "$readdir_ok" -ne 1 ] || [ "$read_ok" -ne 1 ] || [ "$write_ok" -ne 1 ]; }; then
	echo "FAIL: strict live-IO mode requires mount/readdir/read/write markers."
	exit 1
fi

