#!/usr/bin/env bash
set -euo pipefail

ITERATIONS="${EXT23_CRASH_ITERS:-10}"
MIN_KILL_DELAY="${EXT23_CRASH_MIN_DELAY:-2}"
MAX_KILL_DELAY="${EXT23_CRASH_MAX_DELAY:-8}"
QEMU_TIMEOUT="${EXT23_CRASH_QEMU_TIMEOUT:-60}"
LOG_DIR="sys/ext23_crash_logs"

if [ ! -d sys ]; then
	echo "Missing sys directory. Run './baremetal.sh setup' first."
	exit 1
fi

if ! command -v e2fsck >/dev/null 2>&1; then
	echo "Missing e2fsck (install e2fsprogs)."
	exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
	echo "Missing timeout command."
	exit 1
fi

if [ "$MIN_KILL_DELAY" -gt "$MAX_KILL_DELAY" ]; then
	echo "Invalid delay range: MIN ($MIN_KILL_DELAY) > MAX ($MAX_KILL_DELAY)"
	exit 1
fi

mkdir -p "$LOG_DIR"
summary_file="$LOG_DIR/summary.txt"
echo "ext23 crash test run $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$summary_file"
echo "iterations=$ITERATIONS min_delay=$MIN_KILL_DELAY max_delay=$MAX_KILL_DELAY qemu_timeout=$QEMU_TIMEOUT" >> "$summary_file"

pass_count=0
fail_count=0

for iter in $(seq 1 "$ITERATIONS"); do
	echo
	echo "=== Iteration $iter/$ITERATIONS ==="
	echo "Preparing fresh datafs image"
	bash ./baremetal.sh datafs
	bash ./baremetal.sh datafs-populate

	kill_delay=$(( MIN_KILL_DELAY + RANDOM % (MAX_KILL_DELAY - MIN_KILL_DELAY + 1) ))
	iter_prefix="$LOG_DIR/iter_${iter}"
	run_log="${iter_prefix}_run.log"
	fsck_log="${iter_prefix}_fsck.log"
	crash_img="${iter_prefix}_ext_data.img"

	echo "Booting QEMU and scheduling forced stop after ${kill_delay}s"
	(
		set +e
		timeout "${QEMU_TIMEOUT}s" bash ./baremetal.sh run >"$run_log" 2>&1
		exit 0
	) &
	run_pid=$!

	sleep "$kill_delay"

	# Terminate the full process tree for the bounded run wrapper.
	pkill -TERM -P "$run_pid" >/dev/null 2>&1 || true
	kill -TERM "$run_pid" >/dev/null 2>&1 || true
	sleep 1
	pkill -KILL -P "$run_pid" >/dev/null 2>&1 || true
	kill -KILL "$run_pid" >/dev/null 2>&1 || true
	wait "$run_pid" >/dev/null 2>&1 || true

	cp sys/ext_data.img "$crash_img"

	echo "Running e2fsck -fn on crash image copy"
	set +e
	e2fsck -fn "$crash_img" >"$fsck_log" 2>&1
	fsck_rc=$?
	set -e

	# e2fsck exit-code bit 2 (value 4) and above indicates uncorrected errors/operational failure.
	if [ "$fsck_rc" -lt 4 ]; then
		echo "PASS iter=$iter delay=${kill_delay}s fsck_rc=$fsck_rc" | tee -a "$summary_file"
		pass_count=$((pass_count + 1))
	else
		echo "FAIL iter=$iter delay=${kill_delay}s fsck_rc=$fsck_rc" | tee -a "$summary_file"
		fail_count=$((fail_count + 1))
	fi
done

echo >> "$summary_file"
echo "pass_count=$pass_count fail_count=$fail_count" | tee -a "$summary_file"

if [ "$fail_count" -gt 0 ]; then
	exit 1
fi
