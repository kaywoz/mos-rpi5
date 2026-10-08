#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 kaywoz
"""setmac.py - set the Pi 5 onboard Ethernet (RP1 GEM) MAC address in a dtb.

The dtb has `local-mac-address = [00 00 00 00 00 00]` on ethernet@40100000.
Normally the Pi firmware fills it in; under UEFI nobody does, so the kernel
(macb) picks a new random MAC on every boot. This writes a fixed one.

Usage: python3 -I setmac.py FILE.dtb aa:bb:cc:dd:ee:ff
Edits FILE.dtb in place and keeps a copy as FILE.dtb.bak (first run only).
Only the six value bytes change; the file size and layout stay the same.
"""
import os
import shutil
import struct
import sys

if len(sys.argv) != 3:
    sys.exit(__doc__)
path, mac = sys.argv[1], sys.argv[2]
new = bytes(int(x, 16) for x in mac.split(':'))
if len(new) != 6:
    sys.exit('MAC must look like aa:bb:cc:dd:ee:ff')
if new[0] & 1:
    sys.exit('MAC must be unicast (first byte must be even)')

d = bytearray(open(path, 'rb').read())
magic, total, off_struct, off_strings = struct.unpack('>4I', d[:16])
if magic != 0xd00dfeed:
    sys.exit('not a dtb')
size_strings, size_struct = struct.unpack('>II', d[32:40])


def name_at(off):
    s = off_strings + off
    return bytes(d[s:d.index(0, s)]).decode()


pos, end, depth, stack, hits = off_struct, off_struct + size_struct, 0, [], []
while pos < end:
    tok = struct.unpack('>I', d[pos:pos + 4])[0]
    pos += 4
    if tok == 1:                                   # FDT_BEGIN_NODE
        n = d.index(0, pos)
        stack.append(bytes(d[pos:n]).decode())
        pos = (n + 4) & ~3
    elif tok == 2:                                 # FDT_END_NODE
        stack.pop()
    elif tok == 3:                                 # FDT_PROP
        ln, noff = struct.unpack('>II', d[pos:pos + 8])
        pos += 8
        if name_at(noff) == 'local-mac-address' and ln == 6 \
                and stack and stack[-1].startswith('ethernet@40100000'):
            hits.append(pos)
        pos = (pos + ln + 3) & ~3
    elif tok == 4:                                 # FDT_NOP
        pass
    else:                                          # FDT_END (9) or unexpected
        break
if len(hits) != 1:
    sys.exit('expected exactly one local-mac-address on ethernet@40100000, found %d' % len(hits))

bak = path + '.bak'
if not os.path.exists(bak):
    shutil.copy2(path, bak)
old = bytes(d[hits[0]:hits[0] + 6])
d[hits[0]:hits[0] + 6] = new
open(path, 'wb').write(d)
print('local-mac-address %s -> %s in %s' % (old.hex(':'), new.hex(':'), path))
