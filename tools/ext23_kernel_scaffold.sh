#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="src/BareMetal"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--repo)
			REPO_PATH="$2"
			shift 2
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		*)
			echo "Unknown argument: $1"
			exit 1
			;;
	esac
done

KERNEL_ASM="$REPO_PATH/src/kernel.asm"
FS_DIR="$REPO_PATH/src/fs"
CACHE_ASM="$FS_DIR/cache.asm"
VFS_ASM="$FS_DIR/vfs.asm"
EXT2_ASM="$FS_DIR/ext2.asm"
EXT2_LAYOUT_INC="$FS_DIR/ext2_layout.inc"
JOURNAL_ASM="$FS_DIR/journal.asm"

if [[ ! -f "$KERNEL_ASM" ]]; then
	echo "Kernel source not found at $KERNEL_ASM"
	echo "Run './baremetal.sh setup' first, or provide '--repo <path>'"
	exit 1
fi

create_file() {
	local path="$1"
	local content="$2"
	if [[ -f "$path" ]]; then
		echo "Exists: $path"
		return
	fi
	if [[ "$DRY_RUN" -eq 1 ]]; then
		echo "Would create: $path"
	else
		mkdir -p "$(dirname "$path")"
		printf '%s' "$content" > "$path"
		echo "Created: $path"
	fi
}

cache_content='; SPDX-License-Identifier: BSD-3-Clause
; ext2/3 block cache scaffold for BareMetal

bits 64

define FS_CACHE_SLOTS 64

global fs_cache_init
global fs_cache_get
global fs_cache_mark_dirty
global fs_cache_flush

section .bss
align 16
fs_cache_state:  resb 4096

section .text
fs_cache_init:
	ret

; in: rsi = logical block number
; out: rax = pointer to cache line (0 on miss/failure)
fs_cache_get:
	xor rax, rax
	ret

; in: rax = pointer to cache line
fs_cache_mark_dirty:
	ret

fs_cache_flush:
	ret
'

vfs_content='; SPDX-License-Identifier: BSD-3-Clause
; ext2/3 VFS shim scaffold for BareMetal

bits 64

global vfs_init
global vfs_mount_datafs
global vfs_lookup
global vfs_read
global vfs_write
global vfs_sync

section .text
vfs_init:
	ret

; out: rax = 0 on success, non-zero on failure
vfs_mount_datafs:
	xor rax, rax
	ret

; in: rsi = path ptr, out: rax = inode handle or 0
vfs_lookup:
	xor rax, rax
	ret

; in: rsi = inode, rdx = buf, rcx = len, r8 = off
; out: rax = bytes read
vfs_read:
	xor rax, rax
	ret

; in: rsi = inode, rdx = buf, rcx = len, r8 = off
; out: rax = bytes written
vfs_write:
	xor rax, rax
	ret

vfs_sync:
	ret
'

ext2_content='; SPDX-License-Identifier: BSD-3-Clause
; ext2 read-path scaffold for BareMetal

bits 64

include "fs/ext2_layout.inc"

global ext2_mount
global ext2_read_inode
global ext2_readdir
global ext2_read_file
global ext2_validate_superblock
global ext2_block_size_from_sb
global ext2_bgdt_offset_from_sb
global ext2_inode_byte_offset
global ext2_dirent_is_valid
global ext2_dirent_next
global ext2_inode_is_dir
global ext2_inode_block_ptr
global ext2_dirent_name_eq
global ext2_find_name_in_block
global ext2_inode_size_lo
global ext2_file_block_ptr_direct
global ext2_alloc_block
global ext2_alloc_inode
global ext2_write_inode
global ext2_dirent_add

section .text
; in: rsi = nvs device id
; out: rax = 0 success, non-zero failure
ext2_mount:
	; TODO: read block 1 superblock via block cache and validate fields
	xor rax, rax
	ret

