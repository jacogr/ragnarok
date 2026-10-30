# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default plan and child/price queries carry no selectable payload; valid mode owns genuine complete prices.
import std/[assertions, cmdline, syncio]
import ../../src/pvm/program
import ../../src/pvm/gas/[gas, plan as gas_plan]
let mode = paramStr(1)
let owner = decodeProgram([0'u8, 0, 2, 0, 0, 3], CodeAddress(0), ProgramByteLimit(32),
    JumpCountLimit(0)).value
var limits = GasPlanLimits(blocks: GasPlanBlockLimit(2), bytes: GasPlanByteLimit(128),
    cycles: GasCycleLimit(100))
var selected = default(GasPlanResult[GasPlan])
if mode == "limited-result":
  limits.bytes = GasPlanByteLimit(0)
  selected = newGasPlan(owner, limits)
elif mode == "cycle-result":
  limits.cycles = GasCycleLimit(0)
  selected = newGasPlan(owner, limits)
elif mode == "partial-result":
  limits.blocks = GasPlanBlockLimit(1)
  selected = newGasPlan(owner, limits)
elif mode == "invalid-result":
  selected = newGasPlan(default(Program), limits)
elif mode == "default-info":
  discard gasPlanInfo(default(GasPlan)).value
elif mode == "default-source":
  discard programOf(default(GasPlan)).value
elif mode == "default-price":
  discard blockGas(default(GasPlan), CodeAddress(0)).value
elif mode == "invalid-price":
  let created = newGasPlan(owner, limits)
  assert created.error == GasPlanError.None
  discard blockGas(created.value, CodeAddress(high(uint64))).value
elif mode == "valid":
  selected = newGasPlan(owner, limits)
  assert selected.error == GasPlanError.None
  assert matchesProgram(selected.value, owner)
  assert gasPlanInfo(selected.value).value.blockCount == 2
  assert uint64(blockGas(selected.value, CodeAddress(0)).value) > 0
  assert programOf(selected.value).value == owner
  echo "GAS_PLAN_RESULT_VALID"
else:
  assert mode == "default-result" # A misspelled mode cannot satisfy the selected payload-access diagnostic.
if mode in ["default-result", "limited-result", "cycle-result", "partial-result", "invalid-result"]:
  discard selected.value
