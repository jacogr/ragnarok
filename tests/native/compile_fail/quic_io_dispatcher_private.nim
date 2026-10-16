## A caller cannot insert arbitrary descriptors into a dispatcher's registration storage.
import ../../../src/quic/io
let dispatcher = newDispatcher()
discard dispatcher.descriptors
