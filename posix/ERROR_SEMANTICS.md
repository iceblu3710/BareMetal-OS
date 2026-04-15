# POSIX Wrapper Error and Return Semantics

This document defines expected behavior for the `bm_*` wrapper surface.

## Global Rules

- On success, wrappers return the same shape as POSIX where applicable (`0`, positive byte count, file descriptor, etc).
- On failure, wrappers return `-1` (or `NULL` for pointer returns) and set `bm_last_error()` to an errno-style code.
- If no backend is bound, wrappers fail with `bm_last_error() == ENOSYS`.

## Behavior Matrix (selected core calls)

| Wrapper | Success return | Failure return | Typical `bm_last_error()` |
|---|---:|---:|---|
| `bm_open` | `fd >= 0` | `-1` | `ENOENT`, `EACCES`, `EINVAL` |
| `bm_close` | `0` | `-1` | `EBADF` |
| `bm_read` | `n >= 0` | `-1` | `EBADF`, `EFAULT`, backend-specific |
| `bm_write` | `n >= 0` | `-1` | `EBADF`, `EFAULT`, backend-specific |
| `bm_lseek`/`bm_lseek64` | `offset >= 0` | `-1` | `EINVAL`, `EBADF` |
| `bm_stat`/`bm_lstat`/`bm_fstat` | `0` | `-1` | `ENOENT`, `EBADF`, `EINVAL` |
| `bm_opendir` | non-NULL handle | `NULL` | `ENOENT`, `ENOTDIR`, `EINVAL` |
| `bm_readdir` | `0` (entry), `1` (end) | `-1` | `EINVAL`, backend-specific |
| `bm_closedir` | `0` | `-1` | `EINVAL`, backend-specific |
| `bm_link`/`bm_symlink`/`bm_unlink` | `0` | `-1` | `ENOENT`, `EEXIST`, `EACCES` |
| `bm_bind_kernel_abi_v1` | `0` | `-1` | `EINVAL` |

## Notes for kernel ABI implementers

- Kernel ABI implementations should mirror POSIX-style error categorization where possible.
- If an operation is not implemented in a backend, fail deterministically with a stable errno-style value.


## Large-file guidance

- `bm_off_t` is the canonical 64-bit offset type for this layer.
- `bm_lseek64` is an alias of `bm_lseek` to make large-file intent explicit in callers/ports.
- Conformance is validated by creating sparse files beyond 4 GiB in `posix/tests/posix_largefile_conformance.c`.
