# Current prepared chain update

Prepare a genuine current composed successor on private StateStore/ChainView
handle copies through the current coordinator exactly once. The opaque owner
retains original state identity, complete prior view, installed candidate state,
view and captured child in one private immutable data handle. Defaults contain no
snapshot graph; copies retain the same acyclic completed preparation. Read-only accessors expose only the completed snapshot,
view and child for durable serialization; defaults authorize no extraction.

After the caller's durable step, canInstallCurrentChainUpdate must still match
exact original state identity and complete ordered view/profile/finality. Guarded
installation replaces both live handles without hashing, recapture, guest replay,
callbacks or fallible work between assignments. Caller ownership is stable and
single-threaded across preflight/durability/install, as in the established chain
publication contract. Actual disk commit/recovery is separate work.

Preparation refusal retains only the actual current coordinator failure. No
successful candidate prefix escapes. Copies retain immutable candidate/provenance
owners independently of source scope, with acyclic ARC lifetime. Authority remains
the Gray Paper pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and current
composition/coordinator contracts; no new protocol interpretation is introduced.

Completion witnesses: preparation leaves live handles unchanged; exact candidate
and full view extraction; hash-free installation; stale state/view/equal-root/
replay/default refusals; changed parameter tuple rejection; retained copies and
source-scope independence; private/nominal/guarded access and ARC release.

Local macOS ARC/Clang checks passed: 304 source modules; current prepared-update/
coordinator and existing durable-preparation native suites; seven exact runtime
probes and six privacy/nominal compiler rejections; fresh 1,000-cycle ARC evidence;
inventory and formatting. Stable retained-owner projections keep checked runtime
preconditions and assertions. Linked native/runtime checks ran serially. Linux
CI and complete JAM parity remain separate evidence.
