#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run compiler contract, privacy, nominal, schema and ownership rejection checks independently."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
from native_checks import NativeChecks, ROOT, announce
from native_tests import unit_jobs
from setup_nimony import cache_directory
from verification_inventory import PRIVATE, NOMINAL, CONTRACTS, EARLY_NOMINAL

BUILD = ROOT/'build/tests/guards'
checks = NativeChecks(BUILD)
command, build = checks.command, checks.build
COUNTS = dict(privacy=len(PRIVATE), nominal=len(NOMINAL), contracts=len(CONTRACTS),
              schemas=5, ownership_compile=3)


# Missing, duplicated or failed checks cannot be replaced by a successful sibling group.
def passed(report):
    return all(len(report.get(key, [])) == count
               and len({row['name'] for row in report[key]}) == count
               and all(row['passed'] for row in report[key]) for key, count in COUNTS.items())


# Compile independent rejection probes in private caches; consume results in original registry order.
def compile_rejections(compiler, expectations):
    # A worker owns one compiler process, output log and cache; diagnostic interpretation stays on the caller.
    def check(item):
        name, expected = item
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{cache_directory(compiler, BUILD, name)}',
                          ROOT/f'tests/native/compile_fail/{name}.nim'], name)
        return name, expected, result

    with ThreadPoolExecutor(max_workers=unit_jobs()) as executor:
        # Ordered consumption preserves the historical evidence layout even when processes finish out of order.
        yield from executor.map(check, expectations.items())


