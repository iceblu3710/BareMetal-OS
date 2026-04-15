#include "../include/posix_layer.h"

#include <stdio.h>
#include <string.h>

int main(void)
{
    const char *path = "/tmp/bm_posix_smoke.txt";
    const char *path2 = "/tmp/bm_posix_smoke_renamed.txt";
    const char *link_path = "/tmp/bm_posix_smoke_hardlink.txt";
    const char *symlink_path = "/tmp/bm_posix_smoke_symlink.txt";
    const char *msg = "hello-posix-layer\n";
    char buf[64] = {0};
    char link_buf[128] = {0};
    int fd;
    int dupfd;
    int pfd[2];
    struct bm_stat st;
    struct bm_stat lst;
    int dirfd;

    bm_use_host_backend();

    if (bm_pipe(pfd) != 0) {
        fprintf(stderr, "bm_pipe failed: %d\n", bm_last_error());
        return 1;
    }
    if (bm_write(pfd[1], "x", 1) != 1 || bm_read(pfd[0], buf, 1) != 1 || buf[0] != 'x') {
        fprintf(stderr, "bm_pipe read/write failed: %d\n", bm_last_error());
        return 1;
    }
    (void)bm_close(pfd[0]);
    (void)bm_close(pfd[1]);

    fd = bm_open(path, BM_O_CREAT | BM_O_TRUNC | BM_O_RDWR, 0644);
    if (fd < 0) {
        fprintf(stderr, "bm_open failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_write(fd, msg, strlen(msg)) < 0) {
        fprintf(stderr, "bm_write failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_fdatasync(fd) != 0) {
        fprintf(stderr, "bm_fdatasync failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_write(fd, msg, strlen(msg)) < 0) {
        fprintf(stderr, "bm_write failed: %d\n", bm_last_error());
        return 1;
    }

    dupfd = bm_dup(fd);
    if (dupfd < 0) {
        fprintf(stderr, "bm_dup failed: %d\n", bm_last_error());
        return 1;
    }
    if (bm_close(dupfd) != 0) {
        fprintf(stderr, "bm_close(dupfd) failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_ftruncate(fd, 5) != 0) {
        fprintf(stderr, "bm_ftruncate failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_lseek(fd, 0, BM_SEEK_SET) < 0) {
        fprintf(stderr, "bm_lseek failed: %d\n", bm_last_error());
        return 1;
    }

    memset(buf, 0, sizeof(buf));
    if (bm_read(fd, buf, sizeof(buf) - 1) < 0) {
        fprintf(stderr, "bm_read failed: %d\n", bm_last_error());
        return 1;
    }

    if (strcmp(buf, "hello") != 0) {
        fprintf(stderr, "content mismatch: %s\n", buf);
        return 1;
    }

    if (bm_fstat(fd, &st) != 0 || st.size != 5) {
        fprintf(stderr, "bm_fstat failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_close(fd) != 0) {
        fprintf(stderr, "bm_close failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_access(path, BM_F_OK) != 0) {
        fprintf(stderr, "bm_access failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_rename(path, path2) != 0) {
        fprintf(stderr, "bm_rename failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_truncate(path2, 2) != 0) {
        fprintf(stderr, "bm_truncate failed: %d\n", bm_last_error());
        return 1;
    }


    if (bm_link(path2, link_path) != 0) {
        fprintf(stderr, "bm_link failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_symlink(path2, symlink_path) != 0) {
        fprintf(stderr, "bm_symlink failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_readlink(symlink_path, link_buf, sizeof(link_buf) - 1) <= 0) {
        fprintf(stderr, "bm_readlink failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_lstat(symlink_path, &lst) != 0) {
        fprintf(stderr, "bm_lstat failed: %d\n", bm_last_error());
        return 1;
    }

    dirfd = bm_open("/tmp", BM_O_RDONLY, 0);
    if (dirfd < 0 || bm_fchdir(dirfd) != 0) {
        fprintf(stderr, "bm_fchdir failed: %d\n", bm_last_error());
        return 1;
    }
    (void)bm_close(dirfd);

    if (bm_getcwd(link_buf, sizeof(link_buf)) != 0) {
        fprintf(stderr, "bm_getcwd failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_readlink(symlink_path, link_buf, sizeof(link_buf) - 1) <= 0) {
        fprintf(stderr, "bm_readlink failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_unlink(path2) != 0) {
        fprintf(stderr, "bm_unlink failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_unlink(link_path) != 0 || bm_unlink(symlink_path) != 0) {
        fprintf(stderr, "cleanup unlink failed: %d\n", bm_last_error());
        return 1;
    }

    puts("ok");
    return 0;
}
