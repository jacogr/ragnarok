# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual Services startup selects a managed directory explicitly and resumes only its intact selected local head.
import std/[assertions, syncio, envvars]
import ../../support/managed_storage_samples
import ../../../src/app/[services, options]
import ../../../src/chain/[genesis, provider]
import ../../../src/storage/managed/manifest as managed_manifest
proc configured(path: string, layout: string): Options =
  ## Harness-owned configured genesis is captured before listeners or storage become observable.
  result = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-storage", "disk", "--state-db", path, "--state-layout", layout], result)
proc main() {.raises.} =
  ## Exclusive locking and wrong-layout/corrupt-CURRENT refusals never replace an existing selected epoch.
  let path = "managed-services-startup"
  var owner = default(Services)
  var competitor = default(Services)
  defer:
    competitor.close()
    owner.close()
  let selected = configured(path, "managed")
  assert owner.start(selected, "validator")
  let before = owner.chainView.bestBlock.value
  assert not competitor.start(selected, "validator")
  competitor.close()
  owner.close()
  assert owner.start(selected, "validator")
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      before.blockHash)
  assert array[32, byte](owner.chainView.bestBlock.value.stateRoot) == array[32, byte](
      before.stateRoot)
  assert owner.chainView.retainedCount == 1
  assert owner.chainView.finalizedBlock.error == GenesisError.Unavailable
  owner.close()
  let current = path & "/CURRENT"
  let intact = readFile(current)
  assert not owner.start(configured(path, "journal"), "validator")
  owner.close()
  assert readFile(current) == intact
  var corrupt = intact
  corrupt[corrupt.high] = char(ord(corrupt[corrupt.high]) xor 1)
  writeFile(current, corrupt)
  assert not owner.start(selected, "validator")
  owner.close()
  assert readFile(current) == corrupt # Normal startup cannot reset or fall back after integrity refusal.
  writeFile(current, intact)
  assert owner.start(selected, "validator")
  owner.close()
  removeManagedSample(path, [ManagedEpoch(1)])
try:
  main()
except:
  quit(2)
echo "PASS managed services startup: opt-in directory, local restart, lock and wrong-layout/corrupt-head refusal"
