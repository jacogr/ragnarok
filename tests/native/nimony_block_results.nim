## Every default/failed parent result and wrong nested-schema alternative is tested in a separate process.
import std/[cmdline, syncio]
import ../../src/codec/[block_codec, bounded, composite, owned, tickets, assurances, guarantees,
    disputes, header]
let useDefault = paramStr(2) == "default"
let config = FrameConfig(cores: CoreCount(2), validators: ValidatorCount(6), epochSlots: EpochSlots(12),
  ticketLimit: TicketLimit(3), preimages: PreimageLimits(items: ElementLimit(10000),
  perBlob: ByteLimit(16777216), totalBlobBytes: ByteLimit(16777216)), maxBytes: ByteLimit(16777216))
let empty: seq[byte] = @[]
var output: seq[byte] = @[]
case paramStr(1)
of "decode-header":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ComponentRead[
      ComponentKind.Header]]) else: decodeComponent[ComponentKind.Header](empty, config)
  echo parsed.value.consumed
of "decode-tickets":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ComponentRead[
      ComponentKind.Tickets]]) else: decodeComponent[ComponentKind.Tickets](empty, config)
  echo parsed.value.consumed
of "decode-preimages":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ComponentRead[
      ComponentKind.Preimages]]) else: decodeComponent[ComponentKind.Preimages](empty, config)
  echo parsed.value.consumed
of "decode-guarantees":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ComponentRead[
      ComponentKind.Guarantees]]) else: decodeComponent[ComponentKind.Guarantees](empty, config)
  echo parsed.value.consumed
of "decode-assurances":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ComponentRead[
      ComponentKind.Assurances]]) else: decodeComponent[ComponentKind.Assurances](empty, config)
  echo parsed.value.consumed
of "decode-disputes":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ComponentRead[
      ComponentKind.Disputes]]) else: decodeComponent[ComponentKind.Disputes](empty, config)
  echo parsed.value.consumed
of "component-info":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ComponentInfo]) else: componentInfo(default(TicketComponent))
  echo parsed.value.consumed
of "component-write":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[int]) else: encodeComponent(default(
      TicketComponent), output)
  echo parsed.value
of "extrinsic-read":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ExtrinsicRead]) else: decodeExtrinsic(empty, config)
  echo parsed.value.consumed
of "extrinsic-own":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[OwnedExtrinsic]) else: ownExtrinsic(default(
      Extrinsic), config)
  echo ord(extrinsicInfo(parsed.value).error)
of "extrinsic-write":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[int]) else: encodeExtrinsic(default(Extrinsic),
      config, output)
  echo parsed.value
of "extrinsic-info":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[ExtrinsicInfo]) else: extrinsicInfo(default(OwnedExtrinsic))
  echo parsed.value.consumed
of "extrinsic-owned-write":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[int]) else: encodeOwnedExtrinsic(default(
      OwnedExtrinsic), output)
  echo parsed.value
of "block-read":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[BlockRead]) else: decodeBlock(empty, config)
  echo parsed.value.consumed
of "block-write":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[int]) else: encodeBlock(default(Block), config, output)
  echo parsed.value
of "block-info":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[BlockInfo]) else: blockInfo(default(OwnedBlock))
  echo parsed.value.consumed
of "block-owned-write":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[int]) else: encodeOwnedBlock(default(OwnedBlock), output)
  echo parsed.value
of "block-header":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[HeaderComponent]) else: blockHeader(default(OwnedBlock))
  echo ord(componentInfo(parsed.value).error)
of "block-extrinsic":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[OwnedExtrinsic]) else: blockExtrinsic(default(OwnedBlock))
  echo ord(extrinsicInfo(parsed.value).error)
of "ticket-records":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[seq[Ticket]]) else: readTickets(default(TicketComponent))
  echo parsed.value.len
of "assurance-records":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[seq[Assurance]]) else: readAssurances(default(AssuranceComponent))
  echo parsed.value.len
of "child-tickets":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[TicketComponent]) else: extrinsicTickets(default(OwnedExtrinsic))
  echo ord(componentInfo(parsed.value).error)
of "child-preimages":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[PreimageComponent]) else: extrinsicPreimages(
      default(OwnedExtrinsic))
  echo ord(componentInfo(parsed.value).error)
of "child-guarantees":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[GuaranteeComponent]) else: extrinsicGuarantees(
      default(OwnedExtrinsic))
  echo ord(componentInfo(parsed.value).error)
of "child-assurances":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[AssuranceComponent]) else: extrinsicAssurances(
      default(OwnedExtrinsic))
  echo ord(componentInfo(parsed.value).error)
of "child-disputes":
  # Failed/default operations cannot authorize any value or progress.
  let parsed = if useDefault: default(FrameResult[DisputeComponent]) else: extrinsicDisputes(
      default(OwnedExtrinsic))
  echo ord(componentInfo(parsed.value).error)
of "cause-default":
  # A default outcome is not a selected child failure.
  let parsed = default(FrameResult[int])
  echo ord(parsed.cause.kind)
of "cause-parent":
  # Parent owner rejection has no child-specific reason.
  echo ord(componentInfo(default(TicketComponent)).cause.kind)
of "cause-success":
  # A complete successful empty extrinsic has no failure cause.
  echo ord(decodeExtrinsic([byte(0), 0, 0, 0, 0, 0, 0], config).cause.kind)
of "header-as-ticket":
  # A header rejection cannot be read as tickets failure.
  echo ord(decodeComponent[ComponentKind.Header](empty, config).cause.ticketError)
