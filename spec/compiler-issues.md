# Compiler issue register

Follow the [tracking process](../docs/compiler-issues.md). This register starts with the four
recently investigated behaviors; older observations remain in the
[compatibility reference](../docs/nimony-compatibility.md) and should receive an entry when reviewed.
IDs are stable. Status below is distinct from the last compiler actually tested.

| ID | Trigger and impact | Status / next action | Last tested |
| --- | --- | --- | --- |
| NIM-001 | Sequence slicing rejected; fixture copies required. | Locally verified fixed. [#2782](https://github.com/nim-lang/nimony/issues/2782), [fix #2789](https://github.com/nim-lang/nimony/pull/2789). Owned slice adapters removed in [Ragnarök #1723](https://github.com/jacogr/ragnarok/pull/1723); retain useful borrowed views. | October 28, 2026; `63fed6cb4`, macOS ARM64. |
| NIM-002 | `$value` in a `SomeInteger` generic rejected; JSON writer uses concrete overloads. | [#2808 closed as not a bug](https://github.com/nim-lang/nimony/issues/2808#issuecomment-6448849445). A type constraint does not guarantee a dollar operator. Retain supported concrete overloads; no pending compiler fix. | October 27, 2026; `358b9bce4`, macOS ARM64. |
| NIM-003 | Second mutable pointee call loses nil proof; callback needed explicitly typed non-null pointer. | Locally verified fixed in October 28 archive containing [#2811](https://github.com/nim-lang/nimony/pull/2811) and [#2813](https://github.com/nim-lang/nimony/pull/2813). Original inferred-local probe and typed control run; transport callback fixtures use inferred pointers again. See [qualification](nimony-nightly-2026-10-28.md). | October 28, 2026; `63fed6cb4`, macOS ARM64. |
| NIM-004 | Qualified `declared(...)` crashes compiler; PVM comparison guard uses unqualified lookup. | Draft for maintainer submission; still crashes in 5/5 clean directories on the newest published archive. No upstream issue filed. | October 28, 2026; `63fed6cb4`, macOS ARM64. |

## Reproducers, workarounds and evidence

The October 26 tested commit is `358b9bce4dd855453f57a80a0c499b0b2e27d7ee`;
the October 28 tested commit is `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, both Nimony 0.6.3.
Preserve each row's own last-tested identity rather than silently refreshing historical results.

- NIM-001: [original report](nimony-reports-2026-10-23/sequence-slice.md),
  [upgrade qualification](nimony-nightly-2026-10-26.md), and permanent
  [sequence-slice suite](../tests/unit/codec/test_nimony_sequence_slices.nim).
- NIM-002: [report and upstream resolution](nimony-reports-2026-10-27/integer-generic.md);
  concrete overloads in [JSON writer](../src/lib/json/writer.nim).
- NIM-003: [report and passing alternative](nimony-reports-2026-10-27/nullable-var-call.md);
  [callback consumer](../tests/support/block_download_transport.nim). The October 28 archive passes the original probe, control and affected native download fixture.
  The guarded fixture annotations are removed and a focused native regression is retained; other explicit
  pointer types may remain where they clarify an API boundary.
- NIM-004: [standalone draft](nimony-reports-2026-10-28/qualified-declared.md).
  The PVM comparison work reports the unqualified guard in
  [Ragnarök #1749](https://github.com/jacogr/ragnarok/pull/1749), head
  `95916dff4a942f6d3f10658c1d7b6cfb4e6e8a93` (open when checked).
  The standalone unqualified control compiles; equivalence of unqualified name resolution is
  context-specific, so keep the guard and its qualified value reference scoped to that consumer.
  Local raw receipts are under ignored `build/ci/qualified-declared/`; the portable evidence is
  preserved in the tracked draft. The October 28 archive is retested; Linux runtime and regression bisect remain
  unchecked. No runtime/library/pin patch is involved.

## Retained ownership rejection regressions

The [October 21 qualification](nimony-nightly-2026-10-21.md) records old-pin acceptance of
scalar-only prohibited copies and array-to-sequence conversion of the live callback owner.
It also records the sequence-element copy/dup reproductions for
[Nimony #2737](https://github.com/nim-lang/nimony/issues/2737) and
[fix d53097d392](https://github.com/nim-lang/nimony/commit/d53097d39240a33c8c63db6423b62a1c27b8adc8).
The later archive qualification in that same record verifies both sequence rejections and retains
a successful explicit-move unit control. The focused Guards preserve all four mechanisms:
`nimony_scalar_copy`, `nimony_sequence_copy`, `nimony_sequence_copy_dup`, and
`application_download_stream_array_copy`. Their exact unavailable-hook diagnostics require actual
lowering. These are recorded fixed regressions, not newly discovered outstanding compiler bugs.
See the [Guards selection audit](compiler-guards-review-2026-10-30.md) for retained consumer hazards
and the separation from routine language-rule checks. Historical last-tested receipts above are
unchanged; the cleanup's current-pin native results are reported separately.
