# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native runtime extraction guards and actual positive controls share each public result accessor.
import std/[assertions, cmdline]
import ../../src/state/ancestor_context
import ../../src/codec/[bounded, header]

proc context(outcome: AncestorContextResult[AncestorContext]) =
  ## Default and refused capture cannot expose a context owner.
  discard outcome.value
proc selected(outcome: AncestorContextResult[OwnedHeader]) =
  ## Invalid indices cannot yield a fabricated header or the first retained owner.
  discard outcome.value
proc main() =
  ## Explicit canonical serialization supplies every positive owner rather than constructing private fields.
  let config = fullHeaderConfig(ByteLimit(1024))
  let limits = AncestorContextLimits(header: config, headers: ElementLimit(1), maxBytes: ByteLimit(1024))
  case paramStr(1)
  of "default": context(default(AncestorContextResult[AncestorContext])) # No selected payload.
  of "refused": context(captureAncestorContext(default(OwnedHeader), [], limits)) # Actual constructor refusal.
  else:
    var source = default(header.Header)
    source.unsigned.slot = HeaderSlot(1)
    var wire = newSeq[byte](1024)
    let encoded = encodeHeader(source, config, wire)
    assert encoded.error == HeaderError.None
    let owner = decodeHeader(wire.toOpenArray(0, encoded.value - 1), config).value.owner
    let captured = captureAncestorContext(owner, [], limits)
    assert captured.error == AncestorContextError.None
    context(captured)
    if paramStr(1) == "index":
      selected(captured.value.headerAt(1)) # Actual out-of-range refusal must reach the runtime contract.
    else:
      selected(captured.value.headerAt(0)) # Same accessor with a genuinely retained valid owner.
main()
