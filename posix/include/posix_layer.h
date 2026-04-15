#ifndef BAREMETAL_POSIX_LAYER_H
#define BAREMETAL_POSIX_LAYER_H

#include <stddef.h>
#include <stdint.h>
#include <termios.h>

#include "bm_kernel_abi.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Compatibility flag values (kept stable for BareMetal callers). */
enum {
    BM_O_RDONLY = 0x0001,
    BM_O_WRONLY = 0x0002,
    BM_O_RDWR   = 0x0004,
    BM_O_CREAT  = 0x0010,
    BM_O_TRUNC  = 0x0020,
    BM_O_APPEND = 0x0040,
    BM_O_EXCL   = 0x0080
};

enum {
    BM_SEEK_SET = 0,
    BM_SEEK_CUR = 1,
    BM_SEEK_END = 2
};

enum {
    BM_F_OK = 0,
    BM_X_OK = 1,
    BM_W_OK = 2,
    BM_R_OK = 4
};

enum {
    BM_DIRENT_TYPE_UNKNOWN = 0,
    BM_DIRENT_TYPE_FILE,
    BM_DIRENT_TYPE_DIR
};

typedef int32_t bm_ssize_t;
typedef int64_t bm_off_t;
typedef uint32_t bm_mode_t;
typedef struct bm_dir bm_dir_t;

struct bm_stat {
    bm_off_t size;
    bm_mode_t mode;
    int is_directory;
};

struct bm_dirent {
    char name[256];
    uint8_t type;
};

struct bm_posix_backend {
    int (*open)(const char *path, int flags, bm_mode_t mode);
    int (*close)(int fd);
    bm_ssize_t (*read)(int fd, void *buf, size_t count);
    bm_ssize_t (*write)(int fd, const void *buf, size_t count);
    bm_off_t (*lseek)(int fd, bm_off_t offset, int whence);
    int (*dup)(int fd);
    int (*dup2)(int oldfd, int newfd);
    int (*pipe)(int pipefd[2]);
    int (*isatty)(int fd);
    int (*getpid)(void);
    int (*getppid)(void);
    int (*setsid)(void);
    int (*tcgetattr)(int fd, struct termios *out_attr);
    int (*tcsetattr)(int fd, int optional_actions, const struct termios *attr);
    bm_ssize_t (*pread)(int fd, void *buf, size_t count, bm_off_t offset);
    bm_ssize_t (*pwrite)(int fd, const void *buf, size_t count, bm_off_t offset);
    int (*fsync)(int fd);
    int (*fdatasync)(int fd);

    int (*access)(const char *path, int mode);
    int (*chmod)(const char *path, bm_mode_t mode);
    int (*truncate)(const char *path, bm_off_t length);
    int (*ftruncate)(int fd, bm_off_t length);

    int (*link)(const char *old_path, const char *new_path);
    int (*symlink)(const char *target, const char *linkpath);
    bm_ssize_t (*readlink)(const char *path, char *buf, size_t bufsize);

    int (*unlink)(const char *path);
    int (*rename)(const char *old_path, const char *new_path);
    int (*mkdir)(const char *path, bm_mode_t mode);
    int (*rmdir)(const char *path);

    int (*stat)(const char *path, struct bm_stat *out_stat);
    int (*lstat)(const char *path, struct bm_stat *out_stat);
    int (*fstat)(int fd, struct bm_stat *out_stat);

    int (*chdir)(const char *path);
    int (*fchdir)(int fd);
    int (*getcwd)(char *buf, size_t size);
    int (*realpath)(const char *path, char *out, size_t out_size);

    bm_dir_t *(*opendir)(const char *path);
    int (*readdir)(bm_dir_t *dir, struct bm_dirent *out_entry);
    int (*closedir)(bm_dir_t *dir);
};

/* Backend management */
int bm_set_backend(const struct bm_posix_backend *backend);
const struct bm_posix_backend *bm_get_backend(void);
void bm_use_host_backend(void);

/* Kernel ABI integration */
int bm_bind_kernel_abi_v1(const struct bm_kernel_abi_v1 *abi);
uint32_t bm_bound_kernel_abi_version(void);

/* POSIX-like wrappers */
int bm_open(const char *path, int flags, bm_mode_t mode);
int bm_close(int fd);
bm_ssize_t bm_read(int fd, void *buf, size_t count);
bm_ssize_t bm_write(int fd, const void *buf, size_t count);
bm_off_t bm_lseek(int fd, bm_off_t offset, int whence);
bm_off_t bm_lseek64(int fd, bm_off_t offset, int whence);
int bm_dup(int fd);
int bm_dup2(int oldfd, int newfd);
int bm_pipe(int pipefd[2]);
int bm_isatty(int fd);
int bm_getpid(void);
int bm_getppid(void);
int bm_setsid(void);
int bm_tcgetattr(int fd, struct termios *out_attr);
int bm_tcsetattr(int fd, int optional_actions, const struct termios *attr);
bm_ssize_t bm_pread(int fd, void *buf, size_t count, bm_off_t offset);
bm_ssize_t bm_pwrite(int fd, const void *buf, size_t count, bm_off_t offset);
int bm_fsync(int fd);
int bm_fdatasync(int fd);

int bm_access(const char *path, int mode);
int bm_chmod(const char *path, bm_mode_t mode);
int bm_truncate(const char *path, bm_off_t length);
int bm_ftruncate(int fd, bm_off_t length);

int bm_link(const char *old_path, const char *new_path);
int bm_symlink(const char *target, const char *linkpath);
bm_ssize_t bm_readlink(const char *path, char *buf, size_t bufsize);

int bm_unlink(const char *path);
int bm_rename(const char *old_path, const char *new_path);
int bm_mkdir(const char *path, bm_mode_t mode);
int bm_rmdir(const char *path);

int bm_stat(const char *path, struct bm_stat *out_stat);
int bm_lstat(const char *path, struct bm_stat *out_stat);
int bm_fstat(int fd, struct bm_stat *out_stat);

int bm_chdir(const char *path);
int bm_fchdir(int fd);
int bm_getcwd(char *buf, size_t size);
int bm_realpath(const char *path, char *out, size_t out_size);
int bm_basename_r(const char *path, char *out, size_t out_size);
int bm_dirname_r(const char *path, char *out, size_t out_size);

bm_dir_t *bm_opendir(const char *path);
int bm_readdir(bm_dir_t *dir, struct bm_dirent *out_entry);
int bm_closedir(bm_dir_t *dir);

/* Error helper */
int bm_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* BAREMETAL_POSIX_LAYER_H */
