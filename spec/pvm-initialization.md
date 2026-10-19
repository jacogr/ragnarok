# Standard PVM initialization

Source of truth: Gray Paper **0.8.0**, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm.tex`, “Standard Program
Initialization”, equations `conditions`, `memlayout` and `registers`. The source
hash is pinned in `spec/pins.json`; no dependency or specification pins change.

## Contract

`initializeMachine(input, arguments, entry, gas, limits)` decodes the standard JAM
program envelope and constructs an immutable executable machine. Envelope order is
E3 read-only length, E3 writable length, E2 extra heap-page count, E3 stack length,
read-only bytes, writable bytes, E4 raw-program length and raw-program bytes. All
integers are fixed-width little-endian. The code extent must consume the remaining
input exactly. Arguments are separately borrowed and cannot exceed 2^24 bytes.

The API combines the standard initializer Y with existing program/entry validation
and machine capture. Y alone may return a malformed raw program; this adapter
returns `InvalidProgram` for it rather than claiming that Y rejects its envelope.
It does not implement the argument-invocation wrapper, host functions, return-buffer
extraction or invocation-level panic/gas normalization.

Let P(x) round upward to 4096 bytes and Q(x) round upward to 65536 bytes:

| Region | Start | Mapped size | Access |
| --- | --- | --- | --- |
| Read-only | 65536 | P(read-only length) | R |
| Writable | 131072 + Q(read-only length) | P(writable length) + 4096 × extra pages | RW |
| Stack | 0xfefe0000 − P(stack length) | P(stack length) | RW |
| Arguments | 0xfeff0000 | P(argument length) | R |

Serialized payload occupies each region's initial bytes; remaining mapped bytes are
zero. Stack and extra heap pages are entirely zero. All other pages remain
inaccessible with zero contents, including page-to-zone padding and guard zones.
Zero-length regions map no pages unless extra heap pages were explicitly requested.
The normative five-zone separation inequality is checked in uint64 before capture;
current fixed-width header maxima already keep its sum below the address-space size.

Registers 0, 1 and 7 are respectively 0xffff0000, 0xfefe0000 and 0xfeff0000.
Register 8 holds argument length; all other registers are zero. Entry and gas come
from distinct caller types, and block charging starts false. Program validation
must accept the entry before any memory pages are materialized.

## Limits, failures and ownership

`InitializationLimits` keeps complete-envelope bytes, embedded-program bytes,
logical jump entries and mapped pages separate. `InitializationByteLimit` is a
nominal envelope cap. Page policy includes payload, padding, extra heap, stack and
argument pages, checked as a complete sum before allocation. Program byte/jump
limits use the existing validated decoder. These are local policies, not guest gas
or new consensus restrictions. Arguments retain their independent protocol bound.

Default results are `Uninitialized`; other failures distinguish `InvalidEnvelope`,
`ArgumentsTooLarge`, `LimitExceeded` and `InvalidProgram`. Only success publishes a
machine. Private variants and success-only accessors prevent retagging and failed
payload reads. Rejection never returns a partially initialized machine.

Input arrays must remain stable during the call. The embedded program and mapped
bytes are copied into private acyclic owners; input mutation afterwards cannot alter
them. Capture temporarily holds the page-image vector as well as final owned pages,
so the page ceiling bounds logical pages rather than claiming a single-copy peak
allocation. Initialization is linear in input/program validation and materialized
page bytes. It performs no guest instruction or host side effect.

## Verification and next scope

Native witnesses check every register, all bytes and permissions across page/zone
rounding boundaries, all empty-region combinations, exact page budgets, maximum
arguments, absent guard pages, malformed/truncated/trailing envelopes, invalid code
and entry, logical jump budgets, fixed-width maxima and seeded input mutations.
Initialization feeds both trap and halt execution witnesses. Input mutation and
independent stores prove snapshot retention; repeated lifetimes record ARC release.
Compiler and isolated runtime probes cover private results, nominal limits and
success-only extraction. Fixtures are original; no upstream code or binaries are
copied.

Standard executable initialization is now available and composes with
[halt return-data capture](pvm-output.md). Host transitions, full argument invocation
and JAM-specific invocation wrappers remain future bounded increments; existing
execution specification gates remain unchanged.
