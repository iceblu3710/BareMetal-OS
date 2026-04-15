#include "../include/posix_layer.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

static int expect_error(int expected, const char *label)
{
    int got = bm_last_error();
    if (got != expected) {
        fprintf(stderr, "%s: expected error %d, got %d\n", label, expected, got);
        return 1;
    }
    return 0;
}

int main(void)
{
    const char *target = "/tmp/bm_edge_target.txt";
    const char *sym = "/tmp/bm_edge_target.lnk";
    char buf[32] = {0};
    struct bm_stat st;
    struct bm_dirent ent;
    bm_dir_t *dir;
    int fd;
    int rc;

    bm_use_host_backend();

    /* invalid fd handling */
    rc = (int)bm_read(-1, buf, sizeof(buf));
    if (rc != -1 || expect_error(EBADF, "invalid-fd-read") != 0) {
        return 1;
    }

    /* short read semantics */
    fd = bm_open(target, BM_O_CREAT | BM_O_TRUNC | BM_O_RDWR, 0644);
    if (fd < 0) {
        fprintf(stderr, "open failed: %d\n", bm_last_error());
        return 1;
    }
    if (bm_write(fd, "abc", 3) != 3) {
        fprintf(stderr, "write failed: %d\n", bm_last_error());
        return 1;
    }
    if (bm_lseek(fd, 0, BM_SEEK_SET) < 0) {
        fprintf(stderr, "lseek failed: %d\n", bm_last_error());
        return 1;
    }
    memset(buf, 0, sizeof(buf));
    if (bm_read(fd, buf, sizeof(buf)) != 3) {
        fprintf(stderr, "short-read contract failed\n");
        return 1;
    }
    if (bm_close(fd) != 0) {
        fprintf(stderr, "close failed: %d\n", bm_last_error());
        return 1;
    }

    /* symlink+lstat edge */
    (void)bm_unlink(sym);
    if (bm_symlink(target, sym) != 0) {
        fprintf(stderr, "symlink failed: %d\n", bm_last_error());
        return 1;
    }
    if (bm_lstat(sym, &st) != 0) {
        fprintf(stderr, "lstat failed: %d\n", bm_last_error());
        return 1;
    }

    /* directory iteration end vs error */
    dir = bm_opendir("/tmp");
    if (dir == NULL) {
        fprintf(stderr, "opendir failed: %d\n", bm_last_error());
        return 1;
    }
    do {
        rc = bm_readdir(dir, &ent);
    } while (rc == 0);
    if (rc != 1) {
        fprintf(stderr, "readdir should end with 1, got %d\n", rc);
        return 1;
    }
    if (bm_closedir(dir) != 0) {
        fprintf(stderr, "closedir failed: %d\n", bm_last_error());
        return 1;
    }
    if (bm_readdir(NULL, &ent) != -1 || expect_error(EINVAL, "readdir-null") != 0) {
        return 1;
    }

    (void)bm_unlink(sym);
    (void)bm_unlink(target);

    puts("ok");
    return 0;
}
