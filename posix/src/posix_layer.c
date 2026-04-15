#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L

#include "../include/posix_layer.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

struct bm_dir {
    DIR *native;
};

struct bm_kdir {
    bm_dir_t *wrapped;
};

static int g_bm_last_error;
static const struct bm_posix_backend *g_backend;
static const struct bm_kernel_abi_v1 *g_kernel_abi;

static int bm_set_error(int error_code)
{
    g_bm_last_error = error_code;
    return -1;
}

static int bm_set_error_from_errno(void)
{
    return bm_set_error(errno);
}

static bm_ssize_t bm_set_rw_error_from_errno(void)
{
    g_bm_last_error = errno;
    return (bm_ssize_t)-1;
}

static bm_off_t bm_set_seek_error_from_errno(void)
{
    g_bm_last_error = errno;
    return (bm_off_t)-1;
}

static int bm_validate_pointer(const void *ptr)
{
    if (ptr == NULL) {
        return bm_set_error(EINVAL);
    }

    return 0;
}

static int bm_to_host_open_flags(int bm_flags)
{
    int host_flags = 0;
    const int access = bm_flags & (BM_O_RDONLY | BM_O_WRONLY | BM_O_RDWR);

    if (access == BM_O_WRONLY) {
        host_flags |= O_WRONLY;
    } else if (access == BM_O_RDWR) {
        host_flags |= O_RDWR;
    } else {
        host_flags |= O_RDONLY;
    }

    if ((bm_flags & BM_O_CREAT) != 0) {
        host_flags |= O_CREAT;
    }
    if ((bm_flags & BM_O_TRUNC) != 0) {
        host_flags |= O_TRUNC;
    }
    if ((bm_flags & BM_O_APPEND) != 0) {
        host_flags |= O_APPEND;
    }
    if ((bm_flags & BM_O_EXCL) != 0) {
        host_flags |= O_EXCL;
    }

    return host_flags;
}

static int bm_to_host_seek_whence(int whence)
{
    switch (whence) {
    case BM_SEEK_SET:
        return SEEK_SET;
    case BM_SEEK_CUR:
        return SEEK_CUR;
    case BM_SEEK_END:
        return SEEK_END;
    default:
        (void)bm_set_error(EINVAL);
        return -1;
    }
}

static int bm_to_host_access_mode(int mode)
{
    int host_mode = 0;

    if (mode == BM_F_OK) {
        return F_OK;
    }
    if ((mode & BM_R_OK) != 0) {
        host_mode |= R_OK;
    }
    if ((mode & BM_W_OK) != 0) {
        host_mode |= W_OK;
    }
    if ((mode & BM_X_OK) != 0) {
        host_mode |= X_OK;
    }

    return host_mode;
}

static void bm_fill_stat(struct bm_stat *dst, const struct stat *src)
{
    dst->size = (bm_off_t)src->st_size;
    dst->mode = (bm_mode_t)src->st_mode;
    dst->is_directory = S_ISDIR(src->st_mode) ? 1 : 0;
}

/* -------------------------- Host backend implementation ------------------------- */

