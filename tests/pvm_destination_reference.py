# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP and explicit JAM destination-byte expectations for every three-register opcode."""
import struct
from pathlib import Path
from pvm_register_reference import oracle
from pvm_gas_reference import tables,simulate

ROOT=Path(__file__).resolve().parents[1]
VALUES=(0,1,2,(1<<64)-1,0x80000000,0x7fffffff,1<<63,(1<<63)-1,31,32,63,64,0xfedcba9876543210)
ROW=struct.Struct('<BBBB6Q')


# Keep original encoded bytes; canonical shadow operands apply only the documented destination rule.
def fixtures():
    rows=[];definitions=tables();cache={}
    for opcode in range(190,231):
        for destination in range(256):
            for variant,descriptor in enumerate((0x10,0x77,0xff)):
                registers=[VALUES[(i+3*variant)%13] for i in range(13)]
                a,b=min(descriptor%16,12),min(descriptor//16,12)
                paper=min(destination%16,12);jam=min(destination%16,12)
                expected_paper=oracle(opcode,registers[a],registers[b],registers[paper],0)
                expected_jam=oracle(opcode,registers[a],registers[b],registers[jam],0)
                prices=[]
                for decoded in (paper,jam):
                    # With no branch byte lookup, canonical D uniquely represents the decoded register roles.
                    key=(opcode,descriptor,decoded)
                    if key not in cache:
                        cache[key]=simulate([bytes((opcode,descriptor,decoded)),b'\0'],definitions)
                    prices.extend(cache[key])
                rows.append(ROW.pack(opcode,descriptor,destination,variant,
                    expected_paper,expected_jam,*prices))
    return b'PVMDST01'+struct.pack('<I13Q',len(rows),*VALUES)+b''.join(rows),len(rows)


# Only explicit regeneration updates the owned frozen input; runtime replay preserves it verbatim.
if __name__=='__main__':
    data,count=fixtures();(ROOT/'tests/fixtures/pvm-destination.bin').write_bytes(data)
    print(f'{count} destination-byte/value/gas witnesses')
