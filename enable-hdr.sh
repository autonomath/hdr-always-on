#!/bin/bash
# Enable HDR on all capable external displays.
# Uses macOS CoreDisplay private API -- no UI, no dependencies.

python3 << 'PYTHON'
import ctypes
import sys
from datetime import datetime

try:
    cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
    cd = ctypes.CDLL('/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay')
except OSError as e:
    print(f"Failed to load frameworks: {e}", file=sys.stderr)
    sys.exit(1)

cd.CoreDisplay_Display_IsHDRModeEnabled.argtypes = [ctypes.c_uint32]
cd.CoreDisplay_Display_IsHDRModeEnabled.restype = ctypes.c_bool
cd.CoreDisplay_Display_SetHDRModeEnabled.argtypes = [ctypes.c_uint32, ctypes.c_bool]
cd.CoreDisplay_Display_SetHDRModeEnabled.restype = ctypes.c_int

max_displays = 16
displays = (ctypes.c_uint32 * max_displays)()
count = ctypes.c_uint32()
cg.CGGetOnlineDisplayList(max_displays, displays, ctypes.byref(count))

now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
found_external = False

for i in range(count.value):
    did = displays[i]
    if cg.CGDisplayIsBuiltin(did):
        continue

    found_external = True
    is_hdr = cd.CoreDisplay_Display_IsHDRModeEnabled(did)

    if is_hdr:
        print(f"[{now}] Display {did}: HDR already on")
        continue

    result = cd.CoreDisplay_Display_SetHDRModeEnabled(did, True)
    if result == 0:
        print(f"[{now}] Display {did}: HDR enabled")
    else:
        # Non-zero return typically means the display doesn't support HDR
        print(f"[{now}] Display {did}: could not enable HDR (display may not support it)")

if not found_external:
    print(f"[{now}] No external displays connected")
PYTHON
