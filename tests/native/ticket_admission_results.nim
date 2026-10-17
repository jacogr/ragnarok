## Default and actually failed admissions cannot expose a fabricated candidate owner.
import std/[assertions, cmdline, syncio]
import ../../src/state/ticket_admission
import ../../src/codec/[state_safrole, state_consensus]

let outcome = if paramStr(1) == "default": default(TicketAdmissionResult) else:
  admitSafroleTickets([], StateTime(0), StateTime(1), default(StateEntropyWord), [], default(
      TicketAdmissionConfig)) # Actual invalid policy.
assert paramStr(1) in ["default", "error"] # Unknown selectors are harness failures.
assert outcome.error == (if paramStr(1) == "default": TicketAdmissionError.Uninitialized else: TicketAdmissionError.InvalidConfig)
echo safroleInfo(outcome.value).value.validators
