# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized bundle result/owner guards include genuine completed execution and full-wire success controls.

import std/assertions
import std/cmdline
import ../../src/state/auditable_bundle as state_auditable_bundle
import ../../src/state/input_refinement as state_input_refinement
import ../../src/codec/bounded as codec_bounded
import ../support/pvm_auditable_bundle
import ../support/pvm_bundle_vectors

proc check(outcome: AuditableBundleResult[AuditableBundle], reason: AuditableBundleError) =
  ## Inspect runtime reasons without statically specializing later deliberate invalid extraction.
  assert outcome.error == reason
let source = bundleExecution()
let done = prepareAuditableBundle(source, ByteLimit(OrdinaryLength))
check(done, AuditableBundleError.None)
assert done.value.bundleBytes.value.len == OrdinaryLength
let missing = default(AuditableBundleResult[AuditableBundle])
let invalid = prepareAuditableBundle(default(InputRefinement), ByteLimit(0))
check(invalid, AuditableBundleError.InvalidSource)
let limited = prepareAuditableBundle(source, ByteLimit(OrdinaryLength-1))
check(limited, AuditableBundleError.LimitExceeded)
case paramStr(1)
of "default": discard missing.value # Defaults carry no successful bundle.
of "source": discard invalid.value # No uninitialized execution can certify input bytes.
of "limit": discard limited.value # A final-byte budget refusal exposes no serialized prefix.
of "info": discard default(AuditableBundle).bundleInfo.value # Defaults have no nominal length or package identity.
of "owner": discard default(AuditableBundle).bundleSource.value # Defaults have no original execution provenance.
else: discard default(AuditableBundle).bundleBytes.value # Defaults cannot manufacture a successful empty wire.
