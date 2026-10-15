# Payload extraction is bound to its owner; a second source pool is not part of the API.
import ../../../src/owned
var frame: OwnedFrame
var wrongPool, output: array[2, byte]
discard copyOwnedBlob(frame, wrongPool, 0, output)
