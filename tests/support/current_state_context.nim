# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared explicit policies and actual producer constructors for supplied-current consumers.
import ./[current_checkpoint_context, current_typed_context, accumulation_current_chain_context, state_inventory_context]
import ../../src/state/current/[state as current_state, globals as current_globals,
    profile as current_profile]
import ../../src/state/global_snapshot
import ../../src/state/accumulation/current/update as accumulation_current_update
import ../../src/codec/bounded
import ../../src/codec/state/composition as state_composition
proc currentQualifiedState*(source: PreparedCurrentChainUpdate): CurrentStateSerialization =
  ## Supply authored declarations and verify every key/value against this original genuine successor.
  let profile = captureCurrentProfile(source, CurrentProfileLimits(validators: ElementLimit(1024),
      bytes: ByteLimit(65536))).value
  let globals = qualifyCurrentGlobals(profile, GlobalStateLimits(chapter: StateChapterPolicy(
      items: ElementLimit(10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
  qualifyCurrentState(globals, currentSuppliedServices(source.currentUpdateState),
      inventoryCaptureLimits).value
