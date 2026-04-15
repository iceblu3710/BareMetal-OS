# POSIX Layer

This directory contains a POSIX-style wrapper API for BareMetal userspace tooling.

## Architecture direction

- Keep POSIX semantics in userspace (`posix/`).
- Keep kernel-facing primitives in a versioned BareMetal ABI contract.
- Bridge the two with `bm_bind_kernel_abi_v1()`.

## Included functionality

### File descriptor I/O

- `bm_open`, `bm_close`
- `bm_read`, `bm_write`
- `bm_lseek`, `bm_lseek64`, `bm_pread`, `bm_pwrite`
- `bm_dup`, `bm_dup2`, `bm_pipe`, `bm_isatty`
- process/session helpers: `bm_getpid`, `bm_getppid`, `bm_setsid`
- tty hooks: `bm_tcgetattr`, `bm_tcsetattr`
- `bm_fsync`, `bm_fdatasync`

### Filesystem operations

- `bm_access`, `bm_chmod`
- `bm_truncate`, `bm_ftruncate`
- `bm_link`, `bm_symlink`, `bm_readlink`
- `bm_unlink`, `bm_rename`
- `bm_mkdir`, `bm_rmdir`
- `bm_stat`, `bm_lstat`, `bm_fstat`
- `bm_chdir`, `bm_fchdir`, `bm_getcwd`, `bm_realpath`
- path helpers: `bm_basename_r`, `bm_dirname_r`

### Directory traversal

- `bm_opendir`, `bm_readdir`, `bm_closedir`

## Backend options

1. **Kernel ABI path (recommended for BareMetal):**
   - Implement `struct bm_kernel_abi_v1` from `include/bm_kernel_abi.h`
   - Bind via `bm_bind_kernel_abi_v1()`
2. **Host backend path (for local dev/testing):**
   - Call `bm_use_host_backend()` explicitly

No backend is selected by default. Wrapper calls return `-1` with `bm_last_error() == ENOSYS` until a backend is bound.

## Error handling

Every failing wrapper sets an internal `bm_last_error()` value (errno-style integer).


## Host test runner

Run all POSIX host validation tests with:

```bash
./posix/tests/run_all_host_tests.sh
```


## Client application (testable)

A runnable client application is now available:

- `posix/apps/bm_client_app.c`

Run its self-test with:

```bash
./posix/tests/run_bm_client_app.sh
```
