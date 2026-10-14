#!/usr/bin/env python3
"""Build pinned isolated QUIC dependencies and verify authenticated JAMNP-S CE 143 peers."""
import argparse
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import tarfile
import time
import urllib.request
from toolchain_checks import odin_matches

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/quic'
PINS = json.loads((ROOT / 'spec/quic-proof-pins.json').read_text())


# Run structured commands without shell interpolation; append diagnostics to a retained reproducible build log.
def run(args, log=None):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, stdout=log, stderr=log)


# Fetch an exact immutable source commit, stripping only the archive root and checking extraction safety.
def fetch_source(entry, destination):
    archive = urllib.request.urlopen(
        f'https://codeload.github.com/{entry["repository"]}/tar.gz/{entry["commit"]}', timeout=60).read()
    destination.mkdir(parents=True, exist_ok=True)
    # Safe tar extraction rejects escaping paths/links; no upstream package hook is run.
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
        for member in tar.getmembers():
            parts = Path(member.name).parts
            if len(parts) > 1:
                member.name = str(Path(*parts[1:]))
                tar.extract(member, destination, filter='data')
    (destination / '.ragnarok-source.json').write_text(json.dumps(
        {**entry, 'archive_sha256': hashlib.sha256(archive).hexdigest()}, indent=2) + '\n')


# Apply only four explicit typed-error conversions; preserve upstream exceptions and leave version/compiler pins unchanged.
def patch_chronos(source):
    for name in ('datagram', 'stream'):
        path = source / f'chronos/transports/{name}.nim'
        text = path.read_text()
        # Match the reviewed original or already-patched body, never guess a changed upstream function.
        for kind in ('local', 'remote'):
            original = f'  {kind}Address2(transp).tryGet()'
            replacement = (f'  let checked = {kind}Address2(transp)\n'
                           '  if checked.isErr:\n    raise getTransportOsError(checked.error)\n  checked.get()')
            if original in text:
                text = text.replace(original, replacement)
            else:
                assert replacement in text, path
        path.write_text(text)


# Avoid retaining an async frame containing its own stream through a scheduler closure under ARC.
def patch_stream_callbacks(source):
    path = source / 'lsquic/connection.nim'
    text = path.read_text()
    helper = """# Capture only the retained transport context, never an async frame containing the stream itself.
proc streamProcessor(ctx: QuicContext): proc(urgent: bool) {.gcsafe, raises: [].} =
  result = proc(urgent: bool) {.gcsafe, raises: [].} =
    if urgent:
      ctx.processWhenReady()
    else:
      ctx.processSoon()

"""
    # Match both reviewed closure sites; a changed dependency cannot silently receive a guessed patch.
    for owner in ('stream', 's'):
        old = f"""  {owner}.doProcess = proc(urgent: bool) {{.gcsafe, raises: [].}} =
    if urgent:
      connection.quicContext.processWhenReady()
    else:
      connection.quicContext.processSoon()"""
        replacement = f'  {owner}.doProcess = streamProcessor(connection.quicContext)'
        if old in text:
            text = text.replace(old, replacement)
        else:
            assert replacement in text, path
    if helper not in text:
        text = text.replace('proc incomingStream*(', helper + 'proc incomingStream*(')
    path.write_text(text)


# Break quiesced timer and UDP callback cycles after shutdown, never during live processing.
def patch_context_lifetime(source):
    path = source / 'lsquic/context/context.nim'
    text = path.read_text()
    original = """  if not ctx.sslCtx.isNil:
    SSL_CTX_free(ctx.sslCtx)
    ctx.sslCtx = nil
"""
    replacement = original + """
  # The timeout closure owns ctx; drop ctx's timeout only after stop and native destruction.
  ctx.tickTimeout = nil
"""
    # Accept exactly the pinned original or this reviewed patch; never append cleanup to guessed upstream code.
    if replacement not in text:
        assert original in text, path
        text = text.replace(original, replacement)
    path.write_text(text)

    path = source / 'lsquic/endpoint.nim'
    text = path.read_text()
    original = '  await noCancel endpoint.udp.closeWait()\n'
    replacement = original + '  # The UDP receive callback owns endpoint; release the closed transport to break that ARC cycle.\n  endpoint.udp = nil\n'
    # This assignment follows awaited close, so no socket callback can borrow released storage.
    if replacement not in text:
        assert original in text, path
        text = text.replace(original, replacement)
    path.write_text(text)


