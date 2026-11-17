# Draft: module block defer reaches shoggoth unlowered

Status: draft, awaiting current upstream retest. No issue submitted and no compiler patch applied.
Found while adding scoped socket cleanup to the telemetry Writer tests; those tests now use
ordinary fixture routines with routine-scoped cleanup.

Tested November 17, 2026 on macOS ARM64 with the official Nimony 0.6.3 archive for
`8102b8e3c46bde87b733ecd82e2249cb562e3a8f`, C backend, ARC and Clang, checks enabled.
The archive's tools were used unchanged. Current upstream master observed during duplicate
search was `3693daa2be7cfceada99e06fb54f7dd0d35d08a4`; it was **not tested**.

## Reproduce

The [standalone source](module-block-defer.nim) imports only `std/syncio`:

```nim
import std/syncio
block:
  defer: echo "done"
```

```sh
"$NIMONY" c --mm:arc --cc:clang -d:release --nimcache:build/defer-fresh \
  spec/nimony-reports-2026-11-17/module-block-defer.nim
```

Five independent empty cache directories produced exit 1 and the same `shoggoth` diagnostic.
Verbatim diagnostic prefix from the reduced local trial:

```text
[Error] BUG: not eliminated: (defer@2,3,build/network-followups/defer-probe/short/short.nim
 (stmts@7
```

The enclosing `nifmake` reports the failed `shoggoth c` command. Full local trial receipts live
under `build/network-followups/defer-probe/`; they are diagnostic evidence, not dependencies.
Adding `{.feature: "v2".}` still produces the same backend error.

## Expected result and control

The pinned language guide describes block-scoped cleanup. A direct module-level `defer`
already receives the normal diagnostic `defer statement not supported at top level`.
If a module block is likewise unsupported, it should receive a normal diagnostic rather than
reaching the C emitter with an unlowered node. This report does not require accepting that syntax.

Moving the same cleanup into `proc main()` and calling it compiles, exits 0 and prints `done`.
Removing `block` instead yields the normal top-level refusal. The three-line source above
is the remaining minimal trigger; no socket, passive task, ownership hook or project import is needed.

Open/closed upstream searches for `"not eliminated" defer` found no matching report.
A broader module/block/defer search found [PR #3043](https://github.com/nim-lang/nimony/pull/3043),
which is open and describes other defer-scope repairs; coverage of this trigger is unverified.
Retest the unchanged reproducer and control on current upstream before maintainer submission.
