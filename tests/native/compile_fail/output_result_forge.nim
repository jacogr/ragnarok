## Callers cannot forge success or change read-only result state.
import ../../../src/codec/state_outputs
discard OutputLogResult[int](status: OutputLogError.None, completed: 0)
