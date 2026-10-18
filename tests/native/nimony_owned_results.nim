# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generic owned-result payloads and copied optional/work metadata reject invalid safe-code reads.
import ../../src/codec/[owned, bounded, composite]
import std/[cmdline, syncio]

# Runtime-selected work errors retain their exact protocol tag without accepting a misspelled probe.
proc workError(text: string): byte =
  case text
  of "1": 1'u8 # OutOfGas.
  of "2": 2'u8 # Panic.
  of "3": 3'u8 # BadExports.
  of "4": 4'u8 # Oversize.
  of "5": 5'u8 # Bad.
  of "6": 6'u8 # Big.
  else: quit 2 # Fixture errors are not guarded accesses.

let useDefault = paramStr(2) == "default"
let missing = default(OwnedFrame)
let empty = newSeq[byte](0)
let frame = if useDefault: default(OwnedResult[OwnedFrame]) else: decodeOwnedBytes(empty, ByteLimit(1))
let info = if useDefault: default(OwnedResult[OwnedInfo]) else: ownedInfo(missing)
let optional = if useDefault: default(OwnedResult[OwnedOptionalInfo]) else: ownedOptionalInfo(missing)
let work = if useDefault: default(OwnedResult[OwnedWorkInfo]) else: ownedWorkInfo(missing)
let digest = if useDefault: default(OwnedResult[OwnedDigestInfo]) else: ownedDigestInfo(missing)
let service = if useDefault: default(OwnedResult[ServiceIndex]) else: ownedService(missing, 0)
let integer = if useDefault: default(OwnedResult[int]) else: ownedBlobLength(missing, 0)
let boolean = if useDefault: default(OwnedResult[bool]) else: ownedFailure[bool](
    OwnershipError.InvalidOwner)
case paramStr(1)
of "frame":
  # A failed decode cannot expose a fabricated empty owner.
  echo ord(ownedInfo(frame.value).error)
of "info":
  # Failed queries cannot expose default cursor progress.
  echo info.value.consumed
of "optional":
  # Failed queries cannot manufacture a successful absent value.
  echo optional.value.present
of "work":
  # Failed queries cannot manufacture a Success work tag.
  echo ord(work.value.kind)
of "digest":
  # Failed queries cannot expose a default service identity.
  echo uint32(digest.value.service)
of "service":
  # Failed index/schema checks cannot expose service zero.
  echo uint32(service.value)
of "integer":
  # Failed copies/length queries cannot masquerade as successful zero extents.
  echo integer.value
of "boolean":
  # The shared result also guards sibling adapters' Boolean instantiations.
  echo boolean.value
of "absent-length":
  # Successful absent metadata still has no length; default metadata has the same shape.
  let absent = if useDefault: default(OwnedOptionalInfo) else: ownedOptionalInfo(
      decodeOwnedOptional([byte(0)], ByteLimit(0)).value).value
  echo absent.length
of "work-error-length":
  # All six valid work errors decode successfully but lack payload-length metadata.
  let owner = decodeOwnedWork([workError(paramStr(2))], ByteLimit(0)).value
  echo ownedWorkInfo(owner).value.length
of "factory-failure":
  # A failure constructor cannot manufacture success without a value.
  let reason = if paramStr(2) == "none": OwnershipError.None else: OwnershipError.InvalidOwner
  echo ord(ownedFailure[int](reason).error)
of "factory-length":
  # Successful copied metadata may not contain a negative payload length.
  let length = if paramStr(2) == "negative": -1 else: 0
  echo successfulOwnedWorkInfo(length).length
of "factory-work":
  # Payload-free metadata construction cannot use the Success alternative.
  let kind = if paramStr(2) == "success": WorkKind.Success else: WorkKind.OutOfGas
  echo ord(failedOwnedWorkInfo(kind).kind)
else:
  # Unknown fixture modes must not count as contract rejections.
  quit 2