# Prepare a closed dependency set from committed pins, including each native submodule's own exact revision.
def dependencies(fetch):
    sources = BUILD / 'sources'
    paths = {}
    # Parent packages must exist before placing their native source submodules.
    for name, entry in PINS['sources'].items():
        if '/' in name:
            continue
        path = sources / name
        marker = path / '.ragnarok-source.json'
        if fetch and not marker.exists():
            fetch_source(entry, path)
        assert marker.exists(), f'Run with --fetch to obtain {name}'
        recorded = json.loads(marker.read_text())
        assert recorded['commit'] == entry['commit'] and recorded['repository'] == entry['repository'], name
        paths[name] = path
    # Keep submodule layouts identical to the package's reviewed include/compile paths.
    for name, entry in PINS['sources'].items():
        if '/' not in name:
            continue
        parent, child = name.split('/', 1)
        path = paths[parent] / child
        marker = path / '.ragnarok-source.json'
        if fetch and not marker.exists():
            fetch_source(entry, path)
        assert marker.exists(), name
        recorded = json.loads(marker.read_text())
        assert recorded['commit'] == entry['commit'], name
    link = paths['nim-lsquic'] / 'libs/lsquic'
    # Replace only the archive's empty gitlink placeholder, never an existing populated directory.
    if not link.is_symlink():
        link.rmdir()
        link.symlink_to(paths['lsquic'], target_is_directory=True)
    assert link.resolve() == paths['lsquic'].resolve()
    patch_chronos(paths['chronos'])
    patch_stream_callbacks(paths['nim-lsquic'])
    patch_context_lifetime(paths['nim-lsquic'])
    return paths


