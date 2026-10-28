# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real nonempty maintenance fixtures preserve one independent root and explicit canonical epoch ownership.
import std/assertions
import ./storage_light_root
import ./storage_light_journal
import ../../src/storage/light_snapshot as storage_light_snapshot
import ../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/file_errors as storage_file_errors
import ../../src/codec/bounded as codec_bounded
func maintenanceLimits*(): LightMaintenanceLimits =
  ## One ordinary frame requests compaction and at most one old canonical pair, without retaining earlier epochs.
  LightMaintenanceLimits(frames: ElementLimit(1), first: ManagedEpoch(1), epochs: ElementLimit(1))
proc seedLightMaintenance*(path: string, fixture: LightRootFixture,
    compacted = false): PreparedLightSnapshot =
  ## A real ordinary edit precedes all maintenance tests; optional confirmed compaction retains the old pair for cleanup-only work.
  var owner = default(LightJournalCache)
  assert initializeLightJournalCache(owner, path, fixture.oldConfig, fixture.source).error ==
      FileError.None, "initialize maintenance source"
  assert owner.update([], [lightKey(32)]).error == FileError.None, "seed maintenance ordinary frame"
  result = owner.preparedSnapshot.value
  if compacted:
    let plan = prepareLightCompaction(owner, owner.epoch.value, owner.sequence.value).value
    assert owner.compact(plan).error == FileError.None, "seed confirmed cleanup-only source"
  assert owner.close == FileError.None, "retire maintenance fixture owner"
