## External callers cannot expose, forge or mutate private chapter-10 results, owners or alternatives.
import ../../../src/codec/[state_availability, state_trie]
var value = default(AvailabilityResult[AvailabilityInfo])
value.error = AvailabilityError.None
