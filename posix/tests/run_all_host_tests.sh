#!/usr/bin/env bash
set -euo pipefail

CC=${CC:-gcc}
CFLAGS=${CFLAGS:--std=c11 -Wall -Wextra -Werror}
SRC=posix/src/posix_layer.c

run_test() {
  local test_src=$1
  local out=$2
  $CC $CFLAGS "$SRC" "$test_src" -o "$out"
  "$out"
}

run_test posix/tests/posix_layer_smoke.c /tmp/posix_layer_smoke
run_test posix/tests/posix_edge_cases.c /tmp/posix_edge_cases
run_test posix/tests/posix_largefile_conformance.c /tmp/posix_largefile_conformance
run_test posix/tests/posix_path_utils.c /tmp/posix_path_utils
run_test posix/tests/posix_process_tty.c /tmp/posix_process_tty

echo "all-posix-host-tests: ok"
