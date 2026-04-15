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
- `baremetal.sh ext23-emu-test` runs a vertical smoke flow: data image prep, scaffold apply, build, bounded QEMU boot, and serial-log tail.
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
- [x] Run one-command emulator smoke flow (`ext23-emu-test`) for vertical milestone iteration.

---

## Ordered Task Breakdown

Each task below is self-contained, testable, and listed in dependency order. Complete them sequentially within each phase; phases build on prior phases.

### Current scaffold state

| Layer | File | Status |
|-------|------|--------|
| Block cache | `fs/cache.asm` | Stub — all functions return immediately |
| VFS shim | `fs/vfs.asm` | Stub — all functions return 0 |
| ext2 parser | `fs/ext2.asm` | **Partially implemented** — superblock validation, block size, BGDT offset, inode offset, dirent validation/traversal/name-matching have real logic. mount, read/write entry points, allocators are stubs. |
| ext2 layout | `fs/ext2_layout.inc` | Complete for basic parsing (SB, BG, dirent, inode fields) |
| Journal | `fs/journal.asm` | Stub — all functions return immediately |
| NVS init | `init/nvs.asm` | Only discovers **first** VirtIO block device |
| NVS syscall | `syscalls/nvs.asm` | Hardcoded to single `os_nvs_io` function pointer |

> **CRITICAL:** `init_nvs` stops after the first mass-storage controller. The ext data disk is the second VirtIO block device. Multi-device NVS enumeration must land before any kernel-side ext2 code can run.

---

### Phase 1 — Enumerate and Select Data Disk

#### Task 1.1 — Add multi-device NVS table to sysvar.asm

**Files:** `sysvar.asm`

- Add `os_nvs_devices` array (8 entries × 32 bytes) in the free `0x120000` region.
- Each entry: `io_func_ptr` (8B), `id_func_ptr` (8B), `bus_record` (4B), `flags` (2B), `serial_hash` (2B), `reserved` (8B).
- Add `os_nvs_device_count` (DB) counter.
- Keep existing `os_nvs_io` / `os_nvs_id` as primary-device alias for backward compatibility.

**Verify:** Assembles cleanly, existing kernel boot is unchanged.

#### Task 1.2 — Extend init_nvs to iterate all bus entries

**Files:** `init/nvs.asm`

- Replace the `jmp init_nvs_done` after the first match with a loop that continues scanning the bus table.
- For each match, call `virtio_blk_init` and register the device in `os_nvs_devices`.
- First registered device still populates `os_nvs_io` / `os_nvs_id` for legacy compatibility.
- Increment `os_nvs_device_count`.

**Verify:** Boot with two VirtIO-blk drives. Serial log shows `nvs ok` and `os_nvs_device_count == 2`.

#### Task 1.3 — Make virtio_blk_init support multiple instances

**Files:** `drivers/nvs/virtio-blk.asm`

Currently stores state in file-scope globals (`os_virtioblk_base`, `notify_offset`, `descindex`, `availindex`, `header`, `footer`). These are per-device.

- Convert globals into per-device context struct (or allocate a second copy for device 1).
- Accept a device-index parameter (e.g., in `r8`) and store per-device state at indexed offsets.
- Return `io` and `id` function pointers to the caller so `init_nvs` can store them in the device table.

> **NOTE:** `virtio_blk_io` uses hardcoded `os_nvs_mem` for queue memory. A second device needs its own queue region. Option: carve `os_nvs_mem` (192 KiB) into two 96 KiB halves, or extend the region into the free `0x120000` area.

**Verify:** Both disks respond to read commands. Read sector 0 from each drive and compare.

#### Task 1.4 — Add NVS helpers that target device N

**Files:** `syscalls/nvs.asm`

- Add `b_nvs_read_dev` / `b_nvs_write_dev` accepting a device index in `RDX` and looking up `os_nvs_devices[RDX].io_func_ptr`.
- Existing `b_nvs_read` / `b_nvs_write` remain unchanged (always device 0).

**Verify:** Read sector 2 (byte offset 1024 = superblock) from device 1, check for magic `0xEF53`.

#### Task 1.5 — Data disk selection policy

**Files:** `init/nvs.asm`, `sysvar.asm`

- After enumeration, store `os_datafs_nvs_id` (DQ) pointing to the device index of the ext data disk.
- Simple policy: device 0 = boot (BMFS), device 1 = data (ext).

**Verify:** `os_datafs_nvs_id` is 1 after boot with two disks; 0 or unset with one disk.

---

### Phase 2 — Block Cache

#### Task 2.1 — Define cache line structure

