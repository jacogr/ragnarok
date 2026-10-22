# Pinned Nimony compatibility

Consult this reference when introducing unfamiliar compiler or stdlib APIs. The project pin is
[spec/toolchain.json](../spec/toolchain.json); the longer [nightly trial](nimony-trial.md) records
ownership, arithmetic and migration evidence.

These observations came from the structured JSON refactor, CE 128 stream integration and PVM work
on macOS ARM64 with Nimony 0.6.3, revision `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`.
The October 21/22 nightly review and retained-workaround decisions are recorded in
[the upgrade audit](../spec/nimony-nightly-2026-10-21.md).
The generic-integer and nullable mutable-callback failures were reproduced on the new pin too.
These observations describe exercised APIs and targets, rather than compiler-wide support guarantees.

| Area | Observed behavior | Working approach and evidence |
| --- | --- | --- |
| Assertions | `doAssert` was undeclared after importing `std/assertions`. | Use Nimony's release-enabled `assert` with the project runner. See the assertion notes in the trial and `tests/unit/crypto/test_rpc.nim`. |
| Integer overloads | Declaring both `int` and `int64` overloads, or both `uint` and `uint64`, produced ambiguous calls on this 64-bit target. | Use the fixed-width overloads in [`src/lib/json_writer.nim`](../src/lib/json_writer.nim); machine integers resolve through their matching width. |
| Generic checking | A `proc encode[T: SomeInteger](value: T): string = $value`-shaped body failed overload resolution during generic checking in the attempted writer. | Concrete integer overloads compiled and passed the RPC suite. This observation does not establish that integer generics are unsupported; probe generic alternatives separately. |
| Tuple arguments | An array literal of unnamed `(string, JsonValue)` tuples did not match the attempted `openArray[tuple[key: string, value: JsonValue]]` parameter. | `openArray[(string, JsonValue)]` with indexed tuple access compiled in `jsonObject`. Probe named conversions before relying on them elsewhere. |
| JSON output | Inspection of the pinned `std/json` typed writer found signed integer output and no full-width unsigned or raw-number overload. Its API differs from Nim 2's `%*` examples. | [`src/lib/json_writer.nim`](../src/lib/json_writer.nim) preserves unsigned decimal values and validated numeric lexemes. `spec/rpc.md` documents the trust boundary; RPC tests cover `uint64` maximum and exact ID spelling. |
| Nullable mutable borrows | In the CE 128 callback, checking a `nil ptr BlockDownload` local once did not preserve the non-null proof across successive calls taking its pointee by `var`. | After checking the nullable local, bind an explicitly typed `ptr BlockDownload` local. The [verified callback](https://github.com/jacogr/ragnarok/blob/5b79c125c33e8e53ff1e08db6ff653961ad940fa/tests/support/block_download_transport.nim) passes the native transfer suite without casting away receiver nilability. |
| Scalar-only exclusive owners | The October 22 pin honors direct copy hooks without a destructor; older pins ignored the exercised scalar-only ban. Sequence copying still bypasses element copy bans on this release ([#2737](https://github.com/nim-lang/nimony/issues/2737)); its fix is newer than the archive. | Keep explicit ownership exclusions and real callback-retirement destructors. The scalar-only and stream-array lowering probes require the exact unavailable-dup diagnostic. Do not add artificial cleanup to scalar views or treat direct-copy rejection as proof of container-copy exclusion. |

## PVM integration observations

The PVM work also exercised the pinned Nim formatter 2.2.12. Some wrapped long assertions acquired
an attached operator such as `==ImportJustificationError.RootMismatch` and then failed semantic
checking. This is an observed integration failure; a standalone trigger has not been minimized.
Keep comparison expressions short, for example by assigning the checked result to a local before
asserting its error, or using a short exact-reason assertion helper. Run semantic checking after
formatting and before the expensive linked suite; a formatting pass alone does not prove validity.
The formatted-source check and native import-justification suite passed with the helper approach.

Nominal diagnostics can omit useful type detail. Generic hash-domain substitutions may print
`ReportHash` on both sides, and a sequence mismatch may print `seq` without its element type.
Preserve the actual diagnostic plus its intended call/argument position, and a compiling positive
control for the accepted domain. Do not weaken a fixture into accepting an arbitrary compile error.
Existing examples include `tests/native/compile_fail/swapped_report_root.nim` and
`tests/native/compile_fail/history_segment_as_package.nim`; the trial records the generic hash
rendering. PVM argument-position fixtures were verified in
[the import-justification PR](https://github.com/jacogr/ragnarok/pull/284).

## Before integrating a new pattern

Read only the relevant pinned declaration and an existing project caller. If compatibility remains
unclear, compile a small example under `build/` using the pinned tools and affected build flags.
For assertion behavior, include a deliberately failing case and verify nonzero exit status;
a compiling or passing assertion alone cannot demonstrate that checks are active.

After integration, run `make unit SUITE=<affected-suite>` and the relevant consumers. Record a new
compatibility entry only for a demonstrated failure or inspected API difference that is likely to
recur, with a working alternative and its evidence. Keep speculative limitations out of this table.

## Variadic POSIX open on Darwin ARM64

The pinned `std/posix` binding declares `open` with a fixed third `Mode`
parameter. A real lock-file positive control on macOS ARM64 observed incorrect
creation permissions and then `IoFailure` on reopen. The checkpoint owner binds
`open` through `<fcntl.h>` with a C integer mode argument so Clang sees the actual
variadic SDK declaration and applies its ABI. A controlled-umask native test
requires exact 0600 permissions and subsequent contention/reacquisition. Keep
the pinned compiler/stdlib unchanged; use the narrow maintained OS declaration
for creation calls. Directory opens without creation flags do not use the mode.

## Disarming exclusive tagged moves

An exclusive prepared checkpoint's generated move reset cleared its sequence but
retained the `None` discriminator in inspected optimized C. A native regression
therefore observed an apparently successful moved-from owner. Supply the public
`=wasMoved` hook with `.nodestroy` to reset the discriminator to `Uninitialized`
without freeing the transferred bytes; the pinned stdlib uses the same public
hook pattern for resource owners. Root/size extraction and publication then reject
the moved source. Test source observation, surviving destination bytes, actual
ARC copy rejection and repeated release; successful semantic checking alone did
not expose this lifecycle mismatch. No compiler/stdlib changes are needed.

## Nested tagged defaults at call boundaries

Recovery startup observed conflicting `completed` fields when a complex
`default(ApplicationChain)` was an optional private parameter, and when
`default(ApplicationRecoveryResult)` appeared directly inside an asserted call.
Explicit helper arguments and a named local default result passed semantic and
native checking. See [the Services binding test](../tests/unit/state/test_application_recovery_services.nim).
Keep negative controls opaque enough to exercise runtime admission rather than
constant construction; this observation does not establish a general default-value
restriction or justify modifying the compiler.

For the observed stale imported generic-call arity after an incremental source edit,
see the [source-sensitive native cache record](../spec/pvm-native-cache-identity.md).
The October 21 nightly fixes the reproduced imported-generic invalidation failure; project-owned
source epochs have been removed after the same-cache control passed. Native ABI, compiler,
configuration and worker/profile cache isolation remain in place.

## Sequence slices on the October 22 candidate

At `8cb7a690ae48363eb3ce65564aafb921ca5d23f3`, instantiating the stdlib sequence
slice with `let bytes = @[1'u8, 2, 3]; let prefix = bytes[0..<2]` fails in
`lib/std/system.nim` with `cannot mutate rawData(result)[i] through a ref/ptr in a
.noSideEffect context` (the diagnostic prints `.noSideEffect` with backticks).
The four-line standalone probe is preserved in the nightly audit evidence. For the record,
journal and context-codec truncation tests, borrow `toOpenArray(0, stop-1)` instead: the caller
retains the source, decoders accept read-only inputs and every prefix including empty remains
covered. No stdlib patch or weaker assertion is required. Recheck the minimal probe on the next
nightly before drafting the remaining compiler reports.

## Deferred Linux RSS return

At pin `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, the management RSS helper's Linux
branch ended a proc with deferred descriptor cleanup using
`digits > 0 and size > 0 and product(pages, uint64(size), output)`.
Linux x86-64 semantic lowering aborted with
`[Bug] and/or should have been handled by the expression elimination pass xelim.nim`.
The macOS conditional branch did not exercise that expression. Replacing only the Boolean
expression with a bare call exposed a subsequent `nimony_model.nim` `n.isTagLit` assertion.
An explicit invalid-input guard followed by `result = product(...)` compiled successfully.
Keep the cleanup, validation and checked multiplication; no compiler or runtime patch is needed.

The Linux branch can be checked on macOS with the pinned compiler's supported command:
`nimony check --os:linux --cpu:amd64 --mm:arc --cc:clang -d:release src/management/resources.nim`.
Use a private `--nimcache` for each target/module. This proves target semantic lowering only;
Linux native tests still own linking, OS behavior and ownership evidence.
