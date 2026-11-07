# Nimony November 7 nightly upgrade

## Identities and scope

Upgrade master `e16e9bd02` from Nimony 0.6.3 `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`
to official nightly `ee5497661fac399ff471d7aff472803e36a1e0f0`, published November 7 at
14:47:37 UTC. Publication time and embedded compiler identity determine the selected release.
All three supported archives were downloaded and verified against published SHA-256 digests;
embedded commit, date and platform metadata match. Runtime qualification below is macOS ARM64,
not native Linux execution.

| Archive | SHA-256 |
| --- | --- |
| linux_amd64 | `a62cd19dc77aa7c372dc9fb25d51509282ed06c81162c57ff583f9824fc6a4cf` |
| linux_arm64 | `988d4f305291e04ae739578759a7e2da2f2a0aefbb26480bbf8f279cb773bf83` |
| macos_arm64 | `0d63394abba32abb12beec5ebe06d2bc337da50d5c94b6284e71fdf6517c694f` |

The browser compiler uses the same Nimony source revision, archive SHA-256
`4f21a5f31331d57c19afb5e29d166d794343b2c6ef6f966dfc4011e406eb45cd`.
Its embedded `src/nativenif.commit` selects `a6ff8e5a883ef0476bd123c5fd18cbc52fec03a0`,
source SHA-256 `90ecd8538a3d1b37d24277687a95dfa16e03d77af5c9a01b705718e161d8ce98`.
The official archive still lacks jorogumo; keep the existing matching-source Make bootstrap.
Nimpretty 2.2.12 and unrelated protocol/provider pins remain unchanged. No upstream source patches,
danger mode, disabled bounds checks or weakened ownership contracts are introduced.

## Relevant compiler changes

- [Copy propagation repair](https://github.com/nim-lang/nimony/pull/2898) handles moved nested
  references reached through rederived pointers. This motivates upgrading; it does not prove that
  the project-bound counter observation in NIM-005 has been fixed.
- [Re-export cache checksums](https://github.com/nim-lang/nimony/pull/2899),
  [per-module option tracking](https://github.com/nim-lang/nimony/pull/2917) and
  [shared stdlib caching](https://github.com/nim-lang/nimony/pull/2922) improve cache correctness
  and offer compilation reuse. No controlled before/after speedup is claimed.
- [Distinct ordinal comparison enforcement](https://github.com/nim-lang/nimony/pull/2915)
  requires explicit same-domain equality for PageIndex and CodeAddress. Service identities are
  compared through their existing uint32 representations at three internal lookup/grouping sites.
  Different nominal domains remain distinct at public API boundaries.
- Range proof changes require validation on original policy fields, not tuple copies. Preserve
  accepted ranges, rejection order and field-specific diagnostics. Explicitly validate converted
  peer indices and selected argument indices before passing bounded API parameters; retain the
  existing array/shape checks. The Tiny signing ordinal has an explicit range check at conversion.
  ARM JIT prefix-read emission now guards the converted integer opcode before passing either
  bounded emitter parameter; supported opcode sets and fallback behavior are unchanged.

## Retained workarounds and limitations

NIM-004 still asserts with `c.rem == 0` and six unconsumed children on the standalone qualified
`declared()` probe; the unqualified control passes. NIM-006 still rejects an omitted variant-default
argument; explicit-default and factory controls compile and execute. These probes use the
checksum-verified official archive, outside-project sources and private caches. Keep both supported
alternatives. NIM-002 is expected generic checking behavior: concrete integer overloads stay.
NIM-005 remains suspected/project-bound and NIM-007 cross-target checking is not freshly qualified;
this upgrade makes no resolution claim for either. See the [issue register](compiler-issues.md).

## Qualification

On macOS ARM64 with the official compiler and matching pristine-source browser backend:

- `make check-modules`: all 607 production modules plus the peer entry point pass checked-release
  semantic compilation. `make check-smoke` passes formatting and unoptimized all-source checking,
  including a final run after the ARM-specific proof adjustment.
- `make build`: complete application compiles and links with ARC, checked bounds, Clang ThinLTO,
  integration, offload and native ARM JIT enabled. Generated C emits warnings; this is a passing
  build, not a warning-free claim.
- All 24 retained compiler rejections pass their original predicates: 21 ownership, two admission
  and one schema guard. Fourteen existing PVM runtime misuse probes compile successfully and
  then fail with their exact expected assertion diagnostics.
- Sixteen selected native suites pass: pvm_machine, pvm_program, nimony_pointer_refinement,
  nimony_sequence_slices, nimony_sequence_ownership, state_code_availability,
  accumulation_statistics, application_logical_service_proofs, jamnp_node_connections,
  jamnp_node_command, pvm_current_download_command, rpc, jamnp_work_policy,
  jamnp_assurance_policy, pvm_checked_read_arbitration and pvm_checked_read_tiny.
  Reported ARC lifecycle checks retain equal occupied bytes before/after.
- Matching browser backend bootstrap and three embedded UI assets succeed; all three existing
  browser setup Python tests pass. This does not claim browser end-to-end execution.

Receipts are retained under ignored `build/ci/nimony-upgrade/` and
`build/upstream-watch/nimony/2026-11-07/`. Full Linux runtime, broad native/corpus coverage,
end-to-end networking and performance comparisons remain separate CI/evaluation work.
