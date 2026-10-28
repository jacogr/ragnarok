# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused certification results and nonselected child reasons cannot expose successful
## data.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import std/syncio
import ../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../src/codec/state_safrole as codec_state_safrole
let outcome = if paramStr(1) == "error":
  verifyGuaranteeCredentials([], default(ValidatorStateSnapshot), default(ValidatorStateSnapshot),
    default(StateEntropy), StateTime(0), [], default(GuaranteeCredentialConfig))
else:
  default(GuaranteeCredentialResult[VerifiedGuaranteeCredentials]) # Default is always a failed alternative.
case paramStr(1)
of "default", "error":
  discard outcome.value # Neither default nor an actual refusal contains a certified owner.
of "structure":
  discard outcome.structureError # Uninitialized is not the selected structure-failure alternative.
of "assignment":
  discard outcome.assignmentError # Uninitialized is not the selected assignment-failure alternative.
else:
  quit(3) # An unsupported selector must never satisfy an intended contract failure.
