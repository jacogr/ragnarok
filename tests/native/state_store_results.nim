# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated misuse probes exercise only public store accessors, with runtime-selected invalid
## origins.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import ../../src/state/store
import ../../src/codec/[state_trie, state_layout, bounded]

## Return a default or actual failed construction without exposing an unchecked store payload.
proc storeFailure(origin: string): StateStoreResult[StateStore] =
  if origin == "default":
    # Default result variants have no successful store handle.
    return default(StateStoreResult[StateStore])
  newStateStore(@[StateEntry(key: default(StateKey))], default(StateStoreLimits))

## Return a default or rejected write result; neither may supply a snapshot or root.
proc snapshotFailure(origin: string): StateStoreResult[StateStoreSnapshot] =
  if origin == "default":
    # Uninitialized result payloads must be protected independently of actual operation failures.
    return default(StateStoreResult[StateStoreSnapshot])
  let made = newStateStore([], default(StateStoreLimits))
  assert made.error == StateStoreError.None
  var state = made.value
  state.apply(@[StateWrite(key: default(StateKey), kind: StateWriteKind.Put)])

## Return a default or real missing-key lookup, preserving the distinction from a present empty value.
proc valueFailure(origin: string): StateStoreResult[StateValue] =
  if origin == "default":
    # Default lookups must never provide an apparently valid zero-length view.
    return default(StateStoreResult[StateValue])
  let made = newStateStore([], default(StateStoreLimits))
  assert made.error == StateStoreError.None
  made.value.snapshot.value.lookup(default(StateKey))

## Selectors remain dynamic so invalid public accesses are tested at runtime, not optimized away as constants.
proc main() =
  let member = paramStr(1)
  let origin = paramStr(2)
  case member
  of "store":
    # Both failed construction and default variants must reject before any handle can be extracted.
    let rejected = storeFailure(origin)
    assert rejected.error == (if origin == "default": StateStoreError.Uninitialized else: StateStoreError.LimitExceeded)
    discard rejected.value.snapshot
  of "snapshot":
    # A failed atomic batch cannot authorize reading a default-looking root/count snapshot.
    let rejected = snapshotFailure(origin)
    assert rejected.error == (if origin == "default": StateStoreError.Uninitialized else: StateStoreError.LimitExceeded)
    echo rejected.value.commitment.entries
  of "lookup":
    # Missing and default lookups must reject before a view can be extracted or read.
    let rejected = valueFailure(origin)
    assert rejected.error == (if origin == "default": StateStoreError.Uninitialized else: StateStoreError.MissingKey)
    echo rejected.value.byteLength
  of "metadata", "length", "bytes":
    # Valid controls use a genuine initialized present-empty entry under the same compiler/link profile.
    let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1),
      perValue: ByteLimit(0), totalValueBytes: ByteLimit(0), nodes: TrieNodeLimit(1)))
    let made = newStateStore(@[StateEntry(key: default(StateKey))], limits)
    assert made.error == StateStoreError.None
    let active = made.value.snapshot.value
    if member == "metadata":
      # Default snapshots cannot supply commitment metadata; the valid control reports one entry.
      let selected = if origin == "default": default(StateStoreSnapshot) else: active
      echo selected.commitment.entries
    else:
      # Default retained views cannot be mistaken for the valid zero-byte value used by the control.
      let selected = if origin == "default": default(StateValue) else: active.lookup(default(
          StateKey)).value
      if member == "length":
        echo selected.byteLength # Contract checks owner validity before reading an entry length.
      else:
        echo selected.bytes.len # Copying requires the exact same initialized retained owner.
  else:
    # Unknown selectors are harness errors, never evidence of a supported contract rejection.
    quit(2)

main()
