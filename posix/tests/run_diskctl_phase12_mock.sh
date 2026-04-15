#!/usr/bin/env bash
set -euo pipefail

gcc -std=c11 -Wall -Wextra -Werror posix/tools/diskctl_phase12.c -o /tmp/diskctl_phase12

/tmp/diskctl_phase12 list | grep -q "disk_id=1"
/tmp/diskctl_phase12 info 0 | grep -q "logical=512"
/tmp/diskctl_phase12 part-list 1 | grep -q "part=1"
/tmp/diskctl_phase12 part-init 1 gpt 42
/tmp/diskctl_phase12 part-create 1 3 9000000 9500000 42
/tmp/diskctl_phase12 part-delete 1 2 42

echo "diskctl-phase12-mock: ok"
