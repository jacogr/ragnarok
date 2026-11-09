# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Run the dedicated connected Read credit witness against actual x86 Linux RX bytes.

when not (defined(linux) and defined(amd64) and defined(pvmX86Jit) and
    not defined(pvmArm64Jit) and defined(pvmSharedReadCycle) and
    defined(pvmX86ResidentProof) and defined(pvmReadCycleBudgetWitness) and
    defined(pvmReadCycleRoleWitness) and defined(pvmReadCycleCreditWitness) and
    defined(pvmX86ReadCycleResident) and defined(pvmX86ReadCycleBudgetRegisters) and
    defined(pvmX86ReadCycleRoleRegisters) and defined(pvmX86ReadCycleCredits)):
  {.error: "require the complete Linux x86-64 credit witness profile".}

import ../../support/pvm_read_cycle_execution

runReadCycleExecution()
