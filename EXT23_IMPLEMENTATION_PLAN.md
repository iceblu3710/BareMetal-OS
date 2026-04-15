# ext2/3 Data Partition Implementation Plan

This branch starts the ext2/3 effort by adding a dedicated second disk image (`sys/ext_data.img`) that can be attached to QEMU as an additional VirtIO block device.

## Current groundwork in this branch

- `baremetal.sh build` now creates `sys/ext_data.img` using `DATAFS_SIZE` (default 512 MiB).
- If `mke2fs` is installed, the image is initialized as ext3 by default (`DATAFS_FS=ext3`, label `BMDATA`).
- `baremetal.sh run` and `baremetal.sh run-uefi` can attach the data image as a second VirtIO block device.
- `baremetal.sh datafs` recreates only the data image.
- `baremetal.sh datafs-info` prints ext metadata (when `dumpe2fs` is available).
- `baremetal.sh datafs-manifest` prints the expected kernel selection values (`DATAFS_SERIAL`, `DATAFS_NVS_ID`).
- `baremetal.sh datafs-populate` writes deterministic smoke-test content (`/bmtest/smoke/probe.txt`) into the ext image.
- `baremetal.sh datafs-check` runs host-side non-destructive fsck (`e2fsck -fn`) for quick consistency checks.
- `baremetal.sh datafs-replay-test` runs a replay-oriented fsck flow on a copied image (`sys/ext_data_replay.img`) and captures logs in `sys/ext_data_replay.log`.
- `tools/ext23_kernel_scaffold.sh` bootstraps `fs/cache.asm`, `fs/vfs.asm`, `fs/ext2_layout.inc`, and `fs/ext2.asm` stubs in a checked-out BareMetal kernel tree and appends includes to `kernel.asm`.
- `tools/ext23_kernel_scaffold.sh` also bootstraps `fs/journal.asm` with ext3-style transaction/replay symbol stubs.
- `baremetal.sh ext23-scaffold` runs that bootstrap directly against `src/BareMetal`.
- Set `ENABLE_DATAFS=0` to temporarily run without the second data disk.

## Kernel implementation sequence (BareMetal repo)

1. **Enumerate and select data disk**
   - Extend storage initialization so the second block device is discoverable.
   - Add a selection policy to keep BMFS boot image as primary and mark ext data disk as filesystem target.
   - Host-side groundwork in this repo now sets fixed disk serials and emits `sys/ext_data.meta` for kernel wiring.

2. **Block cache + VFS shim**
   - Introduce cache pages (4 KiB) for metadata and data blocks.
   - Implement a minimal VFS interface: mount, lookup, read, write, create, unlink, sync.
   - Host-side scaffolding script now exists to create starter files and symbol stubs in the kernel repo.

3. **ext2 read path first**
   - Parse superblock/group descriptors.
   - Support inode lookup and directory traversal.
   - Read regular files end-to-end.
   - Host-side scaffolding script now provides `ext2_mount`, `ext2_validate_superblock`, `ext2_block_size_from_sb`, `ext2_bgdt_offset_from_sb`, `ext2_inode_byte_offset`, `ext2_dirent_is_valid`, `ext2_dirent_next`, `ext2_dirent_name_eq`, `ext2_find_name_in_block`, `ext2_inode_is_dir`, `ext2_inode_block_ptr`, `ext2_inode_size_lo`, `ext2_file_block_ptr_direct`, `ext2_read_inode`, `ext2_readdir`, and `ext2_read_file` stubs plus ext2 layout constants.

4. **ext2 write path**
   - Inode/block bitmap allocation.
   - Directory entry insert/remove.
   - File growth/truncation support.
   - Host-side scaffolding script now provides initial write-phase symbols: `ext2_alloc_block`, `ext2_alloc_inode`, `ext2_write_inode`, and `ext2_dirent_add`.

5. **ext3-style journaling (metadata first)**
   - Add transaction API (`tx_begin`, `tx_log`, `tx_commit`).
   - Journal descriptor/commit parsing and recovery replay at mount.
   - Start with ordered metadata journaling; data journaling can be optional later.
   - Host-side scaffolding script now provides starter symbols: `journal_init`, `journal_tx_begin`, `journal_tx_log_block`, `journal_tx_commit`, `journal_tx_abort`, and `journal_replay`.

6. **Crash recovery validation**
   - Automate kill/reboot tests under QEMU.
   - Confirm replay invariants and mount safety fallback.
   - Host-side groundwork in this repo now supports deterministic image population, fsck checks, and replay-oriented fsck workflow on copied images.

## Developer notes

- The first target is correctness and recoverability, then performance.
- Keep BMFS boot workflow unchanged while ext2/3 support matures.

## ext3 parity tracker

- [x] Dedicated data disk image and QEMU attachment path.
- [x] ext3-formatted disk image generation for development/testing.
- [~] Disk identification contract defined (`DATAFS_SERIAL`, `DATAFS_NVS_ID`, manifest output).
- [~] Host-side workload + consistency check helpers (`datafs-populate`, `datafs-check`).
- [ ] Kernel-level block cache integrated with filesystem code paths.
- [~] Kernel block-cache/VFS scaffold script prepared (`tools/ext23_kernel_scaffold.sh`).
- [~] ext2 read-path symbol scaffold prepared (`fs/ext2_layout.inc` + `fs/ext2.asm` stubs, superblock/block-size/BGDT/inode-offset/dirent/inode-field/name-lookup/file-block helpers).
- [ ] ext2-compatible inode/directory read path in kernel.
- [~] ext2 write-path symbol scaffold prepared (`ext2_alloc_block`, `ext2_alloc_inode`, `ext2_write_inode`, `ext2_dirent_add`).
- [ ] ext2 write path (allocation + directory updates + truncation).
- [~] ext3 journal symbol scaffold prepared (`fs/journal.asm`).
- [ ] ext3 journal transaction engine (descriptor/commit/replay).
- [~] Host-side replay validation scaffold prepared (`datafs-replay-test`).
- [ ] Crash-recovery replay validation and consistency tests.

## BareMetal-OS integration checklist (completed)

- [x] Create and format dedicated ext data disk image.
- [x] Attach data disk optionally for BIOS and UEFI runs.
- [x] Emit and inspect data disk selection manifest.
- [x] Seed deterministic ext image content for kernel smoke tests.
- [x] Run host-side image consistency check (`e2fsck -fn`).
- [x] Run replay-oriented fsck flow on copied image (`datafs-replay-test`).
