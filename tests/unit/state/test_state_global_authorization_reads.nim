# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Distinct authenticated pool and fixed queue chapters preserve row order and exact caller ceilings.
import std/assertions
import std/syncio
import ../../support/state_proof_global_helpers
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_authorization as codec_state_authorization
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
let config = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
    maxBytes: ByteLimit(6000))
for kind in [AuthorizationKind.Pools, AuthorizationKind.Queues]:
  # Both shapes retain core and row ordinals; queue lengths have no pool-style count prefix.
  let count = if kind == AuthorizationKind.Pools: 2 else: 80
  var rows = @[newSeq[AuthorizerHash](count), newSeq[AuthorizerHash](count)]
  var marker = default(array[32, byte])
  marker[0] = 77
  rows[1][count-1] = AuthorizerHash(bytes: marker)
  let entry = authorizationEntry(kind, rows, config).value
  let view = globalView(@[entry], [entry.key])
  let owner = view.readGlobalAuthorization(kind, config).value
  assert owner.authorizationKind.value == kind and owner.authorizationCores.value == 2
  assert owner.authorizerCount(AuthorizationCoreIndex(1)).value == count
  assert owner.authorizerAt(AuthorizationCoreIndex(1), AuthorizationIndex(
      count-1)).value.bytes[0] == 77
  rows[1][count-1] = default(AuthorizerHash)
  assert owner.authorizerAt(AuthorizationCoreIndex(1), AuthorizationIndex(
      count-1)).value.bytes[0] == 77
  assert default(ProofView).readGlobalAuthorization(kind, config).error ==
      GlobalProofError.Uninitialized
  assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalAuthorization(kind,
      config).error == GlobalProofError.MissingWitness
  assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalAuthorization(kind,
      config).error == GlobalProofError.AbsentValue
  let other = if kind == AuthorizationKind.Pools: AuthorizationKind.Queues else: AuthorizationKind.Pools
  assert view.readGlobalAuthorization(other, config).error == GlobalProofError.MissingWitness
  var policy = config
  policy.maxHashes = ElementLimit(0)
  assert view.readGlobalAuthorization(kind, policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.maxBytes = ByteLimit(entry.value.len-1)
  assert view.readGlobalAuthorization(kind, policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.cores = CoreCount(0)
  assert view.readGlobalAuthorization(kind, policy).error == GlobalProofError.InvalidConfig
  for length in [0, 1, 31, entry.value.len-1]:
    # Probe count/hash/row boundaries and the final required byte with real authenticated membership.
    var truncated = newSeq[byte](length)
    for i in 0..<length: truncated[i] = entry.value[i]
    assert globalView(@[StateEntry(key: entry.key, value: truncated)], [
        entry.key]).readGlobalAuthorization(kind, config).error == GlobalProofError.InvalidValue
  var suffix = entry.value
  suffix.add(0)
  assert globalView(@[StateEntry(key: entry.key, value: suffix)], [
      entry.key]).readGlobalAuthorization(kind, config).error == GlobalProofError.InvalidValue
echo "state-global-authorization-reads: ok"
