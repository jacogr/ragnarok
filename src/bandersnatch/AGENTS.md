# Bandersnatch implementation instructions

- Use the current Gray Paper's Draft 35 Thin v1 profile, qualified in
  `spec/bandersnatch-thin-qualification.md`: pristine ark-vrf 0.6.1 commit
  `cf1dbbb260ec3e7ea88eac68148f05d5cbd587ac`, suite `Bandersnatch-SHA512-ELL2-v1`.
  Do not select the RFC-padding v2 suite. Preserve the maintained 96/784-byte ABI,
  transcript/nonce separation, canonical/subgroup checks, checked identity policy,
  locked builds, source/SRS hashes and native ring/domain policy. Never use
  `new_without_blinding`, insecure seeded setup or unsafe vector features in production.
- Historical IETF evidence is archived in `spec/bandersnatch-release-reference.md`;
  historical published tickets are not current Thin parity. Source discrepancies and
  current consumer evidence belong in `spec/bandersnatch.md`. Passing vectors is not an audit.
