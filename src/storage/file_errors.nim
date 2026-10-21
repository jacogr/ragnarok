# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared storage IO refusal reasons preserve the existing file backend's public error domain.
type
  FileError* {.pure.} = enum ## Partial/uncertain writes never expose a successful successor view.
    Uninitialized, None, Busy, InvalidPath, AlreadyExists, IoFailure, LimitExceeded,
    WrongIdentity, InvalidJournal, InvalidBatch, InvalidFrame, PublishedUnsynced, RecoveryRequired,
      BackendFailure, RecoveryMismatch
