# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent expectations for a small correctness-checked PVM performance subset."""
import struct
from pathlib import Path
from pvm_gas_reference import blob, simulate, tables

ROOT=Path(__file__).resolve().parents[1]
HEADER=struct.Struct('<IBII4QI2Q26Q')
NAMES=('arithmetic-10000','memory-aligned-1000','memory-crossing-1000',
       'hosts-aligned-1000','hosts-crossing-1000','arithmetic-1','arithmetic-16',
       'bits-mixed-1000','sparse-aligned-1000','sparse-crossing-1000','blocks-alternating-1000')


# Derive fixed guest bytes, exact gas and complete outcomes independently of measured implementations.
def fixtures():
    rows=[];definitions=tables()
    for kind,iterations,address in ((0,10000,0),(1,1000,0x10000),(1,1000,0x10fff),
                                    (2,1000,0x10000),(2,1000,0x10fff),(0,1,0),(0,16,0),
                                    (3,1000,0),(4,1000,0x10000),(4,1000,0x10fff)):
        if kind==0:
            # Simple register arithmetic and a real backward branch exercise interpreter dispatch.
            body=[bytes((131,0x77,3)),bytes((131,0xaa,1))]
        elif kind in (1,4):
            # Memory writes use a register value computed by the guest, with no host assistance.
            body=[bytes((130,0x97,0)),bytes((131,0x77,1)),bytes((123,0x97,0)),bytes((131,0xaa,1))]
        elif kind==3:
            # Bit counting, reversal, rotation and dependent updates exercise integer paths beyond addition.
            body=[bytes((101,0x71)),bytes((103,0x72)),bytes((105,0x73)),bytes((110,0x74)),
                  bytes((222,0x67,5)),bytes((211,0x47,7)),bytes((149,0x77,1)),bytes((131,0xaa,1))]
        else:
            # The same load/host/store/host/counter loop already has a complete paired correctness corpus.
            body=[bytes((130,0x97,0)),bytes((10,13)),bytes((123,0x97,0)),
                  bytes((10,14)),bytes((131,0xaa,1))]
        pc=sum(map(len,body))
        body.append(bytes((83,0x4a))+iterations.to_bytes(4,'little')+(-pc).to_bytes(4,'little',signed=True))
        halt=bytes((50,0));halt_pc=sum(map(len,body));wire=blob([*body,halt])
        price,cycles=simulate([*body,halt],definitions);halt_price,halt_cycles=simulate([halt],definitions)
        registers=[0x1111111111111111*i for i in range(13)]
        registers[0]=0xffff0000;registers[7]=0;registers[8]=0
        registers[9]=(0x12345678<<32)|address;registers[10]=0
        expected=registers.copy();expected[7]=iterations*(3 if kind==0 else 1);expected[10]=iterations
        if kind==3:
            # Independent mathematical expectations use Python integers and byte conversion, not VM decoding.
            registers[6]=13;expected=registers.copy();expected[10]=iterations
            value=0;mask=(1<<64)-1
            for _ in range(iterations):
                expected[1]=value.bit_count();expected[2]=64-value.bit_length()
                expected[3]=64 if value==0 else (value & -value).bit_length()-1
                expected[4]=int.from_bytes(value.to_bytes(8,'little'),'big')
                expected[5]=((value>>13)|(value<<51))&mask
                value=((value^expected[4])+1)&mask
            expected[7]=value
        if kind==2:expected[8]=iterations*(iterations+1)//2
        rows.append(HEADER.pack(len(wire),kind,iterations,address,0,iterations if kind in (1,2,4) else 0,
            price,cycles,halt_pc,halt_price,halt_cycles,*registers,*expected)+wire)
    # Two genuine basic blocks alternate; price the second at its real PC against the complete preceding code.
    iterations=1000
    first=[bytes((131,0x77,1)),bytes((40,))+int(5).to_bytes(4,'little',signed=True)]
    second_pc=sum(map(len,first))
    branch_pc=second_pc+3
    second=[bytes((131,0xaa,1)),bytes((83,0x4a))+iterations.to_bytes(4,'little')+
            (-branch_pc).to_bytes(4,'little',signed=True)]
    halt=bytes((50,0));halt_pc=sum(map(len,[*first,*second]))
    wire=blob([*first,*second,halt])
    price,cycles=simulate([*first,*second,halt],definitions)
    second_price,second_cycles=simulate([*second,halt],definitions,prefix=first)
    halt_price,halt_cycles=simulate([halt],definitions)
    registers=[0x1111111111111111*i for i in range(13)]
    registers[0]=0xffff0000;registers[7]=0;registers[8]=0
    registers[9]=(0x12345678<<32)|second_pc;registers[10]=0
    expected=registers.copy();expected[7]=iterations;expected[10]=iterations
    # Memoryless kind5 uses address/initial-word slots for the second block PC/price; original ten record meanings/bytes stay fixed.
    rows.append(HEADER.pack(len(wire),5,iterations,second_pc,second_price,0,
        price,max(cycles,second_cycles,halt_cycles),halt_pc,halt_price,halt_cycles,*registers,*expected)+wire)
    return b'PVMBEN01'+struct.pack('<I',len(rows))+b''.join(rows),len(rows)


# Explicit regeneration changes only the owned portable benchmark corpus.
if __name__=='__main__':
    data,count=fixtures();(ROOT/'tests/fixtures/pvm-benchmark.bin').write_bytes(data)
    print(f'{count} benchmark workloads; {HEADER.size}-byte headers')
