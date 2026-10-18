# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default header results and absent marker alternatives reject invalid application access.
import std/[cmdline, syncio]
import ../../src/codec/[header, bounded, assurances]
let useDefault = paramStr(2) == "default"
let config = HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
    epochSlots: EpochSlots(12), maxBytes: ByteLimit(4096))
let empty: seq[byte] = @[]
var output = newSeq[byte](0)
let missingHeader = default(OwnedHeader)
let missingUnsigned = default(OwnedUnsignedHeader)
let missingEpoch = default(OwnedEpochMarker)
let missingWinners = default(OwnedWinnersMarker)
let fullRead = if useDefault: default(HeaderResult[HeaderRead]) else: decodeHeader(empty, config)
let unsigned = if useDefault: default(HeaderResult[UnsignedHeaderRead]) else: decodeUnsignedHeader(
    empty, config)
let epoch = if useDefault: default(HeaderResult[EpochMarkerRead]) else: decodeEpochMarker(empty, config)
let winners = if useDefault: default(HeaderResult[WinnersMarkerRead]) else: decodeWinnersMarker(
    empty, config)
let fixedTicket = if useDefault: default(HeaderResult[WinningTicketRead]) else: decodeWinningTicket(empty)
let info = if useDefault: default(HeaderResult[HeaderInfo]) else: headerInfo(missingHeader)
let inspection = if useDefault: default(HeaderResult[HeaderInfo]) else: inspectHeader(empty, config)
let unsignedInfo = if useDefault: default(HeaderResult[
    UnsignedHeaderInfo]) else: unsignedHeaderInfo(missingUnsigned)
let unsignedView = if useDefault: default(HeaderResult[OwnedUnsignedHeader]) else: unsignedPart(missingHeader)
let epochView = if useDefault: default(HeaderResult[OwnedEpochMarker]) else: headerEpoch(
    missingUnsigned)
let winnersView = if useDefault: default(HeaderResult[OwnedWinnersMarker]) else: headerWinners(
    missingUnsigned)
let epochInfo = if useDefault: default(HeaderResult[EpochMarkerInfo]) else: epochMarkerInfo(missingEpoch)
let winnersInfo = if useDefault: default(HeaderResult[WinnersMarkerInfo]) else: winnersMarkerInfo(missingWinners)
let validator = if useDefault: default(HeaderResult[EpochValidator]) else: epochValidatorAt(
    missingEpoch, 0)
let ticket = if useDefault: default(HeaderResult[WinningTicket]) else: winningTicketAt(
    missingWinners, 0)
let offender = if useDefault: default(HeaderResult[HeaderEdKey]) else: headerOffenderAt(
    missingUnsigned, 0)
let headerWrite = if useDefault: default(HeaderResult[int]) else: encodeHeader(default(Header),
    config, output)
let unsignedWrite = if useDefault: default(HeaderResult[int]) else: encodeUnsignedHeader(default(
    UnsignedHeader), config, output)
let epochWrite = if useDefault: default(HeaderResult[int]) else: encodeEpochMarker(absentEpoch(),
    config, output)
let winnersWrite = if useDefault: default(HeaderResult[int]) else: encodeWinnersMarker(
    absentWinners(), config, output)
let ticketWrite = if useDefault: default(HeaderResult[int]) else: encodeWinningTicket(default(
    WinningTicket), output)
let ownedHeader = if useDefault: default(HeaderResult[int]) else: encodeOwnedHeader(missingHeader, output)
let ownedUnsigned = if useDefault: default(HeaderResult[int]) else: encodeOwnedUnsignedHeader(
    missingUnsigned, output)
let ownedEpoch = if useDefault: default(HeaderResult[int]) else: encodeOwnedEpochMarker(
    missingEpoch, output)
let ownedWinners = if useDefault: default(HeaderResult[int]) else: encodeOwnedWinnersMarker(
    missingWinners, output)
var sourceEpoch = if useDefault: default(EpochMarker) else: absentEpoch()
var sourceWinners = if useDefault: default(WinnersMarker) else: absentWinners()
let absentEpochInfo = if useDefault: default(EpochMarkerInfo) else: epochMarkerInfo(
    decodeEpochMarker([byte(0)], config).value.owner).value
let absentWinnersInfo = if useDefault: default(WinnersMarkerInfo) else: winnersMarkerInfo(
    decodeWinnersMarker([byte(0)], config).value.owner).value
