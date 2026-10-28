# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused coordinator payloads and nonselected stage reasons must never be readable.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/state/safrole_transition as state_safrole_transition
import ../../src/state/store as state_store
import ../../src/codec/header as codec_header
var state = default(StateStore)
let outcome = if paramStr(1) == "default": default(SafroleTransitionResult) else:
  advanceSafroleState(state, default(OwnedHeader), [], [], default(SafroleTransitionConfig))
case paramStr(1)
of "default", "error":
  # Both the default and actual invalid-policy failure must reject snapshot extraction.
  echo outcome.value.authentication.ticketed
of "rotation":
  # A preflight/default outcome cannot provide a rotation stage reason.
  echo outcome.rotationError
of "admission":
  # A preflight/default outcome cannot provide a admission stage reason.
  echo outcome.admissionError
of "schedule":
  # A preflight/default outcome cannot provide a schedule stage reason.
  echo outcome.scheduleError
of "marker":
  # A preflight/default outcome cannot provide a marker stage reason.
  echo outcome.markerError
of "authentication":
  # A preflight/default outcome cannot provide a authentication stage reason.
  echo outcome.authenticationError
of "entropy":
  # A preflight/default outcome cannot provide a entropy stage reason.
  echo outcome.entropyError
of "publication":
  # A preflight/default outcome cannot provide a publication stage reason.
  echo outcome.publicationError
else:
  quit(3) # An unknown selector cannot masquerade as a successful guard.
