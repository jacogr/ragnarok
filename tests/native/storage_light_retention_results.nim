# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic plan/result misuse guards have genuine initialized empty-knowledge positive controls.
import std/[cmdline, syncio]
import ../../src/storage/[light_snapshot, light_state_cache, database_identity]
import ../../src/codec/[bounded, state_trie]
let member = paramStr(1)
let origin = paramStr(2)
if member == "result" and origin != "valid":
  # A missing source or default result never exposes a completed removal prefix.
  let outcome = if origin == "default": default(LightSnapshotResult[LightRetentionPlan])
    else: planLightRetention(default(PreparedLightSnapshot), [], default(LightRetentionLimits))
  echo outcome.value.len
elif origin == "default":
  # Opaque default plans guard every payload accessor, independently of failed-result guards.
  let plan = default(LightRetentionPlan)
  if member == "len": echo plan.len
  else: echo plan.forgottenKeys.len
else:
  # A successful empty rooted image produces a real zero-removal plan with exact inherited ceilings.
  let policy = LightSnapshotLimits(bytes: ByteLimit(4096))
  let source = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy).value
  let limits = LightRetentionLimits(bytes: policy.bytes)
  let plan = planLightRetention(source, [], limits).value
  if member == "keys": echo plan.forgottenKeys.len
  else: echo plan.len
