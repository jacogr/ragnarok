## Intentional nominal domain misuse must fail compilation.
import ../../../src/assurances
let value: AssuranceAnchor = default(AssuranceSignature)
discard value
