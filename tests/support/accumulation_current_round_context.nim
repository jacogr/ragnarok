# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Maintained tiny-chain current round configuration and real deferred-transfer/yield programs.
import ../../src/chain/parameters
import ../../src/codec/[bounded, composite]
import ../../src/codec/state/outputs as state_outputs
import ../../src/pvm/[machine, step, gas]
import ../../src/state/accumulation/current/round as accumulation_current_round
import ../../src/state/accumulation/[guest_runner as accumulation_guest_runner,
    provisions as accumulation_provisions, annulled_outputs as accumulation_annulled_outputs,
    transfers as accumulation_transfers, pending_transfers as accumulation_pending_transfers]
import ./[accumulation_current_guests_context, pvm_accumulation_program]
proc currentRoundLimits*(): CurrentAccumulationRoundLimits =
  ## Independent phase policies make every actual parent refusal observable without weakening later completeness.
  var guests = currentGuestLimits()
  guests.steps = ExecutionStepLimit(200)
  guests.calls = HostCallLimit(32)
  guests.copyBytes = MemoryByteLimit(128)
  guests.transfers = ElementLimit(2)
  guests.modifiedAccounts = ElementLimit(8)
  guests.accountWriteFacts = ElementLimit(8)
  CurrentAccumulationRoundLimits(guests: guests, accounts: currentAccountStageLimits(),
    provisions: AccumulationProvisionUnionLimits(contexts: ElementLimit(2),
      values: PreimageLimits(items: ElementLimit(0), perBlob: ByteLimit(0),
          totalBlobBytes: ByteLimit(0)), encodedBytes: ByteLimit(8)),
    globals: currentGlobalStageLimits(),
    outputs: AnnulmentOutputLimits(outcomes: ElementLimit(2), log: OutputLogConfig(
        items: ElementLimit(2), maxBytes: ByteLimit(100))),
    transfers: AccumulationTransferCollectionLimits(sources: ElementLimit(2),
        transfers: ElementLimit(2), memoBytes: ByteLimit(256)),
    pending: PendingTransferLimits(sources: ElementLimit(2), transfers: ElementLimit(2),
        memoBytes: ByteLimit(256)))
proc currentRoundParameters*(): Parameters =
  ## Match the genuine tiny chain and current fixed128-byte transfer memo independently of local copy limits.
  var wire = encodeParameters(currentGuestParameters())
  for index in 110..<114: wire[index] = 0 # Entire Appendix B memo extent, not a truncated override.
  wire[110] = 128
  decodeParameters(wire).value
proc currentRoundServiceCode*(instructions: seq[seq[byte]]): seq[byte] =
  ## Real deferred transfer and yield instructions share one canonical service preimage/envelope.
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable = newSeq[byte](128)): result.add(octet)
proc currentTransferProgram*(destination: uint64, gas = 3'u64): seq[byte] =
  ## A genuine nonzero memo pointer selects deferred transfer even with zero token value.
  currentRoundServiceCode(@[registerImmediate(7, high(uint64)), registerImmediate(8, destination),
      registerImmediate(9, 0),
    registerImmediate(10, 0), registerImmediate(11, gas), registerImmediate(12, 196608), @[10'u8, 22],
    registerImmediate(7, 65536), @[10'u8, 27], @[50'u8, 0]])
