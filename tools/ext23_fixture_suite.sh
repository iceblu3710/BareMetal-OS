#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
IMG_PATH="${EXT23_DATA_IMG:-sys/ext_data.img}"
MANIFEST_PATH="${EXT23_FIXTURE_MANIFEST:-sys/ext_data_fixture_manifest.tsv}"
TMP_ROOT="$(mktemp -d)"

cleanup() {
	rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

hash_file() {
	local file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	else
		echo "Missing sha256 tool (sha256sum/shasum)"
		exit 1
	fi
}

require_tools() {
	if ! command -v debugfs >/dev/null 2>&1; then
		echo "Install e2fsprogs (missing debugfs)."
		exit 1
	fi
}

populate_suite() {
	require_tools
	if [ ! -f "$IMG_PATH" ]; then
		echo "Missing data image: $IMG_PATH"
		echo "Run 'bash ./baremetal.sh datafs' first."
		exit 1
	fi

	local fixture_dir="$TMP_ROOT/fixtures"
	mkdir -p "$fixture_dir/nested"

	cat > "$fixture_dir/probe.txt" <<'EOF'
BareMetal ext3 payload v2
path=/bmtest/smoke/probe.txt
EOF

	cat > "$fixture_dir/alpha.txt" <<'EOF'
abcdefghijklmnopqrstuvwxyz
0123456789
EOF

	cat > "$fixture_dir/nested/notes.txt" <<'EOF'
Nested fixture for ext2 readdir/lookup validation.
EOF

	# ~96 KiB deterministic text payload for direct + indirect read-path testing.
	: > "$fixture_dir/large.txt"
	for i in $(seq 1 1536); do
		printf 'EXT23-LARGE-LINE-%04d-0123456789abcdef\n' "$i" >> "$fixture_dir/large.txt"
	done

	debugfs -w -R "mkdir /bmtest" "$IMG_PATH" >/dev/null 2>&1 || true
	debugfs -w -R "mkdir /bmtest/smoke" "$IMG_PATH" >/dev/null 2>&1 || true
	debugfs -w -R "mkdir /bmtest/smoke/nested" "$IMG_PATH" >/dev/null 2>&1 || true

	debugfs -w -R "write $fixture_dir/probe.txt /bmtest/smoke/probe.txt" "$IMG_PATH" >/dev/null
	debugfs -w -R "write $fixture_dir/alpha.txt /bmtest/smoke/alpha.txt" "$IMG_PATH" >/dev/null
	debugfs -w -R "write $fixture_dir/nested/notes.txt /bmtest/smoke/nested/notes.txt" "$IMG_PATH" >/dev/null
	debugfs -w -R "write $fixture_dir/large.txt /bmtest/smoke/large.txt" "$IMG_PATH" >/dev/null

	{
		printf "/bmtest/smoke/probe.txt\t%s\t%s\n" "$(hash_file "$fixture_dir/probe.txt")" "$(wc -c < "$fixture_dir/probe.txt" | tr -d ' ')"
		printf "/bmtest/smoke/alpha.txt\t%s\t%s\n" "$(hash_file "$fixture_dir/alpha.txt")" "$(wc -c < "$fixture_dir/alpha.txt" | tr -d ' ')"
		printf "/bmtest/smoke/nested/notes.txt\t%s\t%s\n" "$(hash_file "$fixture_dir/nested/notes.txt")" "$(wc -c < "$fixture_dir/nested/notes.txt" | tr -d ' ')"
		printf "/bmtest/smoke/large.txt\t%s\t%s\n" "$(hash_file "$fixture_dir/large.txt")" "$(wc -c < "$fixture_dir/large.txt" | tr -d ' ')"
	} > "$MANIFEST_PATH"

	echo "Wrote fixture suite to $IMG_PATH"
	echo "Wrote fixture manifest to $MANIFEST_PATH"
}

verify_suite() {
	require_tools
	if [ ! -f "$IMG_PATH" ]; then
		echo "Missing data image: $IMG_PATH"
		exit 1
	fi
	if [ ! -f "$MANIFEST_PATH" ]; then
		echo "Missing fixture manifest: $MANIFEST_PATH"
		echo "Run 'bash ./tools/ext23_fixture_suite.sh populate' first."
		exit 1
	fi

	local pass_count=0
	local fail_count=0
	while IFS=$'\t' read -r path expected_hash expected_size; do
		[ -z "${path:-}" ] && continue
		local out_file="$TMP_ROOT/out.bin"
		if ! debugfs -R "cat $path" "$IMG_PATH" >"$out_file" 2>/dev/null; then
			echo "FAIL missing_path path=$path"
			fail_count=$((fail_count + 1))
			continue
		fi

		local actual_hash actual_size
		actual_hash="$(hash_file "$out_file")"
		actual_size="$(wc -c < "$out_file" | tr -d ' ')"

		if [ "$actual_hash" = "$expected_hash" ] && [ "$actual_size" = "$expected_size" ]; then
			echo "PASS path=$path size=$actual_size"
			pass_count=$((pass_count + 1))
		else
			echo "FAIL path=$path expected_hash=$expected_hash actual_hash=$actual_hash expected_size=$expected_size actual_size=$actual_size"
			fail_count=$((fail_count + 1))
		fi
	done < "$MANIFEST_PATH"

	echo "suite_verify_pass=$pass_count suite_verify_fail=$fail_count"
	[ "$fail_count" -eq 0 ]
}

case "$MODE" in
	populate)
		populate_suite
		;;
	verify)
		verify_suite
		;;
	*)
		echo "Usage: bash ./tools/ext23_fixture_suite.sh <populate|verify>"
		exit 1
		;;
esac

