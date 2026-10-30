# JAMNP-S audit-source upgrade

The networking reference advances from
`439c45aad135dc654b3de6f56d7d694fd02b7aa8` to
[`aa0e2b8498c0b1bc1725af2903704d701c6577ab`](https://github.com/zdave-parity/jam-np/tree/aa0e2b8498c0b1bc1725af2903704d701c6577ab).
`quic-proof-pins.json` records the immutable `simple.md` digest; the pristine
`vendor/jam-np` gitlink supplies the same source. The ten-commit delta changes
CE138, CE144 and CE145. Identity names, ALPN, message E4 lengths, UP0 and the
implemented CE128/CE143 wire formats are unchanged.

CE138 permits non-validator nodes to request audit shards for bundle recovery;
assurers may throttle those requests. Validator membership alone is no longer
a required requester condition.

CE144 sends a sequence of announcements in one message. Each announcement is
`Header Hash ++ Validator Index ++ Intent ++ Bandersnatch Signature`, where
intent is a one-byte zero for the initial tranche or one followed by the core
index for a later tranche. Initial cores and later tranche numbers are derived
from the authenticated VRF evidence rather than declared in legacy lists.
The old explicit tranche, Ed25519 announcement and nested no-show representation
is no longer the pinned format. Audits triggered by negative judgments are not
announced.

CE145 batches judgments, including different auditors, work-reports and epochs.
Each judgment is `Epoch Index ++ Validator Index ++ Validity ++ Work-Report Hash
++ Ed25519 Signature`. Invalid validity is zero followed immediately by its
guarantee; valid validity is one without a guarantee. The guarantee no longer
follows the report hash/signature as a separate message. The enclosing message
extent determines the sequence, under the specification's general framing rules.

## Implementation boundary and checks

Ragnarok does not currently implement CE138 shard service, CE144 audit intent or
CE145 judgment transport. Updating this reference does not claim their runtime
support or consensus authentication. Future handlers must implement the new
schemas and their bounded validation directly, without accepting the old forms.
Existing CE143 framing rejects selectors138/144/145 before payload access,
including complete frames and either FIN state.

`test_spec.py` verifies the pinned source bytes and the changed normative schemas.
The native `quic_protocol` suite retains exact-prefix/FIN, length and malformed
DER/framing coverage and checks those unsupported selectors explicitly. Existing
UP0 announcement and current download consumers remain on their unchanged
formats. The Gray Paper remains the authority for audit selection, judgments,
credentials and state transitions; these source checks do not establish full
JAMNP-S interoperability.
