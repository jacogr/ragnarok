## A caller cannot forge success by modifying a plan result discriminator.
import ../../../src/state/validators
var hidden = default(ValidatorRotationResult)
hidden.status = ValidatorRotationError.None
