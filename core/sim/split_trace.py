#!/usr/bin/env python3
"""Split a rasteriser trace by triangle type, to narrow down testbench failures.
usage: split_trace.py <trace dir>   -> <trace dir>_<type>/ with the same mem.hex"""
import collections, os, shutil, sys

src = sys.argv[1].rstrip("/")
words = [int(l, 16) for l in open(src + "/cmds.hex")]
out = collections.defaultdict(list)
target = []
i = 0
while i < len(words):
    head = words[i]
    op, n, flags = head & 0xff, (head >> 8) & 0xff, head >> 16
    cmd = words[i:i + n]
    i += n
    if op == 1:
        target = cmd
        continue
    if op == 2:
        name = {0: "z", 2: "zi", 4: "zt", 6: "zti"}[flags & 6] + ("_rl" if flags & 1 else "_lr")
    elif op == 3:
        name = ("zpti" if flags & 2 else "zpt") + ("_b" if flags & 1 else "_f")
    elif op == 6:
        name = "zta" + ("_rl" if flags & 1 else "_lr")
    else:
        name = "op%d" % op
    if not out[name]:
        out[name] += target
    out[name] += cmd
for name, cmds in sorted(out.items()):
    d = "%s_%s" % (src, name)
    os.makedirs(d, exist_ok=True)
    shutil.copy(src + "/mem.hex", d + "/mem.hex")
    with open(d + "/cmds.hex", "w") as f:
        f.writelines("%08x\n" % w for w in cmds)
    print(d, len(cmds), "words")
