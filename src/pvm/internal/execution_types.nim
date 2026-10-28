# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared execution domains; private interpreter workers never import public snapshot adapters.
import ../machine as pvm_machine

type
  HostCallId* = distinct uint64 ## Host identifiers occupy a register-width domain distinct from gas, addresses and step budgets.
  StepExit* {.pure.} = enum ## Guest outcomes shared by single-step and bounded recursive execution.
    Continued, OutOfGas, Panic, Halt, Fault, Host
  StepError* {.pure.} = enum ## Local scope/resource/specification failures are distinct from guest execution outcomes.
    Uninitialized, None, InvalidMachine, UnsupportedInstruction, GasCycleLimitExceeded,
    NegativeBranchTarget, AmbiguousAccessOrder, StepLimitExceeded, InvalidHostSuspension,
      InvalidHostResponse, HostCallLimitExceeded, InvalidGasPlan, InvalidGasMemo,
        InvalidPreparedProgram, PreparedProgramBusy, BackendNotBuilt, BackendUnavailable,
        BackendReentryUnsupported, BackendRevisionMismatch, BackendProgramUnsupported,
          BackendCapabilityUnsupported, BackendFailure
