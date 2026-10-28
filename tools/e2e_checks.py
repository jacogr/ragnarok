# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run named E2E tasks; their declarations own scheduling and required report identities.

Exposes PLAN and run, preserving peer builds, workload order, resource budgets and cleanup.
"""
import subprocess
import sys
import traceback
from types import SimpleNamespace
from native_checks import ROOT, announce
from e2e_plan import E2EPlan

PLAN = E2EPlan()


# Preserve this task and its original checks in dependency order.
@PLAN.setup
def prepare_peer(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    build = context.checks.build
    compiler = context.compiler
    report = context.report
    crypto_library = context.crypto
    quic_library = context.quic
    # Download preparation imports Bandersnatch in every peer shape, including ordinary startup.
    compiled, binary = build(compiler, ROOT/'src/ragnarok.nim', 'ragnarok', crypto_library,
                             native_libraries=(context.bs,), quic_library=quic_library)
    report['quic_peer_build'] = compiled
    context.peer = compiled, binary


# Run one no-socket selftest only after its corresponding peer build succeeds.
def peer_selftest(context, prepared, flag, log_name):
    """Retain the exact command, build evidence and nonzero-exit refusal for one entry point."""
    compiled, binary = prepared
    row = dict(build=compiled, passed=False)
    if compiled['exit_code'] == 0:
        # Failed builds never execute stale binaries.
        row['run'] = context.checks.command([binary, flag], log_name)
        row['passed'] = row['run']['exit_code'] == 0
    return row

@PLAN.selftest(group='transport', requires=('prepare_peer',))
def quic_peer_parser(context):
    """Exercise the real peer parser selftest."""
    return peer_selftest(context, context.peer, '--selftest', quic_peer_parser.__name__)

@PLAN.selftest(group='transport', requires=('prepare_peer',))
def quic_peer_io(context):
    """Exercise peer readiness and I/O checks."""
    return peer_selftest(context, context.peer, '--io-selftest', quic_peer_io.__name__)

@PLAN.selftest(group='transport', requires=('prepare_peer',))
def quic_peer_mesh_policy(context):
    """Exercise the peer's mesh policy checks."""
    return peer_selftest(context, context.peer, '--mesh-selftest', quic_peer_mesh_policy.__name__)

# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_peer',))
def quic_peer(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    quic_fixtures = context.certificates
    compiled, binary = context.peer
    context.peer_exchanged = False
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        from nimony_peer import exchanges
        try:
            # Retain the original identity/framing matrix and both endpoint outputs.
            observed = exchanges(binary, quic_fixtures, BUILD/'peer-cases')
            context.peer_exchanged = True
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            observed = dict(passed=False, failure=str(error))
    announce('authenticated CE 143 peer matrix and repeated startup', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('quic_peer',))
def quic_peer_controls(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    report = context.report
    quic_fixtures = context.certificates
    compiled, binary = context.peer
    observed = dict(passed=False)
    if compiled['exit_code'] == 0 and context.peer_exchanged:
        from nimony_peer import controls
        try:
            # Controls follow a completed matrix call, exactly as in the original shared try block.
            observed = controls(binary, quic_fixtures)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            report['quic_peer'] = dict(passed=False, failure=str(error))
            observed = dict(passed=False, failure=str(error))
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='testnet', requires=('prepare_peer',))
def rpc(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    quic_fixtures = context.certificates
    compiled, binary = context.peer
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        from rpc_checks import run as rpc_checks, parameter_checks
        try:
            chain = BUILD/'rpc-browser-chain.json'
            chain.write_bytes((ROOT/'tests/fixtures/rpc-genesis.json').read_bytes())
            observed = rpc_checks(binary, quic_fixtures, BUILD/'rpc', chain=chain, ui=True, browser=True)
            observed['development_ui'] = rpc_checks(binary, quic_fixtures, BUILD/'rpc-dev-ui', ui=True, dev_ui=True)
            observed['passed'] &= observed['development_ui']['passed']
            observed['parameters'] = parameter_checks(binary, quic_fixtures, BUILD/'rpc-parameters')
            observed['passed'] &= observed['parameters']['passed']
        except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
            # A protocol, cleanup or concurrency failure is an independent required E2E verdict.
            observed = dict(passed=False, failure=repr(error), traceback=traceback.format_exc())
    announce('WebSocket RPC and concurrent peer progress', observed['passed'])
    return observed


@PLAN.workload(group='testnet', requires=('prepare_peer',))
def mcp(context):
    """Exercise the real MCP-only CLI endpoint using independent HTTP client lifecycle messages."""
    from mcp_checks import run as mcp_checks
    compiled, binary = context.peer
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        try:
            observed = mcp_checks(binary, context.certificates, context.checks.folder/'mcp')
        except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
            # Startup, protocol or cleanup failures remain an independent required E2E verdict.
            observed = dict(passed=False, failure=repr(error), traceback=traceback.format_exc())
    announce('MCP lifecycle and configured chain queries', observed['passed'])
    return observed


@PLAN.workload(group='testnet', requires=('prepare_peer',))
def startup_defaults(context):
    """Bare startup must provide stable identity, usable path defaults and graceful foreground cleanup."""
    from startup_checks import run as startup_checks
    compiled, binary = context.peer
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        try:
            observed = startup_checks(binary, context.checks.folder/'startup-defaults')
        except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
            # No failed startup or cleanup can be converted into a successful default-configuration verdict.
            observed = dict(passed=False, failure=repr(error), traceback=traceback.format_exc())
    announce('Default foreground startup and persistent identity', observed['passed'])
    return observed


@PLAN.workload(group='testnet', requires=('prepare_peer',))
def testnet_tiny_devnet(context):
    """Fourteen blocks on six native validators must cross an epoch and recover a stopped node with independent maps."""
    compiled, binary = context.peer
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        from tiny_devnet_checks import check
        try:
            import time
            observed = check(binary, context.checks.folder/('tiny-devnet-'+str(time.time_ns())))
        except (AssertionError, OSError, ValueError, RuntimeError, TimeoutError, subprocess.SubprocessError) as error:
            # Independent transcript, process, network, convergence and cleanup failures all fail this workload.
            observed = dict(passed=False, failure=repr(error), traceback=traceback.format_exc())
    announce('Six-node Tiny epoch and restart conformance', observed['passed'])
    return observed


@PLAN.workload(group='testnet', requires=('prepare_peer',))
def application_state(context):
    """Verify explicit executable policy selection in both peer shapes and enabled RPC."""
    compiled, binary = context.peer
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        from application_state_checks import run as state_checks
        try:
            observed = state_checks(binary, context.certificates, context.checks.folder/'application-state')
        except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
            # A startup, protocol or cleanup failure remains this workload's independent failed verdict.
            observed = dict(passed=False, failure=str(error))
    announce('Executable canonical state policy', observed['passed'])
    return observed


@PLAN.workload(group='testnet', requires=('prepare_peer',))
def application_checkpoint_import(context):
    """Verify explicit trusted checkpoint imports in the production executable and both retained peer shapes."""
    compiled, binary = context.peer
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        from application_recovery_checks import run as recovery_checks
        try:
            observed = recovery_checks(binary, context.certificates, context.checks.folder/'application-checkpoint-import')
        except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
            # Startup, RPC, preservation and child-retirement failures remain this workload's own failed verdict.
            observed = dict(passed=False, failure=str(error))
    announce('Executable trusted checkpoint import', observed['passed'])
    return observed


@PLAN.workload(group='testnet')
def application_download_load(context):
    """Repeat authenticated signed download cancellation and native reset progress before real adoption."""
    import hashlib
    import os
    from native_fixtures import unit_runtime_fixtures
    from application_download_resources import observe
    checks = context.checks
    compiled, binary = checks.build(context.compiler, ROOT/'tests/native/application_download_load.nim',
                                   'application-download-load', context.crypto,
                                   native_libraries=(context.bs,), quic_library=context.quic)
    observed = dict(build=compiled, passed=False)
    if compiled['exit_code'] == 0:
        # Reuse the signed-report/two-identity fixture adapter without reporting a native unit verdict.
        _, inputs, files = unit_runtime_fixtures(context.certificates, None, None,
            suite='application_download_loop')['application_download_loop']
        for path, expected in files:
            # Missing or altered independent inputs fail before launching the linked workload.
            if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                raise ValueError('Download load fixture mismatch: '+str(path))
        environment = dict(os.environ, **{name: str(path) for name, path in inputs.items()})
        directory = checks.folder/'download-load-work'
        directory.mkdir(exist_ok=True)
        result = observe(binary, directory, environment)
        observed.update(run=result, fixtures={str(path): digest for path, digest in files},
                        passed=result['passed'])
    announce('signed download cancellation and native reset load', observed['passed'])
    return observed


@PLAN.setup
def prepare_current_download_peer(context):
    """Build the shipped integration/offload profile for the current executable workload."""
    context.current_download_peer = context.checks.build(context.compiler, ROOT/'src/ragnarok.nim',
        'ragnarok-current-download', context.crypto, native_libraries=(context.bs,),
        quic_library=context.quic, defines=('integration', 'offload'))


@PLAN.workload(group='current', requires=('prepare_current_download_peer',))
def application_current_download(context):
    """Verify explicit current command success, partial refusal and timeout through independent TLS/maps."""
    import hashlib
    import os
    from native_fixtures import unit_runtime_fixtures
    from application_current_download import observe
    peer_build, peer = context.current_download_peer
    observed = dict(passed=False)
    if peer_build['exit_code'] == 0:
        # A failed current peer build must never execute a previous binary or build an unrelated witness.
        compiled, responder = context.checks.build(context.compiler,
            ROOT/'tests/native/application_current_download.nim', 'application-current-download',
            context.crypto, native_libraries=(context.bs,), quic_library=context.quic)
        observed['build'] = compiled
        if compiled['exit_code'] == 0:
            _, inputs, files = unit_runtime_fixtures(context.certificates, None, None,
                suite='pvm_current_download_command')['pvm_current_download_command']
            for path, expected in files:
                # Preserve independent input identities before launching either live process.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Current download fixture mismatch: '+str(path))
            environment = dict(os.environ, **{name: str(path) for name, path in inputs.items()})
            try:
                result = observe(peer, responder, context.checks.folder/'current-download-work', environment)
                observed.update(run=result, fixtures={str(path): digest for path, digest in files},
                                passed=result['passed'])
            except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
                observed['failure'] = str(error) # Process, CLI, protocol and cleanup refusals remain this workload's own failure.
    announce('executable current downloads and durable partial progress', observed['passed'])
    return observed


@PLAN.setup(requires=('prepare_current_download_peer',))
def prepare_current_sequence_responder(context):
    """Compile one witness for every current-sequence case; modes are selected at process startup."""
    context.current_sequence_responder = ({'exit_code': 1}, None)
    if context.current_download_peer[0]['exit_code'] == 0:
        # Failed peer builds cannot launch stale witnesses; every consumer checks this same build result.
        context.current_sequence_responder = context.checks.build(context.compiler,
            ROOT/'tests/native/application_current_sequence.nim', 'application-current-sequence',
            context.crypto, native_libraries=(context.bs,), quic_library=context.quic)


@PLAN.workload(group='current', requires=('prepare_current_sequence_responder',))
def application_current_sequence(context):
    """Verify explicit current command success, partial refusal and timeout through independent TLS/maps."""
    import hashlib
    import os
    from native_fixtures import unit_runtime_fixtures
    from application_current_sequence import observe
    peer_build, peer = context.current_download_peer
    observed = dict(passed=False)
    if peer_build['exit_code'] == 0:
        # A failed current peer build must never execute a previous binary or build an unrelated witness.
        # Reuse compilation evidence, while each scenario still launches its own fresh processes and state.
        compiled, responder = context.current_sequence_responder
        observed['build'] = compiled
        if compiled['exit_code'] == 0:
            _, inputs, files = unit_runtime_fixtures(context.certificates, None, None,
                suite='pvm_current_download_command')['pvm_current_download_command']
            for path, expected in files:
                # Preserve independent input identities before launching either live process.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Current download fixture mismatch: '+str(path))
            environment = dict(os.environ, **{name: str(path) for name, path in inputs.items()})
            try:
                result = observe(peer, responder, context.checks.folder/'current-sequence-work', environment)
                observed.update(run=result, fixtures={str(path): digest for path, digest in files},
                                passed=result['passed'])
            except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
                observed['failure'] = str(error) # Process, CLI, protocol and cleanup refusals remain this workload's own failure.
    announce('executable consecutive current downloads and restart', observed['passed'])
    return observed


@PLAN.workload(group='current', requires=('prepare_current_sequence_responder',))
def application_current_preimages(context):
    """Verify explicit current command success, partial refusal and timeout through independent TLS/maps."""
    import hashlib
    import os
    from native_fixtures import unit_runtime_fixtures
    from application_current_sequence import observe_preimages as observe
    peer_build, peer = context.current_download_peer
    observed = dict(passed=False)
    if peer_build['exit_code'] == 0:
        # A failed current peer build must never execute a previous binary or build an unrelated witness.
        # Reuse compilation evidence, while each scenario still launches its own fresh processes and state.
        compiled, responder = context.current_sequence_responder
        observed['build'] = compiled
        if compiled['exit_code'] == 0:
            _, inputs, files = unit_runtime_fixtures(context.certificates, None, None,
                suite='pvm_current_preimage_sequence_command')['pvm_current_preimage_sequence_command']
            for path, expected in files:
                # Preserve independent input identities before launching either live process.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Current download fixture mismatch: '+str(path))
            environment = dict(os.environ, **{name: str(path) for name, path in inputs.items()})
            try:
                result = observe(peer, responder, context.checks.folder/'current-preimages-work', environment)
                observed.update(run=result, fixtures={str(path): digest for path, digest in files},
                                passed=result['passed'])
            except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
                observed['failure'] = str(error) # Process, CLI, protocol and cleanup refusals remain this workload's own failure.
    announce('executable nonempty current delivery and prior-request refusal', observed['passed'])
    return observed


@PLAN.workload(group='current', requires=('prepare_current_sequence_responder',))
def application_current_guarantees(context):
    """Verify explicit current command success, partial refusal and timeout through independent TLS/maps."""
    import hashlib
    import os
    from native_fixtures import unit_runtime_fixtures
    from application_current_sequence import observe_guarantees as observe
    peer_build, peer = context.current_download_peer
    observed = dict(passed=False)
    if peer_build['exit_code'] == 0:
        # A failed current peer build must never execute a previous binary or build an unrelated witness.
        # Reuse compilation evidence, while each scenario still launches its own fresh processes and state.
        compiled, responder = context.current_sequence_responder
        observed['build'] = compiled
        if compiled['exit_code'] == 0:
            _, inputs, files = unit_runtime_fixtures(context.certificates, None, None,
                suite='pvm_current_guarantee_remote')['pvm_current_guarantee_remote']
            for path, expected in files:
                # Preserve independent input identities before launching either live process.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Current download fixture mismatch: '+str(path))
            environment = dict(os.environ, **{name: str(path) for name, path in inputs.items()})
            try:
                result = observe(peer, responder, context.checks.folder/'current-guarantees-work', environment)
                observed.update(run=result, fixtures={str(path): digest for path, digest in files},
                                passed=result['passed'])
            except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
                observed['failure'] = str(error) # Process, CLI, protocol and cleanup refusals remain this workload's own failure.
    announce('executable current guarantees and original ancestry acquisition', observed['passed'])
    return observed


@PLAN.workload(group='current', requires=('prepare_current_sequence_responder',))
def application_current_rotated(context):
    """Verify real validator rotation across executable success, restart, maintenance and later resource refusal."""
    import hashlib
    import os
    from native_fixtures import unit_runtime_fixtures
    from application_current_sequence import observe_rotated as observe
    peer_build, peer = context.current_download_peer
    observed = dict(passed=False)
    if peer_build['exit_code'] == 0:
        # A failed current peer build must never execute a previous binary or build an unrelated witness.
        # Reuse compilation evidence, while each scenario still launches its own fresh processes and state.
        compiled, responder = context.current_sequence_responder
        observed['build'] = compiled
        if compiled['exit_code'] == 0:
            _, inputs, files = unit_runtime_fixtures(context.certificates, None, None,
                suite='pvm_current_rotated_fixture')['pvm_current_rotated_fixture']
            for path, expected in files:
                # Preserve independent input identities before launching either live process.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Current download fixture mismatch: '+str(path))
            environment = dict(os.environ, **{name: str(path) for name, path in inputs.items()})
            try:
                result = observe(peer, responder, context.checks.folder/'current-rotated-work', environment)
                observed.update(run=result, fixtures={str(path): digest for path, digest in files},
                                passed=result['passed'])
            except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
                observed['failure'] = str(error) # Process, CLI, protocol and cleanup refusals remain this workload's own failure.
    announce('executable current rotation and second-epoch successors', observed['passed'])
    return observed


@PLAN.workload(group='testnet', requires=('prepare_peer',))
def application_download_sequence(context):
    """Verify actual executable multi-child success, later refusal and timeout against independent native TLS/maps."""
    import hashlib
    import os
    from native_fixtures import unit_runtime_fixtures
    from application_download_sequence import observe
    peer_build, peer = context.peer
    observed = dict(passed=False)
    if peer_build['exit_code'] == 0:
        # A failed current peer build must never execute a previous binary or build an unrelated witness.
        compiled, responder = context.checks.build(context.compiler,
            ROOT/'tests/native/application_download_sequence.nim', 'application-download-sequence',
            context.crypto, native_libraries=(context.bs,), quic_library=context.quic)
        observed['build'] = compiled
        if compiled['exit_code'] == 0:
            _, inputs, files = unit_runtime_fixtures(context.certificates, None, None,
                suite='application_download_progress')['application_download_progress']
            for path, expected in files:
                # Preserve independent input identities before launching either live process.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Download sequence fixture mismatch: '+str(path))
            environment = dict(os.environ, **{name: str(path) for name, path in inputs.items()})
            try:
                result = observe(peer, responder, context.checks.folder/'download-sequence-work', environment)
                observed.update(run=result, fixtures={str(path): digest for path, digest in files},
                                passed=result['passed'])
            except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
                observed['failure'] = str(error) # Process, CLI, protocol and cleanup refusals remain this workload's own failure.
    announce('executable successive signed downloads', observed['passed'])
    return observed


def ancestor_executable(context, *, discovery=False):
    """Verify real executable ancestor acquisition, complete maps, managed restart and atomic refusal."""
    import hashlib
    import os
    from native_fixtures import unit_runtime_fixtures
    from application_remote_ancestors import observe
    peer_build, peer = context.peer
    observed = dict(passed=False)
    if peer_build['exit_code'] == 0:
        # Only the current production build may drive the independent native witness.
        compiled, responder = context.checks.build(context.compiler,
            ROOT/'tests/native/application_remote_ancestors.nim', 'application-remote-ancestors',
            context.crypto, native_libraries=(context.bs,), quic_library=context.quic)
        observed['build'] = compiled
        if compiled['exit_code'] == 0:
            _, inputs, files = unit_runtime_fixtures(context.certificates, None, None,
                suite='application_download_progress')['application_download_progress']
            for path, expected in files:
                # Actual generated input identities remain independently checked before either process starts.
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Remote ancestry fixture mismatch: '+str(path))
            environment = dict(os.environ, **{name: str(path) for name, path in inputs.items()})
            try:
                result = observe(peer, responder, context.checks.folder/('discovery-ancestor-work' if discovery else 'remote-ancestor-work'), environment, discovery=discovery)
                observed.update(run=result, fixtures={str(path): digest for path, digest in files},
                    passed=result['passed'])
            except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
                observed['failure'] = str(error) # Protocol, CLI, process and cleanup failures remain this workload's own verdict.
    announce('executable on-demand ancestor context' if discovery else 'executable remote ancestor context', observed['passed'])
    return observed


@PLAN.workload(group='testnet', requires=('prepare_peer',))
def application_remote_ancestors(context):
    """Verify explicit up-front acquisition through the shared actual executable/map witness."""
    return ancestor_executable(context)


@PLAN.workload(group='testnet', requires=('prepare_peer',))
def application_discovery_ancestors(context):
    """Verify child-driven acquisition, deadline/refusal, managed restart and successive-child reconnect."""
    return ancestor_executable(context, discovery=True)


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='telemetry', requires=('prepare_peer',))
def telemetry(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    quic_fixtures = context.certificates
    compiled, binary = context.peer
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        from telemetry_incoming import incoming_reconnect
        from telemetry_checks import reconnect, peer_registration, dial_failure, peer_loss, incoming_failure, incoming_lifetimes, mesh_lifetimes, mesh_shutdown, capacity_refusal, mesh_collector_isolation, pending_reconnect
        try:
            refusal = capacity_refusal(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-refusal')
            pending = pending_reconnect(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-pending-reconnect')
            incoming_reset = incoming_reconnect(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-incoming-reconnect')
            incoming_rejected = incoming_reconnect(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-incoming-rejected', rejected=True)
            observed = reconnect(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-reconnect')
            observed6 = reconnect(binary, quic_fixtures, ROOT/'tests/fixtures/telemetry-dev.json', BUILD/'telemetry-reconnect-ipv6', ipv6=True)
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
            observed = dict(passed=True, incoming_reconnect=incoming_reset, incoming_rejected=incoming_rejected, pending_reconnect=pending, collector_isolation=isolated, capacity_refusal=refusal, mesh=mesh, mesh_failed=mesh_failed, mesh_pending=mesh_pending, mesh_teardown=mesh_teardown, reconnect=observed, reconnect_ipv6=observed6, peer=peer, peer_ipv6=peer6, failed_dial=failed, peer_loss=lost, incoming_failure=incoming, incoming_expiry=expiry, incoming_teardown=teardown)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Collector failures remain visible while process finalizers retire every live child.
            observed = dict(passed=False, failure=repr(error), traceback=traceback.format_exc())
            print(observed['traceback'], flush=True) # Preserve the scenario and assertion in CI console output.
    announce('JIP-3 telemetry registration/status/reconnect', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.setup
def prepare_integrated_peer(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    build = context.checks.build
    compiler = context.compiler
    crypto_library = context.crypto
    quic_library = context.quic
    compiled, binary = build(compiler, ROOT/'src/ragnarok.nim', 'ragnarok-integration', crypto_library,
                             native_libraries=(context.bs,), quic_library=quic_library, defines=('integration',))
    context.integrated = compiled, binary


# Preserve this task and its original checks in dependency order.
@PLAN.selftest(group='transport', requires=('prepare_integrated_peer',))
def quic_peer_integration(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    return peer_selftest(context, context.integrated, '--integration-selftest', 'quic-peer-integration-selftest')


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_peer',))
def quic_service(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    report = context.report
    quic_fixtures = context.certificates
    observed = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_service import service as retained_service
        try:
            # One server engine survives sixteen waves, including malformed peers and two forced peer deaths.
            result = retained_service('nim', quic_fixtures, 16, 4, binaries={'nim': context.peer[1]},
                                      directory=BUILD/'retained-service')
            observed = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Finalizers preserve logs and retire children; failure cannot be replaced by later integration success.
            observed = dict(passed=False, failure=str(error))
    announce('retained CE 143 service lifecycle', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_integrated_peer',))
def quic_integration_service(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    quic_fixtures = context.certificates
    integration_wires = context.wires
    compiled, binary = context.integrated
    observed = dict(passed=False)
    if compiled['exit_code'] == 0:
        from test_integration import service as integrated_service
        try:
            # Three concurrent identities per wave exercise real capture/hash/copy/cancellation owners.
            result = integrated_service('nim', quic_fixtures, integration_wires, 12, 4,
                                        binaries={'nim': binary}, directory=BUILD/'retained-integration')
            observed = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Typed protocol rejections are checked by the harness; assertion/timeouts remain workload failures.
            observed = dict(passed=False, failure=str(error))
    announce('retained integrated digest lifecycle', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_peer',))
def quic_mesh(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    report = context.report
    quic_fixtures = context.certificates
    observed = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_mesh import pairing as mesh_pairing
        try:
            # Reuse exact original rounds, warmup, wrong-identity gate and finite resource limits.
            result = mesh_pairing(('nim', 'nim'), quic_fixtures, 16, 4,
                                  binaries={'nim': context.peer[1]}, directory=BUILD/'mesh')
            bad_pin = mesh_pairing(('nim', 'nim'), quic_fixtures, 1, 0, bad_pin=True,
                                   binaries={'nim': context.peer[1]}, directory=BUILD/'mesh-bad-pin')
            observed = dict(passed=True, result=result, bad_pin=bad_pin)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # All live endpoints retire in harness finalizers; a failed arbitration remains a failed gate.
            observed = dict(passed=False, failure=str(error))
    announce('retained IPv6 mesh/reconnect and wrong identity', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_peer',))
def quic_mesh_disruption(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    report = context.report
    quic_fixtures = context.certificates
    observed = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_resilience import disruption as mesh_disruption
        try:
            # One keeper retains its two engines through twelve killed peers and a final healthy generation.
            result = mesh_disruption(('nim', 'nim'), quic_fixtures, 12, 4,
                                     binaries={'nim': context.peer[1]}, directory=BUILD/'mesh-disruption')
            observed = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Recovery must settle all eight pending operations before reconnect; ordinary mesh success cannot hide failure.
            observed = dict(passed=False, failure=str(error))
    announce('retained IPv6 peer-death recovery', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_peer',))
def quic_endpoint_soak(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    report = context.report
    quic_fixtures = context.certificates
    observed = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_soak import pairing as endpoint_soak
        try:
            # Preserve the original forty sessions, eight warmup samples, mixed streams and finite budgets.
            result = endpoint_soak('nim', 'nim', quic_fixtures, 40, 8,
                                   binaries={'nim': context.peer[1]}, directory=BUILD/'endpoint-soak')
            observed = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Finalizers retain resource evidence and kill live peers; later corpus success cannot hide failure.
            observed = dict(passed=False, failure=str(error))
    announce('same-process endpoint teardown soak', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_peer',))
def quic_admission(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    report = context.report
    quic_fixtures = context.certificates
    observed = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_resilience import overload as admission
        try:
            # Keep the original twelve waves/four warmup samples and exact connection/stream ceilings.
            result = admission('nim', quic_fixtures, 12, 4, binaries={'nim': context.peer[1]},
                               directory=BUILD/'admission')
            observed = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # Capacity rejection must recover within the original deadlines and release all retained owners.
            observed = dict(passed=False, failure=str(error))
    announce('connection/stream admission recovery', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_peer',))
def quic_closed_before_request(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    report = context.report
    quic_fixtures = context.certificates
    observed = dict(passed=False)
    if report['quic_peer_build']['exit_code'] == 0:
        from test_quic_resilience import closed_before_request
        try:
            # Idle clients open no application streams; connection close must settle the authenticated failure.
            result = closed_before_request(('nim', 'nim'), quic_fixtures,
                                           binaries={'nim': context.peer[1]}, directory=BUILD/'closed-before-request')
            observed = dict(passed=True, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # A stale AUTH_OK marker cannot turn connection loss into successful application exchange.
            observed = dict(passed=False, failure=str(error))
    announce('authenticated connection loss before request', observed['passed'])
    return observed


# Preserve this task and its original checks in dependency order.
@PLAN.setup
def prepare_offload_peer(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    build = context.checks.build
    compiler = context.compiler
    report = context.report
    crypto_library = context.crypto
    bs_library = context.bs
    quic_library = context.quic
    from test_quic_offload import corpus as offload_fixture
    offload_wire, offload_metadata = offload_fixture(BUILD/'offload')
    compiled, binary = build(compiler, ROOT/'src/ragnarok.nim', 'ragnarok-offload', crypto_library,
                             native_libraries=(bs_library,), quic_library=quic_library, defines=('offload',))
    report['quic_offload_build'] = compiled
    context.offload = compiled, binary
    context.offload_wire, context.offload_metadata = offload_wire, offload_metadata
    context.offload_failed = False


# The direct offload harness owns these callables; import registration does not run native work.
sys.path.insert(0, str(ROOT/'tests'))
from test_quic_offload import OFFLOAD_SELFTESTS


def run_offload_selftest(function, context):
    """Keep direct and cumulative selftests identical and preserve stop-on-first-failure behavior."""
    compiled, binary = context.offload
    row = dict(build=compiled, passed=False)
    if compiled['exit_code'] == 0 and not context.offload_failed:
        try:
            # The original helper enforces exact markers, timeout and joined shutdown.
            row.update(function(binary, context.offload_wire, context.checks.folder/'offload'))
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            context.offload_failed = True
            row['failure'] = str(error)
    return row


PLAN.include_selftests(OFFLOAD_SELFTESTS, run_offload_selftest,
                      group='transport', requires=('prepare_offload_peer',))

# Preserve this task and its original checks in dependency order.
@PLAN.workload(group='transport', requires=('prepare_offload_peer',))
def quic_offload(context):
    """Execute the owning E2E task; failed prerequisites remain explicit failures."""
    BUILD = context.checks.folder
    quic_fixtures = context.certificates
    compiled, binary = context.offload
    from test_quic_offload import exercise as offload_exercise
    offload_wire, offload_metadata = context.offload_wire, context.offload_metadata
    observed = dict(passed=False, fixture=offload_metadata)
    if compiled['exit_code'] == 0 and not context.offload_failed:
        try:
            # Ten waves preserve two workers, four job slots and 128 real verifications per accepted job.
            result = offload_exercise('nim', quic_fixtures, offload_wire, 10, 2, 128,
                                      binaries={'nim': binary}, directory=BUILD/'offload')
            observed = dict(passed=True, fixture=offload_metadata, result=result)
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            # A selftest, callback, resource or joined-shutdown failure cannot be hidden by another workload.
            observed = dict(passed=False, fixture=offload_metadata, failure=str(error))
    announce('bounded proof offload and joined shutdown', observed['passed'])
    return observed


# Explicit prerequisites remain ordered tasks; names and expected verdicts come from the same plan.
def run(compiler, crypto_library, bs_library, quic_library, quic_fixtures, integration_wires, report, checks, group=None):
    """Run every declared task once with this invocation's binaries and fixture ownership."""
    context = SimpleNamespace(compiler=compiler, crypto=crypto_library, bs=bs_library,
                              quic=quic_library, certificates=quic_fixtures,
                              wires=integration_wires, report=report, checks=checks)
    PLAN.select(group).run(context)
