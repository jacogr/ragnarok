# Host byte-range memory access

## Scope and source

`readBytes` and `writeBytes` in `src/pvm/machine.nim` provide bounded, owned byte-range
access for host functions. The normative basis is GP 0.8.0 memory readability and
writability sets, and the natural intervals used by General Functions in
`vendor/graypaper/text/pvm_invocations.tex`, notably `fetch` (`Omega_Y`) and its
`Nrange{o}{l}` writable-range check. The pinned Gray Paper commit is
`07f041dabd073f9018b418e9ee72e79dd2185401`.

These are memory primitives, not implementations of `fetch`, its selectors, charging
or invocation-specific result mapping. Concrete host functions remain responsible
for their specified permission/error precedence and for converting memory diagnostics
to panic, OOB or another result. Scalar `load`/`store` semantics are unchanged.

## Range and policy contract

Addresses use `MemoryAddress`; read lengths use the distinct `MemoryLength` and both
operations require `MemoryByteLimit`. A nonempty range must lie entirely within the
32-bit physical address domain. Validation uses subtraction before adding endpoints;
high address bits are never truncated and the top of memory never wraps to page zero.
An empty interval succeeds for any address, including UINT64_MAX, but still requires
a valid memory owner. Empty writes return the immutable source owner.

Checks occur in this order: owner validity, empty interval, physical range, local
copy limit/native index representability, then every affected page's permissions.
`InvalidRange` means a nonempty natural interval leaves physical memory. Local policy
refusal is `LimitExceeded` and can precede an inaccessible-page diagnostic. A concrete
host must not treat such a local refusal as a consensus result.

Reads accept ReadOnly and ReadWrite pages. Writes require ReadWrite pages throughout.
Missing and explicitly inaccessible pages both fail. `MachineError.Fault` carries the
first failing aligned page address in ascending range order; it is a diagnostic here,
not an instruction to emit a guest Fault exit. Low physical pages are permitted when
their actual permissions allow access, matching host set membership rather than the
scalar instruction rule that protects the first 64 KiB.

## Atomicity, ownership and work

The complete range is preflighted before allocating a read buffer or cloning any write
storage. A failed operation exposes no bytes, prefix count or new memory owner and
cannot alter the source. Successful reads return independently owned byte sequences.
Writes borrow input only during the call, clone each touched page once, preserve its
permissions and unmodified bytes, and share all untouched immutable pages. They do not
insert pages or alter the source's page limit. Extracted read bytes and later input
mutation cannot modify retained snapshots; all ownership is acyclic.

The byte limit bounds payload copying and page preflight. Nonempty writes additionally
copy the existing sparse reference vector, whose size is bounded by the memory
owner's page limit. This is not a total allocation-byte or elapsed-time budget.
The implementation allocates no buffer proportional to a rejected untrusted length.

## Verification and remaining scope

Independent native witnesses cover aligned/unaligned multi-page reads and writes,
all bytes inside and outside the changed interval, exact/short limits, late permission
failures, absent/inaccessible/read-only pages, empty ranges, high-bit pointers,
UINT64_MAX lengths, low pages and the last physical byte. Ownership tests mutate
borrowed inputs and extracted bytes and retain independent descendants. A trusted
host callback writes across a page boundary, resumes the guest and returns the bytes
through halt-output capture. Fresh 1,000-cycle ARC evidence is checked by the harness.
Compiler guards enforce nominal length/budget domains; eight isolated runtime probes
reject failed read/write payload extraction.

The next concrete host function can use this range boundary without repeated scalar
stores or partial writes. Host selectors/context, signed host-gas accounting and
complete JAM invocation policy remain open; no new conformance claim is made for them.
