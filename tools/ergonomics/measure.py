#!/usr/bin/env python3
"""Reproduce curated implementation LOC and intentional compiler-protection diagnostics."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


# Hash exact bytes so changing a source cannot silently invalidate numeric inline-test exclusions.
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# Lex comments while preserving quoted comment delimiters, nested blocks and Nim numeric suffixes.
def code_lines(source, language):
    block_open, block_close = ('#[', ']#') if language == 'nim' else ('/*', '*/')
    line_comment = '#' if language in ('nim', 'mojo') else '//'
    depth, quote, triple = 0, '', False
    result = []
    # Track state across physical lines for block comments and multiline strings.
    for line in source.splitlines():
        i, code = 0, False
        # Inspect each character so inline comments do not erase preceding implementation code.
        while i < len(line):
            # Nested comments contain no implementation even when they resemble quoted source.
            if depth:
                # A nested opener extends the comment rather than contributing implementation.
                if line.startswith(block_open, i):
                    depth += 1
                    i += len(block_open)
                # Only the matching close reduces nested comment depth.
                elif line.startswith(block_close, i):
                    depth -= 1
                    i += len(block_close)
                else:
                    i += 1
            # Quoted comment markers belong to source literals, not comments.
            elif quote:
                code = True
                marker = quote * (3 if triple else 1)
                # Escapes apply to ordinary strings; backtick strings retain their literal content.
                if line[i] == '\\' and quote != '`':
                    i += 2
                # The matching delimiter ends the literal and permits later inline comments.
                elif line.startswith(marker, i):
                    quote, triple = '', False
                    i += len(marker)
                else:
                    i += 1
            # Nim and C-family block comments can span multiple physical lines.
            elif language != 'mojo' and line.startswith(block_open, i):
                depth = 1
                i += len(block_open)
            # Everything after an unquoted line-comment marker is documentation.
            elif line.startswith(line_comment, i):
                break
            # Remember literal boundaries before scanning any embedded comment-like text.
            elif line[i] in ('"', "'", '`'):
                code = True
                # Nim's 42'u64 is a typed number, not an unterminated character literal.
                if language == 'nim' and line[i] == "'" and i and line[i-1].isalnum() and i+1 < len(line) and line[i+1].isalpha():
                    i += 1
                    continue
                quote = line[i]
                triple = line.startswith(quote * 3, i)
                i += 3 if triple else 1
            else:
                code |= not line[i].isspace()
                i += 1
        result.append(code)
        # Single-line quote syntax must not turn the next physical line's comments into code.
        if quote and not triple and quote != '`':
            quote = ''
    return result


# Record actual tools/configuration without capturing unrelated or sensitive environment variables.
def environment():
    commands = {'nim': ['nim', '--version'], 'odin': ['odin', 'version'],
                'mojo': [str(ROOT/'build/mojo-env/bin/mojo'), '--version'],
                'clang': ['clang', '--version'], 'rust': ['rustc', '--version']}
    values = {}
    # An unavailable tool remains unavailable, never inferred from its pin alone.
    for name, command in commands.items():
        # Record the installed executable output rather than substituting the requested pin.
        try:
            run = subprocess.run(command, capture_output=True, text=True, timeout=15)
            values[name] = {'command': command, 'returncode': run.returncode,
                            'stdout': run.stdout.strip(), 'stderr': run.stderr.strip()}
        # Missing or unresponsive tools are explicit gaps in the environment evidence.
        except (OSError, subprocess.TimeoutExpired) as error:
            values[name] = {'unavailable': str(error)}
    configurations = ['.editorconfig', 'odinfmt.json', 'tools/format.py', 'tools/mojo-requirements.txt',
                      'spec/ci-toolchains.json', 'spec/quic-proof-pins.json', 'spec/crypto-pins.json',
                      'spec/bandersnatch-pins.json', 'spec/mojo-pins.json', '.github/workflows/linux.yml']
    return {'platform': platform.platform(), 'machine': platform.machine(), 'python': sys.version,
            'tools': values, 'configuration_sha256': {name:digest(ROOT/name) for name in configurations}}


# Count only the explicit, reviewed file set; fail closed if code moved since exclusion review.
def snapshot(manifest, manifest_path=None):
    per_file, totals = [], {}
    # Shared C/Rust, drivers, benches, tests and generated build trees are absent from this manifest.
    for item in manifest['files']:
        path = ROOT/item['path']
        # Fail before using line ranges that may now cover different functions.
        if digest(path) != item['sha256']:
            raise ValueError(f'Review changed inline-test ranges before counting {item["path"]}')
        excluded = {n for span in item['exclude'] for n in range(span['start'], span['end']+1)}
        flags = code_lines(path.read_text(), item['language'] if path.suffix != '.c' else 'c')
        count = sum(code for n, code in enumerate(flags, 1) if n not in excluded)
        per_file.append({**item, 'physical_lines': len(flags), 'implementation_loc': count,
                         'excluded_code_lines': sum(code for n, code in enumerate(flags, 1) if n in excluded)})
        groups = totals.setdefault(item['language'], {})
        groups[item['group']] = groups.get(item['group'], 0) + count
    return {'kind': 'measured static snapshot, not development-history metrics',
            'definition': manifest['definition'], 'baseline_revision': manifest['baseline_revision'],
            'manifest_sha256': digest(manifest_path or ROOT/'tools/ergonomics/loc-scope.json'),
            'tool_sha256': digest(Path(__file__)), 'environment': environment(),
            'totals': totals, 'files': per_file}


# Compile existing intentional misuses in matched categories; these are protections, not repair iterations.
def diagnostics(directory):
    directory.mkdir(parents=True, exist_ok=True)
    names = {'domain': ('swapped_digest_hash.nim', 'swapped_digest_hash.odin', 'swapped_hash.mojo'),
             'integer': ('natural_as_fixed.nim', 'natural_as_fixed.odin', 'natural_as_fixed.mojo'),
             'storage': ('mutable_owner.nim', 'mutable_owner.odin', 'mutable_owner.mojo')}
    needles = {'nim': ('type mismatch', 'undeclared field'),
               'odin': ('Cannot assign', 'Cannot use', 'not exported', 'not declared by', 'has no field'),
               'mojo': ('cannot be converted', 'cannot implicitly convert', 'has no attribute', 'no attribute')}
    records = []
    # Each candidate sees the same misuse category; no protocol implementation is edited.
    for category, filenames in names.items():
        # Pair the same misuse categories with each candidate's existing typed API.
        for language, filename in zip(('nim', 'odin', 'mojo'), filenames):
            path = ROOT/language/'tests/compile_fail'/filename
            # Nim check enforces its native type/privacy rules without running a program.
            if language == 'nim':
                command = ['nim', 'check', '--mm:arc', '--skipParentCfg', '--skipUserCfg', str(path)]
            # Odin file mode checks the intentional standalone misuse fixture.
            elif language == 'odin':
                command = ['odin', 'check', str(path), '-file']
            else:
                command = [str(ROOT/'build/mojo-env/bin/mojo'), 'build', '-I', str(ROOT/'mojo'),
                           '--emit', 'llvm', str(path), '-o', str(directory/'negative.ll')]
            run = subprocess.run(command, capture_output=True, text=True, timeout=120)
            text = run.stdout + run.stderr
            log = directory/f'{language}-{category}.log'
            log.write_text(text)
            # Import/setup/link failures must not be mistaken for a demonstrated safety property.
            matched = run.returncode != 0 and any(word in text for word in needles[language])
            # A setup/import failure is not evidence that the intended invalid program was rejected.
            if not matched or 'unable to locate module' in text:
                raise ValueError(f'Unexpected diagnostic: {command}: {text}')
            records.append({'language': language, 'category': category, 'intentional': True,
                            'source': str(path.relative_to(ROOT)), 'source_sha256': digest(path),
                            'command': command, 'returncode': run.returncode,
                            'log': str(log.relative_to(ROOT)), 'log_sha256': digest(log)})
    # This unpaired SDK/FFI restriction explains adapter work; it is not an extra matched language task.
    archived = ROOT/'results/ergonomics/observations/mojo-abi-layout.mojo.txt'
    probe = ROOT/'build/ergonomics/abi-layout.mojo'
    probe.parent.mkdir(parents=True, exist_ok=True)
    probe.write_bytes(archived.read_bytes())
    command = [str(ROOT/'build/mojo-env/bin/mojo'), 'build', '--emit', 'llvm',
               str(probe), '-o', str(probe.with_suffix('.ll'))]
    run = subprocess.run(command, capture_output=True, text=True, timeout=120)
    text = run.stdout + run.stderr
    # Require the specific ABI restriction, not an unrelated failure of the contextual probe.
    if run.returncode == 0 or "all members of 'RegisterPassable'" not in text:
        raise ValueError('The archived ABI restriction was not reproduced: '+text)
    log = ROOT/'results/ergonomics/observations/mojo-abi-layout-current.log'
    log.write_text(text)
    contextual = {'language':'mojo', 'category':'ffi', 'intentional':True, 'matched':False,
                  'source':str(archived.relative_to(ROOT)), 'source_sha256':digest(archived),
                  'command':command, 'returncode':run.returncode,
                  'log':str(log.relative_to(ROOT)), 'log_sha256':digest(log)}
    return {'classification': 'intentional compiler protection probes; excluded from defect/repair counts',
            'environment': environment(), 'tool_sha256':digest(Path(__file__)),
            'records': records, 'contextual_probes':[contextual]}


# Produce explicit static/diagnostic artifacts; never synthesize historical iteration or elapsed-time data.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('snapshot', 'diagnostics'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=ROOT/'tools/ergonomics/loc-scope.json')
    args = parser.parse_args()
    # Static scope auditing and compiler probes produce different evidence schemas.
    if args.operation == 'snapshot':
        result = snapshot(json.loads(args.manifest.read_text()), args.manifest)
    else:
        result = diagnostics(ROOT/'results/ergonomics/diagnostics')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    # Snapshot and probe records have different schemas; do not evaluate an irrelevant fallback eagerly.
    summary = result['totals'] if 'totals' in result else {'diagnostic_probes': len(result['records'])}
    print(json.dumps(summary, indent=2))


# Importing lexical helpers performs no compilation or filesystem writes.
if __name__ == '__main__':
    main()
