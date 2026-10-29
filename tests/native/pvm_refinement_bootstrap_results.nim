# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized probes reject default/refused bootstrap values, BAD executable payloads and absent preimages.

import std/[assertions, cmdline]
import ../../src/state/refinement/[bootstrap as refinement_bootstrap,
    dispatch as refinement_dispatch, lookup as refinement_lookup]
import ../../src/state/store
import ../../src/pvm/[host_fetch, refinement_exports]
import ../../src/chain/parameters
import ../../src/codec/bounded
import ../../src/codec/work/[package as work_package, report as work_report]
import ../../src/codec/state/trie as state_trie

proc parameters(): Parameters =
  ## Positive configuration is independent of the intentionally absent service/code data.
  var wire = default(array[122, byte])
  for index in 0..<122: wire[index] = 255
  decodeParameters(wire).value
proc checkRefusal(outcome: RefinementBootstrapResult[PreparedRefinementBootstrap]) =
  ## Default package ownership selects a local refusal before any machine or arguments exist.
  assert outcome.error == RefinementBootstrapError.InvalidSelection

let missing = default(RefinementBootstrapResult[PreparedRefinementBootstrap])
let owner = default(PreparedRefinementBootstrap)
let refused = prepareRefinementBootstrap(default(StateStoreSnapshot), default(OwnedWorkPackage),
  FetchItemIndex(0), CoreIndex(0), parameters(), default(RefinementBootstrapLimits))
checkRefusal(refused)
var wire = default(array[512, byte])
let config = fullPackageConfig(ByteLimit(512))
let size = encodeWorkPackage(WorkPackage(items: @[WorkItem()]), config, wire).value
let package = decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
let state = newStateStore([], StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(0),
  perValue: ByteLimit(0), totalValueBytes: ByteLimit(0), nodes: TrieNodeLimit(
      0)))).value.snapshot.value
let bad = prepareRefinementBootstrap(state, package, FetchItemIndex(0), CoreIndex(0), parameters(),
  default(RefinementBootstrapLimits)).value
assert bad.bootstrapInfo.value.status == RefinementCodeStatus.Bad
case paramStr(1)
of "default":
  discard missing.value # Default result has no retained bootstrap.
of "refused":
  discard refused.value # Failed selection has no partial bootstrap.
of "bad-machine":
  discard bad.bootstrapMachine.value # BAD cannot fabricate an executable CPU.
of "bad-arguments":
  discard bad.bootstrapArguments.value # BAD cannot fabricate successful empty arguments.
of "bad-hash":
  discard bad.bootstrapPackageHash.value # BAD has no computed package hash.
of "bad-hosts":
  discard bad.bootstrapHosts([], default(RefinementInputs), ExportOffset(0),
    default(RefinementCaptureLimits)).value # BAD cannot authorize a host environment.
of "default-info":
  discard owner.bootstrapInfo.value # Default owners cannot masquerade as protocol BAD.
else:
  let absent = default(HistoricalPreimage)
  discard absent.value # Optional absence has no immutable preimage bytes.
