## Cross-module generic support must not export an unchecked scalar writer.
import ../../../src/codec/[collections, natural]
var output: array[1, byte] = default(array[1, byte])
var cursor = 0
put(JamNatural(1), output, cursor)
