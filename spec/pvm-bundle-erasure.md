# Source-bound audit bundle erasure chunks

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
erasure_coding.tex erasurecoding/transpose/erasurecodinginv and code-word
representation; work_packages_and_reports.tex availability specifier bundle arm
and zeropadding. Vector pin remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume a completed ErasureLayout, derive its exact original executed
AuditableBundle and validator geometry, and encode all systematic/parity chunks.
Split the zero-padded bundle into d contiguous chunks of 2k bytes, take the
same little-endian word offset from each chunk, apply the scalar word encoder,
and transpose the result back into v contiguous 2k-byte chunks. Missing suffix
bytes are zero, including the high byte of a word crossing the original end.
Never interleave adjacent input words as if they were distinct original chunks.

Success owns a private immutable flat encoded buffer and retains the original
layout/bundle provenance. Metadata and chunk extraction copy; no constructor
accepts detached original bytes, geometry or an unrelated scalar codeword.
Chunk ordinals use the full-width ErasureShardIndex, including parity positions.
These chunks are the input to the bundle arm of availability commitment; this
layer performs no hashing, availability Merklization or root/state certification.

Preflight native-int output representability and two aggregate local policies
before copying original bytes or doing field work. With d originals, span the
least power of two >=d, and k=chunkBytes/2, per-column products are
31*(span-1)+d*(d-1)/2+(v-d)*(d-1). Total work is k times this quantity, including
repeated inverse setup in the current scalar implementation. The byte policy
covers the retained encoded buffer plus simultaneous logical workspace:
original bundle length + 2d input words + 2*(v+d+span) scalar buffers. Original
source retention, allocation headers/fixed stack data and returned chunk copies
are separate. E4 length and validated dimensions bound all arithmetic below
2^50. A scalar refusal aborts without publishing any encoded prefix.

Completion: independent literal bundle construction and Lagrange coding for
6/1023-validator complete encoded-buffer hash witnesses, explicit parity chunks,
full systematic reconstruction/padding, mixed/repeated inputs, exact/refused
aggregate byte and product limits, invalid/default sources and indices,
copy/source/detached lifetime, zero hashes, compiler privacy/nominal guards,
optimized result guards and fresh ARC release.

Next: source-bound export/page erasure chunks, then bundle chunk hashes and
availability-root assembly. Production recovery and faster transforms remain
separate. Root/state freshness and package-to-root trust integration remain open.
M1 framing is complete; full state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_bundle_erasure`
passes complete independent encoded-buffer hashes for ordinary bundles at
6/1023 validators and rich inputs at 1023, explicit first/final parity chunks,
full systematic reconstruction/zero padding, exact/refused aggregate caps,
full-width index/source refusals and copy/source/detached ownership. Ordinary
1023-validator output is 26598 bytes, workspace 13251 bytes and total field
products 3982849; six-validator total products are 149838. No hashing occurs
during encoding, including with the primitive backend refused. Fresh 1000-cycle
ARC reports 309840/309840 occupied bytes. Seven strict optimized result guards
with genuine completed controls and six compiler privacy/nominal guards pass.
Three independent reference tests reproduce complete encoded-buffer/parity
witnesses, systematic layout and parity-only reconstruction of the real ordinary
bundle. Formatted unit/driver semantic checks, inventory, 20 affected inventory/
provenance tests and pinned formatting pass. Lower production modules and their
fixtures are unchanged. Exact-head Linux CI remains separate; remote checks
were not requested.
