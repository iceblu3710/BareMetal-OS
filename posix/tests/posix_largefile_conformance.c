#include "../include/posix_layer.h"

#include <stdio.h>

int main(void)
{
    const char *path = "/tmp/bm_largefile_test.bin";
    const bm_off_t target_offset = (bm_off_t)5 * 1024 * 1024 * 1024; /* 5 GiB */
    char marker = 'Z';
    struct bm_stat st;
    int fd;

    bm_use_host_backend();

    fd = bm_open(path, BM_O_CREAT | BM_O_TRUNC | BM_O_RDWR, 0644);
    if (fd < 0) {
        fprintf(stderr, "open failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_lseek64(fd, target_offset, BM_SEEK_SET) < 0) {
        fprintf(stderr, "lseek64 failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_write(fd, &marker, 1) != 1) {
        fprintf(stderr, "write marker failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_fstat(fd, &st) != 0) {
        fprintf(stderr, "fstat failed: %d\n", bm_last_error());
        return 1;
    }

    if (st.size != target_offset + 1) {
        fprintf(stderr, "unexpected file size: %lld\n", (long long)st.size);
        return 1;
    }

    if (bm_close(fd) != 0) {
        fprintf(stderr, "close failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_unlink(path) != 0) {
        fprintf(stderr, "unlink failed: %d\n", bm_last_error());
        return 1;
    }

    puts("ok");
    return 0;
}
