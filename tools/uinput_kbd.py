#!/usr/bin/env python3
"""Virtual keyboard for end-to-end input tests on the MiSTer.
Keys go through Main_MiSTer -> hps_io -> Dethrace core -> shared memory -> game.
usage: uinput_kbd.py "<ms> <key> <hold_ms>" ...   (Linux key codes, e.g. 28 = Enter, 23 = I)"""
import fcntl, os, struct, sys, time

UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x5501, 0x5502
EV_SYN, EV_KEY = 0, 1

fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
for k in range(1, 256):
    fcntl.ioctl(fd, UI_SET_KEYBIT, k)
fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 3, 0x1d6b, 0x0104, 1, b"dethrace test keyboard", 0))
fcntl.ioctl(fd, UI_DEV_CREATE)

def emit(type_, code, value):
    os.write(fd, struct.pack("llHHi", 0, 0, type_, code, value))

events = []
for arg in sys.argv[1:]:
    t, key, hold = (int(x) for x in arg.split())
    events.append((t, key, 1))
    events.append((t + hold, key, 0))
events.sort()

start = time.monotonic()
for t, key, value in events:
    delay = start + t / 1000.0 - time.monotonic()
    if delay > 0:
        time.sleep(delay)
    emit(EV_KEY, key, value)
    emit(EV_SYN, 0, 0)
time.sleep(0.5)
fcntl.ioctl(fd, UI_DEV_DESTROY)
os.close(fd)
