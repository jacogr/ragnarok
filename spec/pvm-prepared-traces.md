# Independent prepared-owner traces

This test-only increment reuses the existing frozen `pvm-mixed-program.bin` corpus and its
independent Gray Paper gas-table simulator, literal host reply equations and full post-state
records. The corpus SHA256 remains
`13a5be9ff1c65e08869dbe31c0ab5b49fa8593a7adfbdc4b32b4e0bbd521cf09`; no program, expected
register, gas price, memory byte, fixture descriptor, production runtime or backend interface
changes. The existing external reference programs remain independent coverage; this increment
does not describe all engine-to-engine comparisons as independent proofs.

Both `pvm_mixed_program_reference` and `pvm_host_memory_reentry_reference` create one genuine
prepared owner per frozen program and retain it through both cold/second passes, response-only
and fallible host adapters, exact/surplus/short gas and every repaired retry. Each suite now
covers1536 policy/host scenarios rather than constructing a fresh prepared owner at each call.
The host-reentry suite includes23616 callbacks and17712 independently selected repaired faults.
All CPU fields,13 registers, exact ordered page identities, permissions and every page byte are
checked against fixed records/equations; real original and intermediate immutable machines remain
retained and rechecked after replacements.

The host-reentry suite also visits PCs20/5/0/5/20/0 through that same owner,192 reordered entry
visits over32 programs. The original terminal, store/host and load/host prefixes provide literal
outcomes for zero, one-short and exact1/2 attempts. Local step refusal publishes no partial machine
and cannot alter the supplied owner. Paid zero-gas entries skip repricing; unpaid block starts use
the corpus's fixed103/22 charges, while unpaid interior PC5 is checked only at zero credit rather
than inventing a suffix price. Paid PC5 permission faults retain exact missing-before-read-only
priority and atomic refusal; independently authored repairs reach the literal host14 outcome.

Native-enabled qualification requires strictly positive actual call and operation deltas for
eligible complete prepared loops. Initial unpaid refusal, explicit executable-storage refusal
and ordinary checked builds cannot claim native work. Private native variants emit cumulative
`PREPARED_TRACE_NATIVE` receipts; the ordinary registered output remains deterministic. These are
correctness witnesses, not cache-capacity tests, clocks or performance claims. JIT-owned resource,
entry-reuse and host-resume suites remain separate.

Verification: run the two existing selected native suites in CI with checked ARC/Clang flags and
preserved bounds/assertions. Local source checks and independent frozen-corpus Python tests are
separate from native evidence. A private CI archive will deliberately change only the common
gas simulator's final successful price by+1, preserve the live source and every fixed expectation,
and require the prepared terminal trace to fail at `independent prepared entry exit trace`.
A separate private control must show dynamic and prepared engines agree on the wrong result,
proving that equality alone would miss the defect. Native qualification and this mutation control
are pending; no runtime or backend fix belongs to this test PR.


A genuine unpaid PC10 admission now precedes the main host scenarios, after the first fixed PC20
oracle. The existing independent GP simulator, retaining original raw prefix bytes and global
branch target positions, derives tail price22/cycles25 for all32 programs. Starting r10 at
iterations−1 and funding44 for tail+halt yields literal Halt/gas0 with r10=iterations and every
other register/page unchanged. This creates a legitimate complete header for the short x86
add/branch prefix; it does not rely on redundant paid-tail compilation. Positive native-delta
assertions are retained for this control and subsequent complete loops. Reordered PC traces and
the shared-price mutation's first terminal assertion remain unchanged.
