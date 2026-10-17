## Default and actual invalid-policy authentication cannot publish entropy or a retained authenticated header.
import std/[assertions, cmdline, syncio]
import ../../src/state/safrole_authentication
import ../../src/codec/[header, state_safrole]
let outcome = if paramStr(1) == "default": default(SafroleAuthResult) else:
  authenticateSafroleSeal(default(OwnedHeader), [], [], StateTime(0), default(StateEntropy),
      default(SafroleAuthConfig)) # Actual zero-epoch refusal precedes header extraction.
assert paramStr(1) in ["default", "error"] # Unknown selectors cannot substitute for extraction protection.
assert outcome.error == (if paramStr(1) == "default": SafroleAuthError.Uninitialized else: SafroleAuthError.InvalidConfig)
echo outcome.value.ticketed