**Files:** `fs/cache.asm`, `sysvar.asm`

- Cache line metadata: `block_number` (8B), `flags` (2B: valid/dirty/pinned), `lru_counter` (2B), `padding` (4B) = 16 bytes/slot.
- 64 slots × 4 KiB data = 256 KiB for data buffers. Place metadata in `fs_cache_state`, data buffers at a known base address.

**Verify:** Assembles. `fs_cache_init` zeroes all slots.

#### Task 2.2 — Implement fs_cache_init

**Files:** `fs/cache.asm`

- Zero all metadata slots and data buffers.
- Set global LRU counter to 0.

**Verify:** Call from init path. Inspect memory via QEMU monitor.

#### Task 2.3 — Implement fs_cache_get (read-through)

**Files:** `fs/cache.asm`

- Search metadata for matching block_number with valid flag → cache hit, return data pointer.
- On miss: LRU eviction, read block via `b_nvs_read_dev` from data disk, populate slot, return pointer.

**Verify:** Read superblock block via `fs_cache_get`. Verify magic bytes. Read again — no NVS I/O (cache hit).

#### Task 2.4 — Implement fs_cache_mark_dirty and fs_cache_flush

**Files:** `fs/cache.asm`

- `mark_dirty`: set dirty flag.
- `flush`: write back all dirty blocks via `b_nvs_write_dev`, clear dirty flags.

**Verify:** Read a block, mark dirty, flush, verify NVS write issued.

---

### Phase 3 — ext2 Read Path

#### Task 3.1 — Implement ext2_mount (real logic)

**Files:** `fs/ext2.asm`

- Call `fs_cache_init`.
- Read superblock (byte offset 1024), validate via `ext2_validate_superblock`.
- Extract and stash block size, blocks_per_group, inodes_per_group, group count.
- Read BGDT via `ext2_bgdt_offset_from_sb` and cache it.
- Store superblock pointer and root inode (inode 2).

**Verify:** Returns 0 on pre-populated `ext_data.img`. Returns non-zero on zeroed image.

#### Task 3.2 — Implement ext2_read_inode

**Files:** `fs/ext2.asm`

- Compute block group from inode number.
- Read group descriptor from cache.
- Use `ext2_inode_byte_offset` to find disk offset.
- Read containing block via `fs_cache_get`, return pointer to inode within block.

**Verify:** Read inode 2 (root directory). `ext2_inode_is_dir` returns 1.

#### Task 3.3 — Implement ext2_readdir

**Files:** `fs/ext2.asm`

- Iterate directory inode's data blocks (direct pointers 0..11).
- For each block, walk entries using `ext2_dirent_is_valid` / `ext2_dirent_next`.
- Invoke callback per entry.

**Verify:** `ext2_readdir` on root inode lists `.`, `..`, `bmtest`, `lost+found`.

#### Task 3.4 — Implement path lookup (vfs_lookup → ext2)

**Files:** `fs/vfs.asm`, `fs/ext2.asm`

- Split path by `/`. Walk from root inode (2) using `ext2_find_name_in_block` per component.
- Return final inode number.

**Verify:** `vfs_lookup("/bmtest/smoke/probe.txt")` returns valid inode. `vfs_lookup("/nonexistent")` returns 0.

#### Task 3.5 — Implement ext2_read_file / vfs_read

**Files:** `fs/ext2.asm`, `fs/vfs.asm`

- Map file offset to logical block + intra-block offset.
- Direct blocks (0..11) via `ext2_file_block_ptr_direct`.
- Copy data to caller buffer, clamp by file size.

**Verify:** Read `/bmtest/smoke/probe.txt`, output via serial. Matches `datafs-populate` payload.

#### Task 3.6 — Indirect block pointer support

**Files:** `fs/ext2.asm`, `fs/ext2_layout.inc`

- Single indirect for blocks 12..1035.
- Double indirect for blocks 1036+.
- Triple indirect deferred.

**Verify:** Read a file > 48 KiB seeded via `debugfs`.

#### Task 3.7 — Wire ext2 mount into kernel boot

**Files:** `kernel.asm` or `init/nvs.asm`

- After device init, call `vfs_mount_datafs` → `ext2_mount`.
- Log success/failure via serial.
- Mount failure is non-fatal.

**Verify:** `ext23-emu-test` shows mount status in `sys/serial.log`.

---

### Phase 4 — ext2 Write Path

#### Task 4.1 — Block bitmap reading

**Files:** `fs/ext2.asm`

- Read block bitmap from group descriptor `bg_block_bitmap`.
- Provide `ext2_bitmap_test_bit` helper.

