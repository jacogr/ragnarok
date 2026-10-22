# Nimony October 21 nightly upgrade

## Scope and pins

Upgrade the official compiler from `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`
(October 15) to `29b96c31be1647665e5c57f2788e1c8cfeeddc9c` (October 21), both 0.6.3.
This is the newest published nightly found on October 22; it is not upstream master.
Review the [44 included commits](https://github.com/nim-lang/nimony/compare/5b51edfedb4d0dbd9028d9e57ac61d69dffe9410...29b96c31be1647665e5c57f2788e1c8cfeeddc9c)
and the [official release](https://github.com/nim-lang/nimony-website/releases/tag/nightly-0.6.3-29b96c31b).

Both supported compiler assets retain explicit SHA-256 pins and NIGHTLY.txt identity checks.
The Linux archive was downloaded and verified; macOS ARM64 runs the installed compiler.
The formatter stays at Nim 2.2.12. No production dependency, protocol byte or compiler source is patched.
The matching browser source dependency changes to `ec471df7e83d6938bd482b4f4dd5c8d2ef210c1f`,
read from the new compiler's `src/nativenif.commit`; both source archives are checksum pinned.
Neither supported nightly contains `bin/jorogumo`, so its existing pristine-source bootstrap remains.

## Included fixes and project decisions

| Upstream change | Project adjustment or checked boundary |
| --- | --- |
| [#2708](https://github.com/nim-lang/nimony/pull/2708), interface checksums include generic bodies and private declarations | Remove whole-tree source epochs from NativeChecks and Hastur. The original private-helper arity reproducer succeeds in one unchanged cache (`7`, `12`, `12`); the old compiler still fails its second build. Preserve flags, ABI/header hashing, compiler isolation, worker locks and source provenance. |
| [#2715](https://github.com/nim-lang/nimony/pull/2715), strict stateless UTF-8 validation | Replace the duplicated RPC scalar decoder with `std/unicode.validateUtf8` (now in shared `src/lib/utf8.nim`). Independent literal tests retain ASCII/NUL, scalar limits, overlong, surrogate, out-of-range, malformed-continuation and truncated-input coverage, including errors between valid runs. |
| [#2719](https://github.com/nim-lang/nimony/pull/2719), reject ref-reached iteration | Traverse immutable owner fields by index, copying fixed values or retaining immutable owners where needed. Also avoid a sequence iterator across mutation of its draft's work counter. No `uncheckedBorrow`, disabled checks or dependency patches. |
| [#2688](https://github.com/nim-lang/nimony/pull/2688), [#2697](https://github.com/nim-lang/nimony/pull/2697), [#2711](https://github.com/nim-lang/nimony/pull/2711), forwarded borrows, results and conditional reassignment | The actual block-download callback probe still reports `cannot prove expression is not nil` without explicit non-null receiver/session bindings. Keep those bindings and short borrow lifetimes. |
| [#2673](https://github.com/nim-lang/nimony/pull/2673), integer formatting and allocation-free NumBuffer/addInt | Existing `$` calls inherit the new implementation. The actual `SomeInteger` JSON-style generic body still fails overload checking on the new pin, so concrete integer overloads remain. |
| [#2707](https://github.com/nim-lang/nimony/pull/2707), contract body field names; [#2652](https://github.com/nim-lang/nimony/pull/2652), static parameters | Keep public result guards and checked bounds. Existing static schema parameters remain valid; no protocol schema or proof is weakened. |
| [#2709](https://github.com/nim-lang/nimony/pull/2709), OS additions and directory/error fixes | The Darwin creation-call `open` binding still has a fixed third mode argument, so the maintained variadic-header binding remains. The newly merged management sampler uses public `DirStream` open/read/close operations instead of the removed libc directory exports; storage semantics remain unchanged. |
| [#2682](https://github.com/nim-lang/nimony/pull/2682), [#2685](https://github.com/nim-lang/nimony/pull/2685), inlining/name fixes; [#2694](https://github.com/nim-lang/nimony/pull/2694), alias copy propagation; cursor-field construction | Inherited compiler fixes; retain ownership/runtime and lowering regression checks. Custom moved-from discriminators remain explicit resource invariants, not removed on the assumption of a related fix. |
| CTFE enum/set/range constants, generic varargs contracts and assembler field access | Inherited fixes. Nonzero enum-index defaults and generic variant constructors are separate recorded limitations; do not remove their alternatives based only on these commit titles. |
| Streams, buffered parsing/deadlines, HTTP headers, terminal/colors, string layout and native math | Newly available APIs reviewed; no matching production workaround requires replacing maintained QUIC, JSON-number policy or bounded network scheduling. |

The scalar-only copy-hook fix `1112e45997` ([#2729](https://github.com/nim-lang/nimony/issues/2729))
is after this release. Explicit destructor/copy/dup protections stay until a published nightly includes
that fix and actual lowering/runtime controls confirm the owner's behavior.

## Verification

Local verification passed all 313 production module checks, all 1,976 compiler guards, 721 Python
tests (three skipped), and the real-browser UI check. Eighteen affected native suites passed, including RPC, block codecs, PVM memory/inner-machine
lifecycle, trie/proof transport, accumulation, storage retention and checkpoint transfer. The old/new same-cache control and both actual
NativeChecks profile controls establish the bounded cache fix. Raw local compiler-range, archive and compatibility-probe evidence
is under ignored `build/ci/` and `build/nimony-upgrade-probes/`. Local results apply to macOS ARM64;
checksum verification of the Linux asset is not a Linux runtime pass. Historical M1 migration evidence
remains historical evidence, not a new claim of complete JAM client parity.

## Qualification after merged storage resource work

Merge master `e0c3a430` into this upgrade without rewriting the published compiler commit.
All 81 master-changed files outside the original upgrade scope remain byte-identical to master;
the shared infrastructure guide retains both the cache-policy update and the merged package-setup
bounds. CI wiring, storage resource/report contracts, workload axes and provenance checks are preserved.
No additional storage compatibility edits were needed.

On the merged tree, all 112 storage Python safeguards and 86 Make/CI/cache integration safeguards
passed. All 11 new or affected native suites passed: allocator observations, deployment domain and
fixtures, seven lifetime controls, and sustained growth fixtures. The five ordinary-growth,
allocator-instrumented, deployment, lifetime and fresh-reopen benchmark profiles built with the
new compiler. Sixteen bounded native invocations passed their maintained independent parsers:
seven lifetime scenarios, three deployment backends, one allocator trajectory, one ordinary growth
trajectory, and separate producer/strict-consumer pairs for journal and managed reopen. Reopen
controls also preserved every stored byte. These are compatibility controls, not a rerun of complete
resource panels or new speed/resource measurements. Earlier production-module/guard verification
covers unchanged runtime sources and compiler pins; the new storage inputs have this additional
qualification. Local raw evidence is under `build/ci/nimony-storage-*`.

The subsequent memory-ceiling tranche was reconciled through master `ebd27f7b` with the same
held compiler pin. All 46 newly changed master files are byte-identical to master; no runtime,
build-profile or compiler-pin adjustment was needed. All 148 storage Python safeguards and
46 Make/CI safeguards passed. `make bench-storage-memory-ceilings` and its setup-free summary
passed: eight unrestricted native consumers validated complete maps and retained selected bytes;
three Darwin probes and all twelve capped attempts remained explicitly unavailable. This supplies
no Linux limit-enforcement evidence. The candidate remains held pending the next published nightly.


## Qualification after merged RPC and state review work

Reconcile master `42112504` while retaining the held compiler pin. Keep master's shared JSON
reader and UTF-8 module extraction, with the fixed stdlib validator in the shared UTF-8 module
so both public RPC and local management HTTP use it. All 368 newly changed upstream files outside
the upgrade's intended scope remain byte-identical to master.

The new management resource sampler used removed `DIR`/`opendir`/`readdir`/`closedir` exports.
Use the public `DirStream` API and an explicit private active flag. Preserve sixteen entries per
turn, the 4,096-entry admission limit, separate EOF/error outcomes, flat-layout accounting and
idempotent close/abandoned-scan cleanup. The immutable owner destructor closes a local copy of the
public stream value; only the retiring owner exercises that cleanup authority. Keep the
sampler's copy/dup rejections and the enclosing server's ownership contract.

On this merged tree, all 341 production modules, 2,113 compiler guards and 52 focused independent
state-oracle/Make/CI Python tests passed. All 35 selected native suites passed, covering the new
state review/checkpoint/deposit/footprint/supervision work, management HTTP/resources/services,
application options, RPC state proofs and public RPC UTF-8/JSON regressions. The resource suite
also passed after adding a forced mid-scan read-error witness, retaining its 1,000 abandoned-scan
ARC baseline check. The complete checked ARC/Clang/LTO native peer build passed. Inventory,
pinned formatting of changed Nim files and `git diff --check` passed. Evidence is under ignored
`build/ci/nimony-rpc-sync-*`. These are macOS ARM64 results; Linux runtime qualification remains
for CI. No storage semantics or compiler pins changed, and the candidate remains held.
