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
| [#2715](https://github.com/nim-lang/nimony/pull/2715), strict stateless UTF-8 validation | Replace the duplicated RPC scalar decoder with `std/unicode.validateUtf8`. Independent literal tests retain ASCII/NUL, scalar limits, overlong, surrogate, out-of-range, malformed-continuation and truncated-input coverage, including errors between valid runs. |
| [#2719](https://github.com/nim-lang/nimony/pull/2719), reject ref-reached iteration | Traverse immutable owner fields by index, copying fixed values or retaining immutable owners where needed. Also avoid a sequence iterator across mutation of its draft's work counter. No `uncheckedBorrow`, disabled checks or dependency patches. |
| [#2688](https://github.com/nim-lang/nimony/pull/2688), [#2697](https://github.com/nim-lang/nimony/pull/2697), [#2711](https://github.com/nim-lang/nimony/pull/2711), forwarded borrows, results and conditional reassignment | The actual block-download callback probe still reports `cannot prove expression is not nil` without explicit non-null receiver/session bindings. Keep those bindings and short borrow lifetimes. |
| [#2673](https://github.com/nim-lang/nimony/pull/2673), integer formatting and allocation-free NumBuffer/addInt | Existing `$` calls inherit the new implementation. The actual `SomeInteger` JSON-style generic body still fails overload checking on the new pin, so concrete integer overloads remain. |
| [#2707](https://github.com/nim-lang/nimony/pull/2707), contract body field names; [#2652](https://github.com/nim-lang/nimony/pull/2652), static parameters | Keep public result guards and checked bounds. Existing static schema parameters remain valid; no protocol schema or proof is weakened. |
| [#2709](https://github.com/nim-lang/nimony/pull/2709), OS additions and directory/error fixes | The Darwin creation-call `open` binding still has a fixed third mode argument, so the maintained variadic-header binding remains. The new directory APIs do not justify changing storage semantics. |
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
