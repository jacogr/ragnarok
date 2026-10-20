# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original combined authorizer/refinement source fixtures bind all code and package fields before authorization executes.

import std/assertions
import ../../src/state/[authorized_refinement, authorization_invocation, refinement_dispatch, store]
import ../../src/codec/[bounded, composite, work_package, work_digest, work_report,
  state_accounts, state_service_values, state_requests, state_trie]
import ../../src/chain/parameters
import ../../src/pvm/host_fetch
import ./[pvm_authorization_invoke, pvm_report_results, pvm_work_digests]

type
  AuthorizedFixture* = object ## Caller-visible test handles permit source-replacement witnesses without production setter APIs.
    authorization*: AuthorizationInvocation
    state*: StateStoreSnapshot
    package*: OwnedWorkPackage
    parameters*: Parameters
    inputs*: RefinementInputs
proc authorizedLimits*(): AuthorizedRefinementLimits =
  ## Independent local caps admit complete ordered computation while retaining bounded child behavior.
  AuthorizedRefinementLimits(trace: FetchTraceLimit(49152), refinement: reportLimits(),
      digests: digestLimits())
proc authorizedFixture*(authCode: openArray[seq[byte]], guests: openArray[ReportGuest],
    authCodeSize = 0, missingAuth = false): AuthorizedFixture =
  ## Merge original test-only complete state entries, then capture a new canonical package before its authorizer runs.
  result = default(AuthorizedFixture)
  let auth = authorizationFixture(authCode, codeSize = authCodeSize, missing = missingAuth)
  let refinement = reportFixture(guests)
  var state = forkStateStore(refinement.state).value
  if not missingAuth:
    let hash = array[32, byte](auth.package.workPackageInfo.value.codeHash)
    let metadata = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(), ByteLimit(89)).value
    let preimage = servicePreimageEntry(ServiceIndex(77), ServicePreimageHash(hash), auth.preimage,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(200000))).value
    let key = serviceRequestKey(ServiceIndex(77), ServicePreimageHash(hash),
      RequestLength(uint32(auth.preimage.len)), ByteLimit(32)).value
    let history = StateEntry(key: key, value: @[1'u8, 10, 0, 0, 0])
    var writes: seq[StateWrite] = @[]
    for entry in [metadata, preimage, history]:
      writes.add(StateWrite(kind: StateWriteKind.Put, key: entry.key, value: entry.value))
    assert state.apply(writes).error == StateStoreError.None # Only fixture construction mutates a private test store.
  result.state = state.snapshot.value
  result.parameters = auth.parameters
  result.inputs = refinement.inputs
  let authInfo = auth.package.workPackageInfo.value
  var source = WorkPackage(host: authInfo.host, codeHash: authInfo.codeHash,
    context: authInfo.context,
    configuration: @[81'u8, 82], authorization: @[91'u8])
  for index in 0..<refinement.package.workPackageInfo.value.items:
    let item = refinement.package.workItemAt(index).value
    let info = item.workItemInfo.value
    var payload = newSeq[byte](info.payloadBytes)
    assert item.copyItemPayload(payload).error == PackageError.None
    source.items.add(WorkItem(service: info.service, codeHash: info.codeHash, payload: payload,
      refineGas: info.refineGas, accumulateGas: info.accumulateGas, exports: info.exports))
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let size = encodeWorkPackage(source, config, wire).value
  result.package = decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
  result.authorization = runAuthorizationInvocation(result.state, result.package, CoreIndex(0x1234),
    result.parameters, authorizationLimits()).value
