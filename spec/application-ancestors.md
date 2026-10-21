# Explicit ancestor inputs for application downloads

## Scope and authority

Use the existing report lookup-anchor contract under GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. This application input boundary changes
no protocol rules, domains, pins, trie/storage interfaces or checkpoint trust.

## Bounded capture

`loadAncestorInputs` captures explicit regular files in caller order. Check the
whole header count/native descriptor extent before any file access. Each read
requires EOF within both the per-header profile and remaining aggregate byte
ceiling; the shared file reader rejects nonregular files, embedded NUL paths,
read/close errors and growth beyond its ceiling. Decode complete sealed headers
under the configured profile and refuse trailing bytes. Zero files need no IO.

Only complete success exposes a copied sequence of immutable owned headers.
Default/refused results contain no prefix; selected file/header failures preserve
their original typed causes. Later caller/path mutation cannot replace a captured
header. Capture is structural input preparation, never proof of ancestry or an
independent trusted checkpoint. The report validator must still hash/redecode
headers and check newest-first linkage to the selected parent, strict slots and
lookup child/state-root binding. A missing header cannot be fabricated from C(3).

## Completion and next work

Test exact/short count, per-header and aggregate bytes, late file/decoder failure,
truncated/suffixed headers, nonregular/invalid paths, full-width ceilings,
caller mutation and detached ownership. Retain result extraction/privacy guards
and fresh repeated ARC evidence. Explicit download-only paths, real report
admission and command startup before outgoing transport are implemented below.
M1 framing remains complete; full state serialization and JAM/STF parity remain open.

## Local capture verification

The selected native `application_ancestor_inputs` suite passes on pinned
Nimony/ARC with exact/short/full-width quotas, late failures, copied observations,
path mutation, complete sealed decoding and nonregular/NUL-path refusal. Its
1,000 repeated success/late-refusal cycles retain 16,192 occupied bytes before
and after. All four strict runtime extraction guards, genuine positive controls,
four compiler privacy rejections and source-owned inventory pass. Logs are under
`build/ancestor-inputs-*`; these local checks are separate from Linux CI.

## Download controls and lifecycle

`--download-ancestor FILE` is repeatable, ordered newest-first and valid only for
state-enabled `download`. Parsing is atomic; reject empty/missing/option-valued
paths, duplicate paths, embedded NULs and more than 64 files. The fixed path cap
does not widen the explicit v1 policy: `input.ancestors` and `input.ancestorBytes`
bound retained input, while `candidate.reporting.reports.ancestors` independently
bounds validation. Its `headers` count includes the selected parent. The loader
uses the smaller input/report byte ceiling and the report's per-header profile;
report validation additionally charges the actual parent.

The command validates path counts and captures all files before starting Services,
opening listeners, creating/opening a disk database or dialing peers. Structural
failure reports InvalidAncestors; count-policy failure reports InvalidPolicy.
Success passes the exact captured headers to raw-input preflight and the existing
native download/preparation owner. The command keeps external aliases untouched
through execution/durable publication, and dispatcher teardown joins before those
aliases retire. An ancestry failure during report validation remains an ordinary
failed attempt; structural capture alone never promises an adopted child.

The new option suite and existing app, disk-storage and recovery-option suites
pass. The real pinned-TLS startup suite passes its existing scenarios plus missing
ancestor/count-policy refusals before fresh disk creation; 1,000 policy cycles
retain 264,448 occupied bytes before/after. The parser privacy rejection, semantic
checks and source-owned inventory pass. Logs use `build/ancestor-{options,app-options,
disk-options,recovery-options,startup}*`.

## Genuine lookup, TLS and durable restart

The startup suite retains its original six scenarios and adds five cases using a
signed child with a genuine newly guaranteed report and two actual guest
executions. Missing ancestry preserves ReportFailure/AnchorFailure/
MissingLookupAnchor; a structurally valid seal mutation preserves BrokenAncestry.
Correct independently encoded headers allow actual pinned-TLS acquisition and
adoption. Omitting/mutating the header exhausts the real attempt; a suffixed file
returns InvalidAncestors and the responder observes zero requests.

The disk scenario returns Adopted only after durable publication. A fresh normal
restart restores both child and parent, leaves finality unset, and matches the
block hash, complete posterior root, entry count and every serialized entry of an
independently prepared/composed in-memory successor. No external trust file or
ancestry input is required for that local restart. All responder children are
reaped; command shutdown joins execution/IO before captured aliases retire.

Final strengthened startup checks pass locally. Its separate 1,000-cycle policy
ownership observation retains 787,648 occupied bytes before/after; this is not a
claim of 1,000 network or disk operations. The affected application-candidate suite
passes with 203,520 occupied bytes unchanged over its 1,000 execution/refusal
cycles. Evidence is `build/ancestor-lookup-final-*` and
`build/ancestor-candidate-regression.log`. Existing no-ancestor startup behavior
and optional-fixture defaults remain covered. Linux CI and full JAM parity remain
separate evidence.

## Operator handoff and remaining scope

The [operator guide](../docs/download-ancestors.md) describes ordering, exact file
content, count/byte policy accounting and import/disk operation. Existing trusted
checkpoint/disk download regression passes unchanged. The actual executable
build and help expose the repeatable control. No trie/storage/PVM implementation
or interface changed; db #1 retains ownership of storage internals. [Explicit remote acquisition](application-remote-ancestors.md) and
[successive child downloads](application-download-progress.md) have their own bounded
contracts. On-demand ancestry discovery, peer discovery/non-loopback endpoints,
fork choice and full/light database selection remain separate work.

Final local documentation-link checks, actual executable help, full pinned
Nim/Rust formatting, verification inventory and Git whitespace checks pass.
Only application inputs/options/command and their tests/docs changed. Remote CI
has not been requested; automatic peer discovery and complete JAM parity are not
claimed by these checks.