of "header-as-preimage":
  # A header rejection cannot be read as preimages failure.
  echo ord(decodeComponent[ComponentKind.Header](empty, config).cause.preimageError)
of "header-as-guarantee":
  # A header rejection cannot be read as guarantees failure.
  echo ord(decodeComponent[ComponentKind.Header](empty, config).cause.guaranteeError)
of "header-as-assurance":
  # A header rejection cannot be read as assurances failure.
  echo ord(decodeComponent[ComponentKind.Header](empty, config).cause.assuranceError)
of "header-as-dispute":
  # A header rejection cannot be read as disputes failure.
  echo ord(decodeComponent[ComponentKind.Header](empty, config).cause.disputeError)
of "tickets-as-header":
  # A tickets rejection cannot be read as header failure.
  echo ord(decodeComponent[ComponentKind.Tickets](empty, config).cause.headerError)
of "tickets-as-preimage":
  # A tickets rejection cannot be read as preimages failure.
  echo ord(decodeComponent[ComponentKind.Tickets](empty, config).cause.preimageError)
of "tickets-as-guarantee":
  # A tickets rejection cannot be read as guarantees failure.
  echo ord(decodeComponent[ComponentKind.Tickets](empty, config).cause.guaranteeError)
of "tickets-as-assurance":
  # A tickets rejection cannot be read as assurances failure.
  echo ord(decodeComponent[ComponentKind.Tickets](empty, config).cause.assuranceError)
of "tickets-as-dispute":
  # A tickets rejection cannot be read as disputes failure.
  echo ord(decodeComponent[ComponentKind.Tickets](empty, config).cause.disputeError)
of "preimages-as-header":
  # A preimages rejection cannot be read as header failure.
  echo ord(decodeComponent[ComponentKind.Preimages](empty, config).cause.headerError)
of "preimages-as-ticket":
  # A preimages rejection cannot be read as tickets failure.
  echo ord(decodeComponent[ComponentKind.Preimages](empty, config).cause.ticketError)
of "preimages-as-guarantee":
  # A preimages rejection cannot be read as guarantees failure.
  echo ord(decodeComponent[ComponentKind.Preimages](empty, config).cause.guaranteeError)
of "preimages-as-assurance":
  # A preimages rejection cannot be read as assurances failure.
  echo ord(decodeComponent[ComponentKind.Preimages](empty, config).cause.assuranceError)
of "preimages-as-dispute":
  # A preimages rejection cannot be read as disputes failure.
  echo ord(decodeComponent[ComponentKind.Preimages](empty, config).cause.disputeError)
of "guarantees-as-header":
  # A guarantees rejection cannot be read as header failure.
  echo ord(decodeComponent[ComponentKind.Guarantees](empty, config).cause.headerError)
of "guarantees-as-ticket":
  # A guarantees rejection cannot be read as tickets failure.
  echo ord(decodeComponent[ComponentKind.Guarantees](empty, config).cause.ticketError)
of "guarantees-as-preimage":
  # A guarantees rejection cannot be read as preimages failure.
  echo ord(decodeComponent[ComponentKind.Guarantees](empty, config).cause.preimageError)
of "guarantees-as-assurance":
  # A guarantees rejection cannot be read as assurances failure.
  echo ord(decodeComponent[ComponentKind.Guarantees](empty, config).cause.assuranceError)
of "guarantees-as-dispute":
  # A guarantees rejection cannot be read as disputes failure.
  echo ord(decodeComponent[ComponentKind.Guarantees](empty, config).cause.disputeError)
of "assurances-as-header":
  # A assurances rejection cannot be read as header failure.
  echo ord(decodeComponent[ComponentKind.Assurances](empty, config).cause.headerError)
of "assurances-as-ticket":
  # A assurances rejection cannot be read as tickets failure.
  echo ord(decodeComponent[ComponentKind.Assurances](empty, config).cause.ticketError)
of "assurances-as-preimage":
  # A assurances rejection cannot be read as preimages failure.
  echo ord(decodeComponent[ComponentKind.Assurances](empty, config).cause.preimageError)
of "assurances-as-guarantee":
  # A assurances rejection cannot be read as guarantees failure.
  echo ord(decodeComponent[ComponentKind.Assurances](empty, config).cause.guaranteeError)
of "assurances-as-dispute":
  # A assurances rejection cannot be read as disputes failure.
  echo ord(decodeComponent[ComponentKind.Assurances](empty, config).cause.disputeError)
of "disputes-as-header":
  # A disputes rejection cannot be read as header failure.
  echo ord(decodeComponent[ComponentKind.Disputes](empty, config).cause.headerError)
of "disputes-as-ticket":
  # A disputes rejection cannot be read as tickets failure.
  echo ord(decodeComponent[ComponentKind.Disputes](empty, config).cause.ticketError)
of "disputes-as-preimage":
  # A disputes rejection cannot be read as preimages failure.
  echo ord(decodeComponent[ComponentKind.Disputes](empty, config).cause.preimageError)
of "disputes-as-guarantee":
  # A disputes rejection cannot be read as guarantees failure.
  echo ord(decodeComponent[ComponentKind.Disputes](empty, config).cause.guaranteeError)
of "disputes-as-assurance":
  # A disputes rejection cannot be read as assurances failure.
  echo ord(decodeComponent[ComponentKind.Disputes](empty, config).cause.assuranceError)
else:
  # Unknown trusted test selectors are fixture errors.
  quit(2)
