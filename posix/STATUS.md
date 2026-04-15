# POSIX Layer Status Update

_Last updated: 2026-04-15_

## Current Phase

**Phase 0.4 — Closeout Complete**

The POSIX compatibility layer has moved beyond stubs and now includes a meaningful file/descriptor/filesystem API set with:

- explicit backend binding
- host backend implementation for development/testing
- versioned kernel ABI contract for BareMetal integration

---

## Completed Tasks

### Architecture and interfaces

- [x] Created public wrapper API (`posix/include/posix_layer.h`)
- [x] Created versioned kernel ABI contract (`posix/include/bm_kernel_abi.h`)
- [x] Added backend registration and selection flow
- [x] Added kernel ABI adapter binding (`bm_bind_kernel_abi_v1`)

### Core file and descriptor operations

- [x] open/close/read/write/lseek
- [x] pread/pwrite
- [x] dup/dup2/pipe/isatty
- [x] fsync/fdatasync

### Filesystem operations

- [x] access/chmod
- [x] truncate/ftruncate
- [x] link/symlink/readlink
- [x] unlink/rename
- [x] mkdir/rmdir
- [x] stat/lstat/fstat
- [x] chdir/fchdir/getcwd

### Directory operations

- [x] opendir/readdir/closedir

### Validation and docs

- [x] Added host-side smoke test (`posix/tests/posix_layer_smoke.c`)
- [x] Added explicit no-backend behavior (`ENOSYS`) checks
- [x] Documented architecture and usage in `posix/README.md`

---

## In Progress

- [x] Harden API semantics baseline and edge-case behavior checks (initial pass)
- [x] Define initial error/return conventions document for wrapper behavior

---

## New Tasks

### Priority 1 (next)

- [x] Add `bm_lseek64`/large-file behavior guidance and conformance tests
- [x] Add `errno` conformance notes per API (return values + failure contracts)
- [x] Add dedicated tests for:
  - [x] symlink/lstat edge cases
  - [x] short reads/writes
  - [x] invalid descriptor handling
  - [x] directory iteration end/error differentiation

### Priority 2

- [x] Add path utilities required by shell/editor tooling:
  - [x] realpath-like resolution wrapper
  - [x] basename/dirname-safe utility helpers
- [x] Add permission/mode translation notes for BareMetal ABI implementers

### Priority 3

- [x] Add optional process/session wrappers (if/when kernel model supports it)
- [x] Add optional tty/termios adapter hooks

---


## New Artifacts (this update)

- `posix/ERROR_SEMANTICS.md` — return/error matrix and baseline conventions
- `posix/tests/posix_edge_cases.c` — focused edge-case validation suite
- `posix/PERMISSION_MODE_NOTES.md` — ABI implementer mode/permission mapping guidance
- `posix/tests/posix_path_utils.c` — path utility conformance checks
- `posix/tests/posix_process_tty.c` — process/session and tty hook validation
- `posix/KERNEL_ABI_IMPLEMENTER_GUIDE.md` — kernel backend implementation requirements
- `posix/tests/run_all_host_tests.sh` — single-command host test runner
- `posix/apps/bm_client_app.c` — runnable client app self-test target
- `posix/tests/run_bm_client_app.sh` — client app compile/run harness

---

## Risks / Gaps

- Kernel ABI currently assumes implementers provide full operation set; no partial capability negotiation yet.
- Behavior may differ between host backend and future BareMetal backend until ABI semantics are fully codified.
- No CI integration yet for POSIX smoke tests.

---

## Exit Criteria for Phase 0.4

To mark Phase 0.4 complete:

- [x] API behavior matrix documented (success/failure semantics per wrapper)
- [x] Smoke test split into focused test targets
- [x] Kernel ABI implementer guide drafted (required behaviors + examples)
- [x] Reproducible host-side test command documented in repo root
