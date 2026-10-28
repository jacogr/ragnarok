# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized canonical-output/reporters guards with real current and prior verified source controls.

import std/assertions
import std/cmdline
import ../../src/state/computed_envelope as state_computed_envelope
import ../../src/state/computed_credentials as state_computed_credentials
import ../../src/codec/bounded as codec_bounded
import ../support/pvm_computed_envelope

proc expect[T](outcome: ComputedEnvelopeResult[T], reason: ComputedEnvelopeError) =
  ## Confirm exact selected failure before deliberate absent application extraction.
  assert outcome.error == reason, "envelope runtime control"
let source = envelopeFixture()
let broad = ComputedEnvelopeLimits(reportBytes: ByteLimit(100000), bytes: ByteLimit(100000),
    reporters: ElementLimit(3))
let done = prepareComputedEnvelope(source, broad)
expect(done, ComputedEnvelopeError.None)
assert done.value.computedEnvelopeInfo.value.reporters == 2
let facts = done.value.computedEnvelopeInfo.value
let missing = default(ComputedEnvelopeResult[ComputedGuaranteeEnvelope])
let invalid = prepareComputedEnvelope(default(CredentialedComputedReport), broad)
expect(invalid, ComputedEnvelopeError.InvalidSource)
var limit = broad
limit.reportBytes = ByteLimit(facts.reportBytes-1)
let report = prepareComputedEnvelope(source, limit)
expect(report, ComputedEnvelopeError.LimitExceeded)
limit = broad
limit.bytes = ByteLimit(facts.bytes-1)
let wire = prepareComputedEnvelope(source, limit)
expect(wire, ComputedEnvelopeError.LimitExceeded)
limit = broad
limit.reporters = ElementLimit(1)
let reporterSet = prepareComputedEnvelope(source, limit)
expect(reporterSet, ComputedEnvelopeError.LimitExceeded)
let index = done.value.computedEnvelopeReporterAt(ComputedReporterIndex(2))
expect(index, ComputedEnvelopeError.InvalidIndex)
case paramStr(1)
of "default": discard missing.value # Defaults have no output certificate.
of "source": discard invalid.value # Loose or missing credentials have no authority.
of "report": discard report.value # Original complete report exceeds copy policy.
of "wire": discard wire.value # Whole standalone guarantee exceeds policy.
of "reporters": discard reporterSet.value # Unique identities exceed budget.
of "index": discard index.value # No third key in the reporter pair.
of "owner": discard default(ComputedGuaranteeEnvelope).computedEnvelopeSource.value # No retained source.
of "info": discard default(ComputedGuaranteeEnvelope).computedEnvelopeInfo.value # No copied facts.
of "guarantee": discard default(ComputedGuaranteeEnvelope).computedEnvelopeGuarantee.value # No report owner.
of "bytes": discard default(ComputedGuaranteeEnvelope).computedEnvelopeBytes.value # No canonical bytes.
else: discard default(ComputedGuaranteeEnvelope).computedEnvelopeReporterAt(ComputedReporterIndex(
    0)).value # No reporter keys.
