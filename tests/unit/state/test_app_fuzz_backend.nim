# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Arbitrary owned fuzz seeds and typed local refusals do not acquire production bootstrap or consensus Error authority.
import std/assertions
import std/syncio
import ../../support/app_fuzz_backend_context
import ../../support/app_fuzz_protocol_context
import ../../../src/app/fuzz_backend as app_fuzz_backend
import ../../../src/state/fuzz_protocol as state_fuzz_protocol
import ../../../src/state/store as state_store
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
proc main() =
  ## Empty seed initialization and exact state retrieval require neither application context nor a fabricated chain.
  let config = fuzzBackendTestConfig()
  let missing = default(FuzzBackendResult[FuzzMessage])
  assert missing.error == FuzzBackendError.Uninitialized
  var absent = default(FuzzBackend)
  assert absent.fuzzBackendHeader.error == FuzzBackendError.MissingSeed
  assert absent.executeFuzz(default(FuzzMessage)).error == FuzzBackendError.Uninitialized
  var bad = config
  bad.parameters = default(Parameters)
  assert initFuzzBackend(bad).error == FuzzBackendError.InvalidConfiguration
  bad = config
  bad.forkStates = ElementLimit(65)
  assert initFuzzBackend(bad).error == FuzzBackendError.InvalidConfiguration
  var backend = initFuzzBackend(config).value
  assert backend.executeFuzz(default(FuzzMessage)).error == FuzzBackendError.InvalidRequest
  var wire = newSeq[byte](300)
  wire[0] = 1
  wire[33] = 77 # Arbitrary parent-state content is retained; it cannot select or authenticate the supplied posterior map.
  let seed = decodeFuzzMessage(wire, config.wire).value
  var body = newSeq[byte](305)
  body[0] = 3
  let imported = decodeFuzzMessage(body, config.wire).value
  assert backend.executeFuzz(imported).error == FuzzBackendError.MissingSeed
  let initialized = backend.executeFuzz(seed)
  assert initialized.error == FuzzBackendError.None
  assert backend.executeFuzz(seed).error == FuzzBackendError.AlreadyInitialized
  assert backend.fuzzBackendHeader.error == FuzzBackendError.None
  let state = backend.executeFuzz(fuzzGetState(seed.fuzzHeader.value))
  assert state.error == FuzzBackendError.None
  assert state.value.copyFuzzMessage(config.wire.bytes).value == @[5'u8, 0]
  assert state.value.fuzzState.value.commitment.entries == 0
  assert backend.executeFuzz(imported).error == FuzzBackendError.SeedContextFailure
  assert backend.executeFuzz(fuzzGetState(seed.fuzzHeader.value)).value.copyFuzzMessage(
      config.wire.bytes).value == @[5'u8, 0]
  var query = newSeq[byte](33)
  query[0] = 4
  assert backend.executeFuzz(decodeFuzzMessage(query, config.wire).value).error ==
      FuzzBackendError.UnknownState
  assert backend.executeFuzz(initialized.value).error == FuzzBackendError.InvalidRequest
  var withAncestry = wire
  withAncestry[withAncestry.high] = 1
  for index in 0..<36: withAncestry.add(0) # Initial ancestry is not advertised by this linear backend.
  var fresh = initFuzzBackend(config).value
  assert fresh.executeFuzz(decodeFuzzMessage(withAncestry, config.wire).value).error ==
      FuzzBackendError.UnsupportedFeature
  assert fresh.fuzzBackendHeader.error == FuzzBackendError.MissingSeed
  assert fresh.executeFuzz(seed).error == FuzzBackendError.None
  backend = initFuzzBackend(config).value
  assert backend.fuzzBackendHeader.error == FuzzBackendError.MissingSeed
  echo "PASS JAM fuzzer backend: exact arbitrary seeds, whole-state queries and typed local refusals"
main()
