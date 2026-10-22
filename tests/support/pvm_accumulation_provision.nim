# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored prepared guest programs for provision host execution and strict failed-result probes.
## Exposes literal full-width register calls, requested source maps and bounded dispatcher invocation.

import std/assertions
import ../../src/state/[accumulation_machine, accumulation_dispatch, accumulation_context, accumulation_effects]
import ../../src/codec/[bounded, assurances, composite, state_accounts, state_requests,
  state_service_values, state_authorization, state_safrole, state_privileges, state_layout, state_trie]
import ../../src/crypto/primitives
import ../../src/pvm/[initialize, machine, program, host_fetch, step, gas]
import ./pvm_accumulation_context

type
  ProvisionGuestCall* = object ## Test-only call descriptors expose all register bits; only provide/yield load their relevant arguments.
    id*: byte
    r7*, r8*, r9*: uint64

proc provisionConfig*(): AccumulationContextConfig =
  ## Exact tiny-profile chapter ceilings are independent from provision retention and guest-memory limits.
  AccumulationContextConfig(validators: ValidatorCount(6),
    queues: AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
        maxBytes: ByteLimit(5120)),
    staging: ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
        maxBytes: ByteLimit(2017)),
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(0),
        maxBytes: ByteLimit(100)),
    totalBytes: ByteLimit(10000))

proc provisionPolicy*(items = 8'u64, perBlob = 4096'u64,
    total = 8192'u64): AccumulationProvisionLimits =
  ## Explicit small finite budgets admit exact-boundary tests without allocating hostile guest lengths.
  AccumulationProvisionLimits(items: ElementLimit(items), perBlob: ByteLimit(perBlob),
      totalBlobBytes: ByteLimit(total))

proc provisionRequest*(service: uint32, bytes: seq[byte], history: seq[byte] = @[
    0'u8]): StateEntry =
  ## Use the maintained namespace primitive to prepare real canonical outstanding/history records.
  let digest = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  StateEntry(key: serviceRequestKey(ServiceIndex(service), digest, RequestLength(uint32(bytes.len)),
    ByteLimit(32)).value, value: history)

proc provisionMachine*(calls: openArray[ProvisionGuestCall], data: seq[byte] = @[9'u8, 8, 7],
    credit = 100000'u64, history: seq[byte] = @[0'u8], requested = true,
    malformedAccount = false, extra: seq[StateEntry] = @[]): PreparedAccumulationMachine =
  ## Prepare real account/code/request backing and a literal guest program with fixed accumulation entry PC 5.
  assert calls.len <= 32 and data.len <= 4096 # Authored fixture sizes stay within fixed helper framing and page policies.
  var code = @[0'u8, 0, 0, 0, 0]
  var starts = @[0, 1, 2, 3, 4]
  # Extended-immediate opcodes set all uint64 bits without relying on signed four-byte immediate inference.
  for call in calls:
    let count = if call.id == 28: 3 elif call.id == 27: 1 else: 0
    let registers = [call.r7, call.r8, call.r9]
    for ordinal in 0..<count:
      starts.add(code.len)
      code.add(20); code.add(byte(7+ordinal))
      for offset in 0..<8: code.add(byte((registers[ordinal] shr (8*offset)) and
          255)) # Independent E8 register payload.
    starts.add(code.len)
    code.add(10); code.add(call.id)
  starts.add(code.len)
  code.add(50); code.add(0)
  assert code.len < 16384 # The helper deliberately supports only one/two-byte compact program lengths.
  var raw = @[0'u8, 0]
  if code.len < 128:
    raw.add(byte(code.len)) # One-byte compact natural.
  else:
    raw.add(byte(128+(code.len shr 8))); raw.add(byte(code.len and 255)) # Independent two-byte compact natural.
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or byte(1 shl (
      start mod 8)) # Exact instruction boundaries.
  for octet in mask: raw.add(octet)
  var envelope = @[byte(data.len and 255), byte(data.len shr 8), 0'u8, 1, 0, 0, 1, 0, 1, 0, 0]
  for octet in data: envelope.add(octet) # RO bytes start at physical address 65536.
  envelope.add(81)
  for offset in 0..<4: envelope.add(byte((uint64(raw.len) shr (8*offset)) and
      255)) # Independent E4 executable extent.
  for octet in raw: envelope.add(octet)
  let config = provisionConfig()
  var entries = @[
    authorizationEntry(AuthorizationKind.Queues, @[newSeq[AuthorizerHash](80),
      newSeq[AuthorizerHash](80)], config.queues).value,
    validatorEntry(ValidatorChapter.Staging, newSeq[StateValidator](6), config.staging).value,
    privilegeStateEntry(PrivilegeState(assigners: @[ServiceIndex(0), ServiceIndex(0)]),
        config.privileges).value]
  # Self metadata comes from pvmBootstrap; other targets include both nominal index boundaries.
  for service in [0'u32, 42'u32, 99'u32, high(uint32)]:
    if service != 42:
      if malformedAccount and service == 99:
        entries.add(StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(service)),
            value: @[0'u8])) # Corrupt local state.
      else:
        entries.add(serviceMetadataEntry(ServiceIndex(service), default(ServiceMetadata), ByteLimit(
            ServiceMetadataBytes)).value)
    if requested:
      entries.add(provisionRequest(service, data, history)) # An empty sequence is encoded as canonical outstanding history.
      if data.len > 0: entries.add(provisionRequest(service, @[],
          history)) # Empty blobs are distinct requested values.
  for entry in extra: entries.add(entry)
  initializeAccumulationMachine(pvmBootstrap(envelope, credit, extra = entries),
    InitializationLimits(envelope: InitializationByteLimit(10000), program: ProgramByteLimit(4096),
      jumps: JumpCountLimit(0), pages: PageLimit(5))).value

proc runProvision*(prepared: PreparedAccumulationMachine,
    policy: AccumulationProvisionLimits = provisionPolicy(), copyBytes = 4096'u64,
    steps = 200'u64, calls = 32'u64): AccumulationDispatchResult =
  ## Start fresh implications for one prepared CPU; the helper never substitutes account/input provenance.
  executeAccumulationMachine(prepared, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1)),
    MemoryByteLimit(copyBytes), ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(
        10000), provisionConfig(), policy)