static int host_open(const char *path, int flags, bm_mode_t mode)
{
    int fd;

    if (bm_validate_pointer(path) != 0) {
        return -1;
    }

    fd = open(path, bm_to_host_open_flags(flags), (mode_t)mode);
    if (fd < 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return fd;
}

static int host_close(int fd)
{
    if (close(fd) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static bm_ssize_t host_read(int fd, void *buf, size_t count)
{
    ssize_t result;

    if (count > 0 && bm_validate_pointer(buf) != 0) {
        return (bm_ssize_t)-1;
    }

    result = read(fd, buf, count);
    if (result < 0) {
        return bm_set_rw_error_from_errno();
    }

    g_bm_last_error = 0;
    return (bm_ssize_t)result;
}

static bm_ssize_t host_write(int fd, const void *buf, size_t count)
{
    ssize_t result;

    if (count > 0 && bm_validate_pointer(buf) != 0) {
        return (bm_ssize_t)-1;
    }

    result = write(fd, buf, count);
    if (result < 0) {
        return bm_set_rw_error_from_errno();
    }

    g_bm_last_error = 0;
    return (bm_ssize_t)result;
}

static bm_off_t host_lseek(int fd, bm_off_t offset, int whence)
{
    off_t result;
    int native_whence = bm_to_host_seek_whence(whence);
    if (native_whence < 0) {
        return (bm_off_t)-1;
    }

    result = lseek(fd, (off_t)offset, native_whence);
    if (result < 0) {
        return bm_set_seek_error_from_errno();
    }

    g_bm_last_error = 0;
    return (bm_off_t)result;
}

static int host_dup(int fd)
{
    int out = dup(fd);
    if (out < 0) {
        return bm_set_error_from_errno();
    }
    g_bm_last_error = 0;
    return out;
}

static int host_dup2(int oldfd, int newfd)
{
    int out = dup2(oldfd, newfd);
    if (out < 0) {
        return bm_set_error_from_errno();
    }
    g_bm_last_error = 0;
    return out;
}

static int host_pipe(int pipefd[2])
{
    if (bm_validate_pointer(pipefd) != 0) {
        return -1;
    }

    if (pipe(pipefd) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_isatty(int fd)
{
    int rc = isatty(fd);
    if (rc == 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 1;
}

static int host_getpid(void)
{
    g_bm_last_error = 0;
    return (int)getpid();
}

static int host_getppid(void)
{
    g_bm_last_error = 0;
    return (int)getppid();
}

static int host_setsid(void)
{
    int sid = (int)setsid();
    if (sid < 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return sid;
}

static int host_tcgetattr(int fd, struct termios *out_attr)
{
    if (bm_validate_pointer(out_attr) != 0) {
        return -1;
    }

    if (tcgetattr(fd, out_attr) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_tcsetattr(int fd, int optional_actions, const struct termios *attr)
{
    if (bm_validate_pointer(attr) != 0) {
        return -1;
    }

    if (tcsetattr(fd, optional_actions, attr) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static bm_ssize_t host_pread(int fd, void *buf, size_t count, bm_off_t offset)
{
    ssize_t result;

    if (count > 0 && bm_validate_pointer(buf) != 0) {
        return (bm_ssize_t)-1;
    }

    result = pread(fd, buf, count, (off_t)offset);
    if (result < 0) {
        return bm_set_rw_error_from_errno();
    }

    g_bm_last_error = 0;
    return (bm_ssize_t)result;
}

static bm_ssize_t host_pwrite(int fd, const void *buf, size_t count, bm_off_t offset)
{
    ssize_t result;

    if (count > 0 && bm_validate_pointer(buf) != 0) {
        return (bm_ssize_t)-1;
    }

    result = pwrite(fd, buf, count, (off_t)offset);
    if (result < 0) {
        return bm_set_rw_error_from_errno();
    }

    g_bm_last_error = 0;
    return (bm_ssize_t)result;
}

static int host_fsync(int fd)
{
    if (fsync(fd) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_fdatasync(int fd)
{
    if (fdatasync(fd) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_access(const char *path, int mode)
{
    if (bm_validate_pointer(path) != 0) {
        return -1;
    }

    if (access(path, bm_to_host_access_mode(mode)) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_chmod(const char *path, bm_mode_t mode)
{
    if (bm_validate_pointer(path) != 0) {
        return -1;
    }

    if (chmod(path, (mode_t)mode) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_truncate(const char *path, bm_off_t length)
{
    if (bm_validate_pointer(path) != 0) {
        return -1;
    }

    if (truncate(path, (off_t)length) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_ftruncate(int fd, bm_off_t length)
{
    if (ftruncate(fd, (off_t)length) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}


static int host_link(const char *old_path, const char *new_path)
{
    if (bm_validate_pointer(old_path) != 0 || bm_validate_pointer(new_path) != 0) {
        return -1;
    }

    if (link(old_path, new_path) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_symlink(const char *target, const char *linkpath)
{
    if (bm_validate_pointer(target) != 0 || bm_validate_pointer(linkpath) != 0) {
        return -1;
    }

    if (symlink(target, linkpath) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static bm_ssize_t host_readlink(const char *path, char *buf, size_t bufsize)
{
    ssize_t rc;

    if (bm_validate_pointer(path) != 0 || (bufsize > 0 && bm_validate_pointer(buf) != 0)) {
        return (bm_ssize_t)-1;
    }

    rc = readlink(path, buf, bufsize);
    if (rc < 0) {
        return bm_set_rw_error_from_errno();
    }

    g_bm_last_error = 0;
    return (bm_ssize_t)rc;
}

static int host_unlink(const char *path)
{
    if (bm_validate_pointer(path) != 0) {
        return -1;
    }

    if (unlink(path) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_rename(const char *old_path, const char *new_path)
{
    if (bm_validate_pointer(old_path) != 0 || bm_validate_pointer(new_path) != 0) {
        return -1;
    }

    if (rename(old_path, new_path) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_mkdir(const char *path, bm_mode_t mode)
{
    if (bm_validate_pointer(path) != 0) {
        return -1;
    }

    if (mkdir(path, (mode_t)mode) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_rmdir(const char *path)
{
    if (bm_validate_pointer(path) != 0) {
        return -1;
    }

    if (rmdir(path) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_stat(const char *path, struct bm_stat *out_stat)
{
    struct stat native;

    if (bm_validate_pointer(path) != 0 || bm_validate_pointer(out_stat) != 0) {
        return -1;
    }

    if (stat(path, &native) != 0) {
        return bm_set_error_from_errno();
    }

    bm_fill_stat(out_stat, &native);
    g_bm_last_error = 0;
    return 0;
}

static int host_lstat(const char *path, struct bm_stat *out_stat)
{
    struct stat native;

    if (bm_validate_pointer(path) != 0 || bm_validate_pointer(out_stat) != 0) {
        return -1;
    }

    if (lstat(path, &native) != 0) {
        return bm_set_error_from_errno();
    }

    bm_fill_stat(out_stat, &native);
    g_bm_last_error = 0;
    return 0;
}

static int host_fstat(int fd, struct bm_stat *out_stat)
{
    struct stat native;

    if (bm_validate_pointer(out_stat) != 0) {
        return -1;
    }

    if (fstat(fd, &native) != 0) {
        return bm_set_error_from_errno();
    }

    bm_fill_stat(out_stat, &native);
    g_bm_last_error = 0;
    return 0;
}

static int host_chdir(const char *path)
{
    if (bm_validate_pointer(path) != 0) {
        return -1;
    }

    if (chdir(path) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_fchdir(int fd)
{
    if (fchdir(fd) != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_getcwd(char *buf, size_t size)
{
    if (bm_validate_pointer(buf) != 0 || size == 0) {
        return bm_set_error(EINVAL);
    }

    if (getcwd(buf, size) == NULL) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static int host_realpath(const char *path, char *out, size_t out_size)
{
    char resolved[PATH_MAX];

    if (bm_validate_pointer(path) != 0 || bm_validate_pointer(out) != 0 || out_size == 0) {
        return bm_set_error(EINVAL);
    }

    if (realpath(path, resolved) == NULL) {
        return bm_set_error_from_errno();
    }

    if (strlen(resolved) + 1 > out_size) {
        return bm_set_error(ENAMETOOLONG);
    }

    (void)strncpy(out, resolved, out_size - 1);
    out[out_size - 1] = '\0';
    g_bm_last_error = 0;
    return 0;
}

static bm_dir_t *host_opendir(const char *path)
{
    DIR *native;
    bm_dir_t *dir;

    if (bm_validate_pointer(path) != 0) {
        return NULL;
    }

    native = opendir(path);
    if (native == NULL) {
        (void)bm_set_error_from_errno();
        return NULL;
    }

    dir = (bm_dir_t *)malloc(sizeof(*dir));
    if (dir == NULL) {
        int save_errno = errno;
        (void)closedir(native);
        (void)bm_set_error(save_errno == 0 ? ENOMEM : save_errno);
        return NULL;
    }

    dir->native = native;
    g_bm_last_error = 0;
    return dir;
}

static int host_readdir(bm_dir_t *dir, struct bm_dirent *out_entry)
{
    struct dirent *entry;

    if (bm_validate_pointer(dir) != 0 || bm_validate_pointer(out_entry) != 0) {
        return -1;
    }

    errno = 0;
    entry = readdir(dir->native);
    if (entry == NULL) {
        if (errno != 0) {
            return bm_set_error_from_errno();
        }

        g_bm_last_error = 0;
        return 1;
    }

    memset(out_entry, 0, sizeof(*out_entry));
    (void)strncpy(out_entry->name, entry->d_name, sizeof(out_entry->name) - 1);

#if defined(DT_REG)
    if (entry->d_type == DT_REG) {
        out_entry->type = BM_DIRENT_TYPE_FILE;
    } else if (entry->d_type == DT_DIR) {
        out_entry->type = BM_DIRENT_TYPE_DIR;
    } else {
        out_entry->type = BM_DIRENT_TYPE_UNKNOWN;
    }
#else
    out_entry->type = BM_DIRENT_TYPE_UNKNOWN;
#endif

    g_bm_last_error = 0;
    return 0;
}

static int host_closedir(bm_dir_t *dir)
{
    int rc;

    if (bm_validate_pointer(dir) != 0) {
        return -1;
    }

    rc = closedir(dir->native);
    free(dir);

    if (rc != 0) {
        return bm_set_error_from_errno();
    }

    g_bm_last_error = 0;
    return 0;
}

static const struct bm_posix_backend g_host_backend = {
    .open = host_open,
    .close = host_close,
    .read = host_read,
    .write = host_write,
    .lseek = host_lseek,
    .dup = host_dup,
    .dup2 = host_dup2,
    .pipe = host_pipe,
    .isatty = host_isatty,
    .getpid = host_getpid,
    .getppid = host_getppid,
    .setsid = host_setsid,
    .tcgetattr = host_tcgetattr,
    .tcsetattr = host_tcsetattr,
    .pread = host_pread,
    .pwrite = host_pwrite,
    .fsync = host_fsync,
    .fdatasync = host_fdatasync,
    .access = host_access,
    .chmod = host_chmod,
    .truncate = host_truncate,
    .ftruncate = host_ftruncate,
    .link = host_link,
    .symlink = host_symlink,
    .readlink = host_readlink,
    .unlink = host_unlink,
    .rename = host_rename,
    .mkdir = host_mkdir,
    .rmdir = host_rmdir,
    .stat = host_stat,
    .lstat = host_lstat,
    .fstat = host_fstat,
    .chdir = host_chdir,
    .fchdir = host_fchdir,
    .getcwd = host_getcwd,
    .realpath = host_realpath,
    .opendir = host_opendir,
    .readdir = host_readdir,
    .closedir = host_closedir
};

/* ----------------------------- Kernel ABI adapter ------------------------------ */

static int k_open(const char *path, int flags, bm_mode_t mode) { return g_kernel_abi->open(path, flags, (bm_kmode_t)mode); }
static int k_close(int fd) { return g_kernel_abi->close(fd); }
static bm_ssize_t k_read(int fd, void *buf, size_t count) { return (bm_ssize_t)g_kernel_abi->read(fd, buf, count); }
static bm_ssize_t k_write(int fd, const void *buf, size_t count) { return (bm_ssize_t)g_kernel_abi->write(fd, buf, count); }
static bm_off_t k_lseek(int fd, bm_off_t offset, int whence) { return (bm_off_t)g_kernel_abi->lseek(fd, (bm_koff_t)offset, whence); }
static int k_dup(int fd) { return g_kernel_abi->dup(fd); }
static int k_dup2(int oldfd, int newfd) { return g_kernel_abi->dup2(oldfd, newfd); }
static int k_pipe(int pipefd[2]) { return g_kernel_abi->pipe(pipefd); }
static int k_isatty(int fd) { return g_kernel_abi->isatty(fd); }
static int k_getpid(void) { return g_kernel_abi->getpid(); }
static int k_getppid(void) { return g_kernel_abi->getppid(); }
static int k_setsid(void) { return g_kernel_abi->setsid(); }
static int k_tcgetattr(int fd, struct termios *out_attr) { return g_kernel_abi->tcgetattr(fd, out_attr, sizeof(*out_attr)); }
static int k_tcsetattr(int fd, int optional_actions, const struct termios *attr) { return g_kernel_abi->tcsetattr(fd, optional_actions, attr, sizeof(*attr)); }

static bm_ssize_t k_pread(int fd, void *buf, size_t count, bm_off_t offset)
{
    bm_off_t original = k_lseek(fd, 0, BM_SEEK_CUR);
    bm_ssize_t rc;

    if (original < 0) {
        return (bm_ssize_t)-1;
    }

    if (k_lseek(fd, offset, BM_SEEK_SET) < 0) {
        return (bm_ssize_t)-1;
    }

    rc = k_read(fd, buf, count);
    (void)k_lseek(fd, original, BM_SEEK_SET);
    return rc;
}

static bm_ssize_t k_pwrite(int fd, const void *buf, size_t count, bm_off_t offset)
{
    bm_off_t original = k_lseek(fd, 0, BM_SEEK_CUR);
    bm_ssize_t rc;

    if (original < 0) {
        return (bm_ssize_t)-1;
    }

    if (k_lseek(fd, offset, BM_SEEK_SET) < 0) {
        return (bm_ssize_t)-1;
    }

    rc = k_write(fd, buf, count);
    (void)k_lseek(fd, original, BM_SEEK_SET);
    return rc;
}

static int k_fsync(int fd) { return g_kernel_abi->fsync(fd); }
static int k_fdatasync(int fd) { return g_kernel_abi->fdatasync(fd); }
static int k_access(const char *path, int mode) { return g_kernel_abi->access(path, mode); }
static int k_chmod(const char *path, bm_mode_t mode) { return g_kernel_abi->chmod(path, (bm_kmode_t)mode); }
static int k_truncate(const char *path, bm_off_t length) { return g_kernel_abi->truncate(path, (bm_koff_t)length); }
static int k_ftruncate(int fd, bm_off_t length) { return g_kernel_abi->ftruncate(fd, (bm_koff_t)length); }

static int k_link(const char *old_path, const char *new_path) { return g_kernel_abi->link(old_path, new_path); }
static int k_symlink(const char *target, const char *linkpath) { return g_kernel_abi->symlink(target, linkpath); }
static bm_ssize_t k_readlink(const char *path, char *buf, size_t bufsize) { return (bm_ssize_t)g_kernel_abi->readlink(path, buf, bufsize); }
static int k_unlink(const char *path) { return g_kernel_abi->unlink(path); }
static int k_rename(const char *old_path, const char *new_path) { return g_kernel_abi->rename(old_path, new_path); }
static int k_mkdir(const char *path, bm_mode_t mode) { return g_kernel_abi->mkdir(path, (bm_kmode_t)mode); }
static int k_rmdir(const char *path) { return g_kernel_abi->rmdir(path); }

static int k_stat(const char *path, struct bm_stat *out_stat)
{
    struct bm_kstat ks;
    int rc = g_kernel_abi->stat(path, &ks);
    if (rc == 0) {
        out_stat->size = (bm_off_t)ks.size;
        out_stat->mode = (bm_mode_t)ks.mode;
        out_stat->is_directory = ks.is_directory;
    }
    return rc;
}

static int k_lstat(const char *path, struct bm_stat *out_stat)
{
    struct bm_kstat ks;
    int rc = g_kernel_abi->lstat(path, &ks);
    if (rc == 0) {
        out_stat->size = (bm_off_t)ks.size;
        out_stat->mode = (bm_mode_t)ks.mode;
        out_stat->is_directory = ks.is_directory;
    }
    return rc;
}

static int k_fstat(int fd, struct bm_stat *out_stat)
{
    struct bm_kstat ks;
    int rc = g_kernel_abi->fstat(fd, &ks);
    if (rc == 0) {
        out_stat->size = (bm_off_t)ks.size;
        out_stat->mode = (bm_mode_t)ks.mode;
        out_stat->is_directory = ks.is_directory;
    }
    return rc;
}

static int k_chdir(const char *path) { return g_kernel_abi->chdir(path); }
static int k_fchdir(int fd) { return g_kernel_abi->fchdir(fd); }
static int k_getcwd(char *buf, size_t size) { return g_kernel_abi->getcwd(buf, size); }
static int k_realpath(const char *path, char *out, size_t out_size) { return g_kernel_abi->realpath(path, out, out_size); }

static bm_dir_t *k_opendir(const char *path)
{
    struct bm_kdir *kdir = (struct bm_kdir *)malloc(sizeof(*kdir));
    if (kdir == NULL) {
        (void)bm_set_error(ENOMEM);
        return NULL;
    }

    kdir->wrapped = (bm_dir_t *)g_kernel_abi->opendir(path);
    if (kdir->wrapped == NULL) {
        free(kdir);
        return NULL;
    }

    return (bm_dir_t *)kdir;
}

static int k_readdir(bm_dir_t *dir, struct bm_dirent *out_entry)
{
    struct bm_kdir *kdir = (struct bm_kdir *)dir;
    uint8_t type = BM_DIRENT_TYPE_UNKNOWN;
    int rc;

    if (bm_validate_pointer(kdir) != 0 || bm_validate_pointer(out_entry) != 0) {
        return -1;
    }

    memset(out_entry, 0, sizeof(*out_entry));
    rc = g_kernel_abi->readdir((bm_kdir_t *)kdir->wrapped, out_entry->name, sizeof(out_entry->name), &type);
    if (rc == 0) {
        out_entry->type = type;
    }
    return rc;
}

static int k_closedir(bm_dir_t *dir)
{
    struct bm_kdir *kdir = (struct bm_kdir *)dir;
    int rc;

    if (bm_validate_pointer(kdir) != 0) {
        return -1;
    }

    rc = g_kernel_abi->closedir((bm_kdir_t *)kdir->wrapped);
    free(kdir);
    return rc;
}

static const struct bm_posix_backend g_kernel_adapter_backend = {
    .open = k_open,
    .close = k_close,
    .read = k_read,
    .write = k_write,
    .lseek = k_lseek,
    .dup = k_dup,
    .dup2 = k_dup2,
    .pipe = k_pipe,
    .isatty = k_isatty,
    .getpid = k_getpid,
    .getppid = k_getppid,
    .setsid = k_setsid,
    .tcgetattr = k_tcgetattr,
    .tcsetattr = k_tcsetattr,
    .pread = k_pread,
    .pwrite = k_pwrite,
    .fsync = k_fsync,
    .fdatasync = k_fdatasync,
    .access = k_access,
    .chmod = k_chmod,
    .truncate = k_truncate,
    .ftruncate = k_ftruncate,
    .link = k_link,
    .symlink = k_symlink,
    .readlink = k_readlink,
    .unlink = k_unlink,
    .rename = k_rename,
    .mkdir = k_mkdir,
    .rmdir = k_rmdir,
    .stat = k_stat,
    .lstat = k_lstat,
    .fstat = k_fstat,
    .chdir = k_chdir,
    .fchdir = k_fchdir,
    .getcwd = k_getcwd,
    .realpath = k_realpath,
    .opendir = k_opendir,
    .readdir = k_readdir,
    .closedir = k_closedir
};

/* ------------------------------- Public API -------------------------------- */

static int bm_validate_backend(const struct bm_posix_backend *backend)
{
    if (backend == NULL) {
        return bm_set_error(EINVAL);
    }

    if (backend->open == NULL || backend->close == NULL ||
        backend->read == NULL || backend->write == NULL ||
        backend->lseek == NULL || backend->dup == NULL ||
        backend->dup2 == NULL || backend->pipe == NULL || backend->isatty == NULL ||
        backend->getpid == NULL || backend->getppid == NULL || backend->setsid == NULL ||
        backend->tcgetattr == NULL || backend->tcsetattr == NULL ||
        backend->pread == NULL || backend->pwrite == NULL ||
        backend->fsync == NULL || backend->fdatasync == NULL || backend->access == NULL || backend->chmod == NULL ||
        backend->truncate == NULL || backend->ftruncate == NULL ||
        backend->link == NULL || backend->symlink == NULL || backend->readlink == NULL ||
        backend->unlink == NULL || backend->rename == NULL ||
        backend->mkdir == NULL || backend->rmdir == NULL ||
        backend->stat == NULL || backend->lstat == NULL || backend->fstat == NULL ||
        backend->chdir == NULL || backend->fchdir == NULL || backend->getcwd == NULL ||
        backend->realpath == NULL ||
        backend->opendir == NULL || backend->readdir == NULL ||
        backend->closedir == NULL) {
        return bm_set_error(EINVAL);
    }

    return 0;
}

int bm_set_backend(const struct bm_posix_backend *backend)
{
    if (bm_validate_backend(backend) != 0) {
        return -1;
    }

    g_backend = backend;
    g_kernel_abi = NULL;
    g_bm_last_error = 0;
    return 0;
}

const struct bm_posix_backend *bm_get_backend(void)
{
    return g_backend;
}

void bm_use_host_backend(void)
{
    g_backend = &g_host_backend;
    g_kernel_abi = NULL;
    g_bm_last_error = 0;
}

int bm_bind_kernel_abi_v1(const struct bm_kernel_abi_v1 *abi)
{
    if (abi == NULL || abi->abi_version != BM_KERNEL_ABI_V1) {
        return bm_set_error(EINVAL);
    }

    if (abi->open == NULL || abi->close == NULL || abi->read == NULL || abi->write == NULL ||
        abi->lseek == NULL || abi->dup == NULL || abi->dup2 == NULL || abi->pipe == NULL || abi->isatty == NULL ||
        abi->getpid == NULL || abi->getppid == NULL || abi->setsid == NULL || abi->tcgetattr == NULL || abi->tcsetattr == NULL ||
        abi->fsync == NULL || abi->fdatasync == NULL || abi->access == NULL || abi->chmod == NULL || abi->truncate == NULL || abi->ftruncate == NULL ||
        abi->link == NULL || abi->symlink == NULL || abi->readlink == NULL ||
        abi->unlink == NULL || abi->rename == NULL || abi->mkdir == NULL || abi->rmdir == NULL ||
        abi->stat == NULL || abi->lstat == NULL || abi->fstat == NULL || abi->chdir == NULL || abi->fchdir == NULL || abi->getcwd == NULL || abi->realpath == NULL ||
        abi->opendir == NULL || abi->readdir == NULL || abi->closedir == NULL) {
        return bm_set_error(EINVAL);
    }

    g_kernel_abi = abi;
    g_backend = &g_kernel_adapter_backend;
    g_bm_last_error = 0;
    return 0;
}

uint32_t bm_bound_kernel_abi_version(void)
{
    return g_kernel_abi == NULL ? 0u : g_kernel_abi->abi_version;
}

static const struct bm_posix_backend *bm_require_backend(void)
{
    if (g_backend == NULL) {
        (void)bm_set_error(ENOSYS);
        return NULL;
    }

    return g_backend;
}

#define BM_DISPATCH_OR_RETURN(expr, fallback)           \
    do {                                                 \
        const struct bm_posix_backend *b = bm_require_backend(); \
        if (b == NULL) {                                 \
            return (fallback);                           \
        }                                                \
        return (expr);                                   \
    } while (0)

int bm_open(const char *path, int flags, bm_mode_t mode) { BM_DISPATCH_OR_RETURN(b->open(path, flags, mode), -1); }
int bm_close(int fd) { BM_DISPATCH_OR_RETURN(b->close(fd), -1); }
bm_ssize_t bm_read(int fd, void *buf, size_t count) { BM_DISPATCH_OR_RETURN(b->read(fd, buf, count), (bm_ssize_t)-1); }
bm_ssize_t bm_write(int fd, const void *buf, size_t count) { BM_DISPATCH_OR_RETURN(b->write(fd, buf, count), (bm_ssize_t)-1); }
bm_off_t bm_lseek(int fd, bm_off_t offset, int whence) { BM_DISPATCH_OR_RETURN(b->lseek(fd, offset, whence), (bm_off_t)-1); }
bm_off_t bm_lseek64(int fd, bm_off_t offset, int whence) { return bm_lseek(fd, offset, whence); }
int bm_dup(int fd) { BM_DISPATCH_OR_RETURN(b->dup(fd), -1); }
int bm_dup2(int oldfd, int newfd) { BM_DISPATCH_OR_RETURN(b->dup2(oldfd, newfd), -1); }
int bm_pipe(int pipefd[2]) { BM_DISPATCH_OR_RETURN(b->pipe(pipefd), -1); }
int bm_isatty(int fd) { BM_DISPATCH_OR_RETURN(b->isatty(fd), -1); }
int bm_getpid(void) { BM_DISPATCH_OR_RETURN(b->getpid(), -1); }
int bm_getppid(void) { BM_DISPATCH_OR_RETURN(b->getppid(), -1); }
int bm_setsid(void) { BM_DISPATCH_OR_RETURN(b->setsid(), -1); }
int bm_tcgetattr(int fd, struct termios *out_attr) { BM_DISPATCH_OR_RETURN(b->tcgetattr(fd, out_attr), -1); }
int bm_tcsetattr(int fd, int optional_actions, const struct termios *attr) { BM_DISPATCH_OR_RETURN(b->tcsetattr(fd, optional_actions, attr), -1); }
bm_ssize_t bm_pread(int fd, void *buf, size_t count, bm_off_t offset) { BM_DISPATCH_OR_RETURN(b->pread(fd, buf, count, offset), (bm_ssize_t)-1); }
bm_ssize_t bm_pwrite(int fd, const void *buf, size_t count, bm_off_t offset) { BM_DISPATCH_OR_RETURN(b->pwrite(fd, buf, count, offset), (bm_ssize_t)-1); }
int bm_fsync(int fd) { BM_DISPATCH_OR_RETURN(b->fsync(fd), -1); }
int bm_fdatasync(int fd) { BM_DISPATCH_OR_RETURN(b->fdatasync(fd), -1); }
int bm_access(const char *path, int mode) { BM_DISPATCH_OR_RETURN(b->access(path, mode), -1); }
int bm_chmod(const char *path, bm_mode_t mode) { BM_DISPATCH_OR_RETURN(b->chmod(path, mode), -1); }
int bm_truncate(const char *path, bm_off_t length) { BM_DISPATCH_OR_RETURN(b->truncate(path, length), -1); }
int bm_ftruncate(int fd, bm_off_t length) { BM_DISPATCH_OR_RETURN(b->ftruncate(fd, length), -1); }
int bm_link(const char *old_path, const char *new_path) { BM_DISPATCH_OR_RETURN(b->link(old_path, new_path), -1); }
int bm_symlink(const char *target, const char *linkpath) { BM_DISPATCH_OR_RETURN(b->symlink(target, linkpath), -1); }
bm_ssize_t bm_readlink(const char *path, char *buf, size_t bufsize) { BM_DISPATCH_OR_RETURN(b->readlink(path, buf, bufsize), (bm_ssize_t)-1); }
int bm_unlink(const char *path) { BM_DISPATCH_OR_RETURN(b->unlink(path), -1); }
int bm_rename(const char *old_path, const char *new_path) { BM_DISPATCH_OR_RETURN(b->rename(old_path, new_path), -1); }
int bm_mkdir(const char *path, bm_mode_t mode) { BM_DISPATCH_OR_RETURN(b->mkdir(path, mode), -1); }
int bm_rmdir(const char *path) { BM_DISPATCH_OR_RETURN(b->rmdir(path), -1); }
int bm_stat(const char *path, struct bm_stat *out_stat) { BM_DISPATCH_OR_RETURN(b->stat(path, out_stat), -1); }
int bm_lstat(const char *path, struct bm_stat *out_stat) { BM_DISPATCH_OR_RETURN(b->lstat(path, out_stat), -1); }
int bm_fstat(int fd, struct bm_stat *out_stat) { BM_DISPATCH_OR_RETURN(b->fstat(fd, out_stat), -1); }
int bm_chdir(const char *path) { BM_DISPATCH_OR_RETURN(b->chdir(path), -1); }
int bm_fchdir(int fd) { BM_DISPATCH_OR_RETURN(b->fchdir(fd), -1); }
int bm_getcwd(char *buf, size_t size) { BM_DISPATCH_OR_RETURN(b->getcwd(buf, size), -1); }
int bm_realpath(const char *path, char *out, size_t out_size) { BM_DISPATCH_OR_RETURN(b->realpath(path, out, out_size), -1); }

int bm_basename_r(const char *path, char *out, size_t out_size)
{
    const char *base;
    size_t len;

    if (path == NULL || out == NULL || out_size == 0) {
        g_bm_last_error = EINVAL;
        return -1;
    }

    base = strrchr(path, '/');
    base = (base == NULL) ? path : base + 1;
    if (*base == '\0') {
        base = ".";
    }

    len = strlen(base);
    if (len + 1 > out_size) {
        g_bm_last_error = ENAMETOOLONG;
        return -1;
    }

    (void)strncpy(out, base, out_size - 1);
    out[out_size - 1] = '\0';
    g_bm_last_error = 0;
    return 0;
}

int bm_dirname_r(const char *path, char *out, size_t out_size)
{
    const char *last;
    size_t len;

    if (path == NULL || out == NULL || out_size == 0) {
        g_bm_last_error = EINVAL;
        return -1;
    }

    last = strrchr(path, '/');
    if (last == NULL) {
        if (out_size < 2) {
            g_bm_last_error = ENAMETOOLONG;
            return -1;
        }
        out[0] = '.';
        out[1] = '\0';
        g_bm_last_error = 0;
        return 0;
    }

    len = (size_t)(last - path);
    if (len == 0) {
        len = 1;
    }

    if (len + 1 > out_size) {
        g_bm_last_error = ENAMETOOLONG;
        return -1;
    }

    (void)memcpy(out, path, len);
    out[len] = '\0';
    g_bm_last_error = 0;
    return 0;
}

bm_dir_t *bm_opendir(const char *path) { BM_DISPATCH_OR_RETURN(b->opendir(path), NULL); }
int bm_readdir(bm_dir_t *dir, struct bm_dirent *out_entry) { BM_DISPATCH_OR_RETURN(b->readdir(dir, out_entry), -1); }
int bm_closedir(bm_dir_t *dir) { BM_DISPATCH_OR_RETURN(b->closedir(dir), -1); }

int bm_last_error(void)
{
    return g_bm_last_error;
}
