# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One independently validated lifetime scenario emits scalar checkpoints after every owner retires.
import std/assertions
import std/cmdline
import std/syncio
import ../support/storage_lifetime_samples

proc main() =
  ## Accept a fixed bounded plan; no argument can widen production storage policy.
  assert paramCount() == 2
  assert paramStr(1) in ["fixture", "owner", "reader", "readers", "extraction", "lookups", "selection"]
  assert paramStr(2) in ["1024", "8192", "32768"]
  let count = if paramStr(2) == "1024": 1024 elif paramStr(2) == "8192": 8192 else: 32768
  let scenario = paramStr(1)
  var observed = default(LifetimeObservation)
  if scenario == "fixture":
    # This branch owns only the named resource lifetime.
    observed = fixtureLifetime(count)
  elif scenario == "owner":
    # This branch owns only the named resource lifetime.
    observed = memoryOwnerLifetime(count)
  elif scenario == "reader":
    # This branch owns only the named resource lifetime.
    observed = memoryReaderLifetime(count)
  elif scenario == "readers":
    # This branch owns only the named resource lifetime.
    observed = memoryReadersLifetime(count)
  elif scenario == "extraction":
    # This branch owns only the named resource lifetime.
    observed = memoryExtractionLifetime(count)
  elif scenario == "lookups":
    # This branch owns only the named resource lifetime.
    observed = memoryLookupsLifetime(count)
  elif scenario == "selection":
    # This branch owns only the named resource lifetime.
    observed = memorySelectionLifetime(count)
  echo "lifetime\t", scenario, "\t", count, "\t64\t", observed.checks, "\t", observed.baseline,
    "\t", observed.fixture, "\t", observed.owner, "\t", observed.held, "\t", observed.closed,
    "\t", observed.released

main()
