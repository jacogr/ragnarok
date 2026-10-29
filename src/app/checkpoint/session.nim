# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed export lifetimes retain an unacknowledged joined publication receipt across repeated shutdown and restart attempts.
import ./[worker as checkpoint_worker, file as checkpoint_file, transfer as checkpoint_transfer]
import ../../codec/bounded
import ../../state/store
import ./identity as checkpoint_identity

type ApplicationCheckpointSession* = object ## One stable worker address and fixed shutdown journal have a single host owner.
  worker: ApplicationCheckpointWorker
  active, pending: bool
  retired: ApplicationCheckpointShutdown
proc `=copy`*(destination: var ApplicationCheckpointSession,
    source: ApplicationCheckpointSession) {.error.}
  ## Native retirement and acknowledgement obligations cannot be implicitly copied.
proc `=dup`*(source: ApplicationCheckpointSession): ApplicationCheckpointSession {.error.}
  ## Actual ARC lowering independently enforces composite ownership.
proc `=wasMoved`*(session: var ApplicationCheckpointSession) {.nodestroy, inline,
    requires: not session.active.} =
  ## Inactive ownership and any fixed pending receipt may relocate; live native addresses remain stable.
  `=wasMoved`(session.worker)
  session.pending = false
proc requireClosed(session: ApplicationCheckpointSession) {.requires: not session.active.} =
  ## A native worker cannot outlive its stable managed parent address.
  discard
proc `=destroy`*(session: ApplicationCheckpointSession) =
  ## Explicit joined close precedes retirement of the child's buffer, synchronization and copied path.
  requireClosed(session)
  `=destroy`(session.worker)
func opened*(session: ApplicationCheckpointSession): bool =
  ## Observe lifecycle without exposing the fixed-address worker.
  session.active
func shutdownPending*(session: ApplicationCheckpointSession): bool =
  ## Callers must acknowledge actual uncollected work or retirement uncertainty before restart.
  session.pending
func shutdown*(session: ApplicationCheckpointSession): ApplicationCheckpointShutdown {.inline,
    requires: session.pending.} =
  ## Repeated observation preserves the same fixed receipt without releasing the restart gate.
  session.retired
proc takeShutdown*(session: var ApplicationCheckpointSession): ApplicationCheckpointShutdown {.requires: session.pending.} =
  ## Explicit acknowledgement returns the actual joined receipt once; it never retries a possible publication.
  result = session.retired
  session.retired = default(ApplicationCheckpointShutdown)
  session.pending = false
proc start*(session: var ApplicationCheckpointSession,
    path: string): ApplicationCheckpointFileError {.raises.} =
  ## No restart may overwrite an unacknowledged completed/cancelled/interrupted operation or native retirement refusal.
  if session.active or session.pending: return ApplicationCheckpointFileError.Busy
  let opened = session.worker.start(path)
  if opened == ApplicationCheckpointFileError.None: session.active = true
  opened
proc phase*(session: var ApplicationCheckpointSession): ApplicationCheckpointWorkerPhase =
  ## Scalar observation delegates to the child's synchronized host API.
  session.worker.phase
proc stage*(session: var ApplicationCheckpointSession, prepared: var PreparedApplicationCheckpoint,
    limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Admission consumes no source on refusal and never accesses the filesystem or a canonical graph.
  session.worker.stage(prepared, limit)
proc begin*(session: var ApplicationCheckpointSession, ticket: ApplicationCheckpointTicket): bool =
  ## Only explicit dispatch permits native I/O for a matching staged request.
  session.worker.begin(ticket)
proc cancel*(session: var ApplicationCheckpointSession, ticket: ApplicationCheckpointTicket): bool =
  ## Staged-only cancellation preserves already dispatched or completed publication.
  session.worker.cancel(ticket)
proc peek*(session: var ApplicationCheckpointSession,
    ticket: ApplicationCheckpointTicket): ApplicationCheckpointCompletion =
  ## Matching completed observation retains acknowledgement capacity.
  session.worker.peek(ticket)
proc collect*(session: var ApplicationCheckpointSession,
    ticket: ApplicationCheckpointTicket): ApplicationCheckpointCompletion =
  ## Explicit host acknowledgement releases the child's sole byte buffer after native aliases retire.
  session.worker.collect(ticket)
proc close*(session: var ApplicationCheckpointSession) =
  ## Joined close stores actual uncollected work and native retirement separately; repeated close preserves the journal.
  if not session.active: return
  let retired = session.worker.close()
  session.active = false
  session.retired = retired
  session.pending = retired.completion.kind != ApplicationCheckpointCompletionKind.Uninitialized or
      retired.retirementError != ApplicationCheckpointFileError.None

proc stageVerification*(session: var ApplicationCheckpointSession,
    expected: ApplicationCheckpointIdentity,

limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Fixed independent trust and budgets reuse the same exclusive acknowledgement slot and retained shutdown journal.
  session.worker.stageVerification(expected, limits, limit)
