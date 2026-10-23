# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine reserved-ID replacement fixtures share signed original namespaces across state and application qualification.
import ./[current_namespace_transition_context, current_namespace_execution_context,
  accumulation_execution_context, accumulation_current_candidate_context,
  current_namespace_context, service_namespace_seed, pvm_accumulation_program]
import ../../src/codec/[bounded, report_owned]
import ../../src/state/accumulation_current_update
proc namespaceReplacementCode*(checkpoint = false, panic = false): seq[byte] =
  ## A genuine registrar ejects junior99, optionally checkpoints, then recreates the same reserved ID.
  var payload = newSeq[byte](60)
  payload[32] = 1
  var code = @[registerImmediate(7, 99), @[10'u8, 23]]
  if checkpoint: code.add(@[10'u8, 19]) # This checkpoint precedes creation and retains only ejection.
  code.add(registerImmediate(7, high(uint64)))
  code.add(registerImmediate(8, 99))
  code.add(registerImmediate(9, 0))
  code.add(registerImmediate(10, 196608))
  code.add(@[10'u8, 20])
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(code, writable = payload): result.add(octet)
proc namespaceReplacementFixture*(base: OwnedReport): NamespaceExecutionFixture =
  ## Author an empty junior and real registrar before signing; declarations come from the already-qualified original parent.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceReplacementCode()
  options.secondProgram = namespaceHaltCode()
  options.second = ExecutionEnding.Missing
  options.registrar = 42
  options.secondSupervisor = 42
  options.signed.serviceNamespaces = namespaceSeeds()
  options.signed.serviceNamespaces[1].storage = @[]
  options.signed.serviceNamespaces[1].preimages = @[]
  options.signed.serviceNamespaces[1].requests = @[]
  let origin = namespaceTransitionFixture(base, options, ElementLimit(4), currentCandidateLimits())
  var seeds: seq[ServiceNamespaceSeed] = @[]
  for service in origin.services:
    # Complete source declarations already contain executable code; empty code slots avoid duplicating those preimages.
    seeds.add(ServiceNamespaceSeed(service: service.service, storage: service.storage,
      preimages: service.preimages, requests: service.requests))
  NamespaceExecutionFixture(source: origin.source, seeds: seeds,
    codes: [newSeq[byte](0), newSeq[byte](0)], parent: origin.update.currentUpdatePriorView,
    update: origin.update)
