# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Own dedicated JAM fuzz setup and socket/minifuzz checks without registering E2E workloads."""
import subprocess
import traceback
from native_checks import ROOT
from e2e_checks import prepare_peer


def prepare_fuzzer_policy(context):
    """Build only native test resource-policy materialization; expected protocol data remains independent."""
    context.fuzzer_policy = context.checks.build(context.compiler,
        ROOT/'tests/native/jam_fuzzer_target_policy.nim', 'jam-fuzzer-target-policy',
        crypto_library=context.crypto, native_libraries=(context.bs,), quic_library=context.quic)


def application_fuzzer_interface(context):
    """Run the real application startup, socket STF exchange and complete-state comparison."""
    compiled, binary = context.peer
    policy_build, policy = context.fuzzer_policy
    if compiled['exit_code'] != 0 or policy_build['exit_code'] != 0:
        return dict(passed=False, failure='fuzzer interface prerequisite build')
    from nimony_fuzz import exercise
    try:
        return exercise(binary, policy, context.checks.folder)
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        return dict(passed=False, failure=repr(error), traceback=traceback.format_exc())


def prepare_minifuzz(context):
    """Resolve pristine hash-pinned upstream codecs without installers or global package changes."""
    from setup_jam_minifuzz import prepare
    context.minifuzz = prepare()


def application_minifuzz_interface(context):
    """Require strict full-map interoperability through the unmodified upstream minifuzz process."""
    compiled, binary = context.peer
    policy_build, policy = context.fuzzer_policy
    if compiled['exit_code'] != 0 or policy_build['exit_code'] != 0:
        return dict(passed=False, failure='minifuzz prerequisite build')
    from nimony_minifuzz import exercise
    try:
        script, environment = context.minifuzz
        return exercise(binary, policy, script, environment, context.checks.folder)
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        return dict(passed=False, failure=repr(error), traceback=traceback.format_exc())