# Compile the same transport/TLS source revisions for both peers; use no global package installs or fetched executables.
def build_peers(paths):
    nim_version = subprocess.check_output(['nim', '--version'], text=True)
    odin_version = subprocess.check_output(['odin', 'version'], text=True)
    assert PINS['nim'] in nim_version and odin_matches(odin_version, PINS['odin'])
    bssl = paths['boringssl'] / 'boringssl'
    system = platform.system()
    assert system in ('Darwin', 'Linux'), system
    library = BUILD / ('libquic_proof.dylib' if system == 'Darwin' else 'libquic_proof.so')
    native = ROOT / 'interoperability/quic'
    # The exact native configure/build output is retained instead of hidden behind a success claim.
    with (BUILD / 'build.log').open('w') as log:
        run(['cmake', '-S', bssl, '-B', BUILD / 'bssl', '-DCMAKE_BUILD_TYPE=Release',
             '-DBUILD_TESTING=OFF', '-DOPENSSL_NO_ASM=ON', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON'], log)
        run(['cmake', '--build', BUILD / 'bssl', '--target', 'ssl', 'crypto', '-j', '4'], log)
        run(['cmake', '-S', paths['lsquic'], '-B', BUILD / 'lsquic', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
             '-DCMAKE_BUILD_TYPE=Release', '-DLSQUIC_BIN=OFF', '-DLSQUIC_TESTS=OFF', '-DLSQUIC_SHARED_LIB=OFF',
             '-DCMAKE_POSITION_INDEPENDENT_CODE=ON', f'-DBORINGSSL_INCLUDE={bssl / "include"}',
             f'-DBORINGSSL_LIB_ssl={BUILD / "bssl/libssl.a"}', f'-DBORINGSSL_LIB_crypto={BUILD / "bssl/libcrypto.a"}'], log)
        run(['cmake', '--build', BUILD / 'lsquic', '-j', '4'], log)
        # The bridge contains transport/TLS field extraction only; identity/framing policy is independently native.
        for name in ('cert_fields', 'transport_bridge'):
            run(['clang', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', f'-I{bssl / "include"}',
                 f'-I{paths["lsquic"] / "include"}', '-c', native / f'{name}.c', '-o', BUILD / f'{name}.o'], log)
        run(['clang++', '-dynamiclib' if system == 'Darwin' else '-shared', BUILD / 'cert_fields.o',
             BUILD / 'transport_bridge.o', BUILD / 'lsquic/src/liblsquic/liblsquic.a',
             BUILD / 'bssl/libssl.a', BUILD / 'bssl/libcrypto.a', '-lz', '-o', library], log)
        run(['nim', 'c', '--mm:arc', '--cc:clang', '--clang.linkerexe:clang++', '--skipParentCfg', '--skipUserCfg',
             '-d:BORINGSSL_USE_ASM=false', '-d:chronicles_log_level=WARN', f'--nimcache:{BUILD / "nimcache"}',
             f'--out:{BUILD / "nim-peer"}', *[f'--path:{p}' for p in paths.values()], ROOT / 'nim/quic/peer.nim'], log)
        linker = []
        # Odin needs the active Xcode SDK on macOS; Linux uses the installed system linker.
        if system == 'Darwin':
            sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
            linker = [f'-extra-linker-flags:-isysroot {sdk}']
        run(['odin', 'build', ROOT / 'odin/quic', f'-out:{BUILD / "odin-peer"}', '-vet', '-strict-style', *linker], log)


# Compute the literal pinned SAN formula independently using arbitrary precision, not native bit loops or standard base32.
def peer_name(key):
    value = int.from_bytes(key, 'little')
    alphabet = '$abcdefghijklmnopqrstuvwxyz234567'
    result = '$e'
    for _ in range(52):
        result += alphabet[value % 32]
        value //= 32
    return result


# Generate local test identities only; private keys stay inside the ignored build directory and are never committed.
def fixtures():
    folder = BUILD / 'fixtures'
    folder.mkdir(exist_ok=True)
    openssl = shutil.which('openssl')
    assert openssl
    # Structured OpenSSL arguments avoid shell expansion; escaped dollars are needed in OpenSSL's config syntax.
    for identity in ('a', 'b', 'wrong-san', 'no-san', 'multi-san', 'ecdsa'):
        key, cert = folder / f'{identity}.key.pem', folder / f'{identity}.cert.pem'
        algorithm = ['-algorithm', 'EC', '-pkeyopt', 'ec_paramgen_curve:P-256'] if identity == 'ecdsa' else ['-algorithm', 'ED25519']
        subprocess.run([openssl, 'genpkey', *algorithm, '-out', key], check=True, capture_output=True)
        public = subprocess.check_output([openssl, 'pkey', '-in', key, '-pubout', '-outform', 'DER'])
        raw = public[-32:]
        # Valid Ed25519 fixture keys must have the expected exact SPKI representation, not merely a matching suffix.
        if identity != 'ecdsa':
            assert public == bytes.fromhex('302a300506032b6570032100') + raw
        (folder / f'{identity}.pub').write_bytes(raw)
        san = '$e' + 'a' * 52 if identity == 'wrong-san' else peer_name(raw)
        args = [openssl, 'req', '-new', '-x509', '-key', key, '-out', cert, '-days', '2', '-subj', '/CN=ragnarok-quic-proof']
        if identity != 'no-san':
            value = san.replace('$', r'\$') + (',DNS:extra' if identity == 'multi-san' else '')
            args += ['-addext', 'subjectAltName=DNS:' + value]
        subprocess.run(args, check=True, capture_output=True)
    # Isolate the certificate-signature check: an Ed25519 leaf key signed by the ECDSA fixture CA must still be rejected.
    identity = 'wrong-signature'
    key, cert = folder / f'{identity}.key.pem', folder / f'{identity}.cert.pem'
    subprocess.run([openssl, 'genpkey', '-algorithm', 'ED25519', '-out', key], check=True, capture_output=True)
    public = subprocess.check_output([openssl, 'pkey', '-in', key, '-pubout', '-outform', 'DER'])
    raw = public[-32:]
    assert public == bytes.fromhex('302a300506032b6570032100') + raw
    (folder / f'{identity}.pub').write_bytes(raw)
    csr = folder / f'{identity}.csr'
    subprocess.run([openssl, 'req', '-new', '-key', key, '-out', csr, '-subj', '/CN=ragnarok-quic-proof',
                    '-addext', 'subjectAltName=DNS:' + peer_name(raw).replace('$', r'\$')], check=True, capture_output=True)
    subprocess.run([openssl, 'x509', '-req', '-in', csr, '-CA', folder / 'ecdsa.cert.pem', '-CAkey', folder / 'ecdsa.key.pem',
                    '-set_serial', '7', '-days', '2', '-copy_extensions', 'copy', '-out', cert], check=True, capture_output=True)
    return folder


# Observe OS thread counts during stalled concurrent streams; this is a snapshot, not a sustained-load benchmark.
def thread_count(pid):
    if platform.system() == 'Darwin':
        output = subprocess.check_output(['ps', '-M', '-p', str(pid)], text=True)
        return max(0, len(output.strip().splitlines()) - 1)
    return len(list(Path(f'/proc/{pid}/task').iterdir()))


# Execute one independently bounded localhost peer pair and retain diagnostics without printing any private-key contents.
def attempt(case, folder):
    server_language, client_language, scenario = case
    # The reserved local port is released just before the server binds; startup errors are explicit failures.
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    client_identity = scenario if scenario in ('wrong-san', 'no-san', 'multi-san', 'ecdsa', 'wrong-signature') else 'b'
    server_identity = 'wrong-san' if scenario == 'bad-server-san' else 'a'
    expected = 'b' if scenario == 'wrong-server-key' else 'a'
    alpn = 'jamnp-s/1/00000000'
    client_alpn = 'jamnp-s/1/11111111' if scenario == 'wrong-alpn' else alpn
    cert = lambda name: str(folder / f'{name}.cert.pem')
    key = lambda name: str(folder / f'{name}.key.pem')
    server = [str(BUILD / f'{server_language}-peer'), 'server', str(port), cert(server_identity), key(server_identity), '-', alpn, '900']
    client = [str(BUILD / f'{client_language}-peer'), 'client', str(port),
              '-' if scenario == 'missing-cert' else cert(client_identity),
              '-' if scenario == 'missing-cert' else key(client_identity), str(folder / f'{expected}.pub'), client_alpn, '900']
    application_failure = scenario in ('bad-kind', 'oversize', 'unknown', 'truncated', 'trailing', 'no-fin')
    if application_failure:
        client.append(scenario)
    logs = BUILD / 'cases'
    logs.mkdir(exist_ok=True)
    path = logs / '-'.join(case)
    process = None
    client_process = None
    # Server readiness uses a log file plus a deadline, avoiding an unbounded pipe readline if startup hangs.
    with path.with_suffix('.server.log').open('w') as server_log:
        try:
            process = subprocess.Popen(server, stdout=server_log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 3
            while 'READY' not in path.with_suffix('.server.log').read_text():
                assert process.poll() is None and time.monotonic() < deadline, (case, 'server startup', path)
                time.sleep(0.01)
            client_process = subprocess.Popen(client, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            observed_threads = None
            # Missing FIN keeps all eight requests pending, allowing a live thread observation before the deadline.
            if scenario == 'no-fin':
                time.sleep(0.1)
                observed_threads = {'server': thread_count(process.pid), 'client': thread_count(client_process.pid)}
                assert observed_threads == {'server': 1, 'client': 1}, (case, observed_threads)
            client_out, client_err = client_process.communicate(timeout=4)
            result = subprocess.CompletedProcess(client, client_process.returncode, client_out, client_err)
            process.wait(timeout=4)
            server_output = path.with_suffix('.server.log').read_text()
            valid = scenario == 'valid'
            assert (result.returncode == 0 and process.returncode == 0) == valid, (case, server_output, result.stdout, result.stderr)
            assert ('EXCHANGE_OK 8' in server_output and 'EXCHANGE_OK 8' in result.stdout) == valid, case
            # Malformed application tests must reach authenticated transport first, or they are not meaningful framing tests.
            if application_failure:
                assert 'AUTH_OK' in server_output and 'AUTH_OK' in result.stdout, (case, server_output, result.stdout)
            return {'server': server_language, 'client': client_language, 'scenario': scenario,
                    'server_exit': process.returncode, 'client_exit': result.returncode, 'observed_threads': observed_threads,
                    'server_stdout': server_output, 'client_stdout': result.stdout, 'client_stderr': result.stderr}
        finally:
            # Retire orphaned servers after assertion/process timeout, leaving no listener running after the suite.
            for active in (client_process, process):
                if active is not None and active.poll() is None:
                    active.kill()
                    active.wait()


# Keep network/build work opt-in and independent of the existing codec verification command.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true', help='fetch missing exact source commits into ignored build storage')
    parser.add_argument('--skip-build', action='store_true', help='reuse previously built native peers')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    if not args.skip_build:
        build_peers(dependencies(args.fetch))
    run([BUILD / 'nim-peer', '--selftest'])
    run([BUILD / 'odin-peer', '--selftest'])
    folder = fixtures()
    scenarios = ('valid', 'wrong-san', 'no-san', 'multi-san', 'ecdsa', 'wrong-signature', 'missing-cert', 'bad-server-san',
                 'wrong-server-key', 'wrong-alpn', 'bad-kind', 'oversize', 'unknown', 'truncated', 'trailing', 'no-fin')
    cases = [(server, client, scenario) for server, client in (('nim', 'nim'), ('odin', 'odin'), ('nim', 'odin'), ('odin', 'nim')) for scenario in scenarios]
    # Independent cases may overlap, but each native peer still owns a single event loop for all its streams.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(lambda case: attempt(case, folder), cases))
    (BUILD / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print('PASS QUIC: 64 peer pairs; 4 valid x 8 concurrent CE 143 requests; '
          '36 TLS/identity rejections; 24 authenticated protocol rejections', flush=True)


# Importing this module never fetches dependencies, creates keys or opens a UDP listener.
if __name__ == '__main__':
    main()
