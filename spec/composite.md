# Optional blobs, work outputs and preimage extrinsics

Normative basis: Gray Paper **v0.7.1**, commit
`1c979cb59bb800f92ffff083a2701004dfc6cd33`, Appendix **C.1.3**
(discriminators) and **C.2** (block serialization), specifically `maybe`,
`encodepreimages` and the work-output operator `O` in
[text/serialization.tex](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/serialization.tex).
Official fixtures retain vector commit
`1dc503af37ae8ecc7b6e24a393f6102801c0c80c`; hashes are in `pins.json`.

## Wire formats

Here `E` is canonical general-natural encoding, `E4` is four-byte unsigned
little-endian encoding, and `blob` bytes have identity encoding.

| Schema | Encoded form |
| --- | --- |
| Absent optional blob | `E(0)` |
| Present optional variable blob | `E(1) + E(blob.length) + blob` |
| Successful work output | `E(0) + E(blob.length) + blob` |
| Work error | `E(tag)` only |
| Preimage extrinsic | `E(recordCount) + (E4(service) + E(blob.length) + blob)*` |

Work-error tags are 1 out-of-gas, 2 panic, 3 bad exports, 4 oversize, 5 BAD,
and 6 BIG, exactly as C.2 specifies. Unknown discriminators are rejected before
constructing enum/union values. Overlong natural discriminators are rejected,
including optional absence encoded as `80 00`.

The optional API explicitly chooses a **variable blob** as its payload schema;
other optional types require their own payload codecs. Preimages preserve wire
order. These functions implement serialization, without imposing state-transition
rules such as preimage ordering/uniqueness or protocol resource constants.

## API and validation

See [the Nim codec guide](../docs/codec.md) and source modules under `src/`.
Independent references, official vectors, boundary/fuzz and failure-atomicity checks live under `tests/`.
