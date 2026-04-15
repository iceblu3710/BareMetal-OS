#include "../include/posix_layer.h"

#include <stdio.h>

int main(void)
{
    struct termios t;
    int tty;

    bm_use_host_backend();

    if (bm_getpid() <= 0) {
        fprintf(stderr, "bm_getpid failed: %d\n", bm_last_error());
        return 1;
    }

    if (bm_getppid() <= 0) {
        fprintf(stderr, "bm_getppid failed: %d\n", bm_last_error());
        return 1;
    }

    tty = bm_isatty(0);
    if (tty == 1) {
        if (bm_tcgetattr(0, &t) != 0) {
            fprintf(stderr, "bm_tcgetattr failed: %d\n", bm_last_error());
            return 1;
        }
    }

    /* bm_setsid is intentionally not forced in this test because it can fail
     * depending on process/session state in CI or containerized environments. */

    puts("ok");
    return 0;
}
