## Two mutable endpoint owners cannot close the same descriptor after an implicit copy.
import ../../../src/quic/io
var original = default(UdpEndpoint)
var duplicate = original
original.close()
duplicate.close()
