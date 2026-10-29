# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently rooted complete sources qualify exact audit budgets, no-hash refusal and targeted predicate execution.
import std/[assertions, envvars, strutils, syncio]
import ../../support/[state_complete_serialization_context, state_inventory_context]
import ../../../src/state/[checkpoint, store, manifest, global_snapshot, validated_checkpoint, inventory]
import ../../../src/state/account/audit/plan as account_audit_plan
import ../../../src/state/account/[audit as account_audit, invariants as account_invariants]
import ../../../src/state/footprint_audit
import ../../../src/state/preimage/[content as preimage_content, linkage as preimage_linkage]
import ../../../src/codec/[bounded, assurances]
import ../../../src/codec/state/[consensus as state_consensus, layout as state_layout,
    trie as state_trie, composition as state_composition]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset observed hash work and optionally force backend refusal after source capture.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Separate account content hashing from mandatory earlier restoration/capture work.
const
  mapLimits = StateTrieLimits(items: ElementLimit(64), nodes: TrieNodeLimit(4096),
      perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288),
    store: StateStoreLimits(trie: mapLimits, writes: ElementLimit(64), writeValueBytes: ByteLimit(
        262144)),
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
        maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: StateManifestLimits(services: ElementLimit(4), serialized: mapLimits,
        storageKeyBytes: ByteLimit(65)))
proc check(input: seq[byte], services: seq[StateService]) =
  ## Admit the whole exact policy before content work, then require the declared account facts and immutable source identity.
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = input[25+i]
  let restored = decodeValidatedCheckpoint(input, StateRoot(root), services, inventoryProfile, limits).value
  let source = captureStateInventory(restored, services, inventoryCaptureLimits).value
  let count = uint64(services.len)
  var total = 0'u64
  var maximum = 0'u64
  for item in services:
    let size = uint64(item.preimages[0].value.len)
    total += size
    if size > maximum: maximum = size
  let policies = AccountAuditLimits(planning: ElementLimit(3*count),
    footprints: FootprintAuditLimits(services: ElementLimit(count), checks: ElementLimit(3*count)),
    content: PreimageContentLimits(services: ElementLimit(count), preimages: ElementLimit(count),
        perValue: ByteLimit(maximum), totalBytes: ByteLimit(total)),
    linkage: PreimageLinkageLimits(services: ElementLimit(count), preimages: ElementLimit(count),
        comparisons: ElementLimit(count)))
  fail(1)
  let planned = planAccountAudit(source, policies)
  assert planned.error == AccountAuditPlanError.None and calls() == 0
  let plan = planned.value
  let info = plan.accountPlanInfo.value
  assert info.services == services.len
  assert info.planningChecks == 3*count and info.footprintChecks == 3*count
  assert info.preimages == count and info.contentBytes == total and info.comparisonCeiling == count
  for phase in 0..<4:
    var short = policies
    case phase
    of 0: short.planning = ElementLimit(3*count-1)
    of 1: short.footprints.checks = ElementLimit(3*count-1)
    of 2: short.content.preimages = ElementLimit(count-1)
    else: short.linkage.comparisons = ElementLimit(count-1)
    let refused = planAccountAudit(source, short)
    assert refused.error == AccountAuditPlanError.LimitExceeded
    assert refused.refusedPhase == AccountAuditRefusal(phase)
    assert calls() == 0
  fail(0)
  let completed = executeAccountAudit(plan)
  assert completed.error == AccountAuditError.None
  assert uint64(calls()) == count
  let observations = completed.value.accountInvariantInfo.value
  assert observations.footprints.services == services.len and observations.footprints.checks == 3*count
  assert observations.content.preimages == count and observations.content.bytes == total
  assert observations.linkage.preimages == count and observations.linkage.comparisons == count
  assert sameStateInventory(completed.value.accountInvariantInventory.value, source)
  assert encodeFullCheckpoint(restored.manifestSource.value, limits.checkpointBytes).value == input
proc main() {.raises.} =
  ## Replay both independently authored complete fixtures, restoring backend availability before each new source.
  var row = 0
  for line in readFile(getEnv("RAGNAROK_COMPLETE_SERIALIZATION")).splitLines():
    if line.len == 0: continue # The SHA-pinned transport ends in a newline.
    fail(0)
    check(serializationOctets(line), @[serializationService(row)])
    inc row
  assert row == 32
  row = 0
  for line in readFile(getEnv("RAGNAROK_MULTISERVICE_SERIALIZATION")).splitLines():
    if line.len == 0: continue
    fail(0)
    var services: seq[StateService] = @[]
    for i in 0..<4: services.add(serializationService(4*row+i))
    check(serializationOctets(line), services)
    inc row
  assert row == 8
  fail(0)
  echo "state-complete-audit-corpus: ok (40 sources, 160 refusals)"
try:
  main()
except:
  quit(2) # Failed fixture/source construction cannot qualify planning or predicate observations.
