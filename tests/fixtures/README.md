# Native unit fixtures

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
