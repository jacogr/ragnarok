# JAMNP-S message and audit codecs

## Target and scope

`src/jamnp-s/messages.nim` implements the stream-kind octet mapping and E4 message encoding
from JAMNP-S `simple.md` at `aa0e2b8498c0b1bc1725af2903704d701c6577ab`.
`src/jamnp-s/audits.nim` implements that revision's CE144/145 batched wire formats.
The reference upgrade is qualified separately in PR #1834. This increment changes no pins.

These codecs are intended for the production dispatcher, but this increment does not yet route
new streams through it or authenticate their claims. In particular, successful audit decoding
provides no VRF selection/tranche claim, Ed25519 credential validity, epoch membership, report
validity or authority to change state. The [compliance inventory](jamnp-compliance.md) retains
those runtime requirements as incomplete. Existing CE143 framing remains specific to CE143;
its rejection of other selectors is preserved independently of the general selector decoder.

## Message ownership and bounds

`MessageReader` is a noncopyable value owning one partial payload. Trusted host configuration
sets separate message-byte, stream-byte and stream-message-count limits. Stream bytes include
all four-byte E4 headers, including empty messages. The claimed E4 length is checked against
both byte budgets and host integer capacity before allocation. Unknown/reserved selectors
are rejected before sparse-enum conversion; every defined kind, including146–148, is recognized.

`feed` reports only the consumed prefix of the offered input. Once a message is complete it
consumes zero further bytes until `takeMessage` transfers the payload. The caller retains any
unconsumed suffix. Thus concatenated messages neither lose bytes nor require an unbounded
queue. Partial headers/payloads never escape; parser failure releases partial storage and poisons
further input until explicit host reconfiguration. `finish` accepts FIN only at a clean message
boundary after the last completed message is taken. Both-half stream completion, protocol
transcripts, role checks and UP stream replacement remain the dispatcher's responsibility.

No thread, foreign resource or source borrow is retained by these codecs. `takeMessage` moves
complete storage to the host. Audit batch handles retain private immutable ARC snapshots;
record access returns fixed-size detached values. Failed/default tagged results contain only
reasons and expose values only through success-guarded accessors.

## Audit representations

CE144 announcement records are131 bytes for initial intent and133 bytes for later intent:
32-byte block hash, E2 auditor index, one-byte intent, optional E2 core,96-byte Thin evidence.
The message has no outer count, explicit tranche, announced core list, Ed25519 announcement
signature or separate evidence message. Initial selected cores and later tranche numbers must
be derived by contextual authentication, not taken from untrusted declarations.

CE145 positive records are103 bytes: E4 epoch, E2 auditor, tag1,32-byte report hash and64-byte
signature. Tag0 inserts E4 guarantee slot, canonical compact count2/3 and E2-index/64-byte
credential pairs before the report hash and judgment signature. Negative records therefore
occupy240 or306 bytes. Guarantee identities must be strictly increasing and within the supplied
structural population ceiling, matching the existing GP guarantee codec contract. Different
auditors, report hashes and epochs can share one batch. The host must still select and verify
the actual validator sets for each record's epoch/slot.

Decoders first scan the whole message without retaining allocations. Every record, variable
extent, index and resource count must pass before immutable batch storage is allocated. A late
malformed record fails the entire batch. A strict prefix ending exactly at a record boundary
is a valid shorter batch because the enclosing message supplies the sequence length; other
strict prefixes fail. Empty batches are structurally representable; whether to emit/process
one belongs to the stream handler's policy.

## Verification

`make unit SUITE=jamnp_messages` covers all256 selector octets, fragmented/concatenated messages,
empty payloads, independent E4 bytes, byte/count budgets, poisoned/default readers and FIN.
`make unit SUITE=jamnp_audits` consumes SHA256-bound static fixtures under `tests/fixtures/jamnp-audit/`.
`tests/jamnp_audit_oracle.py` constructs those bytes independently using Python fixed-width
packing; `test_jamnp_audit_oracle.py` checks exact frozen bytes and normative field offsets.
These are structural samples, with deliberately opaque evidence bytes; they are not valid
cryptographic proofs.

Audit checks compare encoder sources constructed independently of decoder output, every input
prefix, both intent forms, both negative guarantee counts, mixed epochs/auditors, byte/count
ceilings, invalid tags/indices, duplicate credentials, trailing partial records, late failures,
default/index errors and input/returned-record mutation. Compiler guards preserve parser
noncopyability and private result/batch storage. Broader corpus/dispatcher interoperability and
cryptographic/state authentication are subsequent completion requirements, not inferred from
these tests.
