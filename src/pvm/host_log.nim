# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JIP-1 host 100: fixed ten-gas response and bounded, escaped operator diagnostics.
## Logging policy and IO never change guest results; see spec/pvm-host-log.md.

import ../lib/logging

import std/syncio
import ./[machine, step]

const LogFieldBytes* = 4096'u64 ## Local user-agent display ceiling per field, independent of gas.

proc quoted(bytes: openArray[byte]): string =
  ## Escape arbitrary guest bytes into a bounded single-line ASCII representation.
  const hex = "0123456789abcdef"
  result = "\""
  for octet in bytes:
    if octet >= 32 and octet <= 126 and octet notin [34'u8, 92'u8]:
      result.add(char(octet)) # Printable non-delimiter bytes remain readable.
    else:
      result.add("\\x") # Never execute terminal controls or interpret invalid UTF-8.
      result.add(hex[int(octet shr 4)])
      result.add(hex[int(octet and 15)])
  result.add('"')

proc logHostResponse*[Context](gas: MachineGas, registers: RegisterFile, memory: Memory,
    context: var Context,
    emit: proc(context: var Context, line: string) {.nimcall, raises: [].},
        recording = true): HostResponse =
  ## Consume 10 gas and always return WHAT; emit exactly once only after both reads succeed.
  ## The trusted synchronous sink borrows one complete escaped line and cannot replace the response.
  result = HostResponse(action: HostAction.Continue, gas: MachineGas(0),
    gasDeficit: GasDeficit(0), registers: registers, memory: memory)
  result.registers[7] = RegisterValue(high(uint64)-1)
  let available = uint64(gas)
  if available < 10:
    result.action = HostAction.OutOfGas # Saturate before unsigned subtraction; never read or log.
    return
  result.gas = MachineGas(available-10)
  if not recording: return # Filter before guest memory reads, allocation and escaping.
  let targetLength = uint64(registers[9])
  let messageLength = uint64(registers[11])
  if targetLength > LogFieldBytes or messageLength > LogFieldBytes:
    return # Local display filtering changes neither gas nor the mandated return value.
  let target = memory.readBytes(MemoryAddress(uint64(registers[8])), MemoryLength(targetLength),
    MemoryByteLimit(LogFieldBytes))
  if target.error != MachineError.None: return # No readable prefix or invalid owner reaches the sink.
  let message = memory.readBytes(MemoryAddress(uint64(registers[10])), MemoryLength(messageLength),
    MemoryByteLimit(LogFieldBytes))
  if message.error != MachineError.None: return # Validate the second interval before emitting either field.
  let targetText = if uint64(registers[8]) == 0 and targetLength == 0: "null"
    else: quoted(target.value) # A nonzero pointer with zero length is a present empty target.
  emit(context, "JIP1 level=" & $uint64(registers[7]) & " target=" & targetText &
    " message=" & quoted(message.value))

proc consoleLog(unused: var bool, line: string) {.raises: [].} =
  ## Best-effort diagnostic output; syncio records write errors without raising into the guest.
  stderr.writeLine(line)

proc logHostResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory): HostResponse =
  ## Production adapter uses stderr without global mutable sink configuration or retained guest bytes.
  var unused = false
  logHostResponse(gas, registers, memory, unused, consoleLog)

func guestLogLevel*(value: uint64): LogLevel =
  ## JIP-1 levels preserve their suggested meaning; unrecognized numeric levels are trace-only.
  case value
  of 0: LogLevel.Fatal
  of 1: LogLevel.Warn
  of 2: LogLevel.Info
  of 3: LogLevel.Debug
  else: LogLevel.Trace

type GuestLogContext = object ## Stack-local adapter retains only the application-owned producer borrow.
  writer: LogWriter
  level: LogLevel
proc sharedLog(context: var GuestLogContext, line: string) {.raises: [].} =
  ## The same bounded shared queue serves guest and ordinary application diagnostics.
  discard submitLog(context.writer, LogTarget.Pvm, context.level, line)
proc logHostResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory,
    writer: LogWriter): HostResponse =
  ## Explicit application policy controls logging, never the guest response or ten-gas price.
  if not writer.configured: return logHostResponse(gas, registers, memory)
  let level = guestLogLevel(uint64(registers[7]))
  var context = GuestLogContext(writer: writer, level: level)
  logHostResponse(gas, registers, memory, context, sharedLog, writer.enabled(LogTarget.Pvm, level))
