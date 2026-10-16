## Callers cannot inject or mutate private retained validator backing storage.
import ../../../src/state_safrole
let snapshot = ValidatorStateSnapshot(data: nil)
discard snapshot
