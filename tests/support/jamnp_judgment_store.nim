# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine opposite original Ed25519 claims test accountable conflict retention, idempotent retries and atomic bounded publication without treating a claimed validity bit as computed report truth.

import std/assertions
import ../../src/jamnp-s/[judgment_claim, judgment_receipt, judgment_store, audits]
import ../../src/codec/[bounded, disputes, guarantees]
import ../../src/crypto/primitives
import ./[jamnp_audit_context, jamnp_guarantee_support, jamnp_judgment_support,
  jamnp_judgment_receipt]

proc judgmentStoreChecks*(fixture: AuditContextFixture) =
  ## Distinct genuine report hashes exceed a one-row policy atomically, while opposite signed claims retain both sides under the same original epoch/index/report key.
  let source = supportFixture(fixture)
  let first = unseenGuarantee(source)
  let second = unseenGuarantee(source, mutation = 2)
  let negative = actualNegativeClaim(fixture, first).judgmentRecord
  let other = actualNegativeClaim(fixture, second).judgmentRecord
  var positive = negative
  positive.valid = true
  positive.slot = GuaranteeSlot(0)
  positive.credentialCount = 0
  positive.credentials = default(array[3, GuaranteeCredential])
  var seed = default(array[32, byte])
  seed[0] = 12
  var message: seq[byte] = @[]
  for character in "jam_valid": message.add(byte(ord(character)))
  for octet in array[32, byte](positive.report): message.add(octet)
  positive.signature = DisputeSignature(array[64, byte](sign(importSeed(seed).value,
      message).value))
  let raw = encodeJudgments([negative, positive, other], actualClaimLimits().message).value
  let claims = verifyJudgmentClaims(fixture.view, raw, actualClaimLimits()).value
  let inputs = [JudgmentSourceInput(source: fixture.blockHash, report: first.report),
    default(JudgmentSourceInput), JudgmentSourceInput(source: fixture.blockHash,
        report: second.report)]
  let prepared = prepareJudgmentReceipt(fixture.view, claims, inputs, receiptLimits()).value
  let a = prepared.judgmentAt(0).value
  let b = prepared.judgmentAt(1).value
  let c = prepared.judgmentAt(2).value
  var small = default(JudgmentStore)
  assert small.configure(JudgmentStoreLimits(records: ElementLimit(1), bytes: ByteLimit(1000000)))
  defer: small.clear()
  assert small.append([a, c]).error == JudgmentStoreError.LimitExceeded
  assert small.len == 0, "a later additional report cannot leave the first inserted"
  assert small.append([a, default(QualifiedJudgment)]).error == JudgmentStoreError.InvalidRecord
  assert small.len == 0
  assert small.append([a, a]).value == 1 and small.len == 1
  assert small.append([a]).value == 0 and not small.conflicted(0)
  var store = default(JudgmentStore)
  assert not store.configured and store.append([a]).error == JudgmentStoreError.Unconfigured
  assert store.configure(JudgmentStoreLimits(records: ElementLimit(3), bytes: ByteLimit(1000000)))
  defer: store.clear()
  assert store.append([a, b, c]).value == 3
  assert store.conflicted(0) and store.conflicted(1) and not store.conflicted(2)
  assert not store.conflicted(-1) and not store.conflicted(3)
  assert store.append([b, a, c]).value == 0 and store.len == 3
  assert not store.judgmentAt(0).value.judgmentRecord.valid and store.judgmentAt(
      1).value.judgmentRecord.valid
  assert store.judgmentAt(3).error == JudgmentStoreError.InvalidIndex
  let epoch = uint64(uint32(negative.epoch))
  store.expireBefore(epoch)
  assert store.len == 3 and store.conflicted(0), "oldest eligible epoch keeps both sides"
  store.expireBefore(epoch+1)
  assert store.len == 0 and not store.canAppendClaims(claims), "stale claims fail preflight"
  store.expireBefore(epoch)
  assert store.append([a, b]).error == JudgmentStoreError.Expired and store.len == 0,
      "qualified replay cannot reopen an expired epoch"
