## A composite RPC owner cannot duplicate its listener and accepted sockets.
import ../../../src/rpc/server
var original = default(Server)
var duplicate = original
original.close()
duplicate.close()
