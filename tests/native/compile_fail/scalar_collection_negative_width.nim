## Direct scalar helpers reject a statically invalid width before generating executable code.
import ../../../src/codec/collections
discard scalarMinimum(CollectionUInt[-1])
