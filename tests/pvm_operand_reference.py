# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent pinned-paper operand equations over complete, globally zero-padded guest code."""
from pathlib import Path
import struct
from pvm_gas_reference import tables

ROOT=Path(__file__).resolve().parents[1]
ROW=struct.Struct('<II8BQQq')
DESCRIPTORS=(0,1,4,7,8,0x70,0x80,0xf7,0xff)
COUNT=139*25*len(DESCRIPTORS)*2


# Classify the thirteen literal opcode groups from the pinned paper, not runtime reflection.
def shape(op):
    if op<=2:return 0
    if op==10:return 1
    if op==20:return 2
    if 30<=op<=33:return 3
    if op==40:return 4
    if 50<=op<=62:return 5
    if 70<=op<=73:return 6
    if 80<=op<=90:return 7
    if 100<=op<=110:return 8
    if 120<=op<=161:return 9
    if 170<=op<=175:return 10
    if op==180:return 11
    if 190<=op<=230:return 12
    raise ValueError('Unknown paper opcode')


# Evaluate mathematical little-endian reads with the paper's infinite zero suffix.
def operands(code,pc,skip):
    def read(start,width,signed=False):
        value=int.from_bytes(bytes(code[start:start+width]).ljust(width,b'\0'),'little')
        if signed and width and value&(1<<(8*width-1)):value-=1<<(8*width)
        return value
    kind=shape(code[pc]);first=read(pc+1,1)
    a=b=d=jam=0;x=y=displacement=0
    if kind in (2,5,6,7):a=min(first%16,12)
    if kind in (9,10,11,12):a,b=min(first%16,12),min(first//16,12)
    if kind==1:x=read(pc+1,min(4,skip),True)
    elif kind==2:x=read(pc+2,8)
    elif kind in (3,6,7,11):
        descriptor=read(pc+2,1) if kind==11 else first
        width=min(4,(descriptor//16 if kind in (6,7) else descriptor)%8)
        start=pc+(3 if kind==11 else 2)
        second=min(4,max(0,skip-width-(2 if kind==11 else 1)))
        x=read(start,width,True)
        if kind==7:displacement=read(start+width,second,True)
        else:y=read(start+width,second,True)
    elif kind==4:displacement=read(pc+1,min(4,skip),True)
    elif kind==5:x=read(pc+2,min(4,max(0,skip-1)),True)
    elif kind==8:d,jam,a=min(first%16,12),min(first%16,12),min(first//16,12)
    elif kind==9:x=read(pc+2,min(4,max(0,skip-1)),True)
    elif kind==10:displacement=read(pc+2,min(4,max(0,skip-1)),True)
    elif kind==12:
        encoded=read(pc+2,1);d,jam=min(encoded,12),min(encoded%16,12)
    return kind,a,b,d,jam,x% (1<<64),y% (1<<64),displacement


# Frozen rows carry complete original blobs; following marked instructions remain operand-read bytes.
def fixtures():
    rows=[]
    for op in sorted(tables()[0]):
        for skip in range(25):
            for variant,descriptor in enumerate(DESCRIPTORS):
                for pc in (0,3):
                    prefix=bytes((51,7,128)) if pc else b''
                    payload=bytes((descriptor,0xff,0x80,0x7f,0,0x81,0x55,0xaa))*3
                    code=prefix+bytes((op,))+payload[:skip]+bytes((51,8,128,0))
                    starts=([0] if pc else [])+[pc,pc+skip+1,pc+skip+4]
                    mask=bytearray((len(code)+7)//8)
                    for at in starts:mask[at//8]|=1<<(at%8)
                    wire=bytes((0,0,len(code)))+code+mask
                    kind,a,b,d,jam,x,y,disp=operands(code,pc,skip)
                    rows.append(ROW.pack(len(wire),pc,op,skip,kind,a,b,d,jam,variant,x,y,disp)+wire)
    assert len(rows)==COUNT
    return b'PVMOPR01'+struct.pack('<I',COUNT)+b''.join(rows),COUNT


# Regeneration is explicit and independent; ordinary native replay never invokes upstream Rust.
if __name__=='__main__':
    data,count=fixtures();(ROOT/'tests/fixtures/pvm-operand.bin').write_bytes(data)
    print(f'{count} complete operand-shape witnesses')
