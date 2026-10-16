## Chapter slots remain private behind nominal chapter accessors.
import ../../../src/codec/state_composition
let chapters = default(StateChapters)
discard chapters.slots
