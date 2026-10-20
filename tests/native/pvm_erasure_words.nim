# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized scalar-code guards include actual independent successful parity controls.

import std/[assertions, cmdline]
import ../../src/state/erasure_words
import ../../src/codec/[bounded, work_report]

proc check[T](outcome: ErasureWordResult[T], reason: ErasureWordError) =
  ## Observe the runtime alternative before attempting deliberate failed extraction.
  assert outcome.error == reason, "word guard control"
let input = [ErasureWord(33059), ErasureWord(33335), ErasureWord(33641)]
let cap = ErasureWordLimits(bytes: ByteLimit(26), products: FieldProductLimit(102))
let done = encodeErasureWords(input, ErasureShards(6), cap)
check(done, ErasureWordError.None)
assert uint16(done.value.codeWord(ErasureShardIndex(5)).value) == 35941, "independent parity control"
let missing = default(ErasureWordResult[ErasureWordCode])
let shards = encodeErasureWords(input, ErasureShards(7), cap)
check(shards, ErasureWordError.InvalidShards)
let length = encodeErasureWords(input.toOpenArray(0, 1), ErasureShards(6), cap)
check(length, ErasureWordError.InvalidLength)
let limited = encodeErasureWords(input, ErasureShards(6), ErasureWordLimits())
check(limited, ErasureWordError.LimitExceeded)
let index = done.value.codeWord(ErasureShardIndex(6))
check(index, ErasureWordError.InvalidIndex)
case paramStr(1)
of "default": discard missing.value # Defaults contain no complete scalar code.
of "shards": discard shards.value # Invalid domains contain no parity.
of "length": discard length.value # Incomplete originals cannot initialize an encoder.
of "limit": discard limited.value # No partial encoding escapes refused budgets.
of "index": discard index.value # Full-width out-of-range indices have no scalar.
of "info": discard default(ErasureWordCode).wordCodeInfo.value # Defaults have no work facts.
else: discard default(ErasureWordCode).codeWord(ErasureShardIndex(
    0)).value # Defaults have no fabricated zero word.
