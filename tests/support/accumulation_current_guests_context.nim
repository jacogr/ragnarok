# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current tiny-chain guest proof ceilings reuse maintained signed-runner engine configuration.
import ../../src/codec/[bounded, work_digest]
import ../../src/state/[accumulation_guest_runner, accumulation_annulment, accumulation_coverage]
import ./accumulation_runner_context
proc currentGuestLimits*(): AccumulationGuestLimits =
  ## Reuse maintained tiny-chain engine ceilings while explicitly enabling current proof capture.
  let old = runnerLimits()
  AccumulationGuestLimits(services: ElementLimit(2), preimageBytes: old.preimageBytes,
    probes: old.probes, initialization: old.initialization, contexts: old.contexts,
    fetch: old.fetch, copyBytes: old.copyBytes, steps: old.steps, calls: old.calls,
    cycles: old.cycles, provisions: old.provisions, modifiedAccounts: ElementLimit(4),
    accountWriteFacts: ElementLimit(4), createdAccounts: ElementLimit(2),
    annulment: AccumulationAnnulmentLimits(outcomes: ElementLimit(2), modified: ElementLimit(8),
      checks: ElementLimit(128)),
    coverage: AccumulationCoverageLimits(services: ElementLimit(2), executed: ElementLimit(2),
      skipped: ElementLimit(2), absent: ElementLimit(2), checks: ElementLimit(128), gas: Gas(high(uint64))))
