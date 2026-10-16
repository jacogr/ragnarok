## Intentional nominal domain misuse must fail compilation.
import ../../../src/codec/assurances
let value: ValidatorIndex = CoreCount(0)
discard value
