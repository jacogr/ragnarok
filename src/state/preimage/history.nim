# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared pinned historical preimage availability equation for complete and authenticated partial state readers.
import ../../codec/state/requests as state_requests

func requestAvailableAt*(history: RequestHistory, slot: RequestSlot): bool =
  ## Inspect the four exact tagged shapes at an explicitly selected time, without adding chronology or chain-time authority.
  let time = uint32(slot)
  case history.state
  of RequestState.Requested:
    false # Outstanding requests have no supply interval.
  of RequestState.Available:
    uint32(history.since) <= time
  of RequestState.Unavailable:
    uint32(history.availableFrom) <= time and time < uint32(history.unavailableFrom)
  of RequestState.Reavailable:
    (uint32(history.originalFrom) <= time and time < uint32(history.removedAt)) or
      uint32(history.restoredAt) <= time
