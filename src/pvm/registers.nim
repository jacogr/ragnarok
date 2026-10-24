# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 register-only instruction mutations; see spec/pvm-registers.md. This evaluator does
## not advance PC, charge gas or publish a machine execution step.
##
## Exposes registerOnlyOpcode, evaluateRegisterWrite, evaluateRegisters and guarded scalar/array results
## and applyRegisterWrite for caller-owned register arrays in the implemented arithmetic/logic subset.

import ./[program, machine]
import ./internal/register_ops

type
  RegisterError* {.pure.} = enum ## Unsupported instructions are scope failures, not guest traps; no partial registers escape.
    Uninitialized, None, InvalidInstruction, UnsupportedInstruction
  RegisterResult* = object ## The fixed register array is copied on success and inaccessible for every failure alternative.
    case status: RegisterError
    of None:
      # No references or mutable storage are shared with the input register file.
      completed: RegisterFile
    else:
      # Failed/default alternatives carry only their reason.
      discard

  RegisterWriteResult* = object ## Successful arithmetic evaluation identifies one copied destination/value; failures grant neither.
    case status: RegisterError
    of None:
      # Only the evaluator can create a validated write from an owned decoded instruction.
      completedIndex: range[0..12]
      completedValue: RegisterValue
    else:
      # Default/invalid/unsupported alternatives contain no writable register selection.
      discard

func error*(r: RegisterWriteResult): RegisterError =
  ## Inspect scalar evaluation status without authorizing either success field.
  r.status
func destination*(r: RegisterWriteResult): RegisterIndex {.inline, requires: r.status ==
    RegisterError.None.} =
  ## Select success before obtaining the evaluator's bounded destination index.
  RegisterIndex(byte(r.completedIndex))
func writeValue*(r: RegisterWriteResult): RegisterValue {.inline, requires: r.status ==
    RegisterError.None.} =
  ## Return a copied register-width bit pattern only for a successful evaluation.
  r.completedValue

proc applyRegisterWrite*(registers: var RegisterFile, r: RegisterWriteResult) {.inline,
    requires: r.status == RegisterError.None.} =
  ## Apply exactly one successful copied write to caller-owned registers; no failed/default payload can authorize mutation.
  registers[r.completedIndex] = r.completedValue

func error*(r: RegisterResult): RegisterError =
  ## Inspect the reason without permitting result retagging.
  r.status
func value*(r: RegisterResult): RegisterFile {.inline, requires: r.status == RegisterError.None.} =
  ## Select success before extracting the copied register file.
  r.completed

func registerOnlyOpcode*(opcode: byte): bool =
  ## Identify the complete register-only scope through the shared internal opcode set.
  isRegisterOpcode(opcode)

proc evaluateRegisterWrite*(decoded: ProgramResult[Instruction],
    registers: RegisterFile): RegisterWriteResult {.inline.} =
  ## Preserve guarded public scalar results while sharing the dispatch arithmetic implementation.
  if decoded.error != ProgramError.None:
    # Invalid/default instructions carry no authorized destination or value.
    return RegisterWriteResult(status: RegisterError.InvalidInstruction)
  var index: range[0..12] = 0
  var value = RegisterValue(0)
  if not computeRegisterWrite(decoded, registers, index, value):
    # Unsupported instructions cannot authorize a register write.
    return RegisterWriteResult(status: RegisterError.UnsupportedInstruction)
  RegisterWriteResult(status: RegisterError.None, completedIndex: index, completedValue: value)

proc evaluateRegisters*(decoded: ProgramResult[Instruction],
    registers: RegisterFile): RegisterResult =
  ## Compatibility evaluation materializes the complete copied array only after the scalar write succeeds.
  let written = evaluateRegisterWrite(decoded, registers)
  if written.error != RegisterError.None:
    return RegisterResult(status: written.error) # Failed scalar results carry no destination or value.
  var copied = registers
  applyRegisterWrite(copied, written)
  RegisterResult(status: RegisterError.None, completed: copied)

proc evaluateRegisters*(program: Program, pc: CodeAddress,
    registers: RegisterFile): RegisterResult =
  ## Look up one owned instruction and evaluate its register mutation without advancing PC or gas.
  ## This compatibility entry point retains the same validation, scope and copied-register contract.
  evaluateRegisters(instruction(program, pc), registers)
