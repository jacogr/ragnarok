## Intentional nominal domain misuse must fail compilation.
import ../../../src/assurances
let value: ValidatorIndex = CoreCount(0)
discard value
