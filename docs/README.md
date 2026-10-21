# Documentation

[Project overview](../README.md) · [Source guide](../src/README.md)

This directory holds development guides, architecture and implementation coverage. Precise
feature contracts, pinned source identities and unresolved protocol interpretations live in
[`spec/`](../spec/README.md).

## Start here

| Guide | What it covers |
| --- | --- |
| [Development](development.md) | Supported hosts, setup, Make targets and local workflows |
| [Disk storage](disk-storage.md) | Backend flags, local restart, imports, durability and bounds |
| [Checkpoint imports](checkpoint-import.md) | Explicit trusted full-state startup inputs and operation |
| [Testing](testing.md) | Verification groups, evidence and requesting CI |
| [GitHub automation](../.github/WORKFLOWS.md) | Workflow jobs, CI labels and retained evidence |
| [Design](design.md) | Module boundaries and links to the pages in [`design/`](design/) |
| [Implementation scope](design/scope.md) | Implemented foundations and remaining client work |
| [Dependencies](dependencies.md) | Pinned upstream sources, provisioning and update policy |
| [Agent workflow](agent-workflow.md) | Focused execution, Git and PR conventions |

## Feature and compiler guides

[Codecs](codec.md), [cryptography](crypto.md) and [networking](networking.md) describe the
corresponding implementation and verification. [M1 progress](m1.md) and
[codec coverage](codec-coverage.md) distinguish codec framing from complete state serialization.

The [Nimony trial](nimony-trial.md) records compiler migration evidence and limitations;
[compatibility notes](nimony-compatibility.md) collect exercised API differences, and
[performance measurements](nimony-performance.md) preserve the bounded comparison.

[`testing/`](testing/) contains [test registration](testing/adding-tests.md),
[harness infrastructure](testing/infrastructure.md) and
[migration history](testing/migration-history.md).
