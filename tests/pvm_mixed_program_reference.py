# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete guest loops combining memory, two host replies, arithmetic and gas."""
import struct
from pathlib import Path
from pvm_gas_reference import blob, simulate, tables

ROOT=Path(__file__).resolve().parents[1]
HEADER=struct.Struct('<III6Q26Q')
MASK=(1<<64)-1


# Hosts increment one loaded value, then accumulate the value already stored by the guest.
def fixtures():
    rows=[]
    definitions=tables()
    for iterations in (1,2,7,31):
        for initial in (0,MASK,(1<<63)-1,1<<63):
            for address in (0x10000,0x10fff):
                # Literal full-width branch displacement keeps raw code-byte gas lookup independently defined.
                body=[bytes((130,0x97,0)),bytes((10,13)),bytes((123,0x97,0)),bytes((10,14)),
                      bytes((131,0xaa,1)),bytes((83,0x1a,iterations))+(-13).to_bytes(4,'little',signed=True)]
                halt=bytes((50,0))
                wire=blob([*body,halt])
                price,cycles=simulate([*body,halt],definitions)
                halt_price,halt_cycles=simulate([halt],definitions)
                registers=[0x1111111111111111*i for i in range(13)]
                registers[0]=0xffff0000
                registers[7],registers[8],registers[9],registers[10]=77,0,(0x12345678<<32)|address,0
                expected=registers.copy()
                expected[7]=(initial+iterations)&MASK
                expected[8]=(iterations*initial+iterations*(iterations+1)//2)&MASK
                expected[10]=iterations
                rows.append(HEADER.pack(len(wire),iterations,address,initial,expected[7],
                    price,cycles,halt_price,halt_cycles,*registers,*expected)+wire)
    return b'PVMMIX01'+struct.pack('<I',len(rows))+b''.join(rows),len(rows)


# Only explicit regeneration updates the owned input; runtime tests read its frozen descriptor.
if __name__=='__main__':
    data,count=fixtures()
    (ROOT/'tests/fixtures/pvm-mixed-program.bin').write_bytes(data)
    print(f'{count} complete memory/host/loop programs')
