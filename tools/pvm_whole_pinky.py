#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Initial Pinky whole-image diagnostic: unchanged guest, checked memory, gas-off ARM64 and sealed controls."""
from pvm_whole_sieve import replace_once, run


def pinky_projection(source):
    """Add nine-frame initialization scope and actual framebuffer checks outside the maintained run clocks."""
    source=replace_once(source,'    let module = module(blob);', '''    let framebuffer_entry=blob.exports().find(|export| export == "get_framebuffer").unwrap().program_counter();
    let module = module(blob);''')
    source=replace_once(source,'        initial = instance(&module, entry, &registers);\n        assert_eq!(initial.run().unwrap(), InterruptKind::Finished);', '''        let initialize_cpu=cpu_nanoseconds();
        let initialize_wall=Instant::now();
        initial = instance(&module, entry, &registers);
        assert_eq!(initial.run().unwrap(), InterruptKind::Finished);
        println!("PINKY_INITIALIZE,{},{},9",cpu_nanoseconds()-initialize_cpu,initialize_wall.elapsed().as_nanos());''')
    # The getter mutates only an instance already checked/snapshotted and about to be dropped.
    # No extra run, readback, hashing or frame comparison enters the guest execution clock.
    helper='''// Read the actual public framebuffer after the complete snapshot; this instance is retired afterward.
fn pinky_frame(instance: &mut RawInstance, entry: polkavm::ProgramCounter, stack: u64) -> (u32,Vec<u8>) {
    instance.set_reg(Reg::RA,0xffff0000);
    instance.set_reg(Reg::SP,stack);
    instance.set_gas(GAS);
    instance.set_next_program_counter(entry);
    assert_eq!(instance.run().unwrap(),InterruptKind::Finished);
    let address=u32::try_from(instance.reg(Reg::A0)).unwrap();
    assert!(address>=65536 && u64::from(address)+245760<=0x100000000);
    let bytes=instance.read_memory(address,245760).unwrap();
    assert_eq!(bytes.len(),245760);
    (address,bytes)
}

'''
    source=replace_once(source,'// Bounded explicit commands separate reference preparation',helper+'// Bounded explicit commands separate reference preparation')
    source=replace_once(source,'        if guest == Guest::Sieve {\n            // Preserve', '''        assert!(guest == Guest::Pinky);
        let (address,frame)=pinky_frame(&mut instance,framebuffer_entry,registers[1]);
        fs::write(output.join("frame-address.txt"),address.to_string()).unwrap();
        fs::write(output.join("frame-abgr.bin"),frame).unwrap();
        println!("PINKY_FRAME_ORACLE,{address},245760");
        if guest == Guest::Sieve {
            // Preserve''')
    source=replace_once(source,'        println!("SIEVE,polkavm_interpreter,{limit},{sample},{elapsed},{cpu_elapsed}");', '''        let (address,frame)=pinky_frame(&mut instance,framebuffer_entry,registers[1]);
        assert_eq!(address.to_string(),fs::read_to_string(output.join("frame-address.txt")).unwrap());
        assert!(frame==fs::read(output.join("frame-abgr.bin")).unwrap(),"Pinky rendered frame mismatch");
        println!("PINKY_FRAME,{sample},{address},245760");
        println!("SIEVE,polkavm_interpreter,{limit},{sample},{elapsed},{cpu_elapsed}");''')
    source=replace_once(source,'println!("FAST_SEQUENCE_OK,sieve,{samples}");','println!("FAST_SEQUENCE_OK,pinky,{samples}");')
    return source


if __name__=='__main__':
    run('pinky')
