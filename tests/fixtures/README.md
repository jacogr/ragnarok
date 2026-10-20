# Native unit fixtures

Static native inputs have a neighboring `*.fixture.json` descriptor declaring their environment
variable, target and exact member SHA-256 pins. Suite requirements reference the descriptor ID
through `"fixtures": ["state_report"]`; the runner discovers contracts without a central fixture
or consumer registry. See [test registration](../../docs/testing/adding-tests.md). Member paths
are relative to the descriptor directory, and every listed file is required and checked before use.

`guarantee-report.bin` is the exact 393-byte report previously generated for each guarantee
selftest by `guarantees_oracle.record(0)['report']`. It is encoded by the independent Python
report oracle, using its minimal report derived from the pinned full-profile published fixture.
It has core zero, no prerequisites and a single successful empty-output digest. It is test data,
not a report authenticated by a validator or produced by the implementation under test.

SHA-256: `8f13efdbca5aa7c5158c7cc62c71e5a9ed6ab2e22032d46946f4a304c55688fc`.

The native launcher checks this identity before execution and supplies the absolute path through
`RAGNAROK_GUARANTEE_FIXTURE`. The guarantee test rejects missing/unreadable input; it has no
fallback. A harness test compares the committed bytes with the original independent oracle.
Updating this fixture requires an explained source/specification change and a corresponding
hash/reference review; never regenerate it from the production encoder to make tests pass.


## Tiny block composition inputs

`block-tiny/` contains the same six child inputs previously prepared by the cumulative runner:
five from `block_oracle.published('tiny', 'E', canonical=True)` plus the header from
`published('tiny', 'B', canonical=True)[0]`. These are the independent oracle's existing
policy-valid counterparts of pinned published fixtures. It sorts dispute verdict targets and
sets the out-of-domain tiny guarantee core to zero; upstream JSON/binary files remain unchanged.
The original opaque header is retained, with no claim of recomputed commitments or signatures.
Original published inputs and their documented rejections remain in the independent corpus.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `tickets.bin` | 2356 | `69d59e7ec8933d92a202d7a439b05f5f69ae3c0a4bf00bc08bf68dcaa256bde3` |
| `preimages.bin` | 64 | `874f3bed57dab9927170d5344b8489ad0662d5ee0c22a58ca25a362415cc8c90` |
| `guarantees.bin` | 621 | `4e5b4574b56bf0f0f974db8f4486fd14219f9d5f5a95c4743100bf5ed75ec690` |
| `assurances.bin` | 199 | `5438827a87cfd20f1eaccd8d20858a69af88df2459172a37e6aa9d9639c506e3` |
| `disputes.bin` | 1132 | `83e526e84c919fb1efb020bee185c9f63c3692e004d13820546473ed59e31b21` |
| `header.bin` | 778 | `c4f4658a9c04bca5d249c7ca5f14845bd012311213f6bb24076dcdddbb268fa2` |

The launcher checks every member before setting `RAGNAROK_BLOCK_FIXTURES` to the absolute
directory. A missing/changed later child cannot be hidden by valid siblings. Harness checks
compare all six snapshots to the original oracle and ensure each member is included in cumulative
source hashes. The native test requires explicit fixture configuration and rejects unavailable
input; there is no fallback or production-encoder fixture generation.


## State report input

`state-report.bin` is exactly `state_availability_oracle.record(0)['report']`, the independent
report previously generated for availability/work-queue tests. Its SHA-256 is
`3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371`.
The launcher verifies these bytes before setting `RAGNAROK_STATE_REPORT`; harness coverage
compares them with the original oracle. Production codec output is never used to refresh it.


## Composition chapters

`composition-chapters.txt` stores the exact sixteen hex lines returned by
`state_composition_oracle.chapters()`, previously prepared by the cumulative launcher. SHA-256:
`3d45577099002c493cb7dc6fa4b3ee2f7ebfa389952a0c4cae3c7c382db7265b`.
The native launcher checks this identity and supplies `RAGNAROK_COMPOSITION_FIXTURE`.
A harness check compares every line with the independent oracle; production encoding is not used.
