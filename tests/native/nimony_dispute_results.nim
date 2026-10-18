# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every public dispute result instantiation guards failed/default application access.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[cmdline, syncio]
import ../../src/codec/[disputes, bounded, assurances]

let useDefault = paramStr(2) == "default"
let config = DisputeConfig(validators: ValidatorCount(6), maxBytes: ByteLimit(1024))
let empty: seq[byte] = @[]
let missing = default(OwnedDisputes)
var destination = newSeq[byte](0)
let decoded = if useDefault: default(DisputeResult[DisputesRead]) else: decodeDisputes(empty, config)
let info = if useDefault: default(DisputeResult[DisputeInfo]) else: disputesInfo(missing)
let verdict = if useDefault: default(DisputeResult[VerdictInfo]) else: verdictAt(missing, 0)
let judgment = if useDefault: default(DisputeResult[Judgment]) else: judgmentAt(missing, 0, 0)
let culprit = if useDefault: default(DisputeResult[Culprit]) else: culpritAt(missing, 0)
let fault = if useDefault: default(DisputeResult[Fault]) else: faultAt(missing, 0)
let written = if useDefault: default(DisputeResult[int]) else: encodeDisputes(default(Disputes),
    config, destination)
let owned = if useDefault: default(DisputeResult[int]) else: encodeOwnedDisputes(missing, destination)
let scanned = if useDefault: default(DisputeResult[DisputeInfo]) else: inspectDisputes(empty, config)
case paramStr(1)
of "owner": echo ord(disputesInfo(decoded.value.owner).error) # No fabricated validated snapshot.
of "decoded-info": echo decoded.value.info.consumed # No partial consumed progress.
of "info": echo info.value.verdicts # No default cardinalities from a missing owner.
of "verdict": echo array[32, byte](verdict.value.target)[0] # No default report identity.
of "verdict-judgments": echo verdict.value.judgments # No default selected judgment count.
of "judgment": echo judgment.value.valid # No fabricated Boolean judgment.
of "culprit": echo array[32, byte](culprit.value.key)[0] # No fabricated offender identity.
of "fault": echo fault.value.valid # No default fault evidence after failure.
of "written": echo written.value # No committed bytes from incomplete output.
of "owned-written": echo owned.value # No byte extent from a missing snapshot.
of "inspect-verdicts": echo scanned.value.verdicts # No scan cardinality until complete validation.
of "inspect-consumed": echo scanned.value.consumed # No scan progress from missing input.
of "factory":
  # A failure factory must reject the success tag without its application value.
  let reason = if paramStr(2) == "none": DisputeError.None else: DisputeError.InvalidOwner
  echo ord(disputeFailure[int](reason).error)
else: quit 2 # Misspelled probes cannot count as protected accesses.
