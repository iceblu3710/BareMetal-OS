#include "../include/bm_kernel_abi_v2_draft.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct bm_kernel_abi_v2_draft *g_abi;

/* --------------------------- Mock backend for phase work --------------------------- */
static struct bm_disk_info g_disks[] = {
    { .disk_id = 1, .name = "virtio0", .total_bytes = 64ULL * 1024 * 1024 * 1024, .logical_sector_size = 512, .physical_sector_size = 4096, .bus_type = BM_DISK_BUS_VIRTIO, .removable = 0, .writable = 1 },
    { .disk_id = 2, .name = "nvme0",   .total_bytes = 128ULL * 1024 * 1024 * 1024, .logical_sector_size = 512, .physical_sector_size = 4096, .bus_type = BM_DISK_BUS_NVME, .removable = 0, .writable = 1 }
};

static struct bm_partition_info g_parts[] = {
    { .disk_id = 1, .part_index = 1, .first_lba = 2048, .last_lba = 1050623, .fs_hint = BM_FS_FAT32, .bootable = 1, .name = "EFI" },
    { .disk_id = 1, .part_index = 2, .first_lba = 1050624, .last_lba = 8388607, .fs_hint = BM_FS_EXT4, .bootable = 0, .name = "DATA" }
};

static int mock_disk_count(void) { return (int)(sizeof(g_disks) / sizeof(g_disks[0])); }
static int mock_disk_info(int disk_slot, struct bm_disk_info *out_info)
{
    if (out_info == NULL || disk_slot < 0 || disk_slot >= mock_disk_count()) {
        return -1;
    }
    *out_info = g_disks[disk_slot];
    return 0;
}
static int mock_disk_read_lba(uint32_t disk_id, uint64_t lba, void *buf, uint32_t sectors) { (void)disk_id; (void)lba; (void)buf; (void)sectors; return 0; }
static int mock_disk_write_lba(uint32_t disk_id, uint64_t lba, const void *buf, uint32_t sectors) { (void)disk_id; (void)lba; (void)buf; (void)sectors; return 0; }
static int mock_disk_flush(uint32_t disk_id) { (void)disk_id; return 0; }

static int mock_part_table_type(uint32_t disk_id) { return disk_id == 1 ? BM_PT_GPT : BM_PT_MBR; }
static int mock_part_table_init(uint32_t disk_id, uint8_t table_type, struct bm_disk_confirm confirm)
{ (void)disk_id; (void)table_type; return confirm.nonce == 42 ? 0 : -1; }
static int mock_part_count(uint32_t disk_id) { return disk_id == 1 ? 2 : 0; }
static int mock_part_info(uint32_t disk_id, int part_slot, struct bm_partition_info *out_info)
{
    if (out_info == NULL || disk_id != 1 || part_slot < 0 || part_slot >= 2) {
        return -1;
    }
    *out_info = g_parts[part_slot];
    return 0;
}
static int mock_part_create(const struct bm_partition_create_request *req)
{ return (req != NULL && req->confirm.nonce == 42) ? 0 : -1; }
static int mock_part_delete(uint32_t disk_id, uint32_t part_index, struct bm_disk_confirm confirm)
{ (void)disk_id; (void)part_index; return confirm.nonce == 42 ? 0 : -1; }
static int mock_mkfs(const struct bm_mkfs_request *req) { (void)req; return 0; }
static int mock_disk_confirmation_nonce(uint32_t disk_id, uint64_t *out_nonce)
{ if (out_nonce == NULL) return -1; *out_nonce = (disk_id == 1 || disk_id == 2) ? 42 : 0; return *out_nonce ? 0 : -1; }

static struct bm_kernel_abi_v2_draft g_mock_abi = {
    .abi_version = BM_KERNEL_ABI_V2_DRAFT,
    .disk_count = mock_disk_count,
    .disk_info = mock_disk_info,
    .disk_read_lba = mock_disk_read_lba,
    .disk_write_lba = mock_disk_write_lba,
    .disk_flush = mock_disk_flush,
    .part_table_type = mock_part_table_type,
    .part_table_init = mock_part_table_init,
    .part_count = mock_part_count,
    .part_info = mock_part_info,
    .part_create = mock_part_create,
    .part_delete = mock_part_delete,
    .mkfs = mock_mkfs,
    .disk_confirmation_nonce = mock_disk_confirmation_nonce
};

