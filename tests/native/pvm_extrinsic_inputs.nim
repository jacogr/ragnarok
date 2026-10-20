# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized failed-result guards with a real successful authentication control.

import std/[assertions, cmdline]
import ../../src/pvm/host_fetch
import ../../src/state/extrinsic_inputs
import ../support/pvm_extrinsic_inputs

proc input(verified: VerifiedExtrinsics, item, index: uint64): ExtrinsicInputsResult[seq[byte]] =
  ## Keep full-width boundary fixtures concise while exercising the public nominal index domains.
  verified.extrinsicInput(FetchItemIndex(item), ExtrinsicInputIndex(index))

proc check(outcome: ExtrinsicInputsResult[VerifiedExtrinsics], reason: ExtrinsicInputsError) =
  ## Inspect runtime reasons without specializing intentional misuse into a static compiler rejection.
  assert outcome.error == reason
let package = extrinsicPackage([@[AbcExtrinsic]])
let done = verifyExtrinsicInputs(package, [@[@[97'u8, 98, 99]]], extrinsicLimits())
check(done, ExtrinsicInputsError.None)
assert done.value.input(0, 0).value == @[97'u8, 98, 99]
let missing = default(ExtrinsicInputsResult[VerifiedExtrinsics])
let altered = verifyExtrinsicInputs(package, [@[@[97'u8, 98, 100]]], extrinsicLimits())
check(altered, ExtrinsicInputsError.HashMismatch)
let limited = verifyExtrinsicInputs(package, [@[@[97'u8, 98, 99]]], default(ExtrinsicInputsLimits))
check(limited, ExtrinsicInputsError.LimitExceeded)
case paramStr(1)
of "default": discard missing.value # Default results have no authenticated table.
of "mismatch": discard altered.value # Late commitment failure exposes no verified prefix.
of "limit": discard limited.value # Local policy failures have no partial copy.
of "owner": discard default(VerifiedExtrinsics).extrinsicInputsPackage.value # Uninitialized owners cannot supply a package.
else: discard done.value.input(high(uint64), 0).value # Invalid ordinals have no bytes.
