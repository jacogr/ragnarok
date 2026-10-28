# Compiler issue register

Follow the [tracking process](../docs/compiler-issues.md). This register starts with the four
recently investigated behaviors; older observations remain in the
[compatibility reference](../docs/nimony-compatibility.md) and should receive an entry when reviewed.
IDs are stable. Status below is distinct from the last compiler actually tested.

| ID | Trigger and impact | Status / next action | Last tested |
| --- | --- | --- | --- |
| NIM-001 | Sequence slicing rejected; fixture copies required. | Locally verified fixed. [#2782](https://github.com/nim-lang/nimony/issues/2782), [fix #2789](https://github.com/nim-lang/nimony/pull/2789). Owned slice adapters removed in [Ragnarök #1723](https://github.com/jacogr/ragnarok/pull/1723); retain useful borrowed views. | October 27, 2026; `358b9bce4`, macOS ARM64. |
| NIM-002 | `$value` in a `SomeInteger` generic rejected; JSON writer uses concrete overloads. | [#2808 closed as not a bug](https://github.com/nim-lang/nimony/issues/2808#issuecomment-6448849445). A type constraint does not guarantee a dollar operator. Retain supported concrete overloads; no pending compiler fix. | October 27, 2026; `358b9bce4`, macOS ARM64. |
| NIM-003 | Second mutable pointee call loses nil proof; callback needs explicitly typed non-null pointer. | [#2809](https://github.com/nim-lang/nimony/issues/2809) closed upstream; [fix #2811](https://github.com/nim-lang/nimony/pull/2811) merged as `60e63d61dc1cb105ea96fa04c8e0dba7faf1457b`. Await archive containing fix; retest before cleanup. | October 27, 2026; `358b9bce4`, macOS ARM64. |
| NIM-004 | Qualified `declared(...)` crashes compiler; PVM comparison guard uses unqualified lookup. | Draft; retest new nightly and refresh duplicate review before submission. No upstream issue filed. | October 28, 2026; `358b9bce4`, macOS ARM64. |

## Reproducers, workarounds and evidence

All four last-tested entries use official Nimony 0.6.3 commit
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee`.

- NIM-001: [original report](nimony-reports-2026-10-23/sequence-slice.md),
  [upgrade qualification](nimony-nightly-2026-10-26.md), and permanent
  [sequence-slice suite](../tests/unit/codec/test_nimony_sequence_slices.nim).
- NIM-002: [report and upstream resolution](nimony-reports-2026-10-27/integer-generic.md);
  concrete overloads in [JSON writer](../src/lib/json_writer.nim).
- NIM-003: [report and passing alternative](nimony-reports-2026-10-27/nullable-var-call.md);
  [callback consumer](../tests/support/block_download_transport.nim). Keep explicit non-null bindings
  until the new archive passes the standalone and affected callback tests. The upstream merge
  does not establish that our current pin is fixed.
- NIM-004: [standalone draft](nimony-reports-2026-10-28/qualified-declared.md).
  The PVM comparison work reports the unqualified guard in
  [Ragnarök #1749](https://github.com/jacogr/ragnarok/pull/1749), head
  `95916dff4a942f6d3f10658c1d7b6cfb4e6e8a93` (open when checked).
  The standalone unqualified control compiles; equivalence of unqualified name resolution is
  context-specific, so keep the guard and its qualified value reference scoped to that consumer.
  Local raw receipts are under ignored `build/ci/qualified-declared/`; the portable evidence is
  preserved in the tracked draft. The latest nightly, Linux runtime and regression bisect are
  not yet checked. No runtime/library/pin patch is involved.