case paramStr(1)
of "header-owner": echo ord(headerInfo(fullRead.value.owner).error) # No success payload or progress from default/failed operations.
of "header-consumed": echo fullRead.value.consumed # No success payload or progress from default/failed operations.
of "unsigned-owner": echo ord(unsignedHeaderInfo(unsigned.value.owner).error) # No success payload or progress from default/failed operations.
of "unsigned-consumed": echo unsigned.value.consumed # No success payload or progress from default/failed operations.
of "epoch-owner": echo ord(epochMarkerInfo(epoch.value.owner).error) # No success payload or progress from default/failed operations.
of "epoch-consumed": echo epoch.value.consumed # No success payload or progress from default/failed operations.
of "winners-owner": echo ord(winnersMarkerInfo(winners.value.owner).error) # No success payload or progress from default/failed operations.
of "winners-consumed": echo winners.value.consumed # No success payload or progress from default/failed operations.
of "fixed-ticket": echo uint8(fixedTicket.value.value.attempt) # No success payload or progress from default/failed operations.
of "fixed-consumed": echo fixedTicket.value.consumed # No success payload or progress from default/failed operations.
of "info": echo info.value.consumed # No success payload or progress from default/failed operations.
of "inspection": echo inspection.value.consumed # No success payload or progress from default/failed operations.
of "unsigned-info": echo unsignedInfo.value.offenders # No success payload or progress from default/failed operations.
of "unsigned-view": echo ord(unsignedHeaderInfo(unsignedView.value).error) # No success payload or progress from default/failed operations.
of "epoch-view": echo ord(epochMarkerInfo(epochView.value).error) # No success payload or progress from default/failed operations.
of "winners-view": echo ord(winnersMarkerInfo(winnersView.value).error) # No success payload or progress from default/failed operations.
of "epoch-info": echo epochInfo.value.present # No success payload or progress from default/failed operations.
of "winners-info": echo winnersInfo.value.present # No success payload or progress from default/failed operations.
of "validator": echo array[32, byte](validator.value.ed25519)[
    0] # No success payload or progress from default/failed operations.
of "ticket": echo uint8(ticket.value.attempt) # No success payload or progress from default/failed operations.
of "offender": echo array[32, byte](offender.value)[
    0] # No success payload or progress from default/failed operations.
of "header-written": echo headerWrite.value # No success payload or progress from default/failed operations.
of "unsigned-written": echo unsignedWrite.value # No success payload or progress from default/failed operations.
of "epoch-written": echo epochWrite.value # No success payload or progress from default/failed operations.
of "winners-written": echo winnersWrite.value # No success payload or progress from default/failed operations.
of "fixed-written": echo ticketWrite.value # No success payload or progress from default/failed operations.
of "owned-header": echo ownedHeader.value # No success payload or progress from default/failed operations.
of "owned-unsigned": echo ownedUnsigned.value # No success payload or progress from default/failed operations.
of "owned-epoch": echo ownedEpoch.value # No success payload or progress from default/failed operations.
of "owned-winners": echo ownedWinners.value # No success payload or progress from default/failed operations.
of "source-entropy": echo array[32, byte](sourceEpoch.entropy)[
    0] # An absent alternative contains none of this present-only field.
of "source-tickets-entropy": echo array[32, byte](sourceEpoch.ticketsEntropy)[
    0] # An absent alternative contains none of this present-only field.
of "source-validators": echo epochValidatorCopies(
    sourceEpoch).len # An absent alternative contains none of this present-only field.
of "source-tickets": echo winnerTicketCopies(sourceWinners).len # An absent alternative contains none of this present-only field.
of "meta-entropy": echo array[32, byte](absentEpochInfo.entropy)[
    0] # An absent alternative contains none of this present-only field.
of "meta-tickets-entropy": echo array[32, byte](absentEpochInfo.ticketsEntropy)[
    0] # An absent alternative contains none of this present-only field.
of "meta-validators": echo absentEpochInfo.validators # An absent alternative contains none of this present-only field.
of "meta-tickets": echo absentWinnersInfo.tickets # An absent alternative contains none of this present-only field.
of "edit-validators":
  # A mutable source view cannot be obtained from an absent epoch marker.
  editEpochValidators(sourceEpoch).setLen(1)
  echo 0
of "edit-tickets":
  # A mutable source view cannot be obtained from an absent winner marker.
  editWinnerTickets(sourceWinners).setLen(1)
  echo 0
of "factory":
  # Failure construction cannot fabricate the success tag without a completed value.
  let reason = if paramStr(2) == "none": HeaderError.None else: HeaderError.InvalidOwner
  echo ord(headerFailure[int](reason).error)
else: quit 2 # Unknown modes cannot count as contract rejections.
