/* Application-specific POSIX output glue. Threading lives in mojo-threads. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

void pb_init(void) { signal(SIGPIPE, SIG_IGN); }
int pb_output(const char *input, const char *output) {
    if (!*output) return dup(STDOUT_FILENO);
    /* Open without truncation; compare the actual descriptor's inode. */
    int fd = open(output, O_WRONLY | O_CREAT, 0666);
    if (fd < 0) return -1;
    struct stat a, b;
    if (fstat(fd, &b) || (!stat(input, &a) && a.st_dev == b.st_dev && a.st_ino == b.st_ino)) {
        close(fd);
        return -1;
    }
    /* Truncating an already-empty file is unnecessary. On ext4, even that
     * no-op can request delayed-allocation writeback at close. Keep the inode
     * check above, and still truncate existing nonempty regular files. */
    if (S_ISREG(b.st_mode) && b.st_size != 0 && ftruncate(fd, 0)) {
        close(fd);
        return -1;
    }
    return fd;
}
int pb_write(int fd, const void *bytes, size_t count) {
    const unsigned char *p = bytes;
    while (count) {
        ssize_t n = write(fd, p, count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        p += n;
        count -= (size_t)n;
    }
    return 0;
}
