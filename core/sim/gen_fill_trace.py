#!/usr/bin/env python3
"""Synthetic trace for FR_OP_FILL: random rectangles over random memory.
usage: gen_fill_trace.py <trace dir>   (then replay with the software model)"""
import os, random, sys

random.seed(1)
d = sys.argv[1]
os.makedirs(d, exist_ok=True)
base, size = 0x140000, 0x40000
with open(d + "/mem.hex", "w") as f:
    f.write("@%x\n" % (base >> 3))
    for _ in range(size // 8):
        f.write("%016x\n" % random.getrandbits(64))
with open(d + "/cmds.hex", "w") as f:
    for n in range(200):
        stride = random.choice([320, 640, 648, 1280, 7, 33])
        nbytes = random.choice([1, 2, 3, 7, 8, 9, 16, 17, 320, 640, 1280, 2048, random.randint(1, 2048)])
        rows = random.randint(1, 12)
        addr = base + random.randint(0, size - stride * rows - nbytes - 8)
        for w in (5 | 6 << 8, addr, nbytes, rows, stride, random.getrandbits(16)):
            f.write("%08x\n" % w)
