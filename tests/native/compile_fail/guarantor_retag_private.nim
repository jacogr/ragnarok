## External callers cannot access private guarantor storage.
import ../../../src/state/guarantors
let owner = default(GuarantorResult[GuarantorPlan])
discard owner.status # Must fail during semantic compilation.
