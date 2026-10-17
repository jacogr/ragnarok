## Callers cannot forge success or mutate read-only request results.
import ../../../src/codec/state_requests
discard RequestResult[int](status: RequestError.None, completed: 0)
