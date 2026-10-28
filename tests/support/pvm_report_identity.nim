# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Construct genuine authorization-bound sources after fixing their import manifests and context.

import std/assertions
import ../../src/state/report_identity as state_report_identity
import ../../src/state/authorized_refinement as state_authorized_refinement
import ../../src/state/authorization_invocation as state_authorization_invocation
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ./pvm_authorized_refinement
import ./pvm_authorization_invoke
import ./pvm_report_results

proc identityLimits*(): ReportIdentityLimits =
  ## Finite independent hash/copy policies admit the small canonical test sources.
  ReportIdentityLimits(packageBytes: ByteLimit(4096), authorizerBytes: ByteLimit(4096))
proc identityFixture*(imports: openArray[seq[ImportReference]], prerequisites = 0,
    configuration: seq[byte] = @[81'u8, 82]): AuthorizedRefinement =
  ## Capture new manifests before executing authorization, retaining real complete state/code provenance.
  let halt = @[50'u8, 0]
  var guests: seq[ReportGuest] = @[]
  for index in 0..<imports.len: guests.add(reportGuest([halt],
      missing = true)) # BAD items still retain their declared imports for E.
  let original = authorizedFixture([halt], guests)
  let info = original.package.workPackageInfo.value
  var context = info.context
  context.prerequisiteCount = prerequisites
  for index in 0..<prerequisites: context.prerequisites[index].bytes[0] = byte(index+1)
  var source = WorkPackage(host: info.host, codeHash: info.codeHash, context: context,
    authorization: @[91'u8], configuration: configuration)
  for index, references in imports:
    let item = original.package.workItemAt(index).value
    let fields = item.workItemInfo.value
    var payload = newSeq[byte](fields.payloadBytes)
    assert item.copyItemPayload(payload).error == PackageError.None
    source.items.add(WorkItem(service: fields.service, codeHash: fields.codeHash,
      refineGas: fields.refineGas, accumulateGas: fields.accumulateGas,
      exports: fields.exports, payload: payload, imports: references))
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let encoded = encodeWorkPackage(source, config, wire)
  assert encoded.error == PackageError.None
  let package = decodeWorkPackage(wire.toOpenArray(0, encoded.value-1), config).value.owner
  let authorization = runAuthorizationInvocation(original.state, package, CoreIndex(0x1234),
    original.parameters, authorizationLimits()).value
  prepareAuthorizedRefinement(authorization, original.inputs, authorizedLimits()).value
proc identityKey*(octet: byte): PackageHash =
  ## Deterministic distinct wire keys make canonical ordering explicit.
  result = PackageHash()
  result.bytes[0] = octet
proc identityPair*(octet: byte): SegmentLookup =
  ## Pair a package key with a deliberately independent root; correspondence authentication is outside this gate.
  result = SegmentLookup(packageHash: identityKey(octet))
  result.segmentRoot.bytes[31] = octet+10
