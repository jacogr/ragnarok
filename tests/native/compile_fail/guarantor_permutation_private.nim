## External callers cannot access private guarantor storage.
import ../../../src/state/guarantors
let owner = default(GuarantorPermutation)
discard owner.data # Must fail during semantic compilation.
