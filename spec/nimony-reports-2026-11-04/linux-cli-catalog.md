# NIM-007: Linux-target semantic check asserts in the CLI catalog

Status: suspected compiler defect, project-bound witness; not ready for upstream submission.
No issue has been filed and no workaround or compiler change has been applied.

Tested November4,2026 with Nimony0.6.3, pinned commit
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, on macOS ARM64, targeting Linux AMD64.
The actual Linux application semantic check and direct check of unchanged
`src/app/cli/catalog.nim` both fail. An import-only project-bound witness produces the same
assertion. Host native tests pass; Linux-target recovery-core semantic checking passes separately.

From the repository root with the provisioned pinned toolchain:

```sh
. build/toolchain/env.sh
"$NIMONY" check --os:linux --cpu:amd64 --mm:arc --cc:clang -d:release --boundchecks:on --nimcache:build/compiler-issues/linux-cli-catalog/cache build/compiler-issues/linux-cli-catalog/probe.nim
```

The tested probe contains the same relative import as the tracked
[project-bound witness](linux-cli-catalog.nim), adjusted for its scratch directory:

```nim
import ../../../src/app/cli/catalog
```

Observed output, copied from the retained probe log (exit1):

```text
assertions.nim(38)       raiseAssert
Error: unhandled exception: nifcore.nim(1942, 3) `i >= 0 and i < b.len`  [AssertionDefect]
```

Full command/output is retained under ignored `build/compiler-issues/linux-cli-catalog/`;
application and direct catalog logs are under `build/jamnp-implementation/work-recovery-linux-*`.
The crash occurs while semantically compiling the catalog, which has no changes in this increment.
This establishes an existing project trigger, not the language validity of a minimized construct.
A normal diagnostic would be appropriate for unsupported source; an internal assertion requires
investigation. Standalone reduction, five independent empty-directory runs, line minimality,
language-contract inspection, upstream duplicate/devel searches and native Linux qualification
remain pending. No Linux runtime pass is claimed.