# Keep the original diagnostics and lowering checks in this group's private workspace.
def run(compiler, bs_library, report):
    # Closed family checks and direct static scalar contracts reject unsupported schemas before execution.
    for name, domain in (('unsupported_collection_scalar', 'string'),
                         ('negative_collection_width', 'CollectionUInt'), ('wide_collection_width', 'CollectionUInt'),
                         ('scalar_collection_negative_width', '-1'), ('scalar_collection_wide_width', '9')):
        result = command([compiler, 'check', '--mm:arc', '--cc:clang',
                          f'--nimcache:{cache_directory(compiler, BUILD, name)}', ROOT/f'tests/native/compile_fail/{name}.nim'], name)
        if name.startswith('scalar_collection_'):
            # Constant-invalid direct helper calls fail at the supported precondition during compilation.
            rejected = ('Error: contract violated:' in result['output']
                        and '0 <= '+domain+' and '+domain+' <= 8' in result['output'])
        else:
            # No unsupported mutable schema or E width can instantiate a collection decoder.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'does not match constraint' in result['output'] and domain in result['output']
                        and 'decodeVariableSet(' in result['output'])
        passed = result['exit_code'] != 0 and rejected
        report['schemas'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    # Unique socket ownership is checked by lowering/code generation, not by semantic checking alone.
    compiled, _ = build(compiler, ROOT/'tests/native/compile_fail/quic_io_endpoint_copy.nim', 'quic-endpoint-copy')
    passed = compiled['exit_code'] != 0 and "'=dup' is not available for type <UdpEndpoint>" in compiled['output']
    report['ownership_compile'].append(dict(name='quic_io_endpoint_copy', passed=passed, check=compiled))
    announce('unique UDP endpoint copy rejection', passed)
    # Telemetry's composite socket/queue owner must independently reject copies during lowering.
    compiled, _ = build(compiler, ROOT/'tests/native/compile_fail/telemetry_client_copy.nim', 'telemetry-client-copy')
    rejected = compiled['exit_code'] != 0 and "'=dup' is not available for type <Client>" in compiled['output']
    report['ownership_compile'].append(dict(name='telemetry_client_copy', passed=rejected, check=compiled))
    announce('unique telemetry client copy rejection', rejected)
    # RawThread membership alone did not reject pool copies; the exported pool-level contract must reject during lowering.
    compiled, _ = build(compiler, ROOT/'tests/native/compile_fail/offload_pool_copy.nim', 'offload-pool-copy',
                        native_libraries=(bs_library,), defines=('offload',))
    passed = compiled['exit_code'] != 0 and "'=dup' is not available for type <OffloadPool>" in compiled['output']
    report['ownership_compile'].append(dict(name='offload_pool_copy', passed=passed, check=compiled))
    announce('unique offload pool copy rejection', passed)
    # Compile-time proven contract violations are recorded separately from runtime guards and privacy/schema rejections.
    rejection_started = time.monotonic()
    report['compiler_rejection_jobs'] = unit_jobs()
    for name, sentinel, result in compile_rejections(compiler, CONTRACTS):
        passed = result['exit_code'] != 0 and 'Error: contract violated: '+sentinel in result['output']
        report['contracts'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    # Raw storage, retagging, success forgery and writing the public reason must all fail compilation.
    for name, member, result in compile_rejections(compiler, PRIVATE):
        if name == 'private_collection_commit':
            # Generic concept support must never export the unchecked writer.
            rejected = "undeclared identifier: 'put'" in result['output']
        elif name.startswith('session_'):
            # Moving the implementation into a module must not export raw owners or callback/buffer helpers.
            rejected = ("undeclared identifier in module: '"+member+"'") in result['output']
        elif name == 'wrong_owner_pool':
            # The second argument must be an index, never a replacement source buffer.
            rejected = 'Type mismatch' in result['output'] and '[2] expected: int64 but got: array' in result['output']
        else:
            # Every raw-state bypass must fail for its private/read-only member.
            rejected = ('undeclared field' in result['output'] or 'cannot assign' in result['output']
                        or 'cannot be assigned' in result['output'])
        passed = result['exit_code'] != 0 and member in result['output'] and rejected
        report['privacy'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    # Report and assurance identity, index and configuration domains must remain statically distinct under Nimony.
    for name, member, result in compile_rejections(compiler, NOMINAL):
        if name == 'bs_key_as_setup':
            # Scalar owners cannot select the allocator/domain of a native ring setup.
            rejected = 'Error: Type mismatch at [position]' in result['output'] and 'commitRing(' in result['output'] and member in result['output']
        elif name in EARLY_NOMINAL:
            # Require the intended domain rejection, not unrelated syntax, initialization or import failures.
            call, diagnostic = EARLY_NOMINAL[name]
            rejected = 'Error: Type mismatch at [position]' in result['output'] and call in result['output'] and diagnostic in result['output']
        elif name in ('state_key_as_hash', 'state_partial_as_hash', 'state_value_as_node_hash', 'state_root_as_node'):
            # A key, truncated left commitment or value hash cannot fill a complete child-hash argument.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'encodeStateBranch(' in result['output']
                        and '[1] expected: StateNodeHash but got: '+member in result['output'])
        elif name in ('composition_service_as_entry', 'composition_service_as_chapter_index'):
            # Service identities cannot address a whole-map entry or the fixed nominal chapter container.
            rejected = 'Error: Type mismatch at [position]' in result['output'] and member in result['output']
        elif name in ('request_length_as_slot', 'request_slot_as_length'):
            # Slot and advertised-length domains stay distinct through safe source constructors and key derivation.
            call, position, actual = (('availableHistory(', 1, 'RequestLength') if name == 'request_length_as_slot'
                                      else ('serviceRequestKey(', 3, 'RequestSlot'))
            rejected = ('Error: Type mismatch at [position]' in result['output'] and call in result['output']
                        and f'[{position}] expected: {member} but got: {actual}' in result['output'])
        elif name in ('service_value_code_as_preimage', 'service_value_hash_as_key'):
            # Equal-purpose hashes and final trie keys retain distinct nominal identities and widths.
            call, position, actual = (('servicePreimageKey(', 2, 'CodeHash') if name == 'service_value_code_as_preimage'
                                      else ('captureServiceValue(', 2, 'ServicePreimageHash'))
            rejected = ('Error: Type mismatch at [position]' in result['output'] and call in result['output']
                        and f'[{position}] expected: {member} but got: {actual}' in result['output'])
        elif name == 'output_service_as_index':
            # Protocol service identities cannot address a retained sequence position.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'outputLogAt(' in result['output']
                        and '[2] expected: '+member+' but got: ServiceIndex' in result['output'])
        elif name.startswith('workqueue_'):
            # Nominal row/item/hash positions and owner kinds cannot be substituted.
            rejected = 'Error: Type mismatch at [position]' in result['output'] and member in result['output']
        elif name == 'statistics_gas_as_counter':
            # A nominal natural gas value cannot fill an E4 validator array element, even for small numeric values.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and '[3] expected: ValidatorCounter but got: '+member in result['output'])
        elif name == 'statistics_service_as_core':
            # Service dictionary ordinals cannot select core statistics.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'coreActivityAt(' in result['output']
                        and '[2] expected: StatisticsCoreIndex but got: '+member in result['output'])
        elif name == 'privilege_entry_as_core':
            # Always-accumulate dictionary ordinals cannot select a core assigner.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'privilegeAssignerAt(' in result['output']
                        and '[2] expected: PrivilegeCoreIndex but got: '+member in result['output'])
        elif name in ('assignment_guarantee_slot', 'assignment_validator_as_core'):
            # Guarantee evaluation time and guarantor indices cannot fill registration/core domains.
            call, position, expected = (('presentAssignment(', 2, 'AssignmentSlot') if name == 'assignment_guarantee_slot'
                                        else ('availabilityAt(', 2, 'AssignmentCoreIndex'))
            rejected = ('Error: Type mismatch at [position]' in result['output'] and call in result['output']
                        and '['+str(position)+'] expected: '+expected+' but got: '+member in result['output'])
        elif name == 'history_block_as_peak':
            # Recent block ordinals cannot select an MMR belt peak.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'historyPeakAt(' in result['output']
                        and '[2] expected: HistoryPeakIndex but got: '+member in result['output'])
        elif name == 'state_bytes_as_dispute_index':
            # Byte budgets cannot substitute for ordinals in the offender set.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'stateOffenderAt(' in result['output']
                        and '[2] expected: DisputeStateIndex but got: '+member in result['output'])
        elif name == 'state_validator_as_slot':
            # Pending validator ordinals cannot fill the distinct schedule-slot argument.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'sealerTicketAt(' in result['output']
                        and '[2] expected: SafroleStateIndex but got: '+member in result['output'])
        elif name == 'auth_core_as_position':
            # Core ordinals cannot fill the distinct per-row hash-position argument.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'authorizerAt(' in result['output']
                        and '[3] expected: AuthorizationIndex but got: '+member in result['output'])
        elif name == 'state_entropy_as_time':
            # Fixed entropy words cannot fill the E4 timeslot argument despite both being copied values.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'timeEntry(' in result['output']
                        and '[1] expected: StateTime but got: '+member in result['output'])
        elif name == 'swapped_import_identity':
            # The typed factory rejection prints generic ReportHash without its static domain; require its exact call/position.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and 'rootImport(' in result['output'] and member in result['output'])
        elif name in ('raw_bit_count', 'swapped_bit_limit', 'raw_collection_count',
                      'swapped_collection_schema', 'dictionary_as_set'):

            # The second parameter must retain its logical-bit domain, independently of array-view diagnostics.
            call = dict(raw_bit_count='decodeFixedBits(', swapped_bit_limit='decodeBits(',
                        raw_collection_count='decodeSet(', swapped_collection_schema='encodeOwnedVariableSet(',
                        dictionary_as_set='setCount(')[name]
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and call in result['output'] and member in result['output'])
        elif name in ('unsigned_as_full_header', 'block_as_extrinsic'):
            # Sealed output accepts only the full owner type, never a signing-only retained view.
            rejected = ('Error: Type mismatch at [position]' in result['output']
                        and ('extrinsicInfo(' if name == 'block_as_extrinsic' else 'encodeOwnedHeader(') in result['output']
                        and member in result['output'])
        else:
            # Other nominal fields provide precise got/wanted domain names.
            rejected = 'Error: type mismatch: '+member in result['output']
        passed = result['exit_code'] != 0 and rejected
        report['nominal'].append(dict(name=name, passed=passed, check=result))
        announce(name, passed)
    report['compiler_rejections_elapsed_seconds'] = round(time.monotonic()-rejection_started, 6)


