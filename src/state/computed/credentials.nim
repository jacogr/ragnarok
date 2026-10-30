# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Verify proposed guarantee credentials against the exact original computed transcript and authenticated assignments.

import ../../codec/guarantees
import ../../codec/state/safrole as state_safrole
import ../../crypto/[primitives, guarantee]
import ./[guarantors as computed_guarantors, roster as computed_roster,
    transition as computed_transition, profile as computed_profile, lookup as computed_lookup,
    recent as computed_recent, state as computed_state, links as computed_links,
    guarantee as computed_guarantee]

type
  ComputedCredentialError* {.pure.} = enum ## Refusals contain no partial verified credentials or substituted transcript.
    Uninitialized, None, InvalidSource, InvalidCount, NonCanonical, AssignmentFailure,
    InvalidSignature, InvalidIndex
  ComputedCredentialIndex* = distinct uint64 ## Credential-array ordinal is separate from a guarantor's selected-roster position.
  ComputedCredentialInfo* = object ## Fixed copied evaluation slot/count are facts, never replacement authority.
    slot*: GuaranteeSlot
    credentials*: int
  ComputedCredentialData = ref object ## Immutable acyclic ownership retains exact source context and complete copied credential records only.
    source: ComputedGuarantors
    info: ComputedCredentialInfo
    records: array[3, GuaranteeCredential]
  CredentialedComputedReport* = object ## Credential verification does not establish report inclusion, availability or signing permission.
    data: nil ComputedCredentialData
  ComputedCredentialResult*[T] = object ## Only selected complete success carries application data; assignment refusals retain their exact cause.
    case status: ComputedCredentialError
    of None:
      completed: T
    of AssignmentFailure:
      assignmentReason: ComputedGuarantorError
    else:
      discard # Defaults and other refusals expose reasons alone.

func error*[T](outcome: ComputedCredentialResult[T]): ComputedCredentialError =
  ## Read selected status without writable discriminator access.
  outcome.status

func value*[T](outcome: ComputedCredentialResult[T]): T
    {.requires: outcome.status == ComputedCredentialError.None.} =
  ## Preserve complete successful extraction in optimized builds.
  outcome.completed

func assignmentError*[T](outcome: ComputedCredentialResult[T]): ComputedGuarantorError
    {.requires: outcome.status == ComputedCredentialError.AssignmentFailure.} =
  ## Inspect only a selected assignment refusal, without exposing a successful credential prefix.
  outcome.assignmentReason

proc computedCredentialSource*(bound: CredentialedComputedReport): ComputedCredentialResult[
    ComputedGuarantors] =
  ## Share exact authenticated assignment and original computed transcript provenance.
  let data = bound.data
  if data == nil: return ComputedCredentialResult[ComputedGuarantors](
      status: ComputedCredentialError.Uninitialized)
  ComputedCredentialResult[ComputedGuarantors](status: ComputedCredentialError.None,
      completed: data.source)

proc computedCredentialInfo*(bound: CredentialedComputedReport): ComputedCredentialResult[
    ComputedCredentialInfo] =
  ## Copy fixed slot/count facts while leaving retained metadata immutable.
  let data = bound.data
  if data == nil: return ComputedCredentialResult[ComputedCredentialInfo](
      status: ComputedCredentialError.Uninitialized)
  ComputedCredentialResult[ComputedCredentialInfo](status: ComputedCredentialError.None,
      completed: data.info)

proc computedCredentialAt*(bound: CredentialedComputedReport,
    index: ComputedCredentialIndex): ComputedCredentialResult[GuaranteeCredential] =
  ## Copy an independently mutable fixed credential after checking its owner-relative ordinal.
  let data = bound.data
  if data == nil: return ComputedCredentialResult[GuaranteeCredential](
      status: ComputedCredentialError.Uninitialized)
  if uint64(index) >= uint64(data.info.credentials): return ComputedCredentialResult[
      GuaranteeCredential](status: ComputedCredentialError.InvalidIndex)
  ComputedCredentialResult[GuaranteeCredential](status: ComputedCredentialError.None,
      completed: data.records[int(uint64(index))])

proc verifyComputedCredentials*(source: ComputedGuarantors, slot: GuaranteeSlot,
    credentials: openArray[GuaranteeCredential]): ComputedCredentialResult[
        CredentialedComputedReport] =
  ## Snapshot bounded borrowed records, then validate structure/assignments and original signatures before retaining success.
  template fail(reason: ComputedCredentialError) =
    return ComputedCredentialResult[CredentialedComputedReport](status: reason)
  if source.computedGuarantorSource.error != ComputedGuarantorError.None: fail(
      ComputedCredentialError.InvalidSource)
  let count = credentials.len
  if count < 2 or count > 3: fail(ComputedCredentialError.InvalidCount)
  var records = default(array[3, GuaranteeCredential])
  for i in 0..<count:
    records[i] = credentials[i] # Fixed bounded input snapshot; no later native verification rereads caller credential storage.
  for i in 1..<count:
    if uint16(records[i-1].validator) >= uint16(records[i].validator):
      fail(ComputedCredentialError.NonCanonical) # No sorting or deduplication fallback, even for otherwise valid signatures.
  var keys = default(array[3, EdPublicKey])
  for i in 0..<count:
    let selected = source.computedGuarantorAt(slot, records[i].validator)
    if selected.error != ComputedGuarantorError.None:
      return ComputedCredentialResult[CredentialedComputedReport](
        status: ComputedCredentialError.AssignmentFailure,
        assignmentReason: selected.error) # All assignments must succeed before the first signature check.
    keys[i] = EdPublicKey(array[32, byte](selected.value.validator.ed25519))
  let transcript = source.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value.computedStateSource.value.computedLinkSource.value
  let message = array[45, byte](transcript.computedGuaranteeMessage.value)
  for i in 0..<count:
    let signature = importSignature(array[64, byte](records[i].signature)).value
    if not verify(keys[i], signature, message): fail(ComputedCredentialError.InvalidSignature)
  let data = ComputedCredentialData(source: source,
    info: ComputedCredentialInfo(slot: slot, credentials: count), records: records)
  ComputedCredentialResult[CredentialedComputedReport](status: ComputedCredentialError.None,
    completed: CredentialedComputedReport(data: data))
