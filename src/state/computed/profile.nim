# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind all original execution parameters to the exact retained configured parent context.

import ../../chain/[genesis, parameters]
import ../../codec/header
import ./[lookup as computed_lookup, recent as computed_recent, state as computed_state,
    links as computed_links, guarantee as computed_guarantee, report as computed_report]
import "../block/admission" as block_admission
import ../store
import ../availability/specifier as availability_specifier
import "../export/erasure" as export_erasure
import ../bundle_erasure
import ../erasure/layout as erasure_layout
import ../[auditable_bundle, input_refinement]
import ../report/identity as report_identity
import ../authorized_refinement
import ../authorization/invocation as authorization_invocation

type
  ComputedProfileError* {.pure.} = enum ## Refusals contain no substituted context or partially configured computation.
    Uninitialized, None, InvalidSource, InvalidContext, StateMismatch, ParentMismatch, ParameterMismatch
  ComputedProfileData = ref object ## Fixed acyclic ownership retains original computed provenance and only projected immutable context handles/facts.
    source: LookupAnchoredComputedReport
    context: BlockSnapshotContext
  ConfiguredComputedReport* = object ## Exact configured-parent binding is not posterior roster or signing eligibility.
    data: nil ComputedProfileData
  ComputedProfileResult*[T] = object ## Private success selection alone carries extractable application data.
    case status: ComputedProfileError
    of None:
      completed: T
    else:
      discard # Defaults/refusals expose their reasons alone.

func error*[T](outcome: ComputedProfileResult[T]): ComputedProfileError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedProfileResult[T]): T
    {.requires: outcome.status == ComputedProfileError.None.} =
  ## Preserve successful payload selection in optimized execution.
  outcome.completed
proc computedProfileSource*(bound: ConfiguredComputedReport): ComputedProfileResult[
    LookupAnchoredComputedReport] =
  ## Retain exact original computation, anchors and state provenance.
  let data = bound.data
  if data == nil: return ComputedProfileResult[LookupAnchoredComputedReport](
      status: ComputedProfileError.Uninitialized)
  ComputedProfileResult[LookupAnchoredComputedReport](status: ComputedProfileError.None,
      completed: data.source)
proc computedProfileContext*(bound: ConfiguredComputedReport): ComputedProfileResult[
    BlockSnapshotContext] =
  ## Copy fixed context facts and share immutable state/header handles; returned mutable copies grant no replacement authority.
  let data = bound.data
  if data == nil: return ComputedProfileResult[BlockSnapshotContext](
      status: ComputedProfileError.Uninitialized)
  ComputedProfileResult[BlockSnapshotContext](status: ComputedProfileError.None,
      completed: data.context)
proc bindComputedProfile*(source: LookupAnchoredComputedReport,
    configured: BlockSnapshotResult): ComputedProfileResult[ConfiguredComputedReport] =
  ## Require completed source/context, exact map/parent identity and equality of the entire original parameter tuple.
  template fail(reason: ComputedProfileError) =
    return ComputedProfileResult[ConfiguredComputedReport](status: reason)
  if source.computedLookupInfo.error != ComputedLookupError.None: fail(
      ComputedProfileError.InvalidSource)
  if configured.error != GenesisError.None: fail(ComputedProfileError.InvalidContext)
  let context = configured.blockSnapshotContext
  let state = source.computedLookupSource.value.computedRecentSource.value
  let binding = state.computedStateAdmission.value
  if not sameStateSnapshot(context.state, state.computedStateSnapshot.value):
    fail(ComputedProfileError.StateMismatch) # Even equal-root rebuilt maps cannot replace the exact original execution version.
  let child = headerInfo(binding.admittedHeader).value.unsigned
  let parent = headerInfo(binding.admittedParent).value.unsigned
  if array[32, byte](context.hash) != array[32, byte](child.parent) or context.slot != uint32(parent.slot):
    fail(ComputedProfileError.ParentMismatch) # Bind full sealed identity and slot, not merely a matching map/configuration.
  let report = state.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value
  let identity = report.computedReportSource.value.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  let original = identity.identitySource.value.authorizedSource.value.authorizationParameters.value
  # Every fixed fetch field participates, including fields unrelated to core/epoch header framing.
  for field in low(Parameter)..high(Parameter):
    if context.parameters.get(field) != original.get(field): fail(
        ComputedProfileError.ParameterMismatch)
  ComputedProfileResult[ConfiguredComputedReport](status: ComputedProfileError.None,
    completed: ConfiguredComputedReport(data: ComputedProfileData(source: source,
        context: context)))
