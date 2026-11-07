# Optimized code ignores mutation through a non-inlined var-parameter call

Submitted by the maintainer as [Nimony #2930](https://github.com/nim-lang/nimony/issues/2930)
on November 7, 2026.

Official Nimony 0.6.3 November 7 nightly, commit
`ee5497661fac399ff471d7aff472803e36a1e0f0` (also current upstream master when checked).
macOS ARM64, `Darwin 27.0.0 arm64 arm`, backend `nimony c`.

## Reproduction

In an empty directory, create `repro.nim`:

```nim
import std/assertions
proc bump(value: var int) {.noinline.} = inc value
proc main() =
  var value = 1
  bump(value)
  assert value == 2
main()
```

Compile and run:

```sh
nimony c --mm:arc --cc:clang -d:release --boundchecks:on --opt:speed \
  --stdcache:"$PWD/stdlib-cache" --nimcache:"$PWD/cache" \
  --out:"$PWD/repro" "$PWD/repro.nim"
./repro
```

## Actual

Compilation succeeds, but the executable exits with code 1:

The output line is `[Assertion Failure] ` (including the trailing space), followed by a newline.

This reproduces in five independent directories with fresh project and stdlib caches.

The generated C retains the call but replaces the following variable read with its initial literal:

```c
NI64 valueX60Qh_4 = IL64(1);
bump_0_repn6ksyd1((&valueX60Qh_4));
if ((!(IL64(1) == IL64(2)))){
```

## Expected

The var parameter aliases the caller's integer. After one increment, `value` is 2 and the
assertion should pass. The generated code should preserve that post-call read.

## Controls

The same complete source compiled with the previously qualified official October 28 compiler,
commit `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, using the same flags except the newer
stdlib-cache option, executes successfully. The November 7 compiler with `--opt:none` also
executes successfully, with all other flags unchanged.

The original project-bound nullable-pointer positive control also fails with the November 7
compiler in checked and ThinLTO profiles and passes both profiles with the October 28 compiler.
Its generated C compares literal `1 == 3` after the call that mutates the addressed integer twice.
The standalone source above does not depend on that project's imports or configuration.

No compiler patches, disabled bounds checks or changed test expectations were used. The
standalone source has not been tested on Linux; the original project-bound failure was observed
in Linux CI too. A separate source-built upstream compiler and a regression bisect were not checked.
No specific compiler pass or originating change is asserted as the root cause.

Searches of open/closed issues and PRs for noinline, stale values, var mutation and copy propagation
found no exact trigger match in returned results. The maintainer submitted the issue linked above; the agent did not post upstream.
