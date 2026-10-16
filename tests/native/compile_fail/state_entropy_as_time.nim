## An entropy word cannot silently become the current state timeslot.
import ../../../src/codec/state_safrole
let word = default(StateEntropyWord)
let entry = timeEntry(word)
discard entry
