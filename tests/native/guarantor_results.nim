## Default and actually refused guarantor results cannot expose a successful owner.
import std/[cmdline, syncio]
import ../../src/state/guarantors
import ../../src/codec/[assurances, state_safrole, bounded]
let outcome = if paramStr(1) == "default": default(GuarantorResult[GuarantorPermutation]) else:
  shuffleValidatorIndices(ValidatorCount(6), default(StateEntropyWord), ElementLimit(0))
discard outcome.value # Both supported selectors must fail the checked extraction contract.
