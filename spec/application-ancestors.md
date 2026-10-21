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
and fresh repeated ARC evidence. Integrate explicit download-only paths, then
exercise real report admission and command startup before outgoing transport.
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
