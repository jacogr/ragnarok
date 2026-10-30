# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Summarize every prespecified measured row; retain orders, ranges and MAD without selecting observations."""
from pathlib import Path
from collections import defaultdict
import csv,json,statistics,zipfile
P=Path('build/pvm-final-push-coordinator/final-evidence-41095176325')
assert json.loads((P/'integrity-proof.json').read_text())['architectures']
def stats(xs):
 m=statistics.median(xs)
 return dict(n=len(xs),median=m,min=min(xs),max=max(xs),mad=statistics.median(abs(x-m) for x in xs))
report={'method':'All rows with sample>=3; fixed10 measured per case/order; pooled summaries combine both complete orders. Process CPU. Median/min/max/MAD; no confidence/p-value claims. Cold components are non-additive diagnostics.','architectures':{}}
worker_csv=[];memory_csv=[];construct_csv=[]
for arch in ['x86_64','arm64']:
 d=json.loads((P/(arch+'-results.json')).read_text());wg=defaultdict(list);mg=defaultdict(list);construct=defaultdict(list)
 for r in d['processes']:
  for row in r['samples']:
   if row[1 if r['family']=='worker' else 2]<3:continue
   if r['family']=='worker':
    c,s,*_=row
    vals={'initialize_ns_per_call':row[2]/64,'dispatch_ns_per_call':row[3]/64,'reset_ns_per_call':row[4]/64,'worker_owner_ns_per_call':row[5]/64,'lifecycle_ns_per_call':row[6]/64,'live_managed_bytes':row[7],'actual_preparations':row[8],'actual_hits':row[9]}
    wg[c,r['role'],r['order']].append(vals);worker_csv.append(dict(architecture=arch,case=d['cohort']['worker_cases'][c],mode=r['role'],order=r['order'],sample=s,**vals))
   else:
    pages,c,s=row[:3];vals={'public_call_ns':row[3]/8,'result_context_retire_ns':row[4]/8,'public_lifecycle_ns':(row[3]+row[4])/8,**{n:row[i] for i,n in enumerate(d['columns']['memory']) if i>=5}}
    mg[pages,c,r['order']].append(vals);memory_csv.append(dict(architecture=arch,pages=pages,case=d['cohort']['memory_cases'][c],order=r['order'],sample=s,**vals))
 with zipfile.ZipFile(P/('pvm-final-evidence-'+arch+'-1.zip')) as z:
  for n in z.namelist():
   if n.endswith('.preparation'):
    c=int(Path(n).stem.split('-')[1]);label=Path(n).parent.name
    for line in z.read(n).decode().splitlines():
     row=[int(x) for x in line.split(',')]
     if row[0]>=3:
      vals=dict(zip(d['columns']['preparation'],row));construct[c].append(vals);construct_csv.append(dict(architecture=arch,case=d['cohort']['worker_cases'][c],process=label,**vals))
 out={'worker':{},'memory':{},'constructor':{}}
 for c,name in enumerate(d['cohort']['worker_cases']):
  modes={}
  for mode in ['one-shot','retained']:
   byorder={o:{k:stats([x[k] for x in wg[c,mode,o]]) for k in wg[c,mode,o][0]} for o in ['forward','reverse']}
   pool=wg[c,mode,'forward']+wg[c,mode,'reverse'];modes[mode]=dict(pooled={k:stats([x[k] for x in pool]) for k in pool[0]},orders=byorder)
  ratios={o:100*(1-modes['retained']['orders'][o]['lifecycle_ns_per_call']['median']/modes['one-shot']['orders'][o]['lifecycle_ns_per_call']['median']) for o in ['forward','reverse']}
  out['worker'][name]=dict(modes=modes,cpu_reduction_percent_by_order=ratios,pooled_cpu_reduction_percent=100*(1-modes['retained']['pooled']['lifecycle_ns_per_call']['median']/modes['one-shot']['pooled']['lifecycle_ns_per_call']['median']))
 for pages in [1,64,1024,4096]:
  out['memory'][str(pages)]={}
  for c,name in enumerate(d['cohort']['memory_cases']):
   pool=mg[pages,c,'forward']+mg[pages,c,'reverse'];out['memory'][str(pages)][name]=dict(pooled={k:stats([x[k] for x in pool]) for k in pool[0]},orders={o:{k:stats([x[k] for x in mg[pages,c,o]]) for k in pool[0]} for o in ['forward','reverse']})
 for c,name in enumerate(d['cohort']['worker_cases']):
  out['constructor'][name]={k:stats([x[k] for x in construct[c]]) for k in d['columns']['preparation'] if k!='sample'}
 report['architectures'][arch]=out
(P/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
for name,rows in [('worker-measured.csv',worker_csv),('memory-measured.csv',memory_csv),('constructor-measured.csv',construct_csv)]:
 with (P/name).open('w') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
for arch,out in report['architectures'].items():
 print(arch)
 for name,x in out['worker'].items():
  a=x['modes']['one-shot']['pooled']['lifecycle_ns_per_call']['median']/1000;b=x['modes']['retained']['pooled']['lifecycle_ns_per_call']['median']/1000
  print('worker',name,'us/call',round(a,3),round(b,3),'reduction/orders',*[round(v,2) for v in x['cpu_reduction_percent_by_order'].values()])
 for pages in ['1','64','1024','4096']:
  x=out['memory'][pages]
  print('memory',pages,'public us/call', {n:round(v['pooled']['public_lifecycle_ns']['median']/1000,3) for n,v in x.items()})
 print('constructor', {n:{k:round(v['median'],2) for k,v in x.items()} for n,x in out['constructor'].items()})
