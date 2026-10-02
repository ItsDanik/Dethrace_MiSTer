#!/usr/bin/env python3
"""Symbolize profile.bin (pairs of u32 pc, lr) from the MiSTer platform's sampling profiler.
usage: profsym.py profile.bin syms.txt (from `nm -n -S --defined-only`) [top N] [maps.txt libsyms_dir]
libsyms_dir holds `nm -D -n -S --defined-only` output of shared libraries as <basename>.syms"""
import bisect, collections, os, struct, sys

samples = open(sys.argv[1], "rb").read()
pairs = list(struct.iter_unpack("<II", samples))
top = int(sys.argv[3]) if len(sys.argv) > 3 else 40

starts, names, ends = [], [], []
for line in open(sys.argv[2]):
    p = line.split()
    if len(p) == 4 and p[2] in "tTwW":
        a, sz = int(p[0], 16), int(p[1], 16)
        starts.append(a); ends.append(a + sz); names.append(p[3])

# shared libraries: (start, end, offset, name, [sorted (addr, size, sym)])
libs = []
if len(sys.argv) > 5:
    for line in open(sys.argv[4]):
        p = line.split()
        if len(p) >= 6 and "x" in p[1] and p[5].endswith(tuple([".so", ".6"]) ) or (len(p) >= 6 and ".so" in p[5] and "x" in p[1]):
            lo, hi = (int(x, 16) for x in p[0].split("-"))
            base = os.path.basename(p[5])
            symfile = os.path.join(sys.argv[5], base + ".syms")
            entries = []
            if os.path.exists(symfile):
                for l in open(symfile):
                    q = l.split()
                    if len(q) == 4 and q[2] in "tTwWiI":
                        entries.append((int(q[0], 16), int(q[1], 16), q[3]))
            entries.sort()
            libs.append((lo, hi, int(p[2], 16), base, entries))

def sym(a):
    i = bisect.bisect_right(starts, a) - 1
    if i >= 0 and a < ends[i]:
        return names[i]
    for lo, hi, off, base, entries in libs:
        if lo <= a < hi:
            rel = a - lo + off
            j = bisect.bisect_right(entries, (rel, 1 << 40, "")) - 1
            if j >= 0 and rel < entries[j][0] + max(entries[j][1], 1):
                return f"{base}:{entries[j][2]}"
            return f"{base}:?"
    return "[libc/other]" if a >= 0x10000000 else "[unknown]"

self_c = collections.Counter()
caller_c = collections.defaultdict(collections.Counter)
for pc, lr in pairs:
    f = sym(pc)
    self_c[f] += 1
    caller_c[f][sym(lr & ~1)] += 1

n = len(pairs)
print(f"{n} samples")
for f, c in self_c.most_common(top):
    callers = ", ".join(f"{k} {v*100//c}%" for k, v in caller_c[f].most_common(3))
    print(f"{c*100.0/n:6.2f}%  {f:40s}  <- {callers}")
