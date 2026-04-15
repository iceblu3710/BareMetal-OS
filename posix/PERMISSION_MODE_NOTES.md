# BareMetal POSIX Permission and Mode Translation Notes

This guide documents expected mode/permission behavior for kernel ABI implementers.

## Core expectations

- `bm_mode_t` and `bm_kmode_t` are treated as bitwise-compatible mode containers.
- Wrapper callers may pass POSIX-like mode values (e.g., `0644`, `0755`) to creation/chmod calls.
- Backends should preserve permission intent when possible; if the underlying platform has reduced semantics, apply deterministic mapping.

## Recommended mapping behavior

1. Respect owner/group/other read/write/execute bits where the backend supports them.
2. Preserve file-type bits in `stat`/`lstat` outputs.
3. Return an errno-style failure when a mode cannot be represented rather than silently discarding critical bits.

## APIs affected

- `bm_open(..., BM_O_CREAT, mode)`
- `bm_chmod(path, mode)`
- `bm_stat`, `bm_lstat`, `bm_fstat` (`mode` field)

## Portability note

Host backend follows native libc behavior. BareMetal kernel backends should document any intentional deviations in their own backend notes.
