#ifndef BAREMETAL_KERNEL_ABI_H
#define BAREMETAL_KERNEL_ABI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BM_KERNEL_ABI_V1 0x00010000u

typedef int32_t bm_kssize_t;
typedef int64_t bm_koff_t;
typedef uint32_t bm_kmode_t;

typedef struct bm_kdir bm_kdir_t;

struct bm_kstat {
    bm_koff_t size;
    bm_kmode_t mode;
    int is_directory;
};

struct bm_kernel_abi_v1 {
    uint32_t abi_version;

    int (*open)(const char *path, int flags, bm_kmode_t mode);
    int (*close)(int fd);
    bm_kssize_t (*read)(int fd, void *buf, size_t count);
    bm_kssize_t (*write)(int fd, const void *buf, size_t count);
    bm_koff_t (*lseek)(int fd, bm_koff_t offset, int whence);
    int (*dup)(int fd);
    int (*dup2)(int oldfd, int newfd);
    int (*pipe)(int pipefd[2]);
    int (*isatty)(int fd);
    int (*getpid)(void);
    int (*getppid)(void);
    int (*setsid)(void);
    int (*tcgetattr)(int fd, void *out_termios, size_t termios_size);
    int (*tcsetattr)(int fd, int optional_actions, const void *termios, size_t termios_size);
    int (*fsync)(int fd);
    int (*fdatasync)(int fd);

    int (*access)(const char *path, int mode);
    int (*chmod)(const char *path, bm_kmode_t mode);
    int (*truncate)(const char *path, bm_koff_t length);
    int (*ftruncate)(int fd, bm_koff_t length);

    int (*link)(const char *old_path, const char *new_path);
    int (*symlink)(const char *target, const char *linkpath);
    bm_kssize_t (*readlink)(const char *path, char *buf, size_t bufsize);

    int (*unlink)(const char *path);
    int (*rename)(const char *old_path, const char *new_path);
    int (*mkdir)(const char *path, bm_kmode_t mode);
    int (*rmdir)(const char *path);

    int (*stat)(const char *path, struct bm_kstat *out_stat);
    int (*lstat)(const char *path, struct bm_kstat *out_stat);
    int (*fstat)(int fd, struct bm_kstat *out_stat);

    int (*chdir)(const char *path);
    int (*fchdir)(int fd);
    int (*getcwd)(char *buf, size_t size);
    int (*realpath)(const char *path, char *out, size_t out_size);

    bm_kdir_t *(*opendir)(const char *path);
    int (*readdir)(bm_kdir_t *dir, char *name_buf, size_t name_buf_size, uint8_t *type_out);
    int (*closedir)(bm_kdir_t *dir);
};

#ifdef __cplusplus
}
#endif

#endif /* BAREMETAL_KERNEL_ABI_H */
