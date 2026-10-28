# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and legacy configurations expose no mutation policy through guarded accessors.

import std/cmdline
import std/assertions
import ../../src/app/options as app_options

let argument = paramStr(1)
var configuration = default(Options)
if argument == "disabled-count" or argument == "disabled-bytes":
  assert parseCanonicalOptions(@["server"], configuration) # A valid legacy configuration still selects no state policy.
if argument == "default-count" or argument == "disabled-count":
  discard configuration.stateWrites # Both accessors require a parsed active canonical policy.
else:
  discard configuration.stateWriteBytes # Default/legacy alternatives cannot expose unused budget storage.
