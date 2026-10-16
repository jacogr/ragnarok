## Service identities cannot silently select mapping ordinals.
import ../../../src/codec/[state_composition, state_accounts]
discard stateEntryAt(default(StateSnapshot), ServiceIndex(0))
