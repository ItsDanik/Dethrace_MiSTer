#!/usr/bin/env python3
"""Sample the audio ring for a while and report level statistics (clipping)."""
import mmap, os, struct, sys, time
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x20000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x30000000)
total = clipped = 0
peaks = []
for _ in range(int(sys.argv[1]) if len(sys.argv) > 1 else 10):
    ring = struct.unpack_from("<32768h", m, 0x10000)
    total += len(ring)
    clipped += sum(1 for v in ring if v >= 32767 or v <= -32768)
    peaks.append(max(abs(v) for v in ring))
    time.sleep(0.35)  # ring holds 0.34s
rms_ring = struct.unpack_from("<32768h", m, 0x10000)
rms = (sum(v * v for v in rms_ring) / len(rms_ring)) ** 0.5
print(f"clipped {clipped}/{total} ({100.0 * clipped / total:.3f}%), peaks {peaks}, rms {rms:.0f}")
