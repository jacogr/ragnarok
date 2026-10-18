# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic public-access misuse probes require supported contract failures, not unrelated
## process crashes.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import ../support/authorization_transition_fixture
import ../../src/state/[authorization, store]
import ../../src/codec/state_trie

## Select default or an actual invalid-core failure without granting access to a proposed C(1) entry.
proc rejectedEntry(origin: string): AuthorizationTransitionResult[StateEntry] =
  if origin == "default":
    return default(AuthorizationTransitionResult[StateEntry]) # Default carries no entry payload.
  let pools = authOwner(AuthorizationKind.Pools, @[newSeq[AuthorizerHash](0), newSeq[
      AuthorizerHash](0)])
  let queues = authOwner(AuthorizationKind.Queues, authQueues())
  advanceAuthorization(pools, queues, @[CoreAuthorizer(core: AuthorizationCoreIndex(2),
      authorizer: authHash(1))],
    AuthorizationSlot(0), authConfig())

## Select default or an actual missing-state failure; neither can authorize snapshot/root access.
proc rejectedState(origin: string): AuthorizationTransitionResult[StateStoreSnapshot] =
  if origin == "default":
    return default(AuthorizationTransitionResult[StateStoreSnapshot]) # Default carries no snapshot payload.
  let made = newStateStore([], default(StateStoreLimits))
  assert made.error == StateStoreError.None
  var state = made.value
  advanceAuthorizationState(state, [], AuthorizationSlot(0), authConfig())

case paramStr(1)
of "entry":
  # Both actual invalid input and default alternatives must stop before their first payload read.
  let parsed = rejectedEntry(paramStr(2))
  assert parsed.error == (if paramStr(2) == "default": AuthorizationTransitionError.Uninitialized else: AuthorizationTransitionError.InvalidCore)
  echo parsed.value.value.len
of "state":
  # Failure cannot publish even apparently harmless copied default metadata.
  let parsed = rejectedState(paramStr(2))
  assert parsed.error == (if paramStr(2) == "default": AuthorizationTransitionError.Uninitialized else: AuthorizationTransitionError.MissingState)
  echo parsed.value.commitment.entries
else:
  quit(2) # Unknown selectors are harness errors rather than accepted contract rejection evidence.
