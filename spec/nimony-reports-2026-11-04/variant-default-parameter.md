# Omitted variant default argument is rejected although explicit default compiles

Submitted by the maintainer as [Nimony #2928](https://github.com/nim-lang/nimony/issues/2928)
on November 7, 2026. Reproduction and controls refreshed on the same date.

## Environment

Nimony 0.6.3, official November 7 nightly commit
`ee5497661fac399ff471d7aff472803e36a1e0f0`, macOS ARM64
(`Darwin 27.0.0 arm64 arm`), backend `nimony c`.
The tested official archive's commit also matches upstream master when checked;
a separate source-built compiler and Linux execution were not checked.

## Reproduction

In an empty directory, create `repro.nim`:

```nim
type Value = object
  case present: bool
  of true: payload: int
  else: discard
proc take(value = default(Value)) = discard
take()
```

Run:

```sh
nimony c --mm:arc --cc:clang --boundchecks:on --opt:speed \
  --stdcache:stdlib-cache --nimcache:cache --out:repro repro.nim
```

## Actual

All five fresh independent empty-directory runs exit with code 1. Diagnostic excerpt:

```text
repro.nim(5, 26) Error: a case selecting discriminator 'present' with value 'false' appears in the object construction, but the field(s) 'payload' are in conflict with this value.
```

## Expected

The omitted argument should use `default(Value)`, selecting `present = false` without an active
payload, just as an explicit argument does. The tested stdlib defines `default(bool)` as `false`.
No root cause is asserted.

## Passing explicit-argument control

In a separate empty directory, compile this complete file with the same options and fresh caches:

```nim
type Value = object
  case present: bool
  of true: payload: int
  else: discard
proc take(value: Value) = discard
take(default(Value))
```

Compilation and execution both exit with code 0.

## Passing factory alternative

This complete file also compiles and executes with code 0 under the same options:

```nim
type Value = object
  case present: bool
  of true: payload: int
  else: discard
func empty(): Value = default(Value)
proc take(value = empty()) = discard
take()
```

## Tracking and historical evidence

The application keeps the chain context explicit in the full capture overload; its computation-only
operation obtains an empty view from the existing owning factory. Retain that supported alternative.

The October 28 archive `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` also failed five independent
clean runs on November 4. The six non-comment lines were deletion-tested then: removing any one
changes/removes the original failure diagnostic. Local-default, explicit-argument and factory
controls passed. Original receipts remain under ignored
`build/compiler-issues/work-recovery-default-view/`; November 7 upgrade receipts are under
`build/upstream-watch/nimony/2026-11-07/`. Fresh submission commands, sources, diagnostics and
controls are retained under `build/compiler-issues/variant-default-submission-2026-11-07/`.

November 7 tracker searches for variant/default issues and PRs found no exact duplicate in the
returned results. Earlier triage distinguished
[#2234](https://github.com/nim-lang/nimony/issues/2234), a nested-case compiler assertion, and
[#2218](https://github.com/nim-lang/nimony/pull/2218), union construction changes.
No compiler modifications were used, and no upstream issue was filed by the agent.

## November 14 retest

The unchanged omitted-argument, explicit-default and factory sources now compile and execute
with exit code 0 on official nightly `8102b8e3c46bde87b733ecd82e2249cb562e3a8f`, macOS ARM64.
The previous compiler restriction no longer requires an API workaround; the application retains
explicit context boundaries and owning factories where they remain appropriate. See the
[upgrade qualification](../nimony-nightly-2026-11-14.md).
