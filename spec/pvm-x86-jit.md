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
release/ARC and Clang ThinLTO settings remain enabled. Exact-head CI evidence is pending.
