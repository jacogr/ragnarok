# Compact validator statistics preview vectors

The unreleased `gp-next` vector pin advances from
`c84f9aa79de298aaefb9b60818c67a9416f66c8f` to
`a49f241a791f559d1502dc1b0b5328372995e375`. The Gray Paper authority remains
`fad0ded4a433052397bf7234352a57fe491883f7`. The source delta regenerates eight
Tiny/Full statistics binaries, widens `pre-images-size` to U64 in the ASN schema,
and updates the changelog. Companion JSON and historical trace bytes are unchanged.
This is a targeted preview update; the dataset's historical codec provenance stays intact.

The qualification reads the exact hash-verified binary and JSON blobs. It finds the
pre- and post-state boundaries from the end using the fixed slot and encoded validator
records, then checks the original counter bytes against independently encoded JSON
values. The native chapter-13 codec decodes each of the 16 extracted validator
prefixes with explicitly authored zero core statistics and an empty service table.
It also encodes the corresponding logical fields and compares the bytes. Both profiles
include ordinary and epoch-change states; the Full resize exercises six current
validators and 1,023 previous validators in the same state. Separate codec cases
exercise all six validator fields above U32 and through the U64 endpoint.

The maintained native corpus passed 2,487 requests including the 32 preview
encode/decode requests. This is codec evidence for the validator component, not
execution of the statistics STF or qualification of the input extrinsics. No
production codec change or historical fallback is needed.

The shared official crypto vector identity follows the new pin; its consumed source
bytes did not change. Six frozen primitive-input records and their dependent
fingerprints were refreshed without changing expected outputs or cryptographic
payloads. The current source audit records the new vector commit with its original
source observations, roots and native metadata transport unchanged.
