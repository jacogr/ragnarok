# Codec result safety

## Scope and outcome

Completed locally on macOS on 2026-10-14 with the repository's pinned Nim
2.2.12 (ARC) and Odin toolchains. This changes result APIs, not protocol bytes.
The Gray Paper v0.7.1 revision and official test-vector pins remain unchanged.
See [the API migration guide](../docs/codec-results.md) for caller examples.

Nim bounded, composite and digest outcomes now use checked case objects.
Success contains the completed value and metadata; failure contains only its
error discriminator. Existing natural and fixed-width `ok` variants remain.
Odin fallible codec operations now return tagged unions of a named success
struct and a typed error enum. Default results are failures in both languages;
new error-discriminated results use `Uninitialized`.

Encoders follow the same contract: failed writes have no written metadata.
Callers, specifications and AGENTS.md were updated together. Destination
atomicity, allocation-free operation and valid zero/empty successes are
preserved.

## Executed verification

Commands:

```sh
python3 tools/format.py
python3 tools/format.py --check
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_codec.py
git diff --check
```

The shared runner passed all native tests, pinned official vectors, malformed
input and fuzz cases, and cross-language comparisons:

| Family | Shared requests per implementation | Official checks |
| --- | ---: | --- |
| Naturals | 45,215 | 20 prefixes |
| Fixed-width integers | 73,278 | 24 fields |
| Bounded containers | 26,712 | 12 blobs |
| Composites | 25,890 | 4 complete preimages and 8 work outputs |
| Work digests | 14,278 | 8 complete digests |
| Total | 185,373 | |

All 28 negative compilation checks passed, including two new checks rejecting
payload construction on a known failed Nim digest and direct `.value` access
on an Odin result union. Nim inactive-field misuse tests passed in debug and
ordinary release builds. All seven Odin native tests passed, including direct
success/failure selection and default-result checks. Tests also cover valid
zero integers, width-zero consumption, absent optionals, empty sequences and
decoded work-error payloads.

These are local macOS results. Linux verification of this change awaits the
existing GitHub CI workflow running after publication.

## Limits and next round

Nim raises `FieldDefect` on inactive-field access; Odin's `success_of` helper
uses a checked union assertion. Caller builds must retain these checks. This
is not a claim that every caller is statically proven to inspect its result,
or that deliberate unsafe casts or fabricated success values are prevented.

Blob spans still hold coordinates into caller-owned buffers. Original-buffer
identity, lifetime and mutation after validation remain unresolved and are
the next bounded ownership round.
