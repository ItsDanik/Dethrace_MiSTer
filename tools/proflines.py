#!/usr/bin/env python3
"""Per source line breakdown of one function in profile.bin.
usage: proflines.py profile.bin <elf> <function> [top N]   (runs addr2line from the toolchain image)"""
import collections, struct, subprocess, sys, os
prof, elf, func = sys.argv[1:4]
top = int(sys.argv[4]) if len(sys.argv) > 4 else 30
tc = ["docker", "run", "--rm", "-i", "-v", os.getcwd() + ":/src", "-w", "/src", "mister-dethrace-tc"]
nm = subprocess.run(tc + ["arm-linux-gnueabihf-nm", "-n", "-S", "--defined-only", elf], capture_output=True, text=True).stdout
lo = hi = None
for l in nm.splitlines():
    p = l.split()
    if len(p) == 4 and p[3] == func:
        lo = int(p[0], 16) & ~1; hi = lo + int(p[1], 16)
pcs = collections.Counter(pc for pc, lr in struct.iter_unpack("<II", open(prof, "rb").read()) if lo <= pc < hi)
total = sum(pcs.values())
out = subprocess.run(tc + ["arm-linux-gnueabihf-addr2line", "-e", elf] , input="\n".join(hex(a) for a in pcs), capture_output=True, text=True).stdout.splitlines()
lines = collections.Counter()
for a, l in zip(pcs, out):
    lines[os.path.basename(l.split(" ")[0])] += pcs[a]
print(f"{func}: {total} samples")
for l, c in lines.most_common(top):
    print(f"{c*100.0/total:6.2f}%  {l}")
