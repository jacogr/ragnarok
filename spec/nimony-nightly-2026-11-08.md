# Nimony November 8 nightly upgrade

## Scope and identities

Upgrade from October 28 `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` to the official November 8
archive `ad334fb80c031da5b9932e3f254c23b6dd5ccbe1`, published at 14:54:03 UTC.
The initial master base is `de2da361d30eefb7011a018df40c726b497ef908`. All three supported
archives were downloaded, checked against official SHA-256 digests, and inspected for the matching
embedded commit, date and platform. Keep the current Nimpretty 2.4.1 formatter, provider/protocol
pins, GitHub asset API fallbacks, checked ARC/Clang profiles and ThinLTO. No upstream tool or
library source is patched.

| Archive | SHA-256 |
| --- | --- |
| linux_amd64 | `539df04c1dc00e2702c0df121b1e7607965541eea7a254112fd11fdefab08cc7` |
| linux_arm64 | `b37839d95ba5c17eb1da070e1cd1ea4ada1b655ce5abc07924db5736870252ce` |
| macos_arm64 | `d09e7b4b632830c9beaf13039836a19294509b7065adcc74656aeacb126cf0b4` |

The browser compiler source is the same revision, SHA-256 `92a18bc7977c7193e3566c19df9ed8ca660b643328b40006d356fc3af730f374`.
Its embedded backend selection is `a6ff8e5a883ef0476bd123c5fd18cbc52fec03a0`, archive
SHA-256 `90ecd8538a3d1b37d24277687a95dfa16e03d77af5c9a01b705718e161d8ce98`. The official binary archive still lacks jorogumo;
the existing Make bootstrap builds that backend from matching pristine sources.

## Fixes, compatibility and cleanup

The archive descends from the complete [merged repair](https://github.com/nim-lang/nimony/pull/2931),
including optimizer write-effect tracking and module-qualified declared lookup. The unchanged
qualified-declared reproducer and missing-name control compile and execute. The seven-line
non-inlined var-write reproducer compiles and executes in checked and ThinLTO builds.

Restore qualified availability checks in the Sieve and DOOM performance drivers. A separate
control asserts that the actual re-exported `reference.DefaultPvmBackend` is declared and that a
missing qualified name is not; merely compiling a fallback branch is not qualification. Retain
the checks themselves, which still support comparison against archived runtimes. Internal include
guards and other useful unqualified lookups are unchanged.

Add a permanent `nimony_noninline_var_write` native suite so future optimized upgrades retain a
non-inlined call boundary even if an inliner changes the original pointer witness. The existing
checked/ThinLTO production-regression driver is unchanged.

The newer comparison rules require explicit same-domain equality for service IDs, header slots,
register words, spendable gas, terminal deficits, fault addresses, page counts and host-call IDs.
Each overload compares its own underlying representation and accepts no other nominal domain.
Existing CodeAddress/PageIndex equality and all ownership exclusions remain. This repairs the
comparison instantiations missed by the November 7 selected local run, including arrays of register
values and the native/ASAN/Contract/Fuzz consumers. No global numeric converter or generic
cross-domain equality is added. The ARM clipped-read witness explicitly checks its selected integer
opcode before calling bounded emitters; the two sampled opcodes and all existing assertions stay.

The archive also contains [readonly string views](https://github.com/nim-lang/nimony/pull/2932)
and the [prover/container/Hastur fixes](https://github.com/nim-lang/nimony/pull/2920). Preserve
read-only borrowing: mutable string views do not become writable through casts. Native codecs
retain byte-buffer output APIs. Shared stdlib caching and stronger string-high proofs are potential
development improvements; no controlled compilation speedup is claimed here.

## Retained issues

- NIM-002 remains expected behavior; keep supported concrete integer formatting overloads.
- NIM-005 remains suspected/project-bound. Keep the test-only physical counter observer until
  a new focused reduction and consumer comparison prove it unnecessary.
- NIM-006 still rejects the omitted variant-default argument. Explicit-default and factory controls
  compile and execute; retain the supported application overload/factory alternative.
- NIM-007 still hits the same nifcore bounds assertion when checking the CLI catalog for Linux
  AMD64 from macOS ARM64. This is a bounded cross-target failure, not a native Linux result.
- NIM-009 still retains 20,800 bytes after 100 retired HTTP messages under checked ThinLTO;
  preserve the HTTP adoption rollback and unchanged cleanup allowance. No upstream issue is filed
  or marked fixed for this ownership investigation.

See the [stable issue register](compiler-issues.md) for statuses and historical evidence.

## Qualification

Standalone monitor receipts are under ignored `build/upstream-watch/nimony/2026-11-08/`; upgrade
receipts and full logs are under `build/ci/nimony-upgrade-2026-11-08/`. The standalone official
archive remained byte-identical across all 1,177 files after private-cache probing. Final local
and exact-head full-CI results are recorded before merge; no Linux/browser runtime or performance
claim is inferred from macOS-only checks.


Local macOS ARM64 qualification before integrating the latest master's unused-entry-point cleanup:

- Optimized semantic graph: all 610 production modules and peer main pass; final formatted
  unoptimized Smoke graph passes after equality/witness adaptations.
- The unchanged production-regression family passes all 16 checked/ThinLTO positive and exact
  runtime rejection cases. All 24 retained compiler rejection predicates pass unchanged.
- Six selected native suites pass: noninline-var-write, pointer refinement, sequence slices,
  sequence ownership, application logical code proofs and RPC.
- The previously failed host-resume ASAN suite and its three calibration controls pass.
- Canonical native ARM qualification passes actual execution, legacy/refusal controls,
  shared asynchronous execution, resident-memory ownership and scalar/policy consumers.
- Linux AMD64 semantic preflight passes the x86 witness and both Sieve/DOOM performance drivers.
  This is cross-target compilation only, not Linux execution.
- The complete application builds with checked ARC/Clang ThinLTO, integration, offload and native
  ARM JIT enabled. Generated-C warnings remain; no warning-free build is claimed.
- Matching-source browser bootstrap and three embedded UI assets build successfully.

Full CI is explicitly requested on the published PR. Its exact-head outcome, native Linux runtime
and post-merge master verification remain separate from this local record.

The upgrade also integrates master `898c0a2d` (removal of unused native preparation entry points).
The merged complete application build and its help command pass. The optimized source graph
again passes all 610 modules and peer main; three browser
bootstrap tests pass. The removed entry points do not overlap the equality or guard changes.
Final native Linux/runtime qualification belongs to the authorized full-CI run on the PR head.
