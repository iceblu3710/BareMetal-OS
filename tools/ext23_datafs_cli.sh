#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
IMG_PATH="${EXT23_DATA_IMG:-sys/ext_data.img}"

require_debugfs() {
	if ! command -v debugfs >/dev/null 2>&1; then
		echo "Install e2fsprogs (missing debugfs)."
		exit 1
	fi
	if [ ! -f "$IMG_PATH" ]; then
		echo "Missing data image: $IMG_PATH"
		echo "Run 'bash ./baremetal.sh datafs' first."
		exit 1
	fi
}

case "$CMD" in
	ls)
		require_debugfs
		target="${2:-/}"
		debugfs -R "ls -p $target" "$IMG_PATH"
		;;
	read)
		require_debugfs
		target="${2:-}"
		if [ -z "$target" ]; then
			echo "Usage: bash ./tools/ext23_datafs_cli.sh read <image-path>"
			exit 1
		fi
		debugfs -R "cat $target" "$IMG_PATH"
		;;
	write)
		require_debugfs
		src="${2:-}"
		dest="${3:-}"
		if [ -z "$src" ] || [ -z "$dest" ]; then
			echo "Usage: bash ./tools/ext23_datafs_cli.sh write <host-file> <image-path>"
			exit 1
		fi
		if [ ! -f "$src" ]; then
			echo "Host file not found: $src"
			exit 1
		fi
		debugfs -w -R "write $src $dest" "$IMG_PATH"
		echo "Wrote $src -> $dest"
		;;
	mkdir)
		require_debugfs
		target="${2:-}"
		if [ -z "$target" ]; then
			echo "Usage: bash ./tools/ext23_datafs_cli.sh mkdir <image-path>"
			exit 1
		fi
		debugfs -w -R "mkdir $target" "$IMG_PATH"
		echo "Created directory: $target"
		;;
	*)
		echo "Usage: bash ./tools/ext23_datafs_cli.sh <ls|read|write|mkdir> [args]"
		exit 1
		;;
esac

