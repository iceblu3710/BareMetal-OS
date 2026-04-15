#include "../include/posix_layer.h"

#include <stdio.h>
#include <string.h>

int main(void)
{
    char out[256] = {0};
    char out2[256] = {0};

    bm_use_host_backend();

    if (bm_basename_r("/tmp/example/file.txt", out, sizeof(out)) != 0 || strcmp(out, "file.txt") != 0) {
        fprintf(stderr, "basename failed: %s (%d)\n", out, bm_last_error());
        return 1;
    }

    if (bm_dirname_r("/tmp/example/file.txt", out2, sizeof(out2)) != 0 || strcmp(out2, "/tmp/example") != 0) {
        fprintf(stderr, "dirname failed: %s (%d)\n", out2, bm_last_error());
        return 1;
    }

    if (bm_realpath("/tmp", out, sizeof(out)) != 0) {
        fprintf(stderr, "realpath failed: %d\n", bm_last_error());
        return 1;
    }

    if (strncmp(out, "/", 1) != 0) {
        fprintf(stderr, "realpath output invalid: %s\n", out);
        return 1;
    }

    puts("ok");
    return 0;
}
