# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine computed admission and independently rebuilt equal-root receivers exercise exact-parent publication.

import std/assertions
import ../../src/state/[computed_admission, store]
import ../../src/codec/state_trie
import ./[pvm_computed_admission, report_context]

proc publicationFixture*(withReady = false, withRound = false,
    withExecution = false, invalidEntry = false, withComposition = false): AdmittedComputedReports =
  ## Complete actual two-package execution, signed inclusion and maintained report admission before successor preparation.
  let source = admissionFixture(withReady = withReady, withRound = withRound,
      withExecution = withExecution, invalidEntry = invalidEntry, withComposition = withComposition)
  let admitted = admitComputedReports(source, computedAdmissionConfig(source))
  assert admitted.error == ComputedAdmissionError.None, "genuine computed admission for publication"
  admitted.value
proc rebuiltStore*(snapshot: StateStoreSnapshot): StateStore =
  ## Equal full serialized mappings remain independently owned and cannot replace the original execution version.
  var entries = newSeq[StateEntry](snapshot.commitment.entries)
  for i in 0..<entries.len:
    let key = snapshot.keyAt(StateEntryIndex(i)).value
    entries[i] = StateEntry(key: key, value: snapshot.lookup(
        key).value.bytes) # Reconstruct all complete-map bytes, never partial state.
  newStateStore(entries, limits()).value
