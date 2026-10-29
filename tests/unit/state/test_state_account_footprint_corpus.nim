# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent arbitrary-precision item/octet expectations cover both output domains without mirroring checked arithmetic.
import std/[assertions, envvars, syncio]
import ../../support/fixed_arithmetic_corpus
import ../../../src/state/account/footprint as account_footprint
import ../../../src/codec/state/accounts as state_accounts
proc main() {.raises.} =
  ## Require every SHA-pinned shape's exact success values or explicit nonrepresentability.
  let records = arithmeticCorpus(getEnv("RAGNAROK_ACCOUNT_FOOTPRINT_CORPUS"), 2048, 57)
  for row in records:
    let result = calculateAccountFootprint(AccountFootprintShape(storage: corpusWord(row, 0),
        requests: corpusWord(row, 8),
      storageKeyBytes: corpusWord(row, 16), storageValueBytes: corpusWord(row, 24),
          requestBytes: corpusWord(row, 32)))
    if row[56] == 1:
      assert result.error == AccountFootprintError.Overflow # Failed payloads are never read.
    else:
      assert row[56] == 0 and result.error == AccountFootprintError.None
      assert uint64(result.value.items) == corpusWord(row, 40)
      assert uint64(result.value.bytes) == corpusWord(row,
          48) # Compare independent exact equations across distinct E4/E8 domains.
  echo "state-account-footprint-corpus: ok (2048 cases)"
try:
  main()
except:
  quit(2) # Fixture failure cannot satisfy differential footprint evidence.
