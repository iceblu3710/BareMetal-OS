# BareMetal Kernel ABI Implementer Guide (v1)

This guide defines required behavior for implementing `struct bm_kernel_abi_v1`.

## 1) Binding contract

To be accepted by `bm_bind_kernel_abi_v1()`, all function pointers in `bm_kernel_abi_v1` must be non-NULL and `abi_version` must equal `BM_KERNEL_ABI_V1`.

## 2) Return/error conventions

- Success/failure should mirror POSIX-style conventions where possible.
- On success:
  - return non-negative values (`0`, positive byte counts, valid fds, etc.)
- On failure:
  - return `-1`
  - expose stable errno-style semantics from backend implementation

Recommended error classes:

- Path errors: `ENOENT`, `ENOTDIR`, `EEXIST`, `EACCES`
- FD errors: `EBADF`
- Argument errors: `EINVAL`
- Capability/unsupported: deterministic backend-defined errno (avoid silent success)

## 3) API families and expectations

### File/FD operations

- `open/close/read/write/lseek/pread/pwrite`
- `dup/dup2/pipe/isatty`
- `fsync/fdatasync`

Expectations:

- preserve short-read/short-write semantics
- EOF should be represented by `read` returning `0`
- large offsets should honor 64-bit `bm_koff_t`

### Filesystem/path

- `access/chmod/truncate/ftruncate`
- `link/symlink/readlink`
- `unlink/rename/mkdir/rmdir`
- `stat/lstat/fstat`
- `chdir/fchdir/getcwd/realpath`

Expectations:

- `lstat` should describe the link itself (not target)
- `realpath` should return canonical absolute path in provided buffer
- mode bits should preserve caller intent as documented in `PERMISSION_MODE_NOTES.md`

### Directory traversal

- `opendir/readdir/closedir`

`readdir` contract:

- return `0` when an entry is emitted
- return `1` when end-of-directory is reached
- return `-1` on error

### Process/session + TTY

- `getpid/getppid/setsid`
- `tcgetattr/tcsetattr`

Expectations:

- `setsid` may fail depending on session state; return deterministic errno-style failures
- `tc*` operations should fail cleanly on non-tty descriptors

## 4) Interoperability checklist

Before enabling a kernel backend:

1. Ensure every v1 callback is implemented.
2. Run host-side tests as a behavior baseline.
3. Run equivalent backend tests against kernel ABI implementation.
4. Compare failure modes for parity with documented semantics.

## 5) Validation commands

Use the host runner first:

```bash
./posix/tests/run_all_host_tests.sh
```

Then run your kernel-backed equivalent and compare outcomes.
