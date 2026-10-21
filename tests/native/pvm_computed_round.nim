# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict original-source initial-round payload and exact child-reason probes with real signed controls.

import std/[assertions, cmdline]
import ../../src/state/[computed_round, computed_publication, accumulation_round, accumulation_queue]
import ../../src/codec/[bounded, work_digest]
import ../support/pvm_computed_round

proc expect[T](outcome: ComputedRoundResult[T], reason: ComputedRoundError) =
  ## Confirm exact alternatives before deliberately extracting absent payloads or unrelated reasons.
  assert outcome.error == reason, "computed round runtime control"
let source = roundFixture()
let config = computedRoundConfig(source)
let done = prepareComputedRound(source, config)
expect(done, ComputedRoundError.None)
assert uint64(done.value.computedRoundPlan.value.roundProjection.value.roundInfo.value.prefix) == 1
let invalid = prepareComputedRound(default(ComputedReportSuccessor), config)
expect(invalid, ComputedRoundError.InvalidSource)
var changed = config
changed.round.reportGas = Gas(1)
let profile = prepareComputedRound(source, changed)
expect(profile, ComputedRoundError.ProfileMismatch)
changed = config
changed.queue.items = ElementLimit(0)
let queue = prepareComputedRound(source, changed)
expect(queue, ComputedRoundError.QueueFailure)
assert queue.queueError == AccumulationQueueError.LimitExceeded
changed = config
changed.round.privileges.maxBytes = ByteLimit(0)
let round = prepareComputedRound(source, changed)
expect(round, ComputedRoundError.RoundFailure)
assert round.roundError == AccumulationRoundError.LimitExceeded
let missing = default(ComputedRoundResult[ComputedAccumulationRound])
case paramStr(1)
of "default": discard missing.value # Default owns no prepared round.
of "source": discard invalid.value # A loose successor supplies no authority.
of "profile": discard profile.value # Source semantic gas remains mandatory.
of "queue": discard queue.value # Queue refusal exposes no prefix.
of "round": discard round.value # Parent privilege refusal exposes no round.
of "owner": discard default(ComputedAccumulationRound).computedRoundSource.value # No original computed map.
of "plan": discard default(ComputedAccumulationRound).computedRoundPlan.value # No genuine initial plan.
of "parameters": discard default(ComputedAccumulationRound).computedRoundParameters.value # No original tuple.
of "reason-queue-success": discard done.queueError # Success contains no queue refusal.
of "reason-round-default": discard missing.roundError # Default contains no round refusal.
of "reason-round-queue": discard queue.roundError # Queue refusal contains no unrelated round cause.
else: discard round.queueError # Round refusal contains no unrelated queue cause.
