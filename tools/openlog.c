// LD_PRELOAD: every file the program opens (fopen, open), "ok <path>" or
// "fail <path>", one a line, to the file $OPENLOG. Made the list of
// Carmageddon's files (dethrace/src/harness/platforms/mister_files.h; CLAUDE.md,
// "Game data"). Build: hybrid/docker.sh sh -c "arm-linux-gnueabihf-gcc -shared
// -fPIC -O2 -o build/openlog.so tools/openlog.c -ldl"; run the game with
// TEST_ENV="LD_PRELOAD=/tmp/openlog.so OPENLOG=/tmp/open.log" tools/test_on_mister.sh.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
static void note(const char *how, const char *p) {
    static int fd = -2;
    char line[1100];
    if (fd == -2) { const char *f = getenv("OPENLOG"); fd = f ? (int)syscall(SYS_openat, AT_FDCWD, f, O_WRONLY | O_CREAT | O_APPEND, 0644) : -1; }
    if (fd < 0 || !p) return;
    int n = snprintf(line, sizeof line, "%s %s\n", how, p);
    if (n > 0) write(fd, line, n);
}
FILE *fopen(const char *p, const char *m) { static FILE *(*r)(const char *, const char *); if (!r) r = dlsym(RTLD_NEXT, "fopen"); FILE *f = r(p, m); note(f ? "ok" : "fail", p); return f; }
FILE *fopen64(const char *p, const char *m) { static FILE *(*r)(const char *, const char *); if (!r) r = dlsym(RTLD_NEXT, "fopen64"); FILE *f = r(p, m); note(f ? "ok" : "fail", p); return f; }
int open(const char *p, int fl, ...) { static int (*r)(const char *, int, ...); if (!r) r = dlsym(RTLD_NEXT, "open"); va_list a; va_start(a, fl); int mo = va_arg(a, int); va_end(a); int x = r(p, fl, mo); note(x >= 0 ? "ok" : "fail", p); return x; }
int open64(const char *p, int fl, ...) { static int (*r)(const char *, int, ...); if (!r) r = dlsym(RTLD_NEXT, "open64"); va_list a; va_start(a, fl); int mo = va_arg(a, int); va_end(a); int x = r(p, fl, mo); note(x >= 0 ? "ok" : "fail", p); return x; }
