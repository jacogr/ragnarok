# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine completed current logical parent and maintained signed in-epoch empty next child, with no legacy completion certificate.
import std/assertions
import ./[current_namespace_transition_context, current_namespace_execution_context,
    current_namespace_context, current_namespace_refresh_context, accumulation_execution_context,
    accumulation_current_candidate_context, application_download_chain]
import ../../src/codec/[bounded, report_owned]
import ../../src/state/current/logical/refresh as current_logical_refresh
import ../../src/state/current/logical as current_logical
import ../../src/state/accumulation/current/update as accumulation_current_update
import ../../src/app/[chain, candidate]
type CurrentRepeatedLogicalFixture* = object ## Public test descriptors hold only genuinely produced immutable opaque owners.
  first*: CurrentNamespaceTransition
  logical*: CurrentLogicalState
  next*: PreparedCurrentChainUpdate
proc nextLogicalEmpty*(source: PreparedCurrentChainUpdate): PreparedCurrentChainUpdate =
  ## The maintained author only signs a bounded in-epoch empty OwnedBlock; actual current candidate execution supplies all completion authority.
  let context = source.currentUpdateChildContext
  assert context.slot >= 2 and context.slot < 9 # Prove the maintained fixture's next-slot increment stays within its explicit first-epoch scope.
  let retention = source.currentUpdateViewInfo
  assert retention.owners <= 9 and retention.bytes <=
      8388608 # Admit the test's actual view/child index copies before either heavy getter.
  let child = signedChild(source.currentUpdateChild)
  let application = initApplicationChain(source.currentUpdateView).value
  var limits = currentCandidateLimits()
  limits.completion.composition.validators.services = ElementLimit(
      2) # Real posterior C13 contains both executed services, rather than the original single stale row.
  prepareCurrentCandidate(application, child, [], limits).value
proc repeatedLogicalFixture*(base: OwnedReport): CurrentRepeatedLogicalFixture =
  ## Original code and complete namespaces enter signatures; the first full logical result is the actual parent of the genuine next preparation.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = options.firstProgram
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let first = namespaceTransitionFixture(base, options)
  let stages = namespaceRefreshStages(first)
  let logical = executeCurrentLogicalRefresh(stages.complete).value
  let next = nextLogicalEmpty(first.update)
  CurrentRepeatedLogicalFixture(first: first, logical: logical, next: next)