; in: rsi = ptr to 1024-byte ext2 superblock payload
; out: rax = 1 valid, 0 invalid
ext2_validate_superblock:
	mov ax, word [rsi + EXT2_SB_MAGIC]
	cmp ax, EXT2_SUPER_MAGIC
	jne .invalid
	mov rax, 1
	ret
.invalid:
	xor rax, rax
	ret

; in: rsi = ptr to 1024-byte ext2 superblock payload
; out: rax = block size in bytes (1024 << s_log_block_size)
ext2_block_size_from_sb:
	mov eax, dword [rsi + EXT2_SB_LOG_BLOCK_SIZE]
	mov ecx, eax
	mov eax, 1024
	shl eax, cl
	ret

; in: rsi = ptr to 1024-byte ext2 superblock payload
; out: rax = byte offset for block group descriptor table (from fs start)
ext2_bgdt_offset_from_sb:
	; For 1KiB block size BGDT starts at block 2; otherwise at block 1.
	call ext2_block_size_from_sb
	cmp eax, 1024
	jne .large_block
	mov rax, 2048
	ret
.large_block:
	; bgdt offset = block_size * 1
	movzx rax, eax
	ret

; in:
;   rsi = ptr to 1024-byte ext2 superblock payload
;   rdx = ptr to ext2 group descriptor for inode group
;   rcx = inode number (1-based)
; out:
;   rax = byte offset of inode record from filesystem start
ext2_inode_byte_offset:
	; Convert inode number to zero-based index
	dec rcx

	; index_within_group = inode_index % inodes_per_group
	mov r11d, dword [rsi + EXT2_SB_INODES_PER_GROUP]
	test r11d, r11d
	jz .fail
	mov eax, ecx
	xor edx, edx
	div r11d
	; edx = index_within_group

	; inode_size defaults to 128 for revision 0
	movzx r8d, word [rsi + EXT2_SB_INODE_SIZE]
	test r8d, r8d
	jnz .have_inode_size
	mov r8d, 128
.have_inode_size:

	; inode_table_block from group descriptor
	mov eax, dword [rdx + EXT2_BG_INODE_TABLE]
	movzx rax, eax

	; inode_table_offset = inode_table_block * block_size
	push rdx
	call ext2_block_size_from_sb
	pop rdx
	movzx r9, eax
	imul rax, r9

	; add inode index offset inside table
	movzx r10, edx
	imul r10, r8
	add rax, r10
	ret
.fail:
	xor rax, rax
	ret

; in:
;   rsi = ptr to ext2 directory entry
;   rdx = bytes remaining in directory block
; out:
;   rax = 1 valid, 0 invalid
ext2_dirent_is_valid:
	; rec_len must be at least 8 bytes and within remaining bytes
	movzx r8, word [rsi + EXT2_DE_REC_LEN]
	cmp r8, 8
	jb .invalid
	cmp r8, rdx
	ja .invalid

	; name_len must fit into rec_len payload (rec_len - 8)
	movzx r9, byte [rsi + EXT2_DE_NAME_LEN]
	mov r10, r8
	sub r10, 8
	cmp r9, r10
	ja .invalid

	mov rax, 1
	ret
.invalid:
	xor rax, rax
	ret

; in:
;   rsi = ptr to ext2 directory entry
;   rdx = bytes remaining in directory block
; out:
;   rax = ptr to next entry, or 0 if invalid
ext2_dirent_next:
	push rdx
	call ext2_dirent_is_valid
	pop rdx
	test rax, rax
	jz .bad
	movzx r8, word [rsi + EXT2_DE_REC_LEN]
	lea rax, [rsi + r8]
	ret
.bad:
	xor rax, rax
	ret

; in: rsi = ptr to ext2 inode record
; out: rax = 1 if directory inode, else 0
ext2_inode_is_dir:
	movzx eax, word [rsi + EXT2_IN_MODE]
	and eax, 0xF000
	cmp eax, 0x4000
	jne .not_dir
	mov rax, 1
	ret
.not_dir:
	xor rax, rax
	ret

