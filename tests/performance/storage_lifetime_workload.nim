# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One independently validated lifetime scenario emits scalar checkpoints after every owner retires.
import std/[assertions, cmdline, syncio]
import ../support/storage_lifetime_samples

proc main() =
  ## Accept a fixed bounded plan; no argument can widen production storage policy.
  assert paramCount() == 2 and paramStr(1) == "fixture"
  assert paramStr(2) in ["1024", "8192", "32768"]
  let count = if paramStr(2) == "1024": 1024 elif paramStr(2) == "8192": 8192 else: 32768
  let observed = fixtureLifetime(count)
  echo "lifetime\tfixture\t", count, "\t64\t", observed.checks, "\t", observed.baseline,
    "\t", observed.fixture, "\t", observed.owner, "\t", observed.held, "\t", observed.closed,
    "\t", observed.released

main()
