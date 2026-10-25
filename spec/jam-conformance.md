# Pinned JAM conformance tooling

The maintainer selected the latest main revision of
[davxy/jam-conformance](https://github.com/davxy/jam-conformance) on2026-10-25:
acd4b2da310ff25226c4d41b918712578483fd2c. The recorded gitlink and
jam-conformance-pins.json bind that immutable revision, the fuzzer-v1 schema,
protocol documentation, minifuzz self-test and CLI workflow/target management
scripts. Selected upstream file SHA-256 identities are checked by Python discovery.

This is the actively maintained upstream, rather than the older w3f mirror.
The selected workflow supports a prebuilt polkajam-fuzz through
POLKAJAM_FUZZ_BIN; access to its source workspace is not a prerequisite.
The live campaign engine is nevertheless a separate artifact and is not included
in this source pin. Existing example sessions retain their upstream GP0.7.0/
0.7.2 identities. Pinning their tooling does not establish GP0.8 campaign success.

Standard make sources/setup/check-python provisioning initializes the new
submodule through tools/setup_submodules.py. A shallow blob-filtered checkout
materializes root documents, fuzz-proto and scripts. It leaves multi-gigabyte
historical fuzz-reports absent and does not initialize upstream's independent
nested test-vectors repository. This preserves Ragnarök's existing vector pin.
No upstream installer, workflow or target binary executes during source setup.

Setup selects the recorded index gitlink rather than following main, preserves
a warm focused checkout, supports deinitialization/reinitialization and refuses
local source edits before moving any selected source. Local Git regression
fixtures cover these properties without using the network. Exact checkout,
source hashes, configured URL and indexed pin are also checked directly.
For focused provisioning, run:

    python3 tools/setup_submodules.py vendor/jam-conformance
    PYTHONPATH=tools:tests python3 -m unittest test_jam_conformance_pin test_setup_submodules

This increment establishes the reproducible input for the planned JAM campaign
target/CI integration. It does not add a campaign pass or a placeholder Fuzz job.
Gray Paper, VRF, protocol vectors and historical fixtures remain unchanged.