# Provision only this group's native ownership dependency and retain a fresh failure report on exceptions.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    compiler = parser.parse_args().compiler.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'results.json').unlink(missing_ok=True)
    started = time.monotonic()
    report = dict(status='failed', **{key: [] for key in COUNTS},
                  environment=dict(system=platform.system(), machine=platform.machine(),
                                   python=platform.python_version()))
    try:
        # Every standalone run records its own compiler, project and fixture identities.
        report['compiler'] = command([compiler, '--version'], 'compiler')
        metadata = compiler.parent.parent/'NIGHTLY.txt'
        report['nightly_metadata'] = metadata.read_text() if metadata.is_file() else None
        report['project_revision'] = command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
        sources = [Path(__file__), ROOT/'tools/verification_inventory.py', ROOT/'tools/verification_inventory.json', ROOT/'tools/native_checks.py', ROOT/'tools/native_dependencies.py', ROOT/'tools/build_crypto.py', ROOT/'tools/build_bandersnatch.py', ROOT/'tools/build_quic.py',
                   ROOT/'spec/toolchain.json', ROOT/'spec/bandersnatch-pins.json',
                   *sorted((ROOT/'tests/native/compile_fail').glob('*.nim'))]
        report['sources'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in sources}
        sys.path.insert(0, str(ROOT/'tests'))
        from bandersnatch_native import prepare
        library, _, report['bandersnatch_native'] = prepare(BUILD)
        run(compiler, library, report)
        report['status'] = 'checks-passed' if passed(report) else 'failed'
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        # A failed setup/compiler invocation must remain visible and cannot reuse stale green evidence.
        report['failure'] = repr(error)
    finally:
        # Preserve partial diagnostics even if preparation or a compiler times out.
        report['elapsed_seconds'] = round(time.monotonic()-started, 6)
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    announce('Compiler rejection guards', report['status'] == 'checks-passed')
    print('Evidence: '+str(BUILD.relative_to(ROOT)/'results.json'))
    raise SystemExit(0 if report['status'] == 'checks-passed' else 1)


# Importing the guard inventory never provisions dependencies or invokes the compiler.
if __name__ == '__main__':
    main()
