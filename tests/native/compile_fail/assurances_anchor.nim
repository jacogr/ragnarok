## Intentional nominal domain misuse must fail compilation.
import ../../../src/codec/assurances
let value: AssuranceAnchor = default(AssuranceSignature)
discard value
