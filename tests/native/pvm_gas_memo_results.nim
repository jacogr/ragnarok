# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default memo values grant no selectable payload; successful mode checks genuine lazy facts and copied children.
import std/[assertions, cmdline, syncio]
import ../../src/pvm/program
import ../../src/pvm/gas/[gas, memo as gas_memo]
let mode = paramStr(1)
let owner = decodeProgram([0'u8, 0, 2, 0, 0, 3], CodeAddress(0), ProgramByteLimit(32),
    JumpCountLimit(0)).value
var limits = GasMemoLimits(bytes: GasMemoByteLimit(128), cycles: GasCycleLimit(100))
var selected = default(GasMemoResult[GasMemo])
if mode == "limited-result":
  limits.bytes = GasMemoByteLimit(0)
  selected = newGasMemo(owner, limits)
elif mode == "invalid-result":
  selected = newGasMemo(default(Program), limits)
elif mode == "cycle-price":
  limits.cycles = GasCycleLimit(0)
  let memo = newGasMemo(owner, limits).value
  assert gasMemoInfo(memo).value.pricedBlocks == 0
  discard blockGas(memo, CodeAddress(0)).value
elif mode == "default-info":
  discard gasMemoInfo(default(GasMemo)).value
elif mode == "default-source":
  discard programOf(default(GasMemo)).value
elif mode == "default-price":
  discard blockGas(default(GasMemo), CodeAddress(0)).value
elif mode == "invalid-price":
  let memo = newGasMemo(owner, limits).value
  discard blockGas(memo, CodeAddress(high(uint64))).value
elif mode == "valid":
  selected = newGasMemo(owner, limits)
  assert selected.error == GasMemoError.None and matchesProgram(selected.value, owner)
  assert gasMemoInfo(selected.value).value.pricedBlocks == 0
  assert uint64(blockGas(selected.value, CodeAddress(0)).value) > 0
  assert uint64(blockGas(selected.value, CodeAddress(0)).value) > 0
  assert gasMemoInfo(selected.value).value.pricedBlocks == 1
  assert programOf(selected.value).value == owner
  echo "GAS_MEMO_RESULT_VALID"
else:
  assert mode == "default-result" # Misspelled modes cannot satisfy the selected guarded-value diagnostic.
if mode in ["limited-result", "invalid-result", "default-result"]:
  discard selected.value
