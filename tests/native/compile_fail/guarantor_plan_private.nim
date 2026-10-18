## External callers cannot access private guarantor storage.
import ../../../src/state/guarantors
let owner = default(GuarantorPlan)
discard owner.data # Must fail during semantic compilation.
