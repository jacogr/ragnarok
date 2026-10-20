# Pinned Nimony compatibility

Consult this reference when introducing unfamiliar compiler or stdlib APIs. The project pin is
[spec/toolchain.json](../spec/toolchain.json); the longer [nightly trial](nimony-trial.md) records
ownership, arithmetic and migration evidence.

These observations came from the structured JSON refactor, CE 128 stream integration and PVM work
on macOS ARM64 with Nimony 0.6.3, revision `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`.
Recheck affected entries when changing the pin.
They describe the exercised APIs and target, rather than compiler-wide support guarantees.

| Area | Observed behavior | Working approach and evidence |
| --- | --- | --- |
| Assertions | `doAssert` was undeclared after importing `std/assertions`. | Use Nimony's release-enabled `assert` with the project runner. See the assertion notes in the trial and `tests/unit/crypto/test_rpc.nim`. |
| Integer overloads | Declaring both `int` and `int64` overloads, or both `uint` and `uint64`, produced ambiguous calls on this 64-bit target. | Use the fixed-width overloads in [`src/lib/json_writer.nim`](../src/lib/json_writer.nim); machine integers resolve through their matching width. |
| Generic checking | A `proc encode[T: SomeInteger](value: T): string = $value`-shaped body failed overload resolution during generic checking in the attempted writer. | Concrete integer overloads compiled and passed the RPC suite. This observation does not establish that integer generics are unsupported; probe generic alternatives separately. |
| Tuple arguments | An array literal of unnamed `(string, JsonValue)` tuples did not match the attempted `openArray[tuple[key: string, value: JsonValue]]` parameter. | `openArray[(string, JsonValue)]` with indexed tuple access compiled in `jsonObject`. Probe named conversions before relying on them elsewhere. |
| JSON output | Inspection of the pinned `std/json` typed writer found signed integer output and no full-width unsigned or raw-number overload. Its API differs from Nim 2's `%*` examples. | [`src/lib/json_writer.nim`](../src/lib/json_writer.nim) preserves unsigned decimal values and validated numeric lexemes. `spec/rpc.md` documents the trust boundary; RPC tests cover `uint64` maximum and exact ID spelling. |
| Nullable mutable borrows | In the CE 128 callback, checking a `nil ptr BlockDownload` local once did not preserve the non-null proof across successive calls taking its pointee by `var`. | After checking the nullable local, bind an explicitly typed `ptr BlockDownload` local. The [verified callback](https://github.com/jacogr/ragnarok/blob/5b79c125c33e8e53ff1e08db6ff653961ad940fa/tests/support/block_download_transport.nim) passes the native transfer suite without casting away receiver nilability. |
| Scalar-only exclusive owners | Error copy/dup declarations alone did not reject the exercised scalar-only controller copy during full compilation. | The final [stream controller](https://github.com/jacogr/ragnarok/blob/5b79c125c33e8e53ff1e08db6ff653961ad940fa/src/quic/block_download_stream.nim) combines explicit copy/dup prohibitions with a destructor checking actual callback retirement. Its [lowering probe](https://github.com/jacogr/ragnarok/blob/5b79c125c33e8e53ff1e08db6ff653961ad940fa/tests/native/compile_fail/application_download_stream_copy.nim) rejects `'=dup' is not available for type <BlockDownloadStream>`. Verify each exclusive owner; do not add artificial cleanup to ordinary scalar views. |

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
