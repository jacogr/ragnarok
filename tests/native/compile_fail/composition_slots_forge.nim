## Chapter slots remain private behind nominal chapter accessors.
import ../../../src/codec/state_composition
discard StateChapters(slots: default(array[16, StateChapterSnapshot]))
