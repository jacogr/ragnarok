## Intentional wrong-domain assignment must be rejected before runtime.
import ../../crypto/[primitives, assurance_context]
import ../../src/assurances
let value: AssuranceParent = default(AssuranceAnchor)
discard value
