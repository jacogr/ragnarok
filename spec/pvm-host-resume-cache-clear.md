# Successful host-resume jump-cache reset

The successful resident-memory path in `resumeFlatHostMemory` no longer clears
the private cache of 256 jump offsets. The next `runFlat` invocation clears the
same cache before any resumed dispatch or dynamic-target lookup. Removing the
duplicate 2048-byte clear preserves invocation-local cache ownership and leaves
the execution-entry reset in place.

Invalid host responses still return before changing the stopped invocation.
Mapping or permission replacement still rebuilds capabilities through the existing
fallback. Host-supplied memory, gas and registers retain their existing validation;
the host supplies neither successor PC nor paid-block authority.

This change is independent of adjacent-instruction fusion. Its scope is only the
successful host-memory resume reset. The existing host-resume and resource-transfer
boundary suites cover paid continuations, real native prefix execution, changed
host state, exact attempt budgets and dynamic targets. Focused validation uses the
pinned checked ARC/Clang/ThinLTO profile with the actual local native backend and
complete expected-output comparison; evidence is recorded with the PR.

Earlier #1979 timings measured a bundle that also changed fusion and are not
evidence of a standalone speedup for this removal. The separately retained
sieve1000 diagnostic does not exercise host resume and cannot establish a
clear-only latency effect. This change makes no standalone performance claim.

On the local Darwin ARM64 host, both focused semantic checks and both native
suites passed with `pvmArm64Jit`, checked ARC/Clang/ThinLTO and complete golden
comparison (five host-resume output lines and one resource-boundary line).
This is local component qualification; no clear-only Linux CI or timing run
is claimed. Only the verified pinned compiler/formatter installation was reused;
the component executables were built and run freshly against this source.
