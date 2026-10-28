# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Measure exact-start pricing lookups with genuine owners, known prices and invalid-start controls.
## Samples include the cold first memo query; the Python runner retains all rows and summarizes warm samples separately.
import std/assertions
import std/syncio
import std/monotimes
import ../../src/pvm/program as pvm_program
import ../../src/pvm/gas as pvm_gas
import ../../src/pvm/gas_plan as pvm_gas_plan
import ../../src/pvm/gas_memo as pvm_gas_memo
let parsed = decodeProgram([0'u8, 0, 3, 0, 0, 0, 7], CodeAddress(0), ProgramByteLimit(7),
    JumpCountLimit(0))
assert parsed.error == ProgramError.None
let owner = parsed.value
let prepared = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(3),
    bytes: GasPlanByteLimit(24), cycles: GasCycleLimit(5)))
let learned = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(24), cycles: GasCycleLimit(5)))
assert prepared.error == GasPlanError.None and learned.error == GasMemoError.None
# Both policies query the same three independently framed trap blocks and one invalid start.
for mode in 0..<2:
  # Retain the first observation rather than silently warming the memo before measurement.
  for sample in 0..<13:
    var total = 0'u64
    let started = getMonoTime().ticks
    # Two million exact-start queries per sample stay bounded and preserve observable checksums.
    for round in 0..<500000:
      # Distinct starts include the out-of-code refusal, whose failure must carry no price.
      for pc in 0..<4:
        if mode == 0:
          # Complete plans never mutate their immutable price payload.
          let price = blockGas(prepared.value, CodeAddress(uint64(pc)))
          if pc < 3:
            # Exact valid starts contribute the independently known two-gas trap price.
            assert price.error == GasPlanError.None
            total += uint64(price.value)
          else:
            # The one-past-code query must never fabricate a default price.
            assert price.error == GasPlanError.InvalidStart
        else:
          # Only the first three successful memo queries may grow private occupancy.
          let price = blockGas(learned.value, CodeAddress(uint64(pc)))
          if pc < 3:
            # Exact valid starts contribute the independently known two-gas trap price.
            assert price.error == GasMemoError.None
            total += uint64(price.value)
          else:
            # The one-past-code query must never fabricate a default price.
            assert price.error == GasMemoError.InvalidStart
    let elapsed = getMonoTime().ticks-started
    assert total == 3000000
    assert gasMemoInfo(learned.value).value.pricedBlocks == (if mode == 0: 0'u64 else: 3'u64)
    echo "PVM_PRICING_LOOKUP,", mode, ",", sample, ",", elapsed, ",", total
