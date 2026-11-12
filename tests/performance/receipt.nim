# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private full-oracle completion and logical lookup receipts, with no clocks.

import std/[assertions, syncio]
import ../../src/pvm/step
when defined(pvmSharedAsyncWitness):
  from ../../src/pvm/internal/native_pipeline import waitNativeCompiler

proc receipt*(prepared: PreparedProgram, runtime: NativeRuntime, label: string, sample: int) =
  ## Settle only already submitted work after all public execution and original state/source checks.
  when defined(pvmSharedAsyncWitness): waitNativeCompiler(runtime)
  let info = preparedInfo(prepared).value
  let primary = when declared(preparedPrimaryNativeStatistics): preparedPrimaryNativeStatistics(prepared)
    else: [info.nativeFragments, info.nativeCalls, info.nativeOperations, info.nativeCodeBytes, 0'u64]
  echo "BYTE_RANK_NATIVE,", label, ",", sample, ",", info.codeBytes, ",",
    info.decodedInstructions, ",", info.streamNodes, ",", info.preparationUnits, ",",
    info.retainedMemoryPayloadBytes, ",", primary[0], ",", primary[1], ",", primary[2], ",",
        primary[3]
  echo "MIXED_OWNER_STATS,", label, ",", sample, ",", info.nativeFragments, ",", info.nativeCalls,
    ",", info.nativeOperations, ",", info.nativeCodeBytes
  when defined(pvmByteRankCounts):
    let reads = privatePreparedByteRankCounts(prepared)
    echo "BYTE_RANK_COUNTS,", label, ",", sample, ",", reads[0], ",", reads[1], ",",
      reads[2], ",", reads[3], ",", reads[4]
  echo "BYTE_RANK_CALL_OK,", label, ",", sample