; in:
;   rsi = ptr to ext2 inode record
;   rcx = block pointer index [0..14]
; out:
;   rax = 32-bit block pointer value (0 when invalid index)
ext2_inode_block_ptr:
	cmp rcx, 15
	jae .bad_index
	mov eax, dword [rsi + EXT2_IN_BLOCK + rcx*4]
	movzx rax, eax
	ret
.bad_index:
	xor rax, rax
	ret

; in:
;   rsi = ptr to ext2 dirent
;   rdx = ptr to candidate name bytes
;   rcx = candidate name length
; out:
;   rax = 1 equal, 0 not equal
ext2_dirent_name_eq:
	movzx r8, byte [rsi + EXT2_DE_NAME_LEN]
	cmp r8, rcx
	jne .neq
	lea r9, [rsi + 8] ; name starts immediately after header
	xor r10, r10
.cmp_loop:
	cmp r10, rcx
	jae .eq
	mov al, byte [r9 + r10]
	mov r11b, byte [rdx + r10]
	cmp al, r11b
	jne .neq
	inc r10
	jmp .cmp_loop
.eq:
	mov rax, 1
	ret
.neq:
	xor rax, rax
	ret

; in:
;   rsi = ptr to start of directory data block
;   rdx = bytes in directory block
;   r8  = ptr to candidate name bytes
;   r9  = candidate name length
; out:
;   rax = ptr to matching dirent, or 0
ext2_find_name_in_block:
	mov r11, rsi ; current entry
	mov r12, rdx ; bytes remaining
.scan_loop:
	test r12, r12
	jz .not_found

	; validate current entry
	mov rsi, r11
	mov rdx, r12
	call ext2_dirent_is_valid
	test rax, rax
	jz .not_found

	; compare current name against target
	mov rsi, r11
	mov rdx, r8
	mov rcx, r9
	call ext2_dirent_name_eq
	test rax, rax
	jnz .found

	; advance to next entry
	movzx r13, word [r11 + EXT2_DE_REC_LEN]
	add r11, r13
	sub r12, r13
	jmp .scan_loop
.found:
	mov rax, r11
	ret
.not_found:
	xor rax, rax
	ret

; in: rsi = ptr to ext2 inode record
; out: rax = lower 32-bit file size
ext2_inode_size_lo:
	mov eax, dword [rsi + EXT2_IN_SIZE_LO]
	movzx rax, eax
	ret

; in:
;   rsi = ptr to ext2 inode record
;   rcx = logical file block index
; out:
;   rax = direct block pointer (0 when out-of-range or unset)
ext2_file_block_ptr_direct:
	cmp rcx, 12
	jae .oob
	call ext2_inode_block_ptr
	ret
.oob:
	xor rax, rax
	ret

; ---- ext2 write-path scaffolds (next phase) ----

; out: rax = allocated block number, or 0 on failure
ext2_alloc_block:
	xor rax, rax
	ret

; out: rax = allocated inode number, or 0 on failure
ext2_alloc_inode:
	xor rax, rax
	ret

; in: rsi = inode number, rdx = ptr to inode bytes
; out: rax = 0 success, non-zero failure
ext2_write_inode:
	xor rax, rax
	ret

; in: rsi = directory inode, rdx = name ptr, rcx = name len, r8 = target inode
; out: rax = 0 success, non-zero failure
ext2_dirent_add:
	xor rax, rax
	ret

; in: rsi = inode number
; out: rax = inode pointer/handle or 0
ext2_read_inode:
	xor rax, rax
	ret

; in: rsi = directory inode, rdx = callback ptr
; out: rax = number of entries iterated
ext2_readdir:
	xor rax, rax
	ret

; in: rsi = inode, rdx = buf, rcx = len, r8 = off
; out: rax = bytes read
ext2_read_file:
	xor rax, rax
	ret
'

ext2_layout_content='; SPDX-License-Identifier: BSD-3-Clause
; ext2 on-disk layout offsets used by parser code

%ifndef EXT2_LAYOUT_INC
%define EXT2_LAYOUT_INC

