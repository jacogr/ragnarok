## Failed/default plans cannot expose mutable success storage.
import ../../../src/state/validators
let hidden = default(ValidatorRotationResult)
discard hidden.completed
