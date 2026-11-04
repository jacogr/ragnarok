# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Included private ISA-only register accessors; no source, window, ledger or admission semantics.
when defined(pvmX86ResidentProof):
  type X86ResidentAccess* = object
    ## Zero selects the canonical array; other bytes encode one of six saved hardware GPRs plus one.
    registers: array[13, uint8]

  func x86ResidentAccess*(mask: uint32): X86ResidentAccess =
    ## Ascending guest lanes map deterministically; invalid masks never produce partial machine code.
    assert (mask and not 0x1fff'u32) == 0
    result = default(X86ResidentAccess)
    const hardware = [3'u8, 5, 12, 13, 14, 15] # RBX,RBP,R12..R15 are SysV preserved.
    var count = 0
    for slot in 0..<13:
      if (mask and (1'u32 shl slot)) != 0:
        assert count < hardware.len
        result.registers[slot] = hardware[count]+1
        inc count

  proc readAccess(fragment: var X86Block, access: X86ResidentAccess,
      slot: range[0..12], right: bool) =
    ## RAX/RCX scratch consume current resident values; unmapped lanes keep original array loads.
    let encoded = access.registers[int(slot)]
    if encoded == 0:
      readSlot(fragment, slot, right)
    else:
      let hardware = encoded-1
      put(fragment, [byte(0x48 or (if hardware >= 8: 1 else: 0)), 0x8b,
        byte(0xc0 or (if right: 8 else: 0) or int(hardware and 7))])

  proc writeAccess(fragment: var X86Block, access: X86ResidentAccess, slot: range[0..12]) =
    ## Only the destination changes after old aliased operands have been consumed into scratch.
    let encoded = access.registers[int(slot)]
    if encoded == 0:
      put(fragment, [0x48'u8, 0x89, 0x47, byte(int(slot)*8)])
    else:
      let hardware = encoded-1
      put(fragment, [byte(0x48 or (if hardware >= 8: 1 else: 0)), 0x89,
        byte(0xc0 or int(hardware and 7))])

  proc beginX86Resident*(fragment: var X86Block, access: X86ResidentAccess) =
    ## Save all six SysV GPRs. Entry RSP%16=8; 48 saved plus40 context bytes align it to16.
    assert fragment.bytes.len == 0
    put(fragment, [0x53'u8, 0x55, 0x41, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57,
      0x48, 0x83, 0xec, 0x28])
    # Four incoming borrows occupy fixed slots0/8/16/24; slot32 is reserved scratch, never a guest lane.
    put(fragment, [0x48'u8, 0x89, 0x3c, 0x24, 0x48, 0x89, 0x74, 0x24, 8,
      0x48, 0x89, 0x54, 0x24, 16, 0x48, 0x89, 0x4c, 0x24, 24])
    for slot in 0..<13:
      # Every mapped lane is initialized, including C-only lanes on an earlier-body refusal.
      let encoded = access.registers[slot]
      if encoded != 0:
        let hardware = encoded-1
        put(fragment, [byte(0x48 or (if hardware >= 8: 4 else: 0)), 0x8b,
          byte(0x47 or (int(hardware and 7) shl 3)), byte(slot*8)])

  proc endX86Resident*(fragment: var X86Block, access: X86ResidentAccess) =
    ## One shared exit flushes every initialized mapped lane and restores the complete SysV context.
    for slot in 0..<13:
      let encoded = access.registers[slot]
      if encoded != 0:
        let hardware = encoded-1
        put(fragment, [byte(0x48 or (if hardware >= 8: 4 else: 0)), 0x89,
          byte(0x47 or (int(hardware and 7) shl 3)), byte(slot*8)])
    put(fragment, [0x48'u8, 0x83, 0xc4, 0x28, 0x41, 0x5f, 0x41, 0x5e, 0x41, 0x5d,
      0x41, 0x5c, 0x5d, 0x5b]) # Caller appends its own RET; RAX return value is preserved.

  func x86ResidentImageProof*(fragment: X86Block): seq[byte] =
    ## Copied cold bytes are available only to this private backend's literal image controls.
    fragment.bytes

  proc emitX86ResidentContextProof*(fragment: var X86Block) =
    ## A literal-only observer copies saved incoming pointers and actual stack alignment to argument four.
    put(fragment, [0x4c'u8, 0x8b, 0x54, 0x24, 24]) # R10 selects the private proof output.
    for slot in 0..<4:
      put(fragment, [0x48'u8, 0x8b, 0x44, 0x24, byte(slot*8),
        0x49, 0x89, 0x42, byte(slot*8)])
    put(fragment, [0x48'u8, 0x89, 0xe0, 0x48, 0x83, 0xe0, 15,
      0x49, 0x89, 0x42, 32])

  proc clobberX86ResidentAbiProof*(fragment: var X86Block) =
    ## The negative child deliberately violates RBX after restoration; the C probe must reject it.
    put(fragment, [0x48'u8, 0x31, 0xdb])

  proc residentAbiNative(handle: nil pointer, offset: uint32, registers: pointer,
      context: cint): uint64 {.cdecl, importc: "pvm_x86_resident_access_proof",
      header: "x86_resident_access_proof.h".}
    ## No ordinary caller includes the test-only fixed-hardware-register sentinel function.

  proc callX86ResidentAbiProof*(jit: X86Jit, offset: uint32,
      registers: var RegisterFile, context = false): uint64 =
    ## Invoke only an actual published raw literal image; this grants no Frame/plan authority.
    if jit == nil or int(offset) >= jit.entries.len or jit.arena.handle == nil: return 0
    let code = jit.entries[int(offset)].code
    if code < 2: return 0
    residentAbiNative(jit.arena.handle, code-2, addr registers[0], (
        if context: 1.cint else: 0.cint))

  proc residentCopyNative(handle: nil pointer, offset: uint32, output: pointer,
      length: uint32): cint {.cdecl, importc: "pvm_x86_resident_copy_proof",
      header: "x86_resident_access_proof.h".}
    ## Actual RX bytes remain a test-only copy; executable addresses never escape.

  proc copyX86ResidentImageProof*(jit: X86Jit, offset, length: uint32,
      image: var seq[byte]): bool =
    ## Copy only a bounded published literal image without changing the native owner.
    image = @[]
    if jit == nil or length == 0 or length > 4096 or int(offset) >= jit.entries.len or
        jit.arena.handle == nil: return false
    let code = jit.entries[int(offset)].code
    if code < 2: return false
    image = newSeq[byte](int(length))
    if residentCopyNative(jit.arena.handle, code-2, addr image[0], length) == 0:
      image = @[]
      return false
    true
