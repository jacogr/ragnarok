# Systematic Reed–Solomon word encoding

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
erasure_coding.tex Code Word representation, Cantor basis and Generator Polynomial;
ecoriginalshards and safrole valcount. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: the scalar erasurecode(v) transform from d input words to v output words.
Words are nominal uint16 numeric values corresponding to little-endian E2 wire
pairs; numeric word bits and validator indices both denote Cantor coordinates.
The polynomial field uses x^16+x^5+x^3+x^2+1 (0x1002d). Convert using the exact
sixteen pinned basis columns, interpolate degree below d through validator
indices 0..d-1, and evaluate parity indices d..v-1. Original words remain exact.
This primitive accepts detached words deliberately: it certifies no bundle,
execution, active roster, availability root or state provenance.

Production uses Newton divided differences, polynomial-basis shift/reduce
multiplication, Fermat inverses and inverse linear basis columns. Denominators
are XOR differences of consecutive original indices. Precompute inverses for
nonzero indices below the least power of two at least d (at most 512). The
inverse of zero is never selected. Every inverse uses exactly 31 field products
(15 selected multiplies and 16 squares). Total field products are
31*(span-1)+d*(d-1)/2+(v-d)*(d-1). All dimensions derive from validated geometry;
counts are bounded below 2^20 before arithmetic or int conversion.

Local limits cover the exact retained v-word output and transient d-word Newton
coefficients plus span-word inverse table: 2*(v+d+span) bytes. This is logical
buffer payload, excluding allocator headers and fixed stack data. Preflight
byte and field-product budgets before variable allocation or field arithmetic.
Success retains private immutable output and copied work facts. Indexed word
extraction returns scalars; defaults and refusals carry reasons only.

Completion: independent Python Lagrange interpolation with Euclidean inverses,
full codeword witnesses at 6/9/51/1023 validators, independent recovery from
parity/mixed subsets, systematic identity, all basis bits, zero/constant words,
exact resource limits, malformed input lengths/domains/indices, copy/lifetime
isolation, compiler privacy/nominal guards, optimized result guards and ARC release.

Source-bound audit bundle encoding continues in [pvm-bundle-erasure.md](pvm-bundle-erasure.md).

Next: source-bound bundle and export/page chunk encoding using the scalar
transform, then availability-root assembly. Production recovery and faster
transforms remain separate. Root/state trust integration remains open. M1
framing is complete; full state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_erasure_words`
passes complete independent codewords at 6/9/51/1023 validators, all sixteen
basis bits and constant/zero polynomials, systematic identity, exact and short
byte/product limits, malformed lengths/domains/indices, mutation isolation and
detached ownership. Fresh 1000-cycle ARC reports 352/352 occupied bytes. Seven
strict optimized result guards include genuine parity controls; six compiler
privacy/nominal guards pass with exact observed diagnostics. The pinned compiler
renders the word-array mismatch as `expected: openArray`, so its fixture also
requires the exact encoder call and `array[0..2, uint16]` argument diagnostic.
Three independent reference tests reproduce every literal codeword, verify field
inversion and reconstruct originals from erased parity/mixed subsets. Formatted
unit/driver semantic checks, inventory, 20 affected inventory/provenance Python
tests and pinned formatting pass. No lower production source or fixture changed.
Exact-head Linux CI remains separate; remote checks were not requested.
