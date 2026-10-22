# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current tiny-chain guest proof ceilings reuse maintained signed-runner engine configuration.
import ../../src/chain/parameters
import ../../src/codec/[bounded, work_digest, composite, state_authorization, state_safrole, state_privileges]
import ../../src/state/[accumulation_guest_runner, accumulation_annulment, accumulation_coverage,
    accumulation_account_stage, accumulation_account_selection, accumulation_creation_union,
    accumulation_selected_writes, accumulation_global_stage, accumulation_global_roles]
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

proc currentAccountStageLimits*(): AccumulationAccountStageLimits =
  ## Charge complete inventory/providers separately from logical selection, creation facts and physical write copies.
  AccumulationAccountStageLimits(entries: ElementLimit(100), providers: ElementLimit(2),
    selection: AccumulationAccountSelectionLimits(accounts: ElementLimit(8), outcomes: ElementLimit(2),
      skipped: ElementLimit(2), checks: ElementLimit(512)),
    creation: AccumulationCreationLimits(outcomes: ElementLimit(2), creations: ElementLimit(4),
      accounts: ElementLimit(2), checks: ElementLimit(256)),
    writes: SelectedAccountWriteLimits(accounts: ElementLimit(10), facts: ElementLimit(64),
      writes: ElementLimit(8), checks: ElementLimit(512), valueBytes: ByteLimit(2048)))
proc currentGuestParameters*(): Parameters =
  ## Zero-deposit chain configuration isolates actual creation while keeping the genuine admitted profile.
  var wire = encodeParameters(runnerParameters())
  for index in 0..<24: wire[index] = 0 # Complete independent deposit words, not host return hooks.
  decodeParameters(wire).value

proc currentGlobalStageLimits*(): AccumulationGlobalStageLimits =
  ## Fixed two-core queues and six-validator rosters have independent original/output byte and work caps.
  AccumulationGlobalStageLimits(roles: AccumulationGlobalRoleLimits(
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(2),
        maxBytes: ByteLimit(1000)),
    outcomes: ElementLimit(2), checks: ElementLimit(256), totalBytes: ByteLimit(2000)),
    queues: AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
        maxBytes: ByteLimit(5120)),
    staging: ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
        maxBytes: ByteLimit(2017)),
    totalBytes: ByteLimit(20000))
