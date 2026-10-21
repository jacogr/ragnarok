# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compose GP-derived cross-page faults, successful store bytes and independent block prices."""
import struct
from pvm_memory_access_reference import ROOT, HEADER, ADDRESSES, witness
from pvm_gas_reference import simulate, tables


# Keep the paper's initial fault and supply the independently derived fully repaired outcome.
def fixtures():
    rows = []
    definitions = tables()
    for opcode in (31,32,33,60,61,62,71,72,73,121,122,123):
        for address in ADDRESSES:
            for variant in range(3):
                # The two models use identical CPU/code; only environmental page permissions differ.
                fault = witness(opcode,address,(2,0),variant)
                success = witness(opcode,address,(1,1),variant)
                header = HEADER.unpack_from(fault)
                if address < 0x11000 < address+header[4]:
                    expected = bytearray(fault[:HEADER.size])
                    expected[17:26] = success[17:26]
                    wire = fault[HEADER.size:]
                    raw = wire[3:3+wire[2]-1]
                    price,cycles = simulate([raw,b'\0'],definitions)
                    assert (price,cycles)==(25,28)
                    rows.append(bytes(expected)+struct.pack('<QQ',price,cycles)+wire)
    return b'PVMCRY01'+struct.pack('<I',len(rows))+b''.join(rows),len(rows)


# Explicit regeneration writes only the named test input; normal verification reads frozen bytes.
if __name__ == '__main__':
    data,count = fixtures()
    (ROOT/'tests/fixtures/pvm-cross-page-retry.bin').write_bytes(data)
    print(f'{count} metered two-stage repair witnesses')
