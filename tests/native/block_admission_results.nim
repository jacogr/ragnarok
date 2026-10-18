# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## No default/refused admission or nonselected reason can expose block/state/progress.
import std/[assertions, cmdline, syncio]
import ../../src/state/[block_admission, safrole_transition, store]
import ../../src/codec/[block_codec, header]
var state = default(StateStore)
case paramStr(1)
of "admission-default", "admission-error":
  # Actual/default refusals must both fail at the success predicate.
  let outcome = if paramStr(1) == "admission-default": default(BlockAdmissionResult) else:
    validateBlockCommitments(default(OwnedBlock), default(OwnedHeader), default(StateStoreSnapshot),
        default(BlockAdmissionConfig))
  discard outcome.value
of "composed-default", "composed-error":
  # The public state composition cannot extract a snapshot after admission refused.
  let outcome = if paramStr(1) == "composed-default": default(BlockSafroleResult) else:
    advanceBlockSafrole(state, default(OwnedBlock), default(OwnedHeader), [], default(
        BlockAdmissionConfig), default(SafroleTransitionConfig))
  discard outcome.value
of "admission-reason", "safrole-reason":
  # A default result cannot expose either alternative's typed reason.
  let outcome = if paramStr(2) == "default": default(BlockSafroleResult) else:
    advanceBlockSafrole(state, default(OwnedBlock), default(OwnedHeader), [], default(
        BlockAdmissionConfig), default(SafroleTransitionConfig))
  if paramStr(1) == "admission-reason":
    echo outcome.admissionError # Exact AdmissionFailure branch required.
  else:
    discard outcome.safroleError # Exact SafroleFailure branch required.
of "block", "header", "parent", "state":
  # Default immutable bindings are not admitted input, even though they can be declared.
  var binding = default(BoundBlock)
  case paramStr(1)
  of "block": discard binding.admittedBlock # No default block capture.
  of "header": discard binding.admittedHeader # No unrelated candidate header.
  of "parent": discard binding.admittedParent # No fabricated trusted parent.
  else: discard binding.admittedState # No fabricated complete-map snapshot.
else:
  quit(3) # Unknown selectors cannot masquerade as expected contract failures.
