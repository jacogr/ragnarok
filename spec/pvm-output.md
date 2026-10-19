# PVM halt return-data capture

Source of truth: Gray Paper **0.8.0**, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm.tex`, “Argument Invocation
Definition”, the halt branches of the result function R inside Psi_M. Its source
hash is recorded in `spec/pins.json`; no upstream pin changes. Readability uses the
page-access definition in `text/overview.tex`, not the scalar-instruction low-address
panic rule: a trusted environment can supply a readable low page.

## Scope and API

`captureOutput(outcome, limit)` applies the halt return-buffer rule to a completed
`StepOutcome`. Registers 7 and 8 supply the pointer and length. A Halt with a wholly
readable interval returns exactly those bytes; a Halt with any unreadable byte
returns successful empty output. Both read-only and read-write pages are readable.
Absent pages and retained inaccessible pages are unreadable. A readable prefix or
suffix never escapes if another page in the interval is inaccessible.

This is the return-data component of argument invocation, not the complete Psi_M
wrapper. Non-halt outcomes—including Panic, OutOfGas, Fault, Host and Continued—are
local `NotHalted` failures rather than being converted into empty successful output.
The caller still owns execution/host dispatch and the invocation exit alternative.
Gas-consumption accounting and host-state mutation are not performed by this API.

## Natural ranges and limits

The GP subset test uses a natural interval, not cyclic scalar memory addressing.
The code checks `start < 2^32` and `length <= 2^32 - start` before constructing a
nonempty interval's end. High register bits are not truncated and arithmetic does
not wrap into low memory. The last physical byte is valid when mapped. An empty
interval is readable regardless of its pointer, even UINT64_MAX, and does not
perform a page lookup.

Preflight checks the entire bounded physical interval before allocating output.
There are at most 2^20 physical pages. The immutable memory API returns copied page
images; preflight retains only one image at a time. The copy pass also works one
page at a time and clips its first and last chunks to the requested range.

`OutputByteLimit` is a nominal local copy/allocation ceiling, not a consensus
return-size restriction. It applies only after readability is established. Thus an
unreadable range returns empty even with a zero local limit; a readable nonempty
range beyond the limit returns local `LimitExceeded`, with no partial output.
Physical ranges fit the supported 64-bit host index domain before allocation.

## Results and ownership

`OutputResult` defaults to `Uninitialized`. Invalid replaced machine handles return
`InvalidMachine`; success alone exposes bytes through `value`. The result's status
and byte storage remain private. Extracting bytes returns independent owned sequence
storage, with no mutable page aliases. Copying/mutating extracted bytes cannot alter
the saved output or machine. The capture operation itself changes no register, gas,
PC, charged flag or memory page and retains no execution history.

## Verification and next boundary

Native tests independently calculate each expected output byte across aligned and
unaligned pages, permission changes, exact budgets, absent and inaccessible middle
pages, and the top of the physical address space. They cover high-bit pointers,
UINT64_MAX lengths and empty ranges, plus every non-halt exit and invalid machine
handles. An end-to-end witness initializes a standard program, halts through its
initial return-address register and returns a three-page argument payload. Mutated
caller/extracted buffers remain independent, and repeated complete lifetimes emit
ARC release evidence. Compiler and isolated runtime probes enforce private results,
nominal copy limits and failure payload selection.

Standard initialization, bounded guest execution and halt output capture now compose.
Host transitions, signed host-gas accounting and complete argument/JAM invocation
wrappers remain separate bounded work; existing execution specification gates remain.
