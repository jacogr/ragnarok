# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized result guards reject refused/default payloads and invalid owner/index/output extraction after positive controls.

import std/[assertions, cmdline]
import ../../src/state/[refinement_digest, refinement_report]
import ../../src/codec/bounded
import ../../src/pvm/host_fetch
import ../support/[pvm_work_digests, pvm_report_results, pvm_refinement_outcome]

proc check(outcome: RefinementDigestResult[RefinementDigests], reason: RefinementDigestError) =
  ## Confirm genuine alternatives without specializing intentional misuse below.
  assert outcome.error == reason
let guest = reportGuest([refinementImmediate(7, 196608), refinementImmediate(8, 3), @[50'u8, 0]])
let report = reportRun(reportFixture([guest]), []).value
let success = prepareRefinementDigests(report, digestLimits())
check(success, RefinementDigestError.None)
assert success.value.digestAt(FetchItemIndex(0)).value.digestOutput.value == @[21'u8, 22, 23]
var cap = digestLimits()
cap.totalEncoding = ByteLimit(0)
let refused = prepareRefinementDigests(report, cap)
check(refused, RefinementDigestError.LimitExceeded)
let invalid = prepareRefinementDigests(default(RefinedPackage), digestLimits())
check(invalid, RefinementDigestError.InvalidReport)
let missing = default(RefinementDigestResult[RefinementDigests])
check(missing, RefinementDigestError.Uninitialized)
case paramStr(1)
of "default": discard missing.value # Default alternatives have no completed digest collection.
of "refused": discard refused.value # Local limits cannot expose a partial canonical prefix.
of "invalid": discard invalid.value # A missing source report cannot fabricate digest identities.
of "owner": discard default(RefinementDigests).digestCount.value # Default collection has no count.
of "item": discard default(RefinedDigest).digestInfo.value # Default item has no fixed fields.
of "index": discard success.value.digestAt(FetchItemIndex(high(
    uint64))).value # Full-width index refusal carries no item.
else:
  let source = reportRun(reportFixture([reportGuest(guest.instructions, 1)]), []).value
  let failure = prepareRefinementDigests(source, digestLimits()).value.digestAt(FetchItemIndex(0)).value
  discard failure.digestOutput.value # Final BadExports has no successful bytes.
