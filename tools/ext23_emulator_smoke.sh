#!/usr/bin/env bash
set -euo pipefail

if [ ! -d src/BareMetal ]; then
	echo "Missing src/BareMetal. Run './baremetal.sh setup' first."
	exit 1
fi

if [ ! -d sys ]; then
	echo "Missing sys directory. Run './baremetal.sh setup' first."
	exit 1
fi

echo "[1/5] Preparing ext data image"
./baremetal.sh datafs
./baremetal.sh datafs-populate

echo "[2/5] Applying kernel scaffolds"
./baremetal.sh ext23-scaffold

echo "[3/5] Building full image"
./baremetal.sh build

echo "[4/5] Boot smoke test in QEMU (20s timeout)"
if command -v timeout >/dev/null 2>&1; then
	timeout 20s ./baremetal.sh run || true
else
	echo "'timeout' not found; skipping bounded QEMU run"
fi

echo "[5/5] Serial log tail"
if [ -f sys/serial.log ]; then
	tail -n 60 sys/serial.log
else
	echo "No sys/serial.log found"
fi

echo "ext23 emulator smoke flow complete"
