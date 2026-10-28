# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent arbitrary-precision expectations cover exact/cancelled/overflowing deposit and pool arithmetic.
import std/assertions
import std/envvars
import std/syncio
import ../../support/testing_fixed_arithmetic_corpus
import ../../../src/state/account_deposit as state_account_deposit
import ../../../src/state/account_footprint as state_account_footprint
import ../../../src/codec/state_accounts as codec_state_accounts
proc main() {.raises.} =
  ## Decode exact SHA-pinned test transport and compare both refusal and nominal successful observations.
  let records = arithmeticCorpus(getEnv("RAGNAROK_ACCOUNT_DEPOSIT_CORPUS"), 1024, 74)
  for row in records:
    let count = corpusWord(row, 0)
    assert count <= uint64(high(uint32))
    let result = calculateAccountMinimum(AccountFootprint(items: AccountStorageItems(uint32(count)),
        bytes: AccountStorageBytes(corpusWord(row, 8))),
      AccountBalance(corpusWord(row, 16)), AccountDepositSchedule(base: AccountBalance(corpusWord(
          row, 24)), item: AccountBalance(corpusWord(row, 32)), octet: AccountBalance(corpusWord(
          row, 40))))
    if row[72] == 1:
      assert result.error == AccountDepositError.Overflow # No failed result payload is extracted.
    else:
      assert row[72] == 0 and result.error == AccountDepositError.None
      assert uint64(result.value) == corpusWord(row, 64)
      assert coversAccountMinimum(AccountBalance(corpusWord(row, 48)), AccountBalance(corpusWord(
          row, 56)), result.value) == (row[73] == 1) # Independent unbounded reference may sum pools beyond E8.
  echo "state-account-deposit-corpus: ok (1024 cases)"
try:
  main()
except:
  quit(2) # Invalid fixture setup cannot count as differential arithmetic evidence.
