"""Run the unchanged peer/lifecycle/resource workloads in an E2E-owned workspace."""
import subprocess
import traceback
from native_checks import ROOT, announce

# Peer-entry selftests and networking workloads retain their original flags, rounds and finalizers.
def run(compiler, crypto_library, bs_library, quic_library, quic_fixtures, integration_wires, report, checks):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    # Shared process-startup and summary safeguards must stay effective with isolated compiler-specific binary paths.
    # Build the actual peer entry point without invoking the historical compiler/build path.
    compiled, binary = build(compiler, ROOT/'src/quic/peer.nim', 'quic-peer', crypto_library, quic_library=quic_library)
    report['quic_peer_build'] = compiled
    report['quic_peer'] = dict(passed=False)
    if compiled['exit_code'] == 0:
        # Parser, readiness and mesh policy tests are separate positive suites, not network parity claims.
        for name, flag in (('quic_peer_parser', '--selftest'), ('quic_peer_io', '--io-selftest'),
                           ('quic_peer_mesh_policy', '--mesh-selftest')):
            result = command([binary, flag], name)
            report['suites'].append(dict(name=name, build=compiled, run=result, passed=result['exit_code'] == 0))
            announce(name, result['exit_code'] == 0)
        from nimony_peer import exchanges, controls
        try:
            # Reuse the original identity/framing matrix and retain both endpoint outputs in the evidence.
            report['quic_peer'] = exchanges(binary, quic_fixtures, BUILD/'peer-cases')
            report['quic_peer_controls'] = controls(binary, quic_fixtures)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Preserve failure instead of allowing a later slice to turn a failed network attempt green.
            report['quic_peer'] = dict(passed=False, failure=str(error))
        announce('authenticated CE 143 peer matrix and repeated startup', report['quic_peer']['passed'])
    # Telemetry exercises native partial framing/reconnect and the actual optional peer CLI.
    report['telemetry'] = dict(passed=False)
    telemetry_build, telemetry_binary = build(compiler, ROOT/'tests/native/telemetry_driver.nim', 'telemetry-driver')
    if compiled['exit_code'] == 0 and telemetry_build['exit_code'] == 0:
        from telemetry_checks import reconnect, peer_registration, dial_failure, peer_loss, incoming_failure, incoming_lifetimes, mesh_lifetimes, mesh_shutdown, capacity_refusal, mesh_collector_isolation
        try:
            refusal = capacity_refusal(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-refusal')
            observed = reconnect(telemetry_binary)
            observed6 = reconnect(telemetry_binary, ipv6=True)
            peer = peer_registration(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry', startup_delay=2.1)
            peer6 = peer_registration(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-ipv6', ipv6=True)
            failed = dial_failure(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry')
            lost = peer_loss(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry')
            incoming = incoming_failure(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry')
            expiry = incoming_lifetimes(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry', True)
            teardown = incoming_lifetimes(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry', False, startup_delay=1.5)
            mesh = mesh_lifetimes(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-mesh')
            mesh_failed = mesh_lifetimes(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-mesh-failed', bad_pin=True)
            mesh_pending = mesh_shutdown(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-mesh-pending', silent=True)
            mesh_teardown = mesh_shutdown(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-mesh-teardown')
            isolated = mesh_collector_isolation(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-collector-isolation')
            report['telemetry'] = dict(passed=True, collector_isolation=isolated, capacity_refusal=refusal, mesh=mesh, mesh_failed=mesh_failed, mesh_pending=mesh_pending, mesh_teardown=mesh_teardown, reconnect=observed, reconnect_ipv6=observed6, peer=peer, peer_ipv6=peer6, failed_dial=failed, peer_loss=lost, incoming_failure=incoming, incoming_expiry=expiry, incoming_teardown=teardown)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Collector failures remain visible while process finalizers retire every live child.
            report['telemetry'] = dict(passed=False, failure=repr(error), traceback=traceback.format_exc())
            print(report['telemetry']['traceback'], flush=True) # Preserve the scenario and assertion in CI console output.
    announce('JIP-3 telemetry registration/status/reconnect', report['telemetry']['passed'])
    # The enabled entry point must compile its migrated integration call sites and retain the original selftest.
    compiled, binary = build(compiler, ROOT/'src/quic/peer.nim', 'quic-peer-integration', crypto_library,
                             quic_library=quic_library, defines=('integration',))
    row = dict(name='quic_peer_integration', build=compiled, passed=False)
    if compiled['exit_code'] == 0:
        # This no-socket selftest proves enabled composition wiring, not integrated service lifecycle parity.
        row['run'] = command([binary, '--integration-selftest'], 'quic-peer-integration-selftest')
        row['passed'] = row['run']['exit_code'] == 0
    report['suites'].append(row)
    announce('enabled peer integration entry point', row['passed'])
    # Retained listeners reuse the original failure schedules, warmup, timeouts and scoped resource limits.
    report['quic_service'] = dict(passed=False)
    report['quic_integration_service'] = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_service import service as retained_service
        try:
            # One server engine survives sixteen waves, including malformed peers and two forced peer deaths.
            result = retained_service('nim', quic_fixtures, 16, 4, binaries={'nim': BUILD/'quic-peer'},
                                      directory=BUILD/'retained-service')
            report['quic_service'] = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Finalizers preserve logs and retire children; failure cannot be replaced by later integration success.
            report['quic_service'] = dict(passed=False, failure=str(error))
    announce('retained CE 143 service lifecycle', report['quic_service']['passed'])
    if compiled['exit_code'] == 0:
        from test_integration import service as integrated_service
        try:
            # Three concurrent identities per wave exercise real capture/hash/copy/cancellation owners.
            result = integrated_service('nim', quic_fixtures, integration_wires, 12, 4,
                                        binaries={'nim': binary}, directory=BUILD/'retained-integration')
            report['quic_integration_service'] = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Typed protocol rejections are checked by the harness; assertion/timeouts remain workload failures.
            report['quic_integration_service'] = dict(passed=False, failure=str(error))
    announce('retained integrated digest lifecycle', report['quic_integration_service']['passed'])
    # Retained IPv6 peers keep both role engines through fallback, duplicate arbitration and reconnects.
    report['quic_mesh'] = dict(passed=False)
    report['quic_mesh_disruption'] = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_mesh import pairing as mesh_pairing
        from test_quic_resilience import disruption as mesh_disruption
        try:
            # Reuse exact original rounds, warmup, wrong-identity gate and finite resource limits.
            result = mesh_pairing(('nim', 'nim'), quic_fixtures, 16, 4,
                                  binaries={'nim': BUILD/'quic-peer'}, directory=BUILD/'mesh')
            bad_pin = mesh_pairing(('nim', 'nim'), quic_fixtures, 1, 0, bad_pin=True,
                                   binaries={'nim': BUILD/'quic-peer'}, directory=BUILD/'mesh-bad-pin')
            report['quic_mesh'] = dict(passed=True, result=result, bad_pin=bad_pin)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # All live endpoints retire in harness finalizers; a failed arbitration remains a failed gate.
            report['quic_mesh'] = dict(passed=False, failure=str(error))
        try:
            # One keeper retains its two engines through twelve killed peers and a final healthy generation.
            result = mesh_disruption(('nim', 'nim'), quic_fixtures, 12, 4,
                                     binaries={'nim': BUILD/'quic-peer'}, directory=BUILD/'mesh-disruption')
            report['quic_mesh_disruption'] = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Recovery must settle all eight pending operations before reconnect; ordinary mesh success cannot hide failure.
            report['quic_mesh_disruption'] = dict(passed=False, failure=str(error))
    announce('retained IPv6 mesh/reconnect and wrong identity', report['quic_mesh']['passed'])
    announce('retained IPv6 peer-death recovery', report['quic_mesh_disruption']['passed'])
    # Recreate both endpoints in the same processes; retained-engine tests cannot establish post-destruction cleanup.
    report['quic_endpoint_soak'] = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_soak import pairing as endpoint_soak
        try:
            # Preserve the original forty sessions, eight warmup samples, mixed streams and finite budgets.
            result = endpoint_soak('nim', 'nim', quic_fixtures, 40, 8,
                                   binaries={'nim': BUILD/'quic-peer'}, directory=BUILD/'endpoint-soak')
            report['quic_endpoint_soak'] = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Finalizers retain resource evidence and kill live peers; later corpus success cannot hide failure.
            report['quic_endpoint_soak'] = dict(passed=False, failure=str(error))
    announce('same-process endpoint teardown soak', report['quic_endpoint_soak']['passed'])
    # Admission and pre-request connection loss are independent gates; healthy mesh traffic cannot substitute for them.
    report['quic_admission'] = dict(passed=False)
    report['quic_closed_before_request'] = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_resilience import overload as admission, closed_before_request
        try:
            # Keep the original twelve waves/four warmup samples and exact connection/stream ceilings.
            result = admission('nim', quic_fixtures, 12, 4, binaries={'nim': BUILD/'quic-peer'},
                               directory=BUILD/'admission')
            report['quic_admission'] = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Capacity rejection must recover within the original deadlines and release all retained owners.
            report['quic_admission'] = dict(passed=False, failure=str(error))
        try:
            # Idle clients open no application streams; connection close must settle the authenticated failure.
            result = closed_before_request(('nim', 'nim'), quic_fixtures,
                                           binaries={'nim': BUILD/'quic-peer'}, directory=BUILD/'closed-before-request')
            report['quic_closed_before_request'] = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # A stale AUTH_OK marker cannot turn connection loss into successful application exchange.
            report['quic_closed_before_request'] = dict(passed=False, failure=str(error))
    announce('connection/stream admission recovery', report['quic_admission']['passed'])
    announce('authenticated connection loss before request', report['quic_closed_before_request']['passed'])
    # Preserve independent fixture identity, missing-marker rejection and failed-server cleanup in CI.
    # Enabled workers use the same maintained Rust/QUIC ABIs and original queue/cancellation workload.
    from test_quic_offload import corpus as offload_fixture, selftests as offload_selftests, exercise as offload_exercise
    offload_wire, offload_metadata = offload_fixture(BUILD/'offload')
    compiled, binary = build(compiler, ROOT/'src/quic/peer.nim', 'quic-peer-offload', crypto_library,
                             native_libraries=(bs_library,), quic_library=quic_library, defines=('offload',))
    report['quic_offload_build'] = compiled
    report['quic_offload'] = dict(passed=False, fixture=offload_metadata)
    if compiled['exit_code'] == 0:
        try:
            # Completed jobs retain capacity; held workers must join without a controller ever releasing their gate.
            for row in offload_selftests(binary, offload_wire, BUILD/'offload'):
                row['build'] = compiled
                report['suites'].append(row)
            # Ten waves preserve two workers, four job slots and 128 real verifications per accepted job.
            result = offload_exercise('nim', quic_fixtures, offload_wire, 10, 2, 128,
                                      binaries={'nim': binary}, directory=BUILD/'offload')
            report['quic_offload'] = dict(passed=True, fixture=offload_metadata, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # A selftest, callback, resource or joined-shutdown failure cannot be hidden by another workload.
            report['quic_offload'] = dict(passed=False, fixture=offload_metadata, failure=str(error))
    announce('bounded proof offload and joined shutdown', report['quic_offload']['passed'])
