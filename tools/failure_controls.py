# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Register specialized failure controls beside their case plans and exact runtime predicates.

Exposes CONTROLS, FailureContext and SpecializedControls. Handler order, source ownership and
expected identities are checked before execution; native resource setup remains with the caller.
"""
from dataclasses import dataclass
import os
from pathlib import Path
import re
from failure_checks import probe_failure
from failure_drivers import SPECIAL_DRIVERS, driver_modes, check_driver_modes
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]


# Explicit runtime inputs keep specialized handlers independent of launcher globals.
@dataclass
class FailureContext:
    """Compiler, callbacks, libraries and independent fixtures for one specialized-control run."""
    compiler: Path
    report: dict
    libraries: dict
    build: object
    command: object
    folder: Path
    availability_fixture: Path | None
    composition_fixture: Path | None


# Expected identities and diagnostics belong to the registered handler, independently of run results.
@dataclass(frozen=True)
class FailureControl:
    """One ordered specialized handler with its complete pre-execution plan and optional typed source."""
    name: str
    order: int
    function: object
    cases: tuple
    fields: tuple
    source: Path | None

    # Preserve each family's identity shape without a central family-name conditional.
    def identities(self):
        """Return expected report identities in original case order."""
        return [dict(zip(self.fields, row[:len(self.fields)])) for row in self.cases]


# Handlers register at definition sites; discovered driver declarations supply their source identities.
class SpecializedControls:
    """Derive specialized scheduling and completeness expectations from source-owned handlers."""
    def __init__(self, drivers):
        """Retain an explicit source-discovery snapshot without executing any handler."""
        self.drivers = drivers
        self.controls = {}

    # A typed driver uses a source-based planner; language/resource controls declare their cases locally.
    def case(self, *, order, plan, driver=False, fields=('member', 'origin')):
        """Register one callable and validate its ordered expected identities before execution."""
        if (type(order) is not int or order < 1 or type(driver) is not bool or not callable(plan)
                or not isinstance(fields, tuple) or not fields
                or any(not isinstance(field, str) or re.fullmatch(r'[a-z][a-z0-9_]*', field) is None
                       for field in fields) or len(fields) != len(set(fields))):
            raise ValueError('Invalid specialized failure metadata')

        # Callable names supply family IDs rather than a parallel handler-name list.
        def register(function):
            match = re.fullmatch(r'run_([a-z][a-z0-9_]*)', function.__name__)
            if match is None or match[1] in self.controls:
                raise ValueError('Invalid or duplicate specialized failure handler')
            name = match[1]
            if any(control.order == order for control in self.controls.values()):
                raise ValueError('Duplicate specialized failure order')
            source = self.drivers.get(name) if driver else None
            if driver and source is None:
                raise ValueError('Missing specialized failure driver: '+name)
            cases = plan(source) if driver else plan()
            if (not isinstance(cases, (tuple, list)) or not cases
                    or any(not isinstance(row, (tuple, list)) or len(row) < len(fields) for row in cases)):
                raise ValueError('Invalid specialized failure case plan: '+name)
            control = FailureControl(name, order, function, tuple(cases), fields, source)
            identities = control.identities()
            if any(identity in identities[:index] for index, identity in enumerate(identities)):
                raise ValueError('Duplicate specialized failure identity: '+name)
            self.controls[name] = control
            return function
        return register

    # Discovering a driver must never count as coverage without a corresponding executable handler.
    def validate_drivers(self):
        """Require exact agreement between marked typed sources and registered driver handlers."""
        actual = {name: control.source for name, control in self.controls.items() if control.source is not None}
        if actual != self.drivers:
            raise ValueError('Specialized failure handlers must cover exactly the discovered drivers')

    # Numeric ranks preserve the established dependency and resource ordering without a call list.
    def run(self, context):
        """Run every registered control once; propagate failures before later controls execute."""
        self.validate_drivers()
        for control in sorted(self.controls.values(), key=lambda item: item.order):
            control.function(context, control)


# Default/error result access shares one typed-mode expansion across the ordinary specialized drivers.
def default_error_cases(source):
    """Retain original origin-major ordering and exact guarded-value diagnostics."""
    return [(mode, origin, 'value.status == None')
            for origin in ('default', 'error') for mode in driver_modes(source)]


# Absence probes retain their additional origins and precondition rather than using generic crash acceptance.
def availability_cases(source):
    """Plan result-access and inactive-assignment checks from the declared typed modes."""
    modes = driver_modes(source)
    return ([(mode, origin, 'value.status == None') for origin in ('default', 'error')
             for mode in modes if not mode.startswith('absent-')]
            +[(mode, origin, 'assignment.isPresent') for origin in ('default', 'source', 'decoded')
              for mode in modes if mode.startswith('absent-')])


# The instance is populated by the following handler declarations, never a family-name registry.
CONTROLS = SpecializedControls(SPECIAL_DRIVERS)


# Preserve the original store build profile, positive controls and per-process failure predicates.
@CONTROLS.case(order=10, plan=lambda: ([(member, origin, 'outcome.status == None')
    for member in ('store', 'snapshot', 'lookup') for origin in ('default', 'error')]
    +[('fork', 'default', 'outcome.status == None'),
      ('metadata', 'default', 'not snapshot.data == nil'),
      ('length', 'default', 'not view.owner.data == nil'),
      ('bytes', 'default', 'not view.owner.data == nil')]))
def run_store(context, control):
    compiler, report = context.compiler, context.report
    build, command = context.build, context.command
    crypto_library = context.libraries['crypto']
    # Public store payloads/views require their own contracts, independent of ordinary success suites.
    compiled, binary = build(compiler, ROOT/'tests/native/state_store_results.nim', 'state-store-results', crypto_library)
    report['store_build'] = compiled
    report['store_controls'] = dict(passed=False)
    if compiled['exit_code'] == 0:
        # Actual and default failures cover every public generic payload family.
        cases = control.cases
        for member, origin, sentinel in cases:
            # Match the supported precondition and exit status, never an unrelated crash or fixture error.
            probe_failure(command, report['store'], [binary, member, origin],
                          'store-' + member + '-' + origin, sentinel,
                          'store ' + member + ' ' + origin + ' runtime guard', member=member, origin=origin)
        controls = {member: command([binary, member, 'valid'], 'store-'+member+'-valid')
                    for member in ('metadata', 'length', 'bytes')}
        report['store_controls'] = dict(checks=controls,
            passed=all(row['exit_code'] == 0 and row['output'].strip() == ('1' if member == 'metadata' else '0')
                       for member, row in controls.items()))


# Preserve the original bandersnatch build profile, positive controls and per-process failure predicates.
@CONTROLS.case(order=20, plan=default_error_cases, driver=True)
def run_bandersnatch(context, control):
    compiler, report = context.compiler, context.report
    build, command = context.build, context.command
    from bandersnatch_native import OWNER_DEFINES
    bs_libraries = (context.libraries['bandersnatch_observer'], context.libraries['bandersnatch'])
    # Actual/default result access must reject for every fixed proof/output, sequence and opaque native owner.
    compiled, binary = build(compiler, control.source, 'bandersnatch-results',
                             native_libraries=bs_libraries, cflags=OWNER_DEFINES)
    report['bandersnatch_build'] = compiled
    if compiled['exit_code'] == 0:
        # Separate processes prevent prior contract failures or test-observer flags from concealing later checks.
        check_driver_modes(command, binary, control.name, report)
        for member, origin, sentinel in control.cases:
            # Each declared mode and failure origin retains its own process and supported diagnostic.
            probe_failure(command, report['bandersnatch'], [binary, member, origin],
                          'bs-' + origin + '-' + member, sentinel,
                          origin + ' Bandersnatch ' + member + ' runtime guard', origin=origin, member=member)


# Preserve the original offload build profile, positive controls and per-process failure predicates.
@CONTROLS.case(order=30, plan=lambda: [(enabled, origin) for enabled in (False, True) for origin in ('default', 'empty')], fields=('enabled', 'origin'))
def run_offload(context, control):
    compiler, report = context.compiler, context.report
    build, command = context.build, context.command
    bs_library = context.libraries['bandersnatch']
    BUILD = context.folder
    # Completion guards need only their public fixture, not the E2E network/soak workloads.
    from test_quic_offload import corpus as offload_fixture
    offload_wire, _ = offload_fixture(BUILD/'offload-fixture')
    # The same guarded completion API must reject defaults and actual empty polls in both build profiles.
    for enabled in (False, True):
        compiled, binary = build(compiler, ROOT/'tests/native/nimony_offload_results.nim',
                                 'offload-results-'+str(enabled), native_libraries=(bs_library,) if enabled else (),
                                 defines=('offload',) if enabled else ())
        report['offload_results_'+str(enabled)] = compiled
        if compiled['exit_code'] == 0:
            # Enabled empty-poll probes start and join their own workers before attempting the invalid read.
            for selected, origin in control.cases:
                # Each enabled/disabled build executes only its own planned origins.
                if selected != enabled:
                    continue
                environment = {**os.environ, 'RAGNAROK_OFFLOAD_FIXTURE': str(offload_wire),
                               'RAGNAROK_OFFLOAD_REPEATS': '1', 'RAGNAROK_OFFLOAD_GATE': ''}
                probe_failure(command, report['offload'], [binary, origin],
                              'offload-result-' + str(enabled) + '-' + origin, 'value.hasCompletion',
                              'offload ' + str(enabled) + ' ' + origin + ' completion runtime guard', environment=environment, enabled=enabled, origin=origin)


# Preserve the original runtime build profile, positive controls and per-process failure predicates.
@CONTROLS.case(order=40, plan=lambda: [('assertion', 'trial assertion sentinel', 1), ('bounds', '[AssertionDefect]', 1),
                  ('wrapping', '-9223372036854775808', 0)], fields=('name',))
def run_runtime(context, control):
    compiler, report = context.compiler, context.report
    build, command = context.build, context.command
    # Wrapping is the accepted Nimony language policy; assertions and bounds must still reject.
    compiled, binary = build(compiler, ROOT/'tests/native/nimony_runtime_guards.nim', 'runtime')
    report['runtime_build'] = compiled
    if compiled['exit_code'] == 0:
        # Every observation is separate so a prior assertion failure cannot conceal wrapping behavior.
        for mode, sentinel, expected_exit in control.cases:
            result = command([binary, mode], mode+'-runtime')
            passed = result['exit_code'] == expected_exit and sentinel in result['output']
            report['runtime'].append(dict(name=mode, passed=passed, run=result))
            announce(mode+' behavior', passed)


# Preserve the original availability build profile, positive controls and per-process failure predicates.
@CONTROLS.case(order=50, plan=availability_cases, driver=True)
def run_availability(context, control):
    compiler, report = context.compiler, context.report
    build, command = context.build, context.command
    crypto_library = context.libraries['crypto']
    availability_fixture = context.availability_fixture
    # Every public/private result and each inactive assignment field must retain its exact contract.
    compiled, binary = build(compiler, control.source, 'availability-results', crypto_library)
    report['availability_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures and dynamic absence origins execute independently, retaining their own diagnostics.
        check_driver_modes(command, binary, control.name, report)
        cases = control.cases
        for member, origin, sentinel in cases:
            probe_failure(command, report['availability'], [binary, member, origin, availability_fixture],
                          'availability-' + origin + '-' + member, sentinel,
                          origin + ' availability ' + member + ' runtime guard', origin=origin, member=member)


# Preserve the original workqueues build profile, positive controls and per-process failure predicates.
@CONTROLS.case(order=60, plan=default_error_cases, driver=True)
def run_workqueues(context, control):
    compiler, report = context.compiler, context.report
    build, command = context.build, context.command
    crypto_library = context.libraries['crypto']
    availability_fixture = context.availability_fixture
    # Both queue domains and internal count/layout proofs require successful payload selection.
    compiled, binary = build(compiler, control.source, 'workqueues-results', crypto_library)
    report['workqueues_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual/default failures execute separately so one rejected access cannot conceal another.
        check_driver_modes(command, binary, control.name, report)
        for member, origin, sentinel in control.cases:
            # Execute every declared access in its own process with the original failure expectation.
            probe_failure(command, report['workqueues'], [binary, member, origin, availability_fixture],
                          'workqueues-' + origin + '-' + member, sentinel,
                          origin + ' workqueues ' + member + ' runtime guard', origin=origin, member=member)


# Preserve the original composition build profile, positive controls and per-process failure predicates.
@CONTROLS.case(order=70, plan=default_error_cases, driver=True)
def run_composition(context, control):
    compiler, report = context.compiler, context.report
    build, command = context.build, context.command
    crypto_observer = context.libraries['observer']
    composition_fixture = context.composition_fixture
    # Complete composition payloads require exact success, including backend and association failures.
    compiled, binary = build(compiler, control.source, 'composition-results', crypto_observer)
    report['composition_build'] = compiled
    if compiled['exit_code'] == 0:
        # Actual and default failures execute separately so one protected read never conceals another.
        check_driver_modes(command, binary, control.name, report)
        for member, origin, sentinel in control.cases:
            # Execute every declared access in its own process with the original failure expectation.
            probe_failure(command, report['composition'], [binary, member, origin, composition_fixture],
                          'composition-' + origin + '-' + member, sentinel,
                          origin + ' composition ' + member + ' runtime guard', origin=origin, member=member)


# Reject a source added without a handler, or a handler whose source was deleted, during preflight.
CONTROLS.validate_drivers()
