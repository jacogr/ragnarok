# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# Independent complete fixture leaf for pvm_checked_read_body_witness.nim.
# Bind literal decoded operands, the three extent guards and both SysV exits.
.intel_syntax noprefix
.text

# Use rel32 even for nearby labels so the assembler cannot relax the encoding.
.macro near_cond opcode, target
    .byte 0x0f, \opcode
    .long \target - . - 4
.endm

.macro near_jump target
    .byte 0xe9
    .long \target - . - 4
.endm

# ADD EDX,imm32, including the signed -1 displacement without imm8 relaxation.
.macro address slot, displacement
    mov edx, dword ptr [rdi + 8*\slot]  # Read the old staged base.
    .byte 0x81, 0xc2                    # ADD EDX,imm32 wraps and zero-extends.
    .long \displacement
.endm

# One extent has length at +8 and the data pointer at +16.
.macro extent field, width, accepted
    mov rcx, qword ptr [r10 + \field + 8]   # Load the unsigned extent length.
    sub rcx, \width                          # Compute the last legal offset.
    near_cond 0x82, .Lskip\@                 # JB skips a short extent.
    mov rax, rdx                             # Keep RDX for the next extent.
    .byte 0x49, 0x2b, 0x42, \field           # SUB RAX,[R10+disp8], including zero.
    cmp rax, rcx                             # A below-start offset wraps large.
    near_cond 0x87, .Lskip\@                 # JA skips any incomplete load.
    mov rcx, qword ptr [r10 + \field + 16]  # Fetch data only after both bounds.
    near_jump \accepted                      # Keep the proved pointer and offset.
.Lskip\@:
.endm

.macro extents width, accepted
    extent 0, \width, \accepted
    extent 24, \width, \accepted
    extent 48, \width, \accepted
    near_jump .Lrefuse                       # All three extents missed.
.endm

sub rsp, 104                         # Reserve the complete private register stage.
mov r10, rsi                         # Save the extent table.
mov r11, rdi                         # Save the original register file.
mov rsi, rdi                         # Copy from the original file.
mov rdi, rsp                         # Copy to the stage.
mov ecx, 13                          # Copy all thirteen qwords.
rep movsq                            # SysV enters with the direction flag clear.
mov rdi, rsp                         # Restore the stage base for slot addressing.

address 1, 0x10002                   # R1 = U8[(low32(old R1)+0x10002) mod 2^32].
extents 1, .Lu8
.Lu8:
movzx eax, byte ptr [rcx + rax]     # Zero-extend the admitted byte.
mov qword ptr [rdi + 8], rax        # Stage the aliased result in R1.

mov rax, qword ptr [rdi + 8]        # Read the newly staged R1.
movabs rcx, 0x10000                  # Materialize the fixture's scalar immediate.
add rax, rcx                         # Apply the full-width wrapping add.
mov qword ptr [rdi + 8], rax        # Stage the new address in R1.

address 1, -1                       # R2 = S32[(low32(new R1)-1) mod 2^32].
extents 4, .Ls32
.Ls32:
movsxd rax, dword ptr [rcx + rax]   # Sign-extend the admitted dword.
mov qword ptr [rdi + 16], rax       # Stage R2.

address 5, 0                        # R4 = U64[low32(R5)].
extents 8, .Lu64
.Lu64:
mov rax, qword ptr [rcx + rax]      # Read all eight admitted bytes.
mov qword ptr [rdi + 32], rax       # Stage R4.

mov rax, qword ptr [rdi + 8]        # Read final staged R1.
mov qword ptr [r11 + 8], rax        # Commit R1 only after the last guard.
mov rax, qword ptr [rdi + 16]       # Read final staged R2.
mov qword ptr [r11 + 16], rax       # Commit R2.
mov rax, qword ptr [rdi + 32]       # Read final staged R4.
mov qword ptr [r11 + 32], rax       # Commit R4.
mov eax, 1                           # Return shared success.
add rsp, 104                         # Release the stage.
ret                                  # Return with the original stack.

.Lrefuse:
mov eax, 0xffffffff                  # Return ordinary refusal without a caller store.
add rsp, 104                         # Discard the entire stage.
ret                                  # Return with the original stack.
