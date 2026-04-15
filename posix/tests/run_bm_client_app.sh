#!/usr/bin/env bash
set -euo pipefail

gcc -std=c11 -Wall -Wextra -Werror posix/src/posix_layer.c posix/apps/bm_client_app.c -o /tmp/bm_client_app
/tmp/bm_client_app --selftest
