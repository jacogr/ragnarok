## External callers cannot access private guarantor storage.
import ../../../src/state/guarantors
let owner = default(GuarantorResult[GuarantorPlan])
discard owner.completed # Must fail during semantic compilation.
