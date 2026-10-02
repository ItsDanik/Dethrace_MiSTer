#!/usr/bin/env python3
"""Generate a MiSTer platform input script: new game -> first race -> benchmark.
usage: genbench.py grid|drive [measure_seconds]"""
import sys
mode = sys.argv[1]
secs = int(sys.argv[2]) if len(sys.argv) > 2 else 40
print("3000 key 0x1c 700")   # skip logo (cutscenes poll keys only every 500ms)
print("6000 key 0x1c 700")   # skip intro movie
t = 10000
for i in range(9):           # main menu -> new game -> driver -> skill -> ... -> START RACE
    print(f"{t} key 0x1c 150"); t += 2500
for tt in range(t, t + 21000, 3000):  # loading, then grid DONE
    print(f"{tt} key 0x1c 150")
t += 21000
if mode == "drive":
    print(f"{t} down 0x17")  # accelerate (I)
start = t + 8000
print(f"{start} stats"); print(f"{start} prof_on")
for tt in range(start, start + secs * 1000, secs * 1000 // 4):
    print(f"{tt} shot")
print(f"{start + secs * 1000} prof_off"); print(f"{start + secs * 1000 + 100} quit")
