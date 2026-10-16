## Link the real maintained transport bridge; no protocol peer migration is claimed by these tests.
import std/[assertions, cmdline, syncio]
import ../../src/quic/transport

# The real transport invokes identity validation only while the stack owner remains alive.
proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl.} = 0
# Setup/teardown should create no application streams, but preserve a valid synchronous callback.
proc stream(user: pointer, handle: NativeStream, event: cint) {.cdecl.} = discard

# Exercise native construction failure and success with the exact production I/O owner and LSQUIC engine.
proc main() {.raises.} =
  let args = commandLineParams()
  assert args.len == 2
  var owner = default(Transport)
  var token: byte = 0
  assert owner.transportStatus == -1
  assert not owner.pollTransport(0)
  owner.closeTransport()
  owner.closeTransport()
  # Failed certificate setup must retire the socket/dispatcher so the same stack owner can recover.
  assert not owner.openTransport(true, false, 0, "missing-certificate.pem", "missing-key.pem",
      "jamnp-s/1/00000000", addr token, verify, stream)
  assert owner.transportStatus == -1
  # Repeated real engines validate synchronous callbacks, C string lifetimes and resource teardown.
  for iteration in 0..<16:
    assert owner.openTransport(true, false, 0, args[0], args[1], "jamnp-s/1/00000000",
        addr token, verify, stream, ipv6 = iteration mod 2 == 1)
    assert not owner.openTransport(true, false, 0, args[0], args[1], "jamnp-s/1/00000000",
        addr token, verify, stream) # Refuse to replace live native resources.
    assert owner.pollTransport(0)
    owner.closeTransport()
    owner.closeTransport()
    assert owner.transportStatus == -1
  let dispatcher = newDispatcher()
  defer: dispatcher.close()
  var incoming = default(Transport)
  var outgoing = default(Transport)
  # Shared native engines borrow one dispatcher; retiring one must leave the other's socket usable.
  for iteration in 0..<4:
    assert incoming.openTransport(true, false, 0, args[0], args[1], "jamnp-s/1/00000000",
        addr token, verify, stream, ipv6 = iteration mod 2 == 1, dispatcher = dispatcher)
    assert outgoing.openTransport(false, false, 0, args[0], args[1], "jamnp-s/1/00000000",
        addr token, verify, stream, ipv6 = iteration mod 2 == 1, dispatcher = dispatcher)
    assert pollPair(incoming, outgoing)
    incoming.closeTransport()
    assert outgoing.pollTransport(0)
    outgoing.closeTransport()
  echo "Nimony shared transport: 4 IPv4/IPv6 engine pairs passed"
  echo "Nimony transport: 16 IPv4/IPv6 native setup/teardown cycles passed"

# Fixture/thread setup errors cannot be reported as a successful native lifecycle check.
try:
  main()
except:
  quit(2)
