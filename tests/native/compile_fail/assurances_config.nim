## Intentional nominal domain misuse must fail compilation.
import ../../../src/assurances
let value = AssuranceConfig(cores: ValidatorCount(2), validators: CoreCount(6))
discard value
