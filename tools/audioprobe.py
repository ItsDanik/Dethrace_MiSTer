#!/usr/bin/env python3
"""Probe the Dethrace core's audio ring on the MiSTer: fetch rate and signal level."""
import mmap, os, struct, time
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x20000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x30000000)
ptr = lambda: struct.unpack_from("<I", m, 0xC0)[0]
p0, t0 = ptr(), time.monotonic()
time.sleep(1.0)
p1, t1 = ptr(), time.monotonic()
ring = struct.unpack_from("<32768h", m, 0x10000)
peak = max(abs(v) for v in ring)
nonzero = sum(1 for v in ring if v)
print(f"fetch rate {(p1 - p0) / (t1 - t0):.0f} frames/s, ring peak {peak}, nonzero samples {nonzero}/32768, audio_en bit {struct.unpack_from('<I', m, 4)[0] >> 24 & 1}")
