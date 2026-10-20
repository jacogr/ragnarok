# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine verified current/prior guarantees, including distinct credential indices sharing one reporter key.

import std/assertions
import ../../src/state/[computed_envelope, computed_credentials, computed_guarantors, computed_roster]
import ../../src/codec/[bounded, guarantees]
import ./[pvm_computed_roster, pvm_computed_guarantors, pvm_computed_credentials]

proc envelopeFixture*(triple = false, prior = false,
    repeatReporter = false): CredentialedComputedReport =
  ## Author exact original state before signing/execution, then complete every population/assignment/credential boundary.
  let fixture = rosterFixture(shrink = prior, core = (if prior: 1'u64 else: 0'u64),
    rotation = 4, repeatReporter = repeatReporter)
  let eligible = checkComputedRoster(fixture.source, guarantorLimits().roster).value
  let context = prepareComputedGuarantors(eligible, guarantorLimits()).value
  let slot = GuaranteeSlot(if prior: 8'u32 else: 2'u32)
  let indices = if prior: @[7'u16, 8] elif triple: @[1'u16, 2, 5] else: @[1'u16, 2]
  let records = signedCredentials(context, slot, indices, credentialMessage(context))
  let verified = verifyComputedCredentials(context, slot, records)
  assert verified.error == ComputedCredentialError.None, "genuine verified source for canonical materialization"
  verified.value