static void print_usage(void)
{
    puts("diskctl list");
    puts("diskctl info <disk-slot>");
    puts("diskctl part-list <disk-id>");
    puts("diskctl part-init <disk-id> <gpt|mbr> <nonce>");
    puts("diskctl part-create <disk-id> <index> <start-lba> <end-lba> <nonce>");
    puts("diskctl part-delete <disk-id> <index> <nonce>");
}

int main(int argc, char **argv)
{
    g_abi = &g_mock_abi;

    if (argc < 2) {
        print_usage();
        return 1;
    }

    if (strcmp(argv[1], "list") == 0) {
        int i;
        for (i = 0; i < g_abi->disk_count(); i++) {
            struct bm_disk_info d;
            if (g_abi->disk_info(i, &d) != 0) return 1;
            printf("disk_id=%u name=%s size=%llu\n", d.disk_id, d.name, (unsigned long long)d.total_bytes);
        }
        return 0;
    }

    if (strcmp(argv[1], "info") == 0 && argc == 3) {
        struct bm_disk_info d;
        int slot = atoi(argv[2]);
        if (g_abi->disk_info(slot, &d) != 0) return 1;
        printf("disk_id=%u bus=%u logical=%u physical=%u writable=%u\n", d.disk_id, d.bus_type, d.logical_sector_size, d.physical_sector_size, d.writable);
        return 0;
    }

    if (strcmp(argv[1], "part-list") == 0 && argc == 3) {
        int i;
        uint32_t disk_id = (uint32_t)strtoul(argv[2], NULL, 10);
        int count = g_abi->part_count(disk_id);
        for (i = 0; i < count; i++) {
            struct bm_partition_info p;
            if (g_abi->part_info(disk_id, i, &p) != 0) return 1;
            printf("part=%u start=%llu end=%llu name=%s\n", p.part_index, (unsigned long long)p.first_lba, (unsigned long long)p.last_lba, p.name);
        }
        return 0;
    }

    if (strcmp(argv[1], "part-init") == 0 && argc == 5) {
        struct bm_disk_confirm c;
        uint8_t type;
        c.policy = BM_CONFIRM_DEVICE_ID;
        c.disk_id = (uint32_t)strtoul(argv[2], NULL, 10);
        c.nonce = strtoull(argv[4], NULL, 10);
        type = (strcmp(argv[3], "gpt") == 0) ? BM_PT_GPT : BM_PT_MBR;
        return g_abi->part_table_init(c.disk_id, type, c);
    }

    if (strcmp(argv[1], "part-create") == 0 && argc == 7) {
        struct bm_partition_create_request r;
        memset(&r, 0, sizeof(r));
        r.disk_id = (uint32_t)strtoul(argv[2], NULL, 10);
        r.part_index = (uint32_t)strtoul(argv[3], NULL, 10);
        r.first_lba = strtoull(argv[4], NULL, 10);
        r.last_lba = strtoull(argv[5], NULL, 10);
        r.confirm.policy = BM_CONFIRM_DEVICE_ID;
        r.confirm.disk_id = r.disk_id;
        r.confirm.nonce = strtoull(argv[6], NULL, 10);
        return g_abi->part_create(&r);
    }

    if (strcmp(argv[1], "part-delete") == 0 && argc == 5) {
        struct bm_disk_confirm c;
        uint32_t disk_id = (uint32_t)strtoul(argv[2], NULL, 10);
        uint32_t index = (uint32_t)strtoul(argv[3], NULL, 10);
        c.policy = BM_CONFIRM_DEVICE_ID;
        c.disk_id = disk_id;
        c.nonce = strtoull(argv[4], NULL, 10);
        return g_abi->part_delete(disk_id, index, c);
    }

    print_usage();
    return 1;
}
