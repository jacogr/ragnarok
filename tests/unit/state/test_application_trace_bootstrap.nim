# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published Genesis ownership and independently supplied header/state/profile anchors govern new replay chains.
import std/[assertions, envvars, syncio, parseutils]
import ../../support/[trace_step_context, accumulation_current_chain_context]
import ../../../src/state/trace/[genesis as trace_genesis, state as trace_state]
import ../../../src/state/store
import ../../../src/app/trace/bootstrap as trace_bootstrap
import ../../../src/app/chain
import ../../../src/chain/[genesis, parameters, provider]
import ../../../src/codec/[header, bounded, assurances]
import ../../../src/codec/state/trie as state_trie
proc word(text: string): array[32, byte] =
  ## Decode only frozen independently calculated trust literals, not roots or hashes read from the incoming Genesis file.
  assert text.len == 64
  result = default(array[32, byte])
  for index in 0..<32:
    var octet: byte = 0
    assert parseHex(text.substr(index*2, index*2+1), octet) == 2
    result[index] = octet
proc main() {.raises.} =
  ## Configured anchors and full Parameters remain separate from untrusted binary input throughout ownership capture.
  let missing = default(TraceBootstrapResult)
  assert missing.error == TraceBootstrapError.Uninitialized
  let absent = default(TraceGenesis)
  assert absent.traceGenesisBytes.error == TraceGenesisError.InvalidOwner
  assert absent.traceGenesisHeader.error == TraceGenesisError.InvalidOwner
  assert absent.traceGenesisState.error == TraceGenesisError.InvalidOwner
  let policy = traceStepTestLimits()
  let limits = TraceGenesisLimits(header: HeaderConfig(cores: CoreCount(2),
      authorValidators: ValidatorCount(6), epochSlots: EpochSlots(12), maxBytes: ByteLimit(4096)),
          state: policy.state, bytes: policy.bytes)
  let path = getEnv("RAGNAROK_TRACE_GENESIS")
  assert path.len != 0
  let text = readFile(path)
  var original = newSeq[byte](text.len)
  for index in 0..<text.len: original[index] = byte(text[
      index]) # Retain exact independent fixture bytes before mutating the separate source buffer.
  var input = original
  input.add(255)
  var decoded = decodeTraceGenesis(input, limits)
  assert decoded.error == TraceGenesisError.None
  var owner = decoded.value
  assert owner.traceGenesisBytes.value == original.len
  let header = owner.traceGenesisHeader.value
  let state = owner.traceGenesisState.value
  for index in 0..<input.len: input[index] = 0 # Neither retained child may alias mutable caller storage.
  assert owner.copyTraceGenesis(policy.bytes).value == original
  for ceiling in 0..<original.len:
    assert owner.copyTraceGenesis(ByteLimit(ceiling)).error == TraceGenesisError.LimitExceeded
  let parameters = currentChainSettings()
  let trust = TraceBootstrapTrust(header: BlockHash(word(
      "1b2fef618dd810d8cedce751dfc54ddc29e0bc16f2989828511f6cd8466e7cad")), state: StateRoot(word(
      "1248002a5bcc6ad701f8729cbb9e033e26acfabd6fbddcd48164c370d4eb8555")))
  assert bootstrapTraceChain(absent, trust, parameters).error == TraceBootstrapError.InvalidOwner
  assert bootstrapTraceChain(owner, trust, default(Parameters)).error ==
      TraceBootstrapError.InvalidParameters
  let captured = bootstrapTraceChain(owner, trust, parameters)
  assert captured.error == TraceBootstrapError.None
  assert array[32, byte](captured.value.chainView.bestBlock.value.blockHash) == array[32, byte](trust.header)
  assert captured.value.chainView.bestBlock.value.chainParameters.encodeParameters ==
      parameters.encodeParameters
  assert sameStateStorePolicy(state.traceStateSnapshot.value, captured.value.stateSnapshot.value)
  var wrong = trust
  var changed = word("1b2fef618dd810d8cedce751dfc54ddc29e0bc16f2989828511f6cd8466e7cad")
  changed[0] = changed[0] xor 1
  wrong.header = BlockHash(changed)
  assert bootstrapTraceChain(owner, wrong, parameters).error == TraceBootstrapError.HeaderMismatch
  wrong = trust
  changed = word("1248002a5bcc6ad701f8729cbb9e033e26acfabd6fbddcd48164c370d4eb8555")
  changed[0] = changed[0] xor 1
  wrong.state = StateRoot(changed)
  assert bootstrapTraceChain(owner, wrong, parameters).error == TraceBootstrapError.StateMismatch
  decoded = default(TraceGenesisResult[TraceGenesis])
  owner = default(TraceGenesis)
  let retained = newTraceGenesis(header, state, policy.bytes)
  assert retained.error == TraceGenesisError.None
  assert retained.value.copyTraceGenesis(policy.bytes).value ==
      original # Independent child owners survive release of both enclosing handles.
  let short = decodeTraceGenesis([0'u8], limits)
  assert short.error == TraceGenesisError.HeaderFailure
  var bad = original
  bad[297] = bad[297] xor 1
  let corrupt = decodeTraceGenesis(bad, limits)
  assert corrupt.error == TraceGenesisError.StateFailure and corrupt.stateFailure ==
      TraceStateError.RootMismatch
  echo "PASS published Genesis: immutable framing and independent header/state/profile anchors"
try:
  main() # Absent configuration and I/O failures cannot become a successful replay bootstrap.
except:
  quit(2)
