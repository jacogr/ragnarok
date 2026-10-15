from std.collections import List
from std.ffi import external_call, c_int, c_size_t
from std.sys import argv, get_defined_bool
from std.os import getenv
from quic.core import run_peer, gate_wait, parser_selftest
from quic.integration import composition_selftest
from quic.mesh import run_mesh, policy_selftest
from quic.selftests import runtime_probe, io_selftest, startup_heap
from tests.support import capacity
import quic.offload as offload


# Complete native owner teardown before returning the documented bounded CLI status to the test controller.
def main() raises:
    var raw = argv()
    var args = List[String]()
    # Own CLI strings before passing them to role setup and synchronous C string views.
    for i in range(len(raw)):
        args.append(String(raw[i]))
    # Baseline/readiness probes create no TLS engine and share the same public runtime/toolchain.
    if len(args) == 2 and args[1] == "--runtime-probe":
        runtime_probe()
        return
    elif len(args) == 2 and args[1] == "--selftest":
        parser_selftest()
        return
    elif len(args) == 2 and args[1] == "--integration-selftest":
        comptime if get_defined_bool["INTEGRATION", False]():
            composition_selftest()
            return
        else:
            # The baseline build does not link crypto composition.
            external_call["exit", NoneType](c_int(2))
    elif len(args) == 2 and args[1] == "--io-selftest":
        io_selftest()
        return
    elif len(args) == 2 and args[1] == "--mesh-selftest":
        policy_selftest()
        return
    elif len(args) == 2 and args[1] == "--offload-selftest":
        comptime if offload.ENABLED:
            offload.selftest()
            return
        else:
            # Ordinary binaries must never claim a linked Rust worker proof.
            external_call["exit", NoneType](c_int(2))
    elif len(args) == 2 and args[1] == "--offload-held-shutdown":
        comptime if offload.ENABLED:
            offload.held_shutdown_test()
            return
        else:
            # Explicit offload tests require the checked fixed-worker build.
            external_call["exit", NoneType](c_int(2))
    var good = False
    if len(args) > 1 and args[1] == "mesh":
        var baseline = startup_heap()
        good = run_mesh(args)
        print("MESH_CLEAN", baseline, external_call["rqm_heap_used", UInt64]())
    elif len(args) == 9 and args[8] == "soak":
        var rounds = capacity(getenv("RAGNAROK_SOAK_ROUNDS"), 1000)
        var gate = getenv("RAGNAROK_SOAK_GATE")
        # Repeated native lifecycles have explicit bounded extent and an external observation gate.
        if rounds < 1 or gate == "":
            raise Error("soak controls")
        for iteration in range(rounds + 1):
            gate_wait(gate + "/" + args[1] + "-" + String(iteration))
            if iteration == rounds:
                # The final gate releases only after the controller records the last idle sample.
                good = True
                break
            if not run_peer(args):
                # Failed application work still completes endpoint cleanup before leaving this loop.
                break
            print("ALLOC_BYTES", external_call["rqm_heap_used", UInt64]())
            print("SESSION_DONE", iteration)
            _ = external_call["rqm_flush", c_int]()
    elif len(args) == 9 and args[8] in ("service", "overload", "integration", "offload"):
        var baseline = startup_heap()
        good = run_peer(args)
        # Live malloc observations include the SDK and native C stack, unlike language-only allocator counters.
        print("SERVICE_CLEAN", baseline, external_call["rqm_heap_used", UInt64]())
    else:
        # The ordinary rejection matrix owns one bounded endpoint lifecycle per process.
        good = run_peer(args)
    # Normal return uses status zero; rejection exits only after run_peer's full native cleanup.
    if not good:
        external_call["exit", NoneType](c_int(2))
