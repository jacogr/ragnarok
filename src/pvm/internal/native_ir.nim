# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Bounded copied register IR shared by every native lowerer. No invocation state is retained.

import std/assertions
import ../program
import ./jit_rules

const
  NativeSpanOperations* = 64   ## One independently compiled non-exiting span, not a profitability floor.
  NativeMinimumOperations* = 2 ## Structural span floor shared by both lowerers.
  NativeEntryLimit* = 262144'u32 ## Existing native-coordinate ceiling, with an exclusive past endpoint.
  NativeImageByteLimit* = 4096 ## Complete image including return on either ISA.
  NativeSessionLimit* = 4      ## Live, installed and retiring code registrations share these credits.
  NativeInvocationFloor* = 4096'u64 ## Initial shared coarse policy; deliberately not a measured break-even.

type
  NativeKind* {.pure.} = enum ## The image kind selects its exact call ABI.
    PurePrefix, ClosedRegisterLoop, CheckedReadBody
  NativeLoopRightKind* {.pure.} = enum ## Right operand of the certified unsigned comparison.
    Register, Immediate
  NativeLoopInfo* = object  ## Copied source certificate for one resolved whole block.
    header*, exitHeader*: uint32
    sourceSpan*: uint32     ## Zero identifies an unpromoted pure prefix.
    price*: uint64
    slots*: RegisterSlots   ## Original unsigned branch operands.
    rightKind*: NativeLoopRightKind
    rightImmediate*: uint64 ## Exact checked sign extension for an immediate comparison.
  NativeLoopContext* = object ## Fresh two-borrow entry context: gas, quota and visits at 0/8/16.
    gas*, remaining*, visits*: uint64
  NativeOperation* = object ## Copied validated semantics; register coordinates are not register values.
    opcode*: byte
    slots*: RegisterSlots
    immediate*: uint64
  NativeSpanInfo* = object ## Small copied call certificate, never a hot-path copy of the fixed IR array.
    entry*, past*, first*, last*: uint32
    epoch*: uint64
    length*: int
  NativeSpan* = object ## Private fixed IR and exact source/node continuation certificate; no ARC graph crosses threads.
    operations: array[NativeSpanOperations, NativeOperation]
    length: int
    entryValue, pastValue, firstValue, lastValue: uint32
    epochValue: uint64
    loopValue: NativeLoopInfo

func kind*(loop: NativeLoopInfo): NativeKind =
  ## Only a complete source certificate selects the region ABI.
  if loop.sourceSpan == 0: NativeKind.PurePrefix else: NativeKind.ClosedRegisterLoop

func loopInfo*(span: NativeSpan): NativeLoopInfo {.inline.} =
  ## Copy only the closed loop certificate, with an empty value for a pure prefix.
  span.loopValue

func kind*(span: NativeSpan): NativeKind {.inline.} =
  ## Read the exact candidate kind without copying its call certificate.
  span.loopValue.kind

proc promote*(span: var NativeSpan, loop: NativeLoopInfo) =
  ## The session owns promotion authority and has validated the checked source certificate.
  assert span.loopValue.sourceSpan == 0 and loop.sourceSpan != 0
  span.loopValue = loop

func initNativeSpan*(entry, first: uint32, epoch: uint64): NativeSpan =
  ## Start an unpublished candidate at an existing checked node and original source fact.
  NativeSpan(entryValue: entry, firstValue: first, epochValue: epoch)

proc add*(span: var NativeSpan, opcode: byte, slots: RegisterSlots, immediate: uint64,
    last, past: uint32): bool =
  ## Reject unsupported/oversized spans before writing any IR; only the common semantic subset is eligible.
  if span.length == NativeSpanOperations or not supportedScalarOpcode(opcode): return false
  let maximumDistance = uint32(NativeSpanOperations)
  if span.epochValue == 0 or last < span.firstValue or last-span.firstValue >= maximumDistance or
      past <= span.entryValue or past > NativeEntryLimit: return false
  span.operations[span.length] = NativeOperation(opcode: opcode, slots: slots, immediate: immediate)
  inc span.length
  span.lastValue = last
  span.pastValue = past
  true

func len*(span: NativeSpan): int =
  ## Copy the populated fixed-array extent, never an exposed mutable IR array.
  span.length

func operation*(span: NativeSpan, index: int): NativeOperation {.requires:
    index >= 0 and index < span.length.} =
  ## Copy one admitted operation into a lowerer's private builder.
  span.operations[index]

func entry*(span: NativeSpan): uint32 =
  ## Existing checked node to replace only under the owning stream epoch.
  span.entryValue

func past*(span: NativeSpan): uint32 =
  ## Already admitted continuation; native code never resolves a new source target.
  span.pastValue

func first*(span: NativeSpan): uint32 =
  ## Original fact ordinal, separate from folded stream-node coordinates.
  span.firstValue

func last*(span: NativeSpan): uint32 =
  ## Last original fact included in the complete pure prefix.
  span.lastValue

func epoch*(span: NativeSpan): uint64 =
  ## Exact rebuild namespace; moving the stream does not change it.
  span.epochValue

func info*(span: NativeSpan): NativeSpanInfo =
  ## Copy only scalar coordinates for installation/entry; compiler IR is copied only into a job.
  NativeSpanInfo(entry: span.entryValue, past: span.pastValue, first: span.firstValue,
    last: span.lastValue, epoch: span.epochValue, length: span.length)

func len*(span: NativeSpanInfo): int =
  ## Source operation count in the scalar call certificate.
  span.length
