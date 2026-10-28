# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually refused guarantor results cannot expose a successful owner.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import std/syncio
import ../../src/state/guarantors as state_guarantors
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/bounded as codec_bounded
let outcome = if paramStr(1) == "default": default(GuarantorResult[GuarantorPermutation]) else:
  shuffleValidatorIndices(ValidatorCount(6), default(StateEntropyWord), ElementLimit(0))
discard outcome.value # Both supported selectors must fail the checked extraction contract.
