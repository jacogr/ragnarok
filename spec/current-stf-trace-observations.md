# Recorded whole-map STF observations

This increment adds a native comparison boundary and profile-bound recorded-observation
orchestration. It does not execute an external implementation. The authority remains
Gray Paper commit1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d, the unchanged gp-next
vectors commit23061ae1f9b51171c01387e7dde0f15794c98e24 and ark-vrf0.6.0 at
dfb696dfb92425009af80dbbb403e647f6c9e3e4. Historical fixtures remain unchanged.

## Native comparison

The existing offline command accepts one additional control:

    build/ragnarok check-traces POLICY GENESIS TRACE... --with-state --chain CHAIN \
      --trace-observations OBSERVATION_DIRECTORY

Observation files are named step-0000.bin, step-0001.bin and so on, one per expected
trace. Each is exactly the published RawState representation, with bounded regular
file reads, complete EOF, independently recomputed root and the supplied state policy.
No observation replaces the expected prior state, signed block or golden posterior.

prepareTraceObservation first validates the observation owner, then uses ordinary
authenticated prepareTraceImport against the actual selected chain and complete
golden maps. Only after this succeeds does it compare every observed key/value,
including present-empty values, with the genuine prepared successor. A matching
commitment alone is insufficient. InvalidObservation or ObservationMismatch never
exposes a prepared update. Only complete three-way agreement permits the existing
guarded continuation on the private offline chain. Input files remain read-only.

ObservationFailure reports missing/nonregular/oversize/root/trailer input failures.
ImportFailure retains ordinary golden/candidate failures or ObservationMismatch.
A later failure reports the checked private prefix without a successful final root.
The new path is bounded, command-scoped and cleared with failed option parsing.

## Export and recorded verification

The supported Python tool owns metadata and process supervision, with all production
binary framing, authenticated execution and complete-map comparison in Nim:

    python3 tools/state_trace_conformance.py export --output FRESH_BUNDLE --policy POLICY
    python3 tools/state_trace_conformance.py verify --bundle FRESH_BUNDLE \
      --observations RECORDED_DIRECTORY --profile TARGET_PROFILE --checker build/ragnarok

Export writes the40 independently authored configured-chain/Genesis/trace bundles
exclusively, preserving255 original signed transitions and complete golden maps.
The manifest binds GP/vector/VRF pins, source fixture SHA-256, every payload SHA-256,
each complete122-byte parameter tuple, checked counts and expected final commitments.
These tuples are custom test profiles, not an implicit standard Tiny profile.

TARGET_PROFILE has exactly these JSON fields:

    {
      "format": "ragnarok-stf-observation-profile-v1",
      "client": {"name": "implementation", "version": "version", "artifact_sha256": null},
      "graypaper_commit": null,
      "graypaper_version": "0.8.0",
      "parameter_profiles": []
    }

An unknown exact GP commit or missing complete parameter declarations yields
profile-unverified, exit4. A different declared version/commit or unsupported
selected full tuple yields profile-mismatch, exit4. The tool refuses before reading
observations or launching the checker. Semver or a Tiny label cannot establish this
project's exact unreleased pin/profile. A declaration is not an independent proof
of provenance; reports retain that distinction.

With matching declarations, verification checks canonical contained relative paths,
closed bounded duplicate-free JSON, complete file identities and aggregate limits.
It also binds the configured-chain tuple to the declared case tuple. The native
checker reads RECORDED_DIRECTORY/case-NNNN/step-NNNN.bin. Structured arguments,
bounded stdout/stderr, per-case timeouts and process-group retirement constrain
execution. Reports say external_execution=false, retain source declarations and the
checker hash, and distinguish observations-match from observations-rejected.
They never claim the tool ran or authenticated an external engine.

Metadata is capped at1MiB per manifest and64KiB per profile, payloads at16MiB/file
and64MiB total. Bundles allow1..256 cases,1..256 steps/case and4096 total steps.
The public native command retains its existing per-invocation limits. Select cases
with repeated --case arguments; --timeout is positive and at most120 seconds.

## Evidence and remaining boundary

The new independently frozen corpus contains40 success jobs/255 complete maps and
seven refusals: missing observation, incorrect root, trailing bytes, a valid
recommitted different map, a later wrong map, a wrong golden post-state despite a
correct observation, and an altered later seal despite correct observations.
All observations here are mathematical test doubles calculated before native
execution. They are not output from another client.

Completion checks cover the new and ordinary command corpora, native default-owner
and scoped-path boundaries, private fields, bounded metadata/process failures,
profile gates, payload tampering, actual production command execution, formatting
idempotence and verification inventory. Reproduction uses make unit
SUITE=application_trace_observations and the registered unit corpus; Python discovery
owns independent reference/tool orchestration tests.

External execution remains unverified. The investigated official [Polkajam0.1.29 nightly](https://github.com/paritytech/polkajam-releases/releases/tag/nightly-2026-10-24)
reports GP0.8.0, but that alone supplies neither the exact GP commit nor our
custom parameter tuples. Its REPL failed before importing a block because the release
bootstrap command expected an unavailable Cargo workspace. Older available clients
advertised GP0.7.x. These are availability/profile limitations, not observed STF
algorithm mismatches. A compatible target or appropriately identified recorded
RawState artifacts are required for a positive external-client differential result.
No historical fixture or native result was changed to manufacture agreement.
