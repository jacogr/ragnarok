# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored authorizer code, complete historical source maps and canonical packages for Psi_I witnesses.

import std/assertions
import ../../src/state/authorization_invocation as state_authorization_invocation
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/natural as codec_natural
import ../../src/codec/composite as codec_composite
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/codec/work_digest as codec_work_digest
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/state_trie as codec_state_trie
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/program as pvm_program
import ../../src/pvm/initialize as pvm_initialize
import ../../src/pvm/gas as pvm_gas
import ../../src/pvm/step as pvm_step
import ../../src/pvm/host_fetch as pvm_host_fetch
import ../../src/pvm/output as pvm_output
import ../../src/chain/parameters as chain_parameters
import ../../src/crypto/primitives as crypto_primitives

type
  AuthorizationFixture* = object ## Test-owned inputs retire independently of the production result's immutable provenance.
    state*: StateStoreSnapshot
    package*: OwnedWorkPackage
    parameters*: Parameters
    envelope*, preimage*: seq[byte]

proc authorizationLimits*(): AuthorizationInvocationLimits =
  ## Finite policies independently bound code copying, initialization, host capture and execution/output work.
  AuthorizationInvocationLimits(preimage: ByteLimit(200000), initialization: InitializationLimits(
    envelope: InitializationByteLimit(64000), program: ProgramByteLimit(160), jumps: JumpCountLimit(0),
    pages: PageLimit(20)), package: FetchPackageLimit(16), encoding: FetchEncodingLimit(4096),
    copy: MemoryByteLimit(512), steps: ExecutionStepLimit(64), calls: HostCallLimit(8),
    cycles: GasCycleLimit(1000), output: OutputByteLimit(65536))
proc authorizationFixture*(instructions: openArray[seq[byte]], metadata: seq[byte] = @[],
    codeSize = 0, missing = false, anchor = 20'u32, host = 77'u32,
    malformedState = false, wrongHash = false, overrideBytes: seq[byte] = @[]): AuthorizationFixture =
  ## Distinct package host 77 and item service 42 catch accidental selection of refinement code or lookup identity.
  result = default(AuthorizationFixture)
  var code: seq[byte] = @[]
  var starts: seq[bool] = @[]
  for instruction in instructions:
    assert instruction.len > 0
    for index, octet in instruction:
      code.add(octet)
      starts.add(index == 0) # Only independently authored instruction starts appear in the program mask.
  assert code.len > 0 and code.len < 128
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for index, marked in starts:
    if marked: mask[index div 8] = mask[index div 8] or byte(1 shl (index mod 8))
  for octet in mask: raw.add(octet)
  let writableSize = if codeSize > 0: codeSize-18-raw.len else: 3
  assert writableSize >= 3 and writableSize <= 65535 # Prove the literal E3 header and test allocation extents.
  result.envelope = @[3'u8, 0, 0, byte(writableSize and 255), byte(writableSize shr 8),
    0, 0, 0, 0, 0, 0, 11, 12, 13]
  var writable = newSeq[byte](writableSize)
  writable[0] = 21
  writable[1] = 22
  writable[2] = 23
  for octet in writable: result.envelope.add(octet)
  result.envelope.add(byte(raw.len))
  for index in 0..<3: result.envelope.add(0) # E4 raw length is bounded by the authored short program.
  for octet in raw: result.envelope.add(octet)
  let prefix = codec_natural.encode(JamNatural(uint64(metadata.len)))
  for index in 0..<prefix.len: result.preimage.add(prefix.bytes[index])
  for octet in metadata: result.preimage.add(octet)
  for octet in result.envelope: result.preimage.add(octet)
  if overrideBytes.len > 0: result.preimage = overrideBytes # Deliberately malformed historical code still has a real commitment.
  let hash = array[32, byte](blake2b256(result.preimage).value)
  var entries: seq[StateEntry] = @[]
  if not missing:
    let account = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(), ByteLimit(
        ServiceMetadataBytes)).value
    entries.add(if malformedState: StateEntry(key: account.key, value: @[1'u8]) else: account)
    var stored = result.preimage
    if wrongHash: stored[stored.len-1] = stored[stored.len-1] xor 1 # Keep the key/history while corrupting its value.
    entries.add(servicePreimageEntry(ServiceIndex(77), ServicePreimageHash(hash), stored,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(200000))).value)
    let key = serviceRequestKey(ServiceIndex(77), ServicePreimageHash(hash),
      RequestLength(uint32(stored.len)), ByteLimit(32)).value
    entries.add(StateEntry(key: key, value: @[1'u8, 10, 0, 0,
        0])) # Available since ten; earlier lookup anchors select BAD.
  result.state = newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4),
    perValue: ByteLimit(200000), totalValueBytes: ByteLimit(201000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(4), writeValueBytes: ByteLimit(201000))).value.snapshot.value
  let package = WorkPackage(host: AuthorizerHost(host), codeHash: CodeHash(hash),
    context: RefinementContext(lookupSlot: LookupSlot(anchor)), configuration: @[81'u8, 82],
    authorization: @[91'u8], items: @[WorkItem(service: ServiceIndex(42), payload: @[31'u8, 32])])
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let size = encodeWorkPackage(package, config, wire).value
  result.package = decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
  var parameterBytes = default(array[122, byte])
  for index in 0..<122: parameterBytes[index] = 255 # Full E2 core domain with valid fixed parameter fields.
  result.parameters = decodeParameters(parameterBytes).value
proc authorizationRun*(fixture: AuthorizationFixture, cap = authorizationLimits(),
    core = 0x1234'u64):
    AuthorizationInvocationResult[AuthorizationInvocation] =
  ## Only original immutable inputs enter the production API; gas, code, CPU and trace cannot be supplied separately.
  runAuthorizationInvocation(fixture.state, fixture.package, CoreIndex(core), fixture.parameters, cap)
proc authorizationPrice*(fixture: AuthorizationFixture): uint64 =
  ## The separately verified gas component prices entry block structure; protocol host prices remain literal expectations.
  let cpu = initializeMachine(fixture.envelope, [0x34'u8, 0x12], CodeAddress(0), MachineGas(
      50000000),
    authorizationLimits().initialization).value
  uint64(blockGas(cpu.programOf.value, CodeAddress(0), GasCycleLimit(1000)).value)
