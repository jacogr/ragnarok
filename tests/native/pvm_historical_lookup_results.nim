# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated default/refused historical lookup accessors retain their optimized runtime contracts.

import std/[assertions, cmdline]
import ../../src/state/[refinement_lookup, store]
import ../../src/codec/[composite, work_report]
import ../../src/pvm/[machine, step]

proc checkRefusal(outcome: HistoricalLookupResult[HistoricalLookupContext]) =
  ## A positive control confirms the intended missing-owner refusal before forbidden extraction.
  assert outcome.error == HistoricalLookupError.InvalidContext

let refused = captureHistoricalLookup(default(StateStoreSnapshot), ServiceIndex(42), LookupSlot(0))
checkRefusal(refused)
case paramStr(1)
of "context-default":
  # Default context results have no immutable owner to extract.
  let empty = default(HistoricalLookupResult[HistoricalLookupContext])
  discard empty.value
of "context-refused":
  # A rejected capture cannot fabricate a usable context.
  discard refused.value
else:
  # Default guest-response results cannot fabricate registers or memory.
  let empty = default(HistoricalLookupResult[HostResponse])
  discard empty.value