; superblock is at byte offset 1024 from partition start
%define EXT2_SUPERBLOCK_OFFSET          1024
%define EXT2_SUPER_MAGIC                0xEF53

; superblock fields (offsets within the 1024-byte superblock payload)
%define EXT2_SB_INODES_COUNT            0x00
%define EXT2_SB_BLOCKS_COUNT            0x04
%define EXT2_SB_LOG_BLOCK_SIZE          0x18
%define EXT2_SB_BLOCKS_PER_GROUP        0x20
%define EXT2_SB_INODES_PER_GROUP        0x28
%define EXT2_SB_MAGIC                   0x38
%define EXT2_SB_INODE_SIZE              0x58
%define EXT2_SB_FIRST_INO               0x54

; group descriptor fields
%define EXT2_BG_BLOCK_BITMAP            0x00
%define EXT2_BG_INODE_BITMAP            0x04
%define EXT2_BG_INODE_TABLE             0x08

; directory entry (linked-list format)
%define EXT2_DE_INODE                   0x00
%define EXT2_DE_REC_LEN                 0x04
%define EXT2_DE_NAME_LEN                0x06
%define EXT2_DE_FILE_TYPE               0x07

; inode fields
%define EXT2_IN_MODE                    0x00
%define EXT2_IN_SIZE_LO                 0x04
%define EXT2_IN_BLOCK                   0x28

%endif
'

journal_content='; SPDX-License-Identifier: BSD-3-Clause
; ext3-style metadata journal scaffold for BareMetal

bits 64

global journal_init
global journal_tx_begin
global journal_tx_log_block
global journal_tx_commit
global journal_tx_abort
global journal_replay

section .text
journal_init:
	ret

; out: rax = tx handle (0 on failure)
journal_tx_begin:
	xor rax, rax
	ret

; in: rsi = tx handle, rdx = block number, rcx = ptr to block bytes
; out: rax = 0 success, non-zero failure
journal_tx_log_block:
	xor rax, rax
	ret

; in: rsi = tx handle
; out: rax = 0 success, non-zero failure
journal_tx_commit:
	xor rax, rax
	ret

; in: rsi = tx handle
journal_tx_abort:
	ret

; out: rax = number of replayed records
journal_replay:
	xor rax, rax
	ret
'

create_file "$CACHE_ASM" "$cache_content"
create_file "$VFS_ASM" "$vfs_content"
create_file "$EXT2_LAYOUT_INC" "$ext2_layout_content"
create_file "$EXT2_ASM" "$ext2_content"
create_file "$JOURNAL_ASM" "$journal_content"

include_cache='include "fs/cache.asm"'
include_vfs='include "fs/vfs.asm"'
include_ext2='include "fs/ext2.asm"'
include_journal='include "fs/journal.asm"'

normalize_include() { # arg 1 is include line
	local include_line="$1"
	if [[ "$DRY_RUN" -eq 1 ]]; then
		if grep -qF "$include_line" "$KERNEL_ASM"; then
			echo "Would normalize in kernel.asm: $include_line"
		else
			echo "Would insert into kernel.asm: $include_line"
		fi
		return
	fi

	local tmpfile
	tmpfile=$(mktemp)
	awk -v include_line="$include_line" '
	{
		if ($0 == include_line) next
		lines[++n]=$0
		if ($0 ~ /^bits[[:space:]]+/ && bits_line == 0) bits_line=n
	}
	END {
		if (n == 0) {
			print include_line
			exit
		}
		if (bits_line == 0) {
			print include_line
			for (i = 1; i <= n; i++) print lines[i]
			exit
		}
		for (i = 1; i <= n; i++) {
			print lines[i]
			if (i == bits_line) print include_line
		}
	}
	' "$KERNEL_ASM" > "$tmpfile"
	mv "$tmpfile" "$KERNEL_ASM"
	echo "Normalized in kernel.asm: $include_line"
}

normalize_include "$include_cache"
normalize_include "$include_vfs"
normalize_include "$include_ext2"
normalize_include "$include_journal"

echo "ext2/3 scaffold step complete"
