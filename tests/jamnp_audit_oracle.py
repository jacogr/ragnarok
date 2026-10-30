# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent CE144/145 wire witnesses for JAMNP-S aa0e2b8.

These are structural samples, not authenticated signatures. Python struct packs fixed E2/E4
fields independently of the Nim codecs. The enclosing message extent supplies each batch count;
negative guarantees use canonical one-octet counts of two/three before report/signature bytes.
"""
import struct


# Deterministic opaque bytes make field displacement visible without pretending to sign evidence.
def pattern(start, length):
    return bytes((start + index) % 256 for index in range(length))


# Each returned file is compared byte-for-byte with the frozen independently generated witness.
def samples():
    initial = bytes(range(32)) + struct.pack('<H', 5) + b'\x00' + pattern(40, 96)
    later = bytes(reversed(range(32))) + struct.pack('<H', 1022) + b'\x01' + struct.pack('<H', 340) + b'\xaa'*96
    positive = struct.pack('<IH', 0x01020304, 17) + b'\x01' + pattern(32, 32) + pattern(128, 64)
    two = (struct.pack('<IH', 9, 18) + b'\x00' + struct.pack('<I', 0xaabbccdd) + b'\x02'
           + struct.pack('<H', 2) + pattern(48, 64)
           + struct.pack('<H', 7) + pattern(64, 64) + b'\x55'*32 + b'\x66'*64)
    three = (struct.pack('<IH', 10, 19) + b'\x00' + struct.pack('<I', 0x11223344) + b'\x03'
             + struct.pack('<H', 0) + b'\x90'*64
             + struct.pack('<H', 256) + b'\x91'*64
             + struct.pack('<H', 1022) + b'\x92'*64 + b'\x77'*32 + b'\x88'*64)
    return {'announcements.bin': initial+later, 'initial.bin': initial, 'later.bin': later,
            'judgments.bin': positive+two+three, 'negative2.bin': two, 'negative3.bin': three,
            'positive.bin': positive}