**Verify:** Free block count matches `dumpe2fs` output.

#### Task 4.2 — ext2_alloc_block

**Files:** `fs/ext2.asm`

- Scan bitmap for first free bit, set it, mark dirty.
- Update superblock and group descriptor free counts.

**Verify:** Allocate, flush, `e2fsck -fn` passes.

#### Task 4.3 — Inode bitmap + ext2_alloc_inode

**Files:** `fs/ext2.asm`

- Same pattern as block allocation on inode bitmap.

**Verify:** Allocate, flush, `e2fsck -fn` passes.

#### Task 4.4 — ext2_write_inode

**Files:** `fs/ext2.asm`

- Compute offset, read containing block, memcpy inode data, mark dirty.

**Verify:** Write inode, flush, read back — fields match.

#### Task 4.5 — ext2_dirent_add

**Files:** `fs/ext2.asm`

- Find slack in existing directory block entries, split rec_len.
- If no space, allocate new directory data block.

**Verify:** Add entry, flush, mount host-side, file visible.

#### Task 4.6 — File create (vfs_create → ext2)

**Files:** `fs/vfs.asm`, `fs/ext2.asm`

- Alloc inode, init fields, write inode, add dirent in parent.

**Verify:** Create file, flush, visible on host, `e2fsck -fn` passes.

#### Task 4.7 — File write (vfs_write → ext2)

**Files:** `fs/vfs.asm`, `fs/ext2.asm`

- Allocate blocks as needed, copy data via cache, update inode size.

**Verify:** Write content, flush, read from host, `e2fsck -fn` passes.

#### Task 4.8 — Truncation and unlink

**Files:** `fs/ext2.asm`

- Free data blocks, clear bitmap bits, remove dirent, decrement link count, free inode if link_count=0.

**Verify:** Create/write/unlink cycle, `e2fsck -fn` passes, free counts restored.

---

### Phase 5 — ext3 Journaling

#### Task 5.1 — Parse journal inode

**Files:** `fs/journal.asm`, `fs/ext2_layout.inc`

- Add ext3 SB fields to layout: `s_journal_inum` (0xE0), features, JBD2 magic `0xC03B3998`.
- Read journal inode (typically inode 8), parse journal superblock.

**Verify:** `journal_init` succeeds on ext3 image, reports sequence number via serial.

#### Task 5.2 — journal_replay

**Files:** `fs/journal.asm`

- Walk journal: descriptor → data → commit blocks.
- Copy committed data blocks to target filesystem locations.
- Update journal superblock.

**Verify:** Dirty image via `datafs-replay-test`, boot, replay runs, `e2fsck -fn` passes.

#### Task 5.3 — journal_tx_begin + journal_tx_log_block

**Files:** `fs/journal.asm`

- Allocate transaction handle, write descriptor entries.

**Verify:** Begin tx, log one block, inspect journal area via QEMU monitor.

#### Task 5.4 — journal_tx_commit + journal_tx_abort

**Files:** `fs/journal.asm`

- Commit: write commit block, flush metadata, update journal SB.
- Abort: discard entries, reset sequence.

**Verify:** Full tx cycle (begin → log → commit), `e2fsck -fn` passes.

#### Task 5.5 — Wrap write-path in journal transactions

**Files:** `fs/ext2.asm`

- Wrap `ext2_alloc_block`, `ext2_alloc_inode`, `ext2_write_inode`, `ext2_dirent_add` in `tx_begin`/`tx_log`/`tx_commit`.
- Ordered metadata journaling only.

**Verify:** File create + write, kill QEMU mid-write, reboot, replay, `e2fsck -fn` passes.

---

### Phase 6 — Crash Recovery Validation

#### Task 6.1 — Automated QEMU kill/reboot test harness

**Files:** `tools/ext23_crash_test.sh` *(new)*

- Fresh image → boot with file-creating payload → random-delay kill → reboot → journal replay → kill → `e2fsck -fn`.

**Verify:** 10 iterations, all pass.

#### Task 6.2 — Deterministic crash-point injection

**Files:** `fs/ext2.asm`, `fs/journal.asm`

- Debug sysvar triggers halt at specific write-path points (after descriptor, before commit, etc.).

**Verify:** Each crash point produces recoverable image.

#### Task 6.3 — Mount safety fallback

**Files:** `fs/ext2.asm`, `fs/vfs.asm`

- Check `s_state` on mount; if not clean, run `journal_replay`.
- Set dirty on mount, clean on sync.

**Verify:** Interrupted boot triggers replay; clean shutdown clears dirty flag.
