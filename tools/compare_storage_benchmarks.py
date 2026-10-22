#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare fully validated matching storage reports with explicit source differences and honest noise flags."""
import argparse
import json
from pathlib import Path,PurePosixPath
from storage_benchmark_report import summarize_benchmark
from storage_benchmark import atomic_text


def compare_reports(baseline,candidate,allowed_sources=()):
    """Require identical workloads, primitive closure, hardware metadata and physical work before ratios."""
    for report in (baseline,candidate):
        summarize_benchmark(report) # Recompute every statistic, command plan and observed SDK witness first.
        if report['status']!='checks-passed' or report['worktree_dirty']:
            raise ValueError('Storage comparison requires complete clean-source reports')
    for field in ('schema_version','profile','compiler_sha256','crypto_sha256','native_components','clang','toolchain'):
        if baseline[field]!=candidate[field]:
            raise ValueError('Storage comparison input differs: '+field)
    for field in ('platform','machine','cpu','logical_cpus'):
        if baseline['hardware'][field]!=candidate['hardware'][field]:
            raise ValueError('Storage comparison hardware differs: '+field)
    if set(baseline['sources'])!=set(candidate['sources']):
        raise ValueError('Storage comparison source inventory differs')
    allowed=set(allowed_sources)
    for name in allowed:
        path=PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or str(path)!=name or name not in baseline['sources']:
            raise ValueError('Invalid allowed source difference')
    changed={name for name in baseline['sources'] if baseline['sources'][name]!=candidate['sources'][name]}
    if changed-allowed:
        raise ValueError('Storage comparison has unapproved source differences: '+', '.join(sorted(changed-allowed)))
    if baseline['growth']['io']['observations']!=candidate['growth']['io']['observations']:
        raise ValueError('CPU storage comparison changed observed SDK work')
    lines=['# Storage benchmark comparison','',f'Baseline: `{baseline["head"]}`. Candidate: `{candidate["head"]}`.',
        'Matching checked profile, native primitive closure and recorded host metadata; all raw statistics and command plans revalidated.',
        'Approved changed sources: '+(', '.join('`'+name+'`' for name in sorted(changed)) or 'none')+'.',
        'Observed SDK work and selected physical counters are identical. Speedup is baseline / candidate median.','',
        '| Panel | Entries | Workload | Operation | Backend | Baseline µs | Candidate µs | Speedup |',
        '| --- | ---: | --- | --- | --- | ---: | ---: | ---: |']
    for panel in ('short','sustained'):
        before=baseline['cases'] if panel=='short' else baseline['growth']['cases']
        after=candidate['cases'] if panel=='short' else candidate['growth']['cases']
        if len(before)!=len(after):
            raise ValueError('Storage comparison case coverage differs')
        for left,right in zip(before,after):
            identity=('items','phase','topology','value_bytes','batch_width') if panel=='short' else ('items','phase','publications','pattern')
            if any(left[k]!=right[k] for k in identity):
                raise ValueError('Storage comparison workload identity differs')
            work=(f'{left["topology"]}, {left["value_bytes"]} B, batch{left["batch_width"]}' if panel=='short' else
                  f'{left["publications"]} publications, {left["pattern"]}')
            for engine in ('memory','journal','managed'):
                a=left['engines'][engine];b=right['engines'][engine]
                if a is None or b is None:
                    if a is not None or b is not None:
                        raise ValueError('Storage comparison availability differs')
                    continue
                if a['metrics']!=b['metrics']:
                    raise ValueError('Storage comparison selected physical work differs')
                paired=[a['pass_medians_ns'][i]/b['pass_medians_ns'][i] for i in range(2)]
                noisy=a['noisy'] or b['noisy'] or max(paired)/min(paired)>1.25
                lines.append(f'| {panel} | {left["items"]} | {work} | {left["phase"]} | {engine} | '+
                    f'{a["median_ns"]/1000:.2f} | {b["median_ns"]/1000:.2f} | '+
                    f'{a["median_ns"]/b["median_ns"]:.3f}×'+(' †' if noisy else '')+' |')
    lines+=['','† Timing spread or opposite-order drift makes this comparison provisional. There is no fixed speed threshold.',
        'These reports describe synthetic physical operations on the recorded host. Separate interleaved executable A/B runs are needed to attribute a change amid host drift.',
        'Memory publication is not durable; live-kernel reopen is not hardware power-loss certification.']
    return '\n'.join(lines)+'\n'


def main():
    """Read existing reports only; this command never builds, changes source, requests CI or mutates databases."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',type=Path,required=True)
    parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--allow-source',action='append',default=[])
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.resolve() in (args.baseline.resolve(),args.candidate.resolve()):
        raise ValueError('Comparison output must not replace an input report')
    args.output.unlink(missing_ok=True) # A failed comparison cannot retain a previous successful result.
    result=compare_reports(json.loads(args.baseline.read_text()),json.loads(args.candidate.read_text()),args.allow_source)
    args.output.parent.mkdir(parents=True,exist_ok=True);atomic_text(args.output,result)


if __name__=='__main__':
    main()
