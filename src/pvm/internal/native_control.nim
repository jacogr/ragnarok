# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed shared control program for a checked first reservation followed by full native visits.

import ./native_ir

type
  LoopLabel* {.pure.} = enum ## Symbolic machine labels, independent of stream coordinates.
    Body, ReturnHeader, ReturnExit, Commit
  LoopLane* {.pure.} = enum ## Unsigned accounting operands.
    Gas, Remaining
  LoopActionKind* {.pure.} = enum ## Mechanical actions consumed in order by each encoder.
    LoadContext, LoadGuest, Label, ExecuteBody, CountVisit, BranchGuestAboveEqual,
    BranchLaneBelow, DebitLane, Jump, SelectReturn, StoreGuest, StoreContext, Return
  LoopAction* = object ## Only the action's relevant operands are consumed by an encoder.
    kind*: LoopActionKind
    target*: LoopLabel
    lane*: LoopLane
    value*: uint64
  LoopControl* = array[20, LoopAction] ## Fixed scaffold; ExecuteBody refers to the bounded scalar IR.

func loopControl*(loop: NativeLoopInfo): LoopControl =
  ## Execute the paid body first. Each backedge reserves the entire next visit or returns unpaid H.
  [LoopAction(kind: LoadContext),
    LoopAction(kind: LoadGuest),
    LoopAction(kind: Label, target: Body),
    LoopAction(kind: ExecuteBody),
    LoopAction(kind: CountVisit),
    LoopAction(kind: BranchGuestAboveEqual, target: ReturnExit),
    LoopAction(kind: BranchLaneBelow, lane: Remaining, value: uint64(loop.sourceSpan),
      target: ReturnHeader),
    LoopAction(kind: BranchLaneBelow, lane: Gas, value: loop.price, target: ReturnHeader),
    LoopAction(kind: DebitLane, lane: Gas, value: loop.price),
    LoopAction(kind: DebitLane, lane: Remaining, value: uint64(loop.sourceSpan)),
    LoopAction(kind: Jump, target: Body),
    LoopAction(kind: Label, target: ReturnHeader),
    LoopAction(kind: SelectReturn, value: uint64(loop.header)),
    LoopAction(kind: Jump, target: Commit),
    LoopAction(kind: Label, target: ReturnExit),
    LoopAction(kind: SelectReturn, value: uint64(loop.exitHeader)),
    LoopAction(kind: Label, target: Commit),
    LoopAction(kind: StoreGuest),
    LoopAction(kind: StoreContext),
    LoopAction(kind: Return)]
