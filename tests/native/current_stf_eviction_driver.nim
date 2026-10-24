# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real ticket contest replacement and non-retention execute through complete current candidate publication.
import std/[assertions, cmdline, syncio]
import ../support/current_stf_epoch_context as epoch
import ../../src/app/[chain, candidate]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, state_layout, state_safrole, report_owned, block_codec, tickets]
import ../../src/state/[store, accumulation_current_update, ticket_admission]
import ../../src/bandersnatch/bandersnatch
import ../support/[current_consecutive_context, accumulation_current_chain_context]

proc generate(parent: BlockSnapshot) =
  ## Explicit generation freezes two Ring/KZG input witnesses; normal verification never invokes the prover.
  let policy = currentConsecutiveLimits().reporting.safrole.state
  let captured = decodeSafroleState(parent.stateSnapshot.lookup(chapterKey(StateChapter(
      4))).value.bytes, policy).value.snapshot
  var roster: seq[StateValidator] = @[]
  for index in 0..<6: roster.add(pendingValidatorAt(captured, StateValidatorIndex(uint64(index))).value)
  let setup = newSetup(6).value
  for secret in [1, 6]:
    let proof = signRing(setup, epoch.key(secret), (secret+4) mod 6, epoch.members(roster),
        epoch.context("jam_ticket_seal", default(array[32, byte]), 3), []).value
    echo "T ", secret, " 3 ", epoch.hex(array[784, byte](proof))
  close(setup)

proc main() {.raises.} =
  ## Ten genuine children retain original parents while the independent oracle owns all expected map bytes.
  let raw = readFile(paramStr(1))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let parent = epoch.original(decodeOwnedReport(bytes, 2).value)
  if paramStr(2) == "--generate":
    generate(parent) # The corpus supplies a frozen bank path instead of this explicit generation mode.
    return
  let bank = epoch.readBank(paramStr(2), 16)
  var chain = initApplicationChain(genesisView(captureBlockSnapshot(currentChainBytes(
      parent.header), parent.stateSnapshot, currentChainSettings()))).value
  let saved = epoch.checkpointHex(parent.stateSnapshot)
  echo "P ", saved
  for slot in [2'u32, 3, 4, 5, 6, 7, 10, 11, 12, 13]:
    let prior = chain.chainView.bestBlock.value
    var submitted: seq[Ticket] = @[]
    if slot in 2'u32..5'u32:
      for index in (int(slot)-2)*3..<(int(slot)-1)*3: submitted.add(bank[index].ticket)
    elif slot == 6:
      submitted.add(bank[14].ticket) # An independently lower score replaces exactly the previous worst ticket.
    if slot == 7:
      epoch.refused(chain, epoch.child(prior, slot, @[bank[15].ticket], bank),
          TicketAdmissionError.NotRetained)
      epoch.refused(chain, epoch.child(prior, slot, @[bank[11].ticket], bank),
          TicketAdmissionError.NotRetained)
    let child = epoch.child(prior, slot, submitted, bank)
    var wire = newSeq[byte](child.blockInfo.value.consumed)
    assert child.encodeOwnedBlock(wire).error == FrameError.None
    echo "B ", epoch.hex(wire)
    let prepared = prepareCurrentCandidate(chain, child, [], currentConsecutiveLimits())
    assert prepared.error == CurrentCandidateError.None
    chain.installPrepared(prepared.value)
    echo "O ", epoch.checkpointHex(chain.stateSnapshot.value)
  assert epoch.checkpointHex(parent.stateSnapshot) == saved

try:
  main() # Any proof, admission or map failure terminates the normal corpus with a nonzero status.
except:
  quit(2)
