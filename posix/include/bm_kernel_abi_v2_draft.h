#ifndef BAREMETAL_KERNEL_ABI_V2_DRAFT_H
#define BAREMETAL_KERNEL_ABI_V2_DRAFT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Draft-only identifier for proposed v2 ABI. */
#define BM_KERNEL_ABI_V2_DRAFT 0x00020000u

#define BM_DISK_NAME_MAX 32
#define BM_PART_NAME_MAX 36
#define BM_FS_LABEL_MAX  32

/* Device/partition types */
enum {
    BM_DISK_BUS_UNKNOWN = 0,
    BM_DISK_BUS_VIRTIO,
    BM_DISK_BUS_AHCI,
    BM_DISK_BUS_NVME
};

enum {
    BM_PT_NONE = 0,
    BM_PT_MBR,
    BM_PT_GPT
};

enum {
    BM_FS_NONE = 0,
    BM_FS_FAT32,
    BM_FS_EXT4,
    BM_FS_BMFS
};

/* Safety policy used by destructive calls. */
enum {
    BM_CONFIRM_NONE = 0,
    BM_CONFIRM_DEVICE_ID,
    BM_CONFIRM_EXPLICIT_FORCE
};

struct bm_disk_info {
    uint32_t disk_id;
    char name[BM_DISK_NAME_MAX];
    uint64_t total_bytes;
    uint32_t logical_sector_size;
    uint32_t physical_sector_size;
    uint8_t bus_type;
    uint8_t removable;
    uint8_t writable;
    uint8_t reserved;
};

struct bm_partition_info {
    uint32_t disk_id;
    uint32_t part_index;
    uint64_t first_lba;
    uint64_t last_lba;
    uint8_t fs_hint;
    uint8_t bootable;
    uint8_t reserved0;
    uint8_t reserved1;
    char name[BM_PART_NAME_MAX];
};

struct bm_disk_confirm {
    uint32_t policy;
    uint32_t disk_id;
    uint64_t nonce;
};

struct bm_mkfs_request {
    uint32_t disk_id;
    uint32_t part_index;
    uint8_t fs_type;
    uint8_t quick;
    uint8_t reserved0;
    uint8_t reserved1;
    char label[BM_FS_LABEL_MAX];
    struct bm_disk_confirm confirm;
};

struct bm_partition_create_request {
    uint32_t disk_id;
    uint32_t part_index;
    uint64_t first_lba;
    uint64_t last_lba;
    uint8_t fs_hint;
    uint8_t bootable;
    uint16_t reserved;
    char name[BM_PART_NAME_MAX];
    struct bm_disk_confirm confirm;
};

struct bm_kernel_abi_v2_draft {
    uint32_t abi_version;

    /* ---------- Raw disk operations ---------- */
    int (*disk_count)(void);
    int (*disk_info)(int disk_slot, struct bm_disk_info *out_info);
    int (*disk_read_lba)(uint32_t disk_id, uint64_t lba, void *buf, uint32_t sectors);
    int (*disk_write_lba)(uint32_t disk_id, uint64_t lba, const void *buf, uint32_t sectors);
    int (*disk_flush)(uint32_t disk_id);

    /* ---------- Partition table operations ---------- */
    int (*part_table_type)(uint32_t disk_id);                    /* returns BM_PT_* */
    int (*part_table_init)(uint32_t disk_id, uint8_t table_type, struct bm_disk_confirm confirm);
    int (*part_count)(uint32_t disk_id);
    int (*part_info)(uint32_t disk_id, int part_slot, struct bm_partition_info *out_info);
    int (*part_create)(const struct bm_partition_create_request *req);
    int (*part_delete)(uint32_t disk_id, uint32_t part_index, struct bm_disk_confirm confirm);

    /* ---------- Filesystem creation operations ---------- */
    int (*mkfs)(const struct bm_mkfs_request *req);

    /* ---------- Safety / identity ---------- */
    int (*disk_confirmation_nonce)(uint32_t disk_id, uint64_t *out_nonce);
};

#ifdef __cplusplus
}
#endif

#endif /* BAREMETAL_KERNEL_ABI_V2_DRAFT_H */
