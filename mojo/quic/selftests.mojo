from std.collections import Array, Span
from std.ffi import external_call, c_int, c_size_t
from quic.transport import *


# Observe startup only after the SDK's fixed workers have settled their initial process malloc activity.
def startup_heap() raises -> UInt64:
    var item = PollFd(c_int(-1), 0, 0)
    var previous = external_call["rqm_heap_used", UInt64]()
    var stable = 0
    # This bounded pre-endpoint window prevents racing SDK startup allocations against a shutdown comparison.
    for tick in range(100):
        _ = external_call["rqm_poll", c_int](Pointer(to=item), c_size_t(0), c_int(10))
        var current = external_call["rqm_heap_used", UInt64]()
        if current == previous:
            # Require consecutive stable samples rather than accepting a transient startup count.
            stable += 1
        else:
            # A new SDK allocation restarts the quiescent observation interval.
            stable = 0
        previous = current
        if tick >= 9 and stable >= 5:
            # At least 100 ms and 50 ms of unchanged live malloc activity precede the baseline.
            return current
    raise Error("SDK startup heap did not settle")


# A live native readiness window gives the controller the SDK's real fixed startup thread baseline.
def runtime_probe() raises:
    var before = startup_heap()
    print("RUNTIME_READY")
    _ = external_call["rqm_flush", c_int]()
    var item = PollFd(c_int(-1), 0, 0)
    # No descriptor/connection/stream exists; every counted thread belongs to the fixed native runtime baseline.
    _ = external_call["rqm_poll", c_int](Pointer(to=item), c_size_t(0), c_int(1000))
    print("RUNTIME_HEAP", before, external_call["rqm_heap_used", UInt64]())


# Repeated idle/ready UDP lifecycles verify public POSIX readiness and exact descriptor retirement.
def io_selftest() raises:
    # Keep one native process/SDK alive across all endpoint creations, like the existing adapters.
    for iteration in range(256):
        var bound: UInt16 = 0
        var fd = external_call["rqm_udp_open", c_int](UInt16(0), Pointer(to=bound))
        # A failed bind creates no accepted endpoint or descriptor owner.
        if fd < 0:
            raise Error("UDP bind")
        try:
            var item = PollFd(fd, 1, 0)
            # Half the endpoints are made readable; the other half retire while completely idle.
            if iteration % 2 == 0:
                var byte: UInt8 = 99
                var sent = external_call["rqm_udp_send", Int64](
                    fd, Pointer(to=byte).as_imm().as_unsafe_any_origin(), c_size_t(1), bound
                )
                # Datagram delivery must be complete before expecting a readiness notification.
                if sent != 1:
                    raise Error("UDP send")
                var ready = external_call["rqm_poll", c_int](
                    Pointer(to=item), c_size_t(1), c_int(10)
                )
                if ready != 1 or (Int(item.revents) & 1) == 0:
                    # Readiness failure cannot be hidden behind eventual endpoint cleanup.
                    raise Error("UDP readiness")
            else:
                # An idle bound endpoint must respect a zero-wait poll without fabricating input.
                if external_call["rqm_poll", c_int](Pointer(to=item), c_size_t(1), c_int(0)) != 0:
                    raise Error("idle readiness")
        finally:
            # Retire the only descriptor before the next endpoint can recycle its OS number.
            _ = external_call["close", c_int](fd)
    print("Mojo I/O selftest: 256 idle/ready UDP retirements passed")
