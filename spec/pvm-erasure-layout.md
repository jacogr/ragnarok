# Systematic erasure input layout

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
erasure_coding.tex equations ecoriginalshards, erasurecoding and erasurecodinginv;
safrole.tex valcount; work_packages_and_reports.tex availability specifier and
zeropadding. Vector pin remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: compute the original-shard count d as the greatest positive divisor of
2052 not exceeding v/3+1. Accept only the established GP validator domain,
multiples of three from 6 through 1023. z=2d; k=ceil(bundleLength/z); padded
length=z*k; each encoded chunk is 2k bytes. Segment chunks are 4104/d bytes.
Geometry is copied descriptive data, never an availability certificate.

The formal erasurecoding equation first splits the padded input into d contiguous
2k-byte chunks, then transposes their little-endian words for coding. Consequently
the first d systematic chunks are contiguous slices, NOT every d-th pair from the
input. Their concatenation reconstructs the padded original. Empty input requires
zero padding bytes and has zero-length chunks. Aligned input adds no extra block.
All geometry arithmetic is uint64 after the E4 BundleLength bound; the largest
intermediate is below 2^43, including all prospective encoded bytes.

Prepare an immutable owner only from a completed AuditableBundle. Preflight the
padded buffer against native-int and local ByteLimit before copying original
bytes. Retain the exact original source, store an independent zero-padded copy,
and copy systematic chunks on extraction with a nominal full-width index.
Reject parity indices rather than fabricate parity. The budget covers this owner's
padded byte buffer; original source retention and returned chunk copies are separate.

Completion tests: exhaustive uint16 validator-domain rejection/acceptance,
maximality/divisibility and E4 arithmetic; 6/1023 validator golden geometry,
contiguous chunk reconstruction/padding with actual executed bundles, exact budgets,
invalid/default sources and indices, independent source/copy lifetimes, no hashing,
optimized result guards, compiler privacy/nominal rejection and fresh ARC release.

Next: GF(2^16) Cantor-basis parity encoding and independent parity/recovery witnesses,
then source-bound export/page erasure chunks and availability-root assembly. No
parity, recovery, availability certificate or active-set equality is claimed here.
Root/state freshness and package-to-root trust integration remain open. M1 framing
is complete; full state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_erasure_layout`
passes all 65536 validator encodings, maximal-divisor/maximum-E4 arithmetic,
empty/aligned/adjacent-stripe geometry, exact-budget real-bundle reconstruction
at 6 and 1023 validators, explicit zero suffixes, index/domain/source refusals,
copy/detached lifetime and zero additional hashes. Fresh 1000-cycle ARC reports
238608/238608 occupied bytes. Six compiler privacy/nominal guards, unit/driver
semantic checks, inventory, 20 affected inventory/provenance tests and pinned
formatting pass. Exact-head Linux CI remains separate; remote checks were not
requested. Existing lower production modules and their fixtures are unchanged.
Eight strict optimized runtime guard cases pass with a genuine completed-layout
control before every deliberate refused extraction.
