#include "../include/posix_layer.h"

#include <stdio.h>
#include <string.h>

static int run_selftest(void)
{
    const char *path = "/tmp/bm_client_app.txt";
    const char *msg = "baremetal-client-selftest\n";
    char buf[128] = {0};
    struct bm_stat st;
    int fd;

    bm_use_host_backend();

    fd = bm_open(path, BM_O_CREAT | BM_O_TRUNC | BM_O_RDWR, 0644);
    if (fd < 0) {
        fprintf(stderr, "open failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_write(fd, msg, strlen(msg)) < 0) {
        fprintf(stderr, "write failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_fsync(fd) != 0) {
        fprintf(stderr, "fsync failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_lseek(fd, 0, BM_SEEK_SET) < 0) {
        fprintf(stderr, "lseek failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_read(fd, buf, sizeof(buf) - 1) < 0) {
        fprintf(stderr, "read failed: %d\n", bm_last_error());
        return 1;
    }

    if (strcmp(buf, msg) != 0) {
        fprintf(stderr, "content mismatch\n");
        return 1;
    }

    if (bm_fstat(fd, &st) != 0 || st.size <= 0) {
        fprintf(stderr, "fstat failed: %d\n", bm_last_error());
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

    puts("bm-client: ok");
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 1 || (argc == 2 && strcmp(argv[1], "--selftest") == 0)) {
        return run_selftest();
    }

    fprintf(stderr, "usage: %s [--selftest]\n", argv[0]);
    return 2;
}
