# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached ticket-proof CPU jobs expose one private verifier capability and no native stream or canonical map.
## Binding the checker only in capture keeps non-ticket proof-worker consumers independent of RingVRF linkage.
import ../../jamnp-s/[ticket_packet, ticket_validation]

type
  TicketVerifier = proc(source: TicketSource, packet: TicketPacket,
      recipient: TicketRecipient): NetworkTicketResult[CheckedNetworkTicket] {.nimcall, raises: [].}
    ## Closed private capability always binds the actual finality/epoch/RingVRF verifier; callers cannot replace it.
  TicketJobData = ref object ## Fresh fixed packet/recipient facts accompany an immutable detached selected-source owner.
    source: TicketSource
    packet: TicketPacket
    recipient: TicketRecipient
    verify: nil TicketVerifier
  TicketVerificationJob* = object ## Defaults carry neither a source nor a callable proof-verification capability.
    data: nil TicketJobData
  TicketJobAdmission* = object ## Capture failures expose no job and confer no proof or collection authority.
    case status: NetworkTicketError
    of None: completed: TicketVerificationJob
    else: discard # Only this private factory constructs a successful input capability.
func error*(outcome: TicketJobAdmission): NetworkTicketError =
  ## Inspect the capture reason before accessing its input.
  outcome.status
func value*(outcome: TicketJobAdmission): TicketVerificationJob {.requires: outcome.status ==
    NetworkTicketError.None.} =
  ## Successful input capture is not successful proof verification.
  outcome.completed
func valid*(job: TicketVerificationJob): bool =
  ## Only the private capture factory constructs a complete executable input.
  job.data != nil
proc captureTicketVerification*(source: TicketSource, packet: TicketPacket,
    recipient: TicketRecipient): TicketJobAdmission =
  ## Canonical source selection and all staging aliases must retire before the containing Services submits this job.
  if not source.valid: return TicketJobAdmission(status: NetworkTicketError.NoSource)
  if not packet.valid: return TicketJobAdmission(status: NetworkTicketError.InvalidPacket)
  TicketJobAdmission(status: NetworkTicketError.None,
      completed: TicketVerificationJob(data: TicketJobData(source: source, packet: packet,
          recipient: recipient, verify: verifyNetworkTicket)))
proc executeTicketVerification*(job: TicketVerificationJob): NetworkTicketResult[
    CheckedNetworkTicket] =
  ## Invoke one bound checker outside native callbacks; typed complete results grant no canonical publication authority.
  let data = job.data
  if data == nil: return ticketFailure[CheckedNetworkTicket](NetworkTicketError.NoSource)
  let verify = data.verify
  if verify == nil: return ticketFailure[CheckedNetworkTicket](NetworkTicketError.NoSource)
  verify(data.source, data.packet, data.recipient)
