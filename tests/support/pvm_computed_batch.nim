# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute multiple original cores against one genuine complete signed transition, then verify their actual credentials.

import std/assertions
import ../../src/state/[computed_batch, computed_envelope, computed_credentials,
  computed_guarantors,
  computed_roster, computed_transition]
import ../../src/codec/[bounded, guarantees]
import ./[pvm_computed_roster, pvm_computed_guarantors, pvm_computed_credentials]

proc batchLimits*(): ComputedBatchLimits =
  ## Broad independent policies cover three configured cores and at most nine reporters.
  ComputedBatchLimits(guarantees: ElementLimit(3), reporters: ElementLimit(9),
    bytes: ByteLimit(100000), headerBytes: ByteLimit(4096))
proc batchEnvelopes*(repeatReporter = false, distinctPackages = false, withReady = false,
    withRound = false, withExecution = false, invalidEntry = false): seq[
        ComputedGuaranteeEnvelope] =
  ## Share the actual original map and posterior snapshot rather than rebuilding equal-root stand-ins.
  let fixture = rosterFixture(rotation = 4, repeatReporter = repeatReporter,
    additionalCores = [1'u64], distinctPackages = distinctPackages, withReady = withReady,
        withRound = withRound, withExecution = withExecution, invalidEntry = invalidEntry)
  let sources = @[fixture.source, fixture.siblings[0]]
  result = newSeq[ComputedGuaranteeEnvelope](sources.len)
  for i, source in sources:
    # Discover the actual three current assigned validators for each authored core and sign the exact original message.
    let eligible = checkComputedRoster(source, guarantorLimits().roster).value
    let context = prepareComputedGuarantors(eligible, guarantorLimits()).value
    var indices: seq[uint16] = @[]
    for index in 0'u16..<6'u16:
      if context.computedGuarantorAt(GuaranteeSlot(2), GuarantorIndex(index)).error ==
          ComputedGuarantorError.None:
        indices.add(index) # Only genuine owner-selected current validators participate.
    assert indices.len == 3, "six current validators assign three each to the two populated cores"
    let records = signedCredentials(context, GuaranteeSlot(2), indices, credentialMessage(context))
    let verified = verifyComputedCredentials(context, GuaranteeSlot(2), records).value
    result[i] = prepareComputedEnvelope(verified, ComputedEnvelopeLimits(reportBytes: ByteLimit(
        100000),
      bytes: ByteLimit(100000), reporters: ElementLimit(3))).value
