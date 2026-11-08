# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_judgment_runtime_arc_release"}

## Original epoch/signature claims preserve whole-batch failure and immutable source-free ownership before the private judgment/forced-audit pipeline consumes them.

import std/[assertions, syncio]
import ../../support/[jamnp_judgment_claim, jamnp_guarantee_support, jamnp_judgment_support,
    jamnp_dispute_evaluation, jamnp_judgment_receipt, jamnp_judgment_store, jamnp_judgment_tls,
    jamnp_audit_participation, jamnp_judgment_gossip,
    jamnp_audit_context, arc_evidence]

proc main() {.raises.} =
  ## Independent raw Ed25519 transcripts and distinct trusted epoch keysets precede a stable repeated release witness.
  judgmentClaimChecks()
  let fixture = auditContextFixture()
  guaranteeSupportChecks(fixture)
  judgmentSupportChecks(fixture)
  disputeEvaluationChecks(fixture)
  judgmentReceiptChecks(fixture)
  judgmentStoreChecks(fixture)
  judgmentTlsChecks(fixture)
  auditParticipationChecks(fixture)
  judgmentGossipChecks(fixture)
  let view = claimView()
  let wire = claimWire([rawClaim(1, 5, 26), rawClaim(0, 8, 9)])
  judgmentClaimCycle(view, wire)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Complete decoding, both real original-key checks and bounded immutable batch release participate in every cycle.
    judgmentClaimCycle(view, wire)
  let after = getOccupiedMem()
  assert before == after, "whole judgment claim release"
  recordArcRelease("jamnp_judgment_runtime", 1000, before, after)
  echo "JAMNP-S judgment runtime passed"
when isMainModule:
  try:
    # Native key-file failures propagate to the registered suite exit status.
    main()
  except:
    quit(2)
