# In-OS Disk Utility: ABI v2 Additions + Command Design (Draft)

This document proposes the exact v2 ABI additions and CLI design to support partitioning and formatting from within BareMetal OS.

## 1) ABI scope and goals

v2 introduces:

1. Raw disk enumeration/read/write/flush
2. Partition table management (GPT/MBR)
3. Filesystem creation (`mkfs`) entrypoint
4. Destructive-action safety confirmations

Draft ABI header: `posix/include/bm_kernel_abi_v2_draft.h`

## 2) Core principles

- **Explicitly destructive operations must require confirmation tokens.**
- **No implicit device guessing** in kernel APIs (disk id/part index always explicit).
- **Deterministic return values**: `0` success, `-1` failure with errno-style reason.
- **Feature evolution** should happen by versioned structs and new function slots.

## 3) Command design (`disk` utility)

Proposed top-level command:

```text
disk <subcommand> [args]
```

### 3.1 Discovery and inspection

```text
disk list
disk info <disk-id>
disk part list <disk-id>
```

Behavior:
- `disk list` prints disk id, name, size, bus, writable flag.
- `disk info` prints sector sizes and partition table type.
- `disk part list` prints partition ranges and fs hints.

### 3.2 Partition table initialization

```text
disk part init <disk-id> --table gpt|mbr --confirm <nonce>
```

Maps to:
- `disk_confirmation_nonce`
- `part_table_init`

### 3.3 Partition create/delete

```text
disk part create <disk-id> --index <n> --start-lba <n> --end-lba <n> [--name <text>] [--fs-hint fat32|ext4|bmfs] [--bootable] --confirm <nonce>

disk part delete <disk-id> --index <n> --confirm <nonce>
```

Maps to:
- `part_create`
- `part_delete`

### 3.4 Format operations

```text
disk mkfs <disk-id> --part <n> --type fat32|ext4|bmfs [--label <name>] [--quick] --confirm <nonce>
```

Maps to:
- `mkfs`

### 3.5 Raw I/O debug commands (optional, developer mode)

```text
disk read-lba <disk-id> --lba <n> --count <n>
disk write-lba <disk-id> --lba <n> --count <n> --from <file> --confirm <nonce>
```

Maps to:
- `disk_read_lba`
- `disk_write_lba`

## 4) Safety model

All destructive subcommands (`part init`, `part create`, `part delete`, `mkfs`, `write-lba`) require:

1. call `disk_confirmation_nonce(disk_id)`
2. user passes nonce via `--confirm`
3. request includes `bm_disk_confirm`

This prevents accidental default-target writes.

## 5) Suggested output style

Human-readable by default, machine-readable optional:

```text
disk list --json
```

JSON schema should mirror `bm_disk_info` and `bm_partition_info` fields.

## 6) Minimal implementation phases

### Phase A: Read-only
- `disk list`
- `disk info`
- `disk part list`

### Phase B: Table + partition mutation
- `disk part init`
- `disk part create`
- `disk part delete`

### Phase C: Filesystem creation
- `disk mkfs`

### Phase D: Debug raw I/O
- `disk read-lba`
- `disk write-lba`

## 7) Immediate next steps

1. Add v2 draft header review to maintainers.
2. Implement read-only ABI functions in kernel backend first.
3. Add `disk list/info/part list` command in Monitor/tooling layer.
4. Add dry-run mode before enabling destructive commands.


## 8) Phase 1 and 2 implementation update

A host/mock prototype for phases A and B is now included:

- `posix/tools/diskctl_phase12.c`
- `posix/tests/run_diskctl_phase12_mock.sh`

Implemented prototype commands:

- `list`, `info`, `part-list` (Phase A)
- `part-init`, `part-create`, `part-delete` (Phase B)

This prototype uses the v2 draft ABI shape and provides a concrete command parser and ABI-call mapping baseline before kernel-side wiring.
