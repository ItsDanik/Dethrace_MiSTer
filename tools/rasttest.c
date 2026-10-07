// Hardware test of the FPGA rasteriser: plays a trace of the software model
// (PENTPRIM_FPGA_TRACE / PENTPRIM_FPGA_REPLAY, see fpgarast.c) through the
// loaded Dethrace core and compares the buffers it leaves with the model's.
// The game must not be running. Built and run by tools/rasttest.sh.
//   rasttest <trace dir> [runs]
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define RAST_PHYS 0x31000000
#define RAST_SIZE 0x1000000
#define RING_OFFSET 0x80000
#define RING_WORDS 0x20000
#define HEAP_BASE 0x900000
#define CTRL_MAGIC 0x54534152   // "RAST"
#define STATUS_MAGIC 0x4B4F5352 // "RSOK"

static volatile uint32_t* reg;
static volatile uint8_t* shm;

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static void sleep_ms(int ms) {
    struct timespec ts = { ms / 1000, (ms % 1000) * 1000000 };
    nanosleep(&ts, NULL);
}

typedef struct {
    uint32_t addr, size;
    uint8_t* data;
} tRange;

// $readmemh file of 64 bit words: "@<word address>" starts a range
static int load_hex(const char* dir, const char* name, tRange* ranges, int max) {
    char path[1024], line[64];
    int count = 0;
    uint32_t cap = 0;
    FILE* f;

    snprintf(path, sizeof(path), "%s/%s", dir, name);
    f = fopen(path, "r");
    if (f == NULL) {
        perror(path);
        exit(1);
    }
    while (fgets(line, sizeof(line), f) != NULL) {
        if (line[0] == '@') {
            if (count == max) {
                break;
            }
            ranges[count].addr = (uint32_t)strtoul(line + 1, NULL, 16) << 3;
            ranges[count].size = 0;
            ranges[count].data = NULL;
            cap = 0;
            count++;
        } else if (count > 0) {
            tRange* r = &ranges[count - 1];
            uint64_t v = strtoull(line, NULL, 16);
            if (r->size + 8 > cap) {
                cap = cap ? cap * 2 : 4096;
                r->data = realloc(r->data, cap);
            }
            memcpy(r->data + r->size, &v, 8);
            r->size += 8;
        }
    }
    fclose(f);
    return count;
}

int main(int argc, char** argv) {
    static tRange mem[4096], expect[64];
    static uint32_t cmds[1 << 20];
    int mem_count, expect_count, cmd_count = 0, runs = argc > 2 ? atoi(argv[2]) : 3;
    int fd, i, run, result = 0;
    char path[1024], line[64];
    FILE* f;

    if (argc < 2) {
        fprintf(stderr, "usage: rasttest <trace dir> [runs]\n");
        return 1;
    }
    mem_count = load_hex(argv[1], "mem.hex", mem, 4096);
    expect_count = load_hex(argv[1], "expect.hex", expect, 64);
    snprintf(path, sizeof(path), "%s/cmds.hex", argv[1]);
    f = fopen(path, "r");
    if (f == NULL) {
        perror(path);
        return 1;
    }
    while (fgets(line, sizeof(line), f) != NULL && cmd_count < (1 << 20)) {
        cmds[cmd_count++] = (uint32_t)strtoul(line, NULL, 16);
    }
    fclose(f);

    fd = open("/dev/mem", O_RDWR | O_SYNC);
    shm = mmap(NULL, RAST_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, RAST_PHYS);
    if (fd < 0 || shm == MAP_FAILED) {
        perror("/dev/mem");
        return 1;
    }
    reg = (volatile uint32_t*)shm;

    for (run = 0; run < runs; run++) {
        uint32_t produced = 0;
        int ci = 0, errors = 0, bytes = 0;
        double t0, t_load, t_push, t_done;

        if (run == 0) {
            // new session: the core answers the magic with its own
            reg[0] = 0;
            sleep_ms(5);
            for (i = 1; i < 6; i++) {
                reg[i] = 0;
            }
            t0 = now_ms();
            for (i = 0; i < mem_count; i++) {
                memcpy((void*)(shm + mem[i].addr), mem[i].data, mem[i].size);
                bytes += mem[i].size;
            }
            t_load = now_ms() - t0;
            reg[1] = 0;
            reg[0] = CTRL_MAGIC;
            for (i = 0; i < 100 && reg[4] != STATUS_MAGIC; i++) {
                sleep_ms(1);
            }
            if (reg[4] != STATUS_MAGIC) {
                fprintf(stderr, "no answer from the rasteriser (is the Dethrace core with the rasteriser loaded?)\n");
                reg[0] = 0;
                return 1;
            }
            printf("rasteriser version %u, loaded %d bytes in %.1f ms\n", reg[5], bytes, t_load);
        } else {
            // the buffers as they were (textures stay, and stay cached)
            for (i = 0; i < mem_count; i++) {
                if (mem[i].addr < HEAP_BASE) {
                    memcpy((void*)(shm + mem[i].addr), mem[i].data, mem[i].size);
                }
            }
            produced = reg[1];
        }

        t0 = now_ms();
        while (ci < cmd_count) {
            const int n = (cmds[ci] >> 8) & 255;
            volatile uint32_t* ring = (volatile uint32_t*)(shm + RING_OFFSET);

            // room in the ring for the command and its padding?
            while (produced + n + 1 - reg[2] > RING_WORDS) {
            }
            for (i = 0; i < n; i++) {
                ring[produced++ % RING_WORDS] = cmds[ci + i];
            }
            if (n & 1) {
                ring[produced++ % RING_WORDS] = 0x00000100;
            }
            ci += n;
            // publish every few commands, like a game that keeps the FPGA fed
            if ((ci & 0xff) < 32 || ci == cmd_count) {
                reg[1] = produced;
            }
        }
        reg[1] = produced;
        t_push = now_ms() - t0;
        while (reg[3] != produced) {
            if (now_ms() - t0 > 5000) {
                fprintf(stderr, "timeout: fetched %u completed %u of %u\n", reg[2], reg[3], produced);
                reg[0] = 0;
                return 1;
            }
        }
        t_done = now_ms() - t0;

        for (i = 0; i < expect_count; i++) {
            uint8_t* got = malloc(expect[i].size);
            uint32_t k;
            memcpy(got, (void*)(shm + expect[i].addr), expect[i].size);
            for (k = 0; k < expect[i].size; k++) {
                if (got[k] != expect[i].data[k]) {
                    if (errors++ < 5) {
                        printf("  mismatch at %06x: got %02x expected %02x\n", expect[i].addr + k, got[k], expect[i].data[k]);
                    }
                }
            }
            free(got);
        }
        printf("run %d: %d command words written in %.2f ms, drawn after %.2f ms, %s (%d bytes differ)\n",
            run, cmd_count, t_push, t_done, errors ? "FAIL" : "PASS", errors);
        result |= errors != 0;
    }
    reg[0] = 0;
    return result;
}
