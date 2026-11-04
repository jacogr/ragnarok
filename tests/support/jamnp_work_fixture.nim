# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only actual PVM/proof fixture extended with a captured source for managed Services admission.
import std/[assertions, syncio]
import ../../src/jamnp-s/work_submission
import ../../src/codec/[bounded, composite, assurances]
import ../../src/codec/work/[package as work_package, report as work_report]
import ../../src/codec/state/[authorization as state_authorization, history as state_history,
    layout as state_layout, trie as state_trie]
import ../../src/state/[store, input_refinement, auditable_bundle, extrinsic_inputs]
import "../../src/state/import/inputs" as import_inputs
import "../../src/state/import/justification" as import_justification
import ../../src/state/authorization/invocation as authorization_invocation
import ../../src/state/report/identity as report_identity
import ../../src/pvm/host/fetch as host_fetch
import ../../src/chain/parameters
import ../../src/chain/presets
import ../../src/crypto/primitives
import ./[pvm_input_refinement, pvm_authorization_invoke, pvm_report_results,
  pvm_refinement_outcome, pvm_import_inputs, pvm_import_justification, pvm_extrinsic_inputs,
  pvm_import_vectors, arc_evidence]

type
  WorkFixture* = object ## Test-owned wire buffers retire independently of immutable headers, grants and completed inputs.
    input*: InputFixture
    package*, first*, extrinsics*, segments*, proofs*: seq[byte]
    limits*: WorkSubmissionLimits
proc workFixture*(external = true, rejected = false, wrongPool = false,
    wrongMapping = false): WorkFixture =
  ## Commit genuine PVM code, selected C(1) authorizer and C(3) package mapping into a private original source.
  result = default(WorkFixture)
  let code = if rejected: @[refinementImmediate(7, 0), refinementImmediate(8, 0), @[0'u8]]
    else: @[refinementImmediate(8, 0), @[50'u8, 0]]
  result.input = executionFixture(code, [fetchedGuest(4), fetchedGuest(4)], external = external)
  result.input.parameters = presetParameters(ChainPreset.Tiny).value # Use the actual two-core profile for managed canonical context.
  result.limits = WorkSubmissionLimits(pools: AuthorizationConfig(cores: CoreCount(2),
    maxHashes: ElementLimit(16), maxBytes: ByteLimit(1024)), history: HistoryConfig(
        cores: CoreCount(2),
    blocks: ElementLimit(8), perBlock: ElementLimit(2), totalPackages: ElementLimit(16),
    peaks: ElementLimit(64), maxBytes: ByteLimit(4096)), authorization: authorizationLimits(),
    extrinsics: extrinsicLimits(), imports: inputLimits(), proof: importLimits())
  let info = result.input.package.workPackageInfo.value
  var authorizer = newSeq[byte](32+info.configurationBytes)
  let codeHash = array[32, byte](info.codeHash)
  for index in 0..<32: authorizer[index] = codeHash[index]
  assert result.input.package.copyPackageBlob(PackageBlob.Configuration,
    authorizer.toOpenArray(32, authorizer.high)).error == PackageError.None
  var hash = array[32, byte](blake2b256(authorizer).value)
  if wrongPool: hash[0] = hash[0] xor 1 # An actual different hash cannot select authorization for this package.
  let pools = authorizationEntry(AuthorizationKind.Pools, [@[AuthorizerHash(bytes: hash)],
    newSeq[AuthorizerHash](0)], result.limits.pools).value
  var root = SegmentRoot(bytes: ThreeRoot)
  if wrongMapping: root.bytes[0] = root.bytes[0] xor 1
  let history = historyStateEntry(HistoryState(blocks: @[HistoryBlock(slot: HistorySlot(10),
    packages: @[ReportedPackage(package: inputKey(1), segment: root)])]),
        result.limits.history).value
  var state = forkStateStore(result.input.state).value
  assert state.apply([StateWrite(kind: StateWriteKind.Put, key: pools.key, value: pools.value),
    StateWrite(kind: StateWriteKind.Put, key: history.key, value: history.value)]).error ==
        StateStoreError.None
  result.input.state = state.snapshot.value
  result.package = newSeq[byte](info.consumed)
  assert result.input.package.encodeOwnedWorkPackage(result.package).error == PackageError.None
  result.first = @[0'u8, 0, byte(if external: 1 else: 0)] # Independent E2 core and canonical mapping-count prefix.
  if external:
    # The original fixture deliberately mixes a direct root and a package-relative import.
    for octet in inputKey(1).bytes: result.first.add(octet)
    for octet in ThreeRoot: result.first.add(octet)
    result.extrinsics = @[97'u8, 98, 99, 97, 98, 100]
    for index in 0..<2:
      let proof = inputProof(index)
      for octet in array[4104, byte](proof.verifiedImportSegment.value): result.segments.add(octet)
      for octet in proof.verifiedImportProof.value: result.proofs.add(octet)

import ../../src/chain/genesis
import ../../src/codec/header
import ../../src/codec/state/safrole
import ../../src/lib/json/writer as json_writer
import std/strutils
import ./jamnp_topology_fixture
proc workSnapshot*(f: WorkFixture): BlockSnapshot =
  ## Merge actual code and commitments with explicit canonical roster/time context; no consensus certificate is invented.
  let base = topologyCaptured([topologyRecords(0, 6), topologyRecords(0, 6), topologyRecords(1, 6)],
    cores = 2, atSlot = 20).value
  var state = forkStateStore(f.input.state).value
  var writes: seq[StateWrite] = @[]
  for index in 0..<base.keyCount:
    let key = base.keyAt(StateKeyIndex(index))
    writes.add(StateWrite(kind: StateWriteKind.Put, key: key, value: base.lookup(key).value.bytes))
  assert state.apply(writes).error == StateStoreError.None
  var wire = newSeq[byte](base.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(base.header, wire).error == HeaderError.None
  let saved = captureBlockSnapshot(wire, state.snapshot.value, f.input.parameters)
  assert saved.error == GenesisError.None
  saved.value
proc hexBytes(input: openArray[byte]): string =
  ## Independent test chainspec spelling exposes no private-key data.
  result = ""
  for octet in input: result.add(toHex(int(octet), 2).toLowerAscii())
proc workChainText*(f: WorkFixture): string =
  ## Serialize only the actual captured source's public complete state and exact profile/header.
  let saved = f.workSnapshot
  var wire = newSeq[byte](saved.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(saved.header, wire).error == HeaderError.None
  var entries = JsonObject()
  for index in 0..<saved.keyCount:
    let key = saved.keyAt(StateKeyIndex(index))
    entries.add(hexBytes(array[31, byte](key)), json(hexBytes(saved.lookup(key).value.bytes)))
  $jsonObject([("protocol_parameters", json(hexBytes(saved.chainParameters.encodeParameters))),
    ("genesis_header", json(hexBytes(wire))), ("genesis_state", json(entries))])
proc workHeader*(f: WorkFixture): WorkSubmissionHeader =
  ## Prepare actual separate CE146 payloads for managed staging under the shared lease.
  let decoded = decodeWorkSubmission(WorkSubmissionKind.Bundle, f.first, f.package,
    fullPackageConfig(ByteLimit(204800)))
  assert decoded.error == WorkSubmissionError.None
  decoded.value
