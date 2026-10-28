# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full report adapter: the crypto check subcommand and standalone codec batch share exact codec
## coverage.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/cmdline
import std/syncio
import ./state_report_check
# Explicit credential verification remains a separate integration workload.
if paramCount() > 0 and paramStr(1) == "check":
  try:
    reportFixtureCheck()
  except:
    # A malformed trusted fixture or I/O failure cannot count as a credential verdict.
    quit(2)
  quit(0)
# Every ordinary request uses the same complete codec/owner adapter as the Nimony trial.
include ./state_report_codec_driver
