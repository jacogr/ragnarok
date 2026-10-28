# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Both authenticated sealer variants preserve nested roster/schedule/ticket scope and complete extents.
import std/assertions
import std/syncio
import ../../support/state_proof_global_helpers
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_consensus as codec_state_consensus
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
let config = SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(2),
  validators: ElementLimit(6), maxBytes: ByteLimit(2017)), epochSlots: EpochSlots(2),
  maxAccumulator: ElementLimit(2), maxBytes: ByteLimit(10000))
let ticket = WinningTicket(attempt: TicketAttempt(7))
for kind in [SealerKind.Tickets, SealerKind.Keys]:
  # Distinct tagged schedules share no implicit representation or fallback interpretation.
  var source = SafroleState(pending: newSeq[StateValidator](6), accumulator: @[ticket])
  source.schedule = if kind == SealerKind.Tickets: ticketSchedule(@[ticket, ticket])
    else: keySchedule(@[default(StateBsKey), default(StateBsKey)])
  let entry = safroleStateEntry(source, config).value
  let view = globalView(@[entry], [entry.key])
  let owner = view.readGlobalSafrole(config).value
  let info = owner.safroleInfo.value
  assert info.kind == kind and info.validators == 6 and info.slots == 2 and info.accumulated == 1
  assert byte(owner.accumulatedTicketAt(SafroleStateIndex(0)).value.attempt) == 7
  if kind == SealerKind.Tickets:
    assert byte(owner.sealerTicketAt(SafroleStateIndex(1)).value.attempt) ==
        7 # Tagged ticket extraction stays ordered.
  else:
    assert array[32, byte](owner.sealerKeyAt(SafroleStateIndex(1)).value) == default(array[32,
        byte]) # Fallback keys remain opaque bytes.
  assert default(ProofView).readGlobalSafrole(config).error == GlobalProofError.Uninitialized
  assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalSafrole(config).error ==
      GlobalProofError.MissingWitness
  assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalSafrole(config).error ==
      GlobalProofError.AbsentValue
  var policy = config
  policy.maxAccumulator = ElementLimit(0)
  assert view.readGlobalSafrole(policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.maxBytes = ByteLimit(entry.value.len-1)
  assert view.readGlobalSafrole(policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.epochSlots = EpochSlots(0)
  assert view.readGlobalSafrole(policy).error == GlobalProofError.InvalidConfig
  for length in [0, 1, 2017, 2161, entry.value.len-1]:
    # Probe nested roster, ring, selected schedule and final ticket boundaries after authentication.
    var truncated = newSeq[byte](length)
    for i in 0..<length: truncated[i] = entry.value[i]
    assert globalView(@[StateEntry(key: entry.key, value: truncated)], [
        entry.key]).readGlobalSafrole(config).error == GlobalProofError.InvalidValue
  var suffix = entry.value
  suffix.add(0)
  assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalSafrole(
      config).error == GlobalProofError.InvalidValue
echo "state-global-safrole-reads: ok"
