## An entropy word cannot silently become the current state timeslot.
import ../../../src/state_safrole
var word: StateEntropyWord
let entry = timeEntry(word)
discard entry
