# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Initialize the PVM for a prepared accumulation invocation at the fixed GP entry point.
## Exposes bounded initialization, retained bootstrap/machine access and guarded typed failures.
## Initialization performs no guest execution, host mutation or state publication.

import ../pvm/[initialize, machine, program]
import ./[accumulation_invocation, accumulation_service]

type
  AccumulationHeapBounds* = object ## Copied envelope-derived heap interval under the adopted GP #538 zone reservation.
    first*, past*: PageIndex ## Half-open RW region; past reserves the stack in 64 KiB zones.
  AccumulationMachineError* {.pure.} = enum ## Adapter failures distinguish invalid ownership, local policy and malformed executable inputs.
    Uninitialized, None, InvalidInvocation, LimitExceeded, InvalidEnvelope, InvalidProgram
  ## Private acyclic storage binds the initialized CPU to the exact immutable invocation provenance.
  AccumulationMachineData = ref object
    bootstrap: PreparedAccumulationInvocation
    machine: Machine
    heap: AccumulationHeapBounds
  PreparedAccumulationMachine* = object ## A prepared CPU is not an executed Psi_A result or an authenticated block certificate.
    data: nil AccumulationMachineData
  AccumulationMachineResult*[T] = object ## Only complete success exposes an owner or retained child; failures have no partial machine.
    case status: AccumulationMachineError
    of None:
      completed: T # Extract only through the selected-success accessor.
    else:
      discard      # No default or failed payload.

func error*[T](outcome: AccumulationMachineResult[T]): AccumulationMachineError =
  ## Inspect the outcome without granting mutable access to its discriminator.
  outcome.status
func value*[T](outcome: AccumulationMachineResult[T]): T {.inline,
    requires: outcome.status == AccumulationMachineError.None.} =
  ## Retain selected success under compiler and runtime result contracts.
  outcome.completed

proc machineBootstrap*(prepared: PreparedAccumulationMachine): AccumulationMachineResult[
    PreparedAccumulationInvocation] =
  ## Retain the exact initialization source independently of this machine wrapper.
  let data = prepared.data
  if data == nil:
    # Default wrappers cannot fabricate service provenance.
    return AccumulationMachineResult[PreparedAccumulationInvocation](
      status: AccumulationMachineError.Uninitialized)
  AccumulationMachineResult[PreparedAccumulationInvocation](status: AccumulationMachineError.None,
    completed: data.bootstrap)

proc accumulationMachine*(prepared: PreparedAccumulationMachine): AccumulationMachineResult[Machine] =
  ## Retain the immutable initial CPU; execution produces independent successor snapshots.
  let data = prepared.data
  if data == nil:
    # No successful empty machine is substituted for an uninitialized owner.
    return AccumulationMachineResult[Machine](status: AccumulationMachineError.Uninitialized)
  AccumulationMachineResult[Machine](status: AccumulationMachineError.None, completed: data.machine)

proc machineHeapBounds*(prepared: PreparedAccumulationMachine): AccumulationMachineResult[
    AccumulationHeapBounds] =
  ## Copy envelope-derived heap bounds from the exact immutable initialized machine owner.
  let data = prepared.data
  if data == nil:
    return AccumulationMachineResult[AccumulationHeapBounds](
      status: AccumulationMachineError.Uninitialized) # Default owners cannot fabricate geometry.
  AccumulationMachineResult[AccumulationHeapBounds](status: AccumulationMachineError.None,
    completed: data.heap)

# Decode an E3 field only after the standard initializer proves exact envelope framing and extents.
func envelopeField(code: openArray[byte], offset: int): uint64 =
  result = 0
  for index in 0..<3:
    # The successful initializer guarantees these fixed header positions exist; shifts fit uint64.
    result = result or (uint64(code[offset+index]) shl (index*8))

# E3 lengths are at most 2^24-1, so adding 65535 and zone rounding cannot overflow uint64.
func envelopeHeapBounds(code: openArray[byte]): AccumulationHeapBounds =
  let readOnly = envelopeField(code, 0)
  let stack = envelopeField(code, 8)
  let roZones = (readOnly+65535) div 65536
  let stackZones = (stack+65535) div 65536
  # Fixed envelope widths prove both endpoints fit the 2^20 page domain and first <= past.
  AccumulationHeapBounds(first: PageIndex(uint32(32+roZones*16)),
    past: PageIndex(uint32((0xfefd0000'u64-stackZones*65536) div 4096)))

proc initializeAccumulationMachine*(bootstrap: PreparedAccumulationInvocation,
    limits: InitializationLimits): AccumulationMachineResult[PreparedAccumulationMachine] =
  ## Use the bootstrap's own code, compact arguments and declared gas at the fixed accumulation PC 5.
  ## Bound the complete code copy before extraction; the standard initializer bounds program and pages.
  ## The bootstrap has already enforced code eligibility. Malformed envelopes/programs remain typed local
  ## preparation failures, not fabricated Psi_M/Psi_A panic, gas usage or posterior-state results.
  ## Refuse without publishing a partial program, memory or retained initialization wrapper.
  template fail(reason: AccumulationMachineError) =
    return AccumulationMachineResult[PreparedAccumulationMachine](status: reason)
  let selected = bootstrap.bootstrapService
  if selected.error != AccumulationInvocationError.None:
    fail(AccumulationMachineError.InvalidInvocation) # A default bootstrap cannot select service code.
  let service = selected.value
  let info = service.serviceInfo.value
  if uint64(info.codeBytes) > uint64(limits.envelope):
    fail(AccumulationMachineError.LimitExceeded) # Apply local envelope policy before allocating its copy.
  let code = service.serviceCode
  if code.error != AccumulationServiceError.None:
    fail(AccumulationMachineError.InvalidInvocation) # Only the bootstrap's original eligible code is usable.
  let arguments = bootstrap.bootstrapArguments.value
  let initialized = initializeMachine(code.value, arguments, CodeAddress(5),
    MachineGas(uint64(info.gas)), limits)
  case initialized.error
  of InitializationError.None:
    # Keep the original bootstrap beside the complete immutable CPU without introducing back-references.
    AccumulationMachineResult[PreparedAccumulationMachine](status: AccumulationMachineError.None,
      completed: PreparedAccumulationMachine(data: AccumulationMachineData(
        bootstrap: bootstrap, machine: initialized.value, heap: envelopeHeapBounds(code.value))))
  of InitializationError.LimitExceeded:
    fail(AccumulationMachineError.LimitExceeded) # Local policy exhaustion is never a consensus panic.
  of InitializationError.InvalidEnvelope:
    fail(AccumulationMachineError.InvalidEnvelope) # Account code eligibility does not validate JAM framing.
  of InitializationError.InvalidProgram:
    fail(AccumulationMachineError.InvalidProgram) # Raw code and the mandatory entry must be executable.
  else:
    fail(AccumulationMachineError.InvalidInvocation) # Impossible argument/default failures expose no CPU.
