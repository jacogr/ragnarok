# Linux x86-64 JIT foundation

Scope: independently lower bounded pure register spans from the existing checked handler stream.
The pinned Gray Paper and established `pvm-registers`, `pvm-execution` and `pvm-handler-stream`
contracts remain authoritative. No dependency, compiler, guest-ISA or protocol pin changes.

This first increment is opt-in through `pvmX86Jit`. Ordinary builds retain the existing ARM64
native backend and interpreted fallback on x86. The target is Linux x86-64 SysV only, using
baseline integer instructions without BMI/AVX or other optional CPU extensions. Unsupported
platforms, unavailable executable storage and unsupported operations use checked execution.

The compiler admits four to sixty-four non-exiting pure operations within one already reserved
source block. Headers, branches, memory, host calls, faults and all partial attempt prefixes
remain canonical interpreter paths. The leaf borrows one register array in RDI; caller-saved
RAX/RCX/RDX/R8 hold temporary values. Every original source is loaded before its destination is
stored, including aliases, signed low-word results, comparison flags, variable shift counts and
mixed-signedness upper multiplication. No invocation pointer is embedded in executable code.

The first conservative emitter loads/stores the register array per source instruction; resident
register allocation, compiled branches, memory operations and connected blocks are future work.
This is a correctness foundation and establishes no performance advantage.

An exclusive exact-source stream owns the code cache. Separate writable/executable aliases have
an unchanged one-MiB physical ceiling; individual leaves are bounded by4096bytes, publications
by1024entries and source coordinates by262144nodes. Publication is append-only and16-byte
aligned. Explicit move/copy lowering controls protect frames and streams; fresh invocations and
host memory replacement retain code-only capabilities with original fallback handlers.

`make check-pvm-x86-jit` is CI-only. The manual `jit-x86` suite uses the existing PVM Comparison
job on native Linux x86-64, preserving incomplete/failure receipts. It requires positive native
arithmetic execution, complete source-prefix agreement, warm-cache reuse, explicit executable
refusal, the existing opcode/memory/host/source-state suites, public policy tests, intended
ownership rejection and OS publication/capacity/retirement controls. All assertions, bounds,
release/ARC and Clang ThinLTO settings remain enabled. Initial exact-head Linux x86-64 qualification passed at
`bc789e550b7637d7ab7bbdf641490feef26bd526` in
[run40663403634](https://github.com/jacogr/ragnarok/actions/runs/40663403634).
Thirteen gates pass, including2,120scalar and2,984source-prefix cases in each native/refused
profile and the existing56,800source-state boundary cases per profile. Independent downloaded
receipt verification matches472source/compiler identities and every raw build/run log;
compiler SHA256:`c31a8e022a831546fff4f918b2fcead217bcc159ec1b02c61b8dcbc70ffe2b19`.
Report SHA256:`b8da02c041e72509a132607a7f3f951ac83001ddd79774e3b98af205ba41d91a`.
Default-source Compile/Smoke also passes. This correctness result is not a speed claim.


## First application comparison

The same manual suite now follows native qualification with `make bench-pvm-x86-applications`,
a CI-only entry into the maintained matched-image application harness. It compares current public
forced interpretation and opt-in JIT in identical binaries, an exact master/parent source,
retained-frame core and pinned PolkaVM interpreted, in both process orders. Pinky, short/long
sieve, minimal, memory fill and DOOM initialization/gameplay retain complete-state/source and
ordered host-event checks. Constructor, cold, reused and reference restoration/teardown costs
remain separate. Fresh private caches and equal-image/positive/refusal controls precede timing.

The shared output protocol retains historical `ARM_OWNER`/`ARM_JIT` record tags for parser
compatibility. Its explicit architecture and backend policy/counter receipts identify actual
x86 generation; those legacy tags make no ARM execution claim. The wrapper's exact-source
baseline is resolved before building; a baseline predating x86 generation preserves its real
checked fallback instead of pretending to have native x86 code. Application timings are pending.
