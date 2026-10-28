# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized recent-anchor result guards include genuine independent full C3 correction controls.

import std/assertions
import std/cmdline
import ../../src/state/computed_recent as state_computed_recent
import ../../src/state/computed_state as state_computed_state
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_history as codec_state_history
import ../../src/codec/assurances as codec_assurances
import ../support/pvm_computed_recent
import ../support/pvm_computed_state_vectors

proc check[T](outcome: ComputedRecentResult[T], reason: ComputedRecentError) =
  ## Confirm selected alternatives before deliberate unsuccessful extraction.
  assert outcome.error == reason, "computed recent guard control"
let fixture = recentFixture()
let done = checkComputedRecentAnchor(fixture.source, recentConfig())
check(done, ComputedRecentError.None)
assert array[32, byte](done.value.computedRecentAnchor.value.header) == StateParentHash, "independent full sealed-parent anchor control"
assert uint32(done.value.computedRecentAnchor.value.slot) == 20, "complete tuple positive control"
let missing = default(ComputedRecentResult[RecentComputedReport])
let source = checkComputedRecentAnchor(default(StateBoundComputedReport), recentConfig())
check(source, ComputedRecentError.InvalidSource)
var foreign = recentConfig()
foreign.cores = CoreCount(3)
let config = checkComputedRecentAnchor(fixture.source, foreign)
check(config, ComputedRecentError.InvalidConfig)
let absent = checkComputedRecentAnchor(recentFixture(9).source, recentConfig())
check(absent, ComputedRecentError.MissingState)
let chapter = checkComputedRecentAnchor(recentFixture(11).source, recentConfig())
check(chapter, ComputedRecentError.InvalidHistory)
var short = recentConfig()
short.maxBytes = ByteLimit(0)
let limited = checkComputedRecentAnchor(fixture.source, short)
check(limited, ComputedRecentError.LimitExceeded)
let anchor = checkComputedRecentAnchor(recentFixture(5).source, recentConfig())
check(anchor, ComputedRecentError.InvalidRecentAnchor)
case paramStr(1)
of "default": discard missing.value # No completed anchor in default alternatives.
of "source": discard source.value # No source-derived history without original admitted state.
of "config": discard config.value # Caller cores cannot replace original execution parameters.
of "missing": discard absent.value # Missing C3 cannot mean genesis history.
of "chapter": discard chapter.value # No corrected prefix from malformed state.
of "limit": discard limited.value # No allocation/anchor payload after budget refusal.
of "anchor": discard anchor.value # Fields from separate records cannot produce a matched tuple.
of "owner": discard default(RecentComputedReport).computedRecentSource.value # Defaults have no original state-bound source.
of "history": discard default(RecentComputedReport).computedRecentHistory.value # Defaults have no corrected history.
else: discard default(RecentComputedReport).computedRecentAnchor.value # Defaults have no matched record.
