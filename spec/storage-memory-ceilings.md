# Child-local storage memory ceilings

## Scope and completion contract

This tranche continues the resource measurements merged at
`206ecf0c1e4448b920ade7068a0ec37bd8a35226`, starting from current master
`e0c3a4309e6326ac63c9b1ab2ed8e0cce8d31c7e`.
The experiment applies a bounded address-space ceiling to an isolated Linux child, after a
separate positive allocation and over-ceiling refusal probe. The parent, compiler, producer,
other processes, cgroups and host memory controls remain outside that mutation.

Fresh native journal and managed consumers retain their existing exact producer root,
generation, complete-map, retained-view and final allocator-release assertions. Selected files
must be byte-identical after each admitted or refused child and after an unrestricted control.
A nonzero native exit is a refusal observation; it is never a validated complete reopen.
Signals, timeouts and arbitrary assertion failures are not automatically allocation failures
or OOM kills. A following unrestricted control must still validate the complete map.

Fixed budgets range from128 MiB to1 GiB; requests outside the declared bounds fail before
execution. There is no adaptive allocation growth, global cache drop, host pressure worker,
privileged cgroup write, production fault hook or production format change.
On unsupported hosts, explicit unavailable receipts retain ordinary native controls.

## Evidence and limits

Record raw probe/limit receipts, exact native commands, binary/source/toolchain identities,
child RSS/faults, read-only Linux process status, PSI and current cgroup memory context where
available. Availability and unsupported/refused outcomes remain distinct from measured zero.
Inherited cgroup counters may include unrelated work and descendants. They cannot attribute
an OOM kill to this child. Address space includes reservations and differs from resident memory;
an enforced ceiling is not evidence of paging, cache eviction, physical reads or out-of-core
storage. Hardware/filesystem power-loss qualification and complete protocol serialization remain
separate work. Existing M1 evidence retains its original scope; this adds no M1 completion claim.

Completion requires parser/budget/provenance/adversarial tests, real subprocess success/failure/
timeout controls, fresh native controls on this host, strict complete-report revalidation,
checked Make integration, grouped CI artifact preservation and a bounded qualification record.
Linux enforcement is claimed only after an actual Linux probe and native execution, never from
simulated parser fixtures on another host.

References: [Python resource limits](https://docs.python.org/3/library/resource.html),
[Linux PSI](https://docs.kernel.org/accounting/psi.html),
[cgroup v2 memory controller](https://docs.kernel.org/admin-guide/cgroup-v2.html).

## Final local qualification

The complete implementation was frozen and checked at
`933f708a219aae225a9e0bf283dfd9bb6c76a5bc` on merged trunk
`e0c3a4309e6326ac63c9b1ab2ed8e0cce8d31c7e`. The final stack layer adds this
qualification record only; all measured source/build inputs retain identical bytes.

- 148 storage tooling tests and35 CI safeguard tests passed. This includes independent complete
 Linux/Darwin report fixtures, malformed/duplicate/overflow telemetry, probe and command identity,
 foreign root/namespace/counter substitution, real nonzero exits and SIGKILL, descendant group
 timeout cleanup, late export refusal and unchanged parent address-space limits.
- `make check-inventory` and `make format-check` passed. Ruby Psych parsed the workflow YAML;
 no actionlint or exact-head Linux CI verdict is claimed.
- `make bench-storage-memory-ceilings` built the pinned checked ARC/Clang release/LTO native
 workload and passed all eight unrestricted before/after consumers across both backends and
 both declared cardinalities. Every consumer validated the exact producer root/generation,
 complete authored map, retained view after close, final ARC baseline and unchanged selected bytes.
- All three actual host probes reported Darwin unsupported. All twelve capped trajectories
 remain explicit unavailable rows; none executed a constrained native consumer. Synthetic Linux
 fixtures exercise validators and orchestration but do not supply Linux enforcement evidence.
- Setup-free Make reporting and strict matching-report self-comparison passed. CSV retains all
 twenty planned rows, with unavailable resources distinct from numeric zero.

Full local identities, raw commands, logs and receipts live under ignored
`build/storage-db4-final-qualification.json`, `build/storage-db4-final-logs/` and
`build/tests/storage-memory-ceilings/`. The earlier exploratory run is preserved separately in
`build/evidence-storage-db4-first/`. Existing storage evidence, parked directories and branches
remain intact. No production runtime/native library, format, default backend, pin or trust-policy
change was made, and no remote CI label was requested.

This completes the bounded child-local ceiling tooling tranche. Actual Linux capped native
qualification remains pending an admitted Linux run. Controlled resident-memory pressure,
induced paging/out-of-core behavior, page packing and filesystem/device/hardware power-loss
qualification remain separate work. Complete protocol serialization remains separate, with no
new M1 completion claim or promotion of a partial light-state root.
