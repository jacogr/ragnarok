# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Audit frozen final cohort data using immutable Git bytes and original archive members; no native execution."""
from pathlib import Path
import hashlib,json,subprocess,sys,tarfile,zipfile
from io import BytesIO
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'tools'))
from pvm_final_lifecycle_ci import parse,fixture_source,accumulation_fixture_source
P=ROOT/'build/pvm-final-push-coordinator/final-evidence-41095176325'
LANDED='4a29188758026f062e2b970b96df2665d8764d4e';PRIVATE='fc8e18dba63f727fe26da1c701d9077fceef2b19'
sha=lambda x:hashlib.sha256(x).hexdigest()
cache={}
def blob(rev,name):
 key=(rev,name)
 if key not in cache:cache[key]=subprocess.check_output(['git','show',rev+':'+name],cwd=ROOT)
 return cache[key]
proof=[];cross={}
for a in json.loads((P/'artifacts.json').read_text())['artifacts']:
 raw=(P/(a['name']+'.zip')).read_bytes();assert sha(raw)==a['digest'].split(':')[1]
 with zipfile.ZipFile(BytesIO(raw)) as z:
  entry=next(n for n in z.namelist() if n.endswith('pvm-final-lifecycle/results.json'));prefix=entry.removesuffix('results.json');d=json.loads(z.read(entry));arch=d['host']['architecture']
  assert d['status']=='passed' and d['frozen_source']==LANDED and d['harness_revision']==PRIVATE
  assert d['cohort']['warmups']==3 and d['cohort']['measured_samples']==10
  assert d['cohort']['worker_invocations_per_row']==64 and d['cohort']['memory_invocations_per_row']==8
  plan=json.loads(z.read(prefix+'prespecified-cohort.json'))
  assert plan==dict(source=LANDED,cohort=d['cohort'],scopes=d['scopes'],columns=d['columns'])
  assert all(x['exit_code']==0 for x in d['semantic_preflight']) and len(d['semantic_preflight'])==2
  for n,h in d['harness'].items():assert sha(blob(PRIVATE,n))==h,n
  rustpin=json.loads(blob(LANDED,'spec/bandersnatch-pins.json'))['rust'];assert d['rust']['pin']==rustpin
  for tool,x in d['rust']['actual'].items():assert x['version'].startswith(tool+' '+rustpin+' ')
  assert d['private_changes']==['.github/workflows/ci.yml','tests/performance/pvm_final_memory.nim','tests/performance/pvm_final_workers.nim','tools/pvm_final_lifecycle_ci.py']
  expected={}
  for role in ['landed','control']:
   sources=json.loads(z.read(prefix+role+'-sources.json'))
   if expected:assert expected==sources
   expected=sources
   for name,h in sources.items():
    if name=='tests/support/pvm_refinement_outcome.nim':data=fixture_source(blob(LANDED,name).decode()).encode()
    elif name=='tests/support/pvm_accumulation_context.nim':data=accumulation_fixture_source(blob(LANDED,name).decode()).encode()
    else:data=blob(PRIVATE if name.startswith('tests/performance/pvm_final_') else LANDED,name)
    assert sha(data)==h,(role,name)
   with tarfile.open(fileobj=BytesIO(z.read(prefix+role+'-sources.tar.gz')),mode='r:gz') as t:
    members={m.name.removeprefix('snapshot/'):m for m in t.getmembers() if m.isfile()}
    assert set(members)==set(sources)
    for name,m in members.items():assert sha(t.extractfile(m).read())==sources[name]
  for build in d['builds']:
   binary=z.read(prefix+'images/'+build['role']+'-'+build['family']);assert sha(binary)==build['binary_sha256']==d['same_image_controls'][build['family']]
   command=build['command']
   for flag in ['--mm:arc','--cc:clang','-d:release','--opt:speed','--boundchecks:on','--passC:-flto=thin','--passL:-flto=thin']:assert flag in command
   assert not any('danger' in x or 'checks:off' in x or 'assertions:off' in x for x in command)
  for name,x in d['libraries'].items():assert sha(z.read(prefix+Path(x['path']).name))==x['sha256']
  assert len(d['controls'])==2
  for control,family in zip(d['controls'],['worker','memory']):
   text=z.read(prefix+family+'-assert.log').decode(errors='replace');message='final worker checks enabled' if family=='worker' else 'final lifecycle checks enabled'
   assert control['exit_code']!=0 and message in text
  assert [[r['order'],r['role'],r['family']] for r in d['processes']]==d['cohort']['process_order']
  rows=0
  for r in d['processes']:
   label=r['order']+'-'+r['role']+'-'+r['family'];text=z.read(prefix+label+'.log').decode();samples,controls=parse(text,r['family'],r['order'],r['role'])
   assert r['exit_code']==0 and samples==r['samples'] and controls==r['qualification']
   assert r['binary_sha256']==d['same_image_controls'][r['family']]
   assert all(len(x)==len(d['columns'][r['family']]) for x in samples)
   rows+=len(samples)
  for name,h in d['observations'].items():assert sha(z.read(prefix+name))==h,name
  for family,base in [('worker','forward-one-shot-worker'),('memory','forward-landed-memory')]:
   refs={n.rsplit('/',1)[-1]:h for n,h in d['observations'].items() if n.startswith('observations/'+base+'/') and not n.endswith('.preparation')}
   assert len(refs)==(20 if family=='worker' else 48)
   for r in d['processes']:
    if r['family']==family:
     label=r['order']+'-'+r['role']+'-'+family
     current={n.rsplit('/',1)[-1]:h for n,h in d['observations'].items() if n.startswith('observations/'+label+'/') and not n.endswith('.preparation')};assert current==refs
   if family in cross:assert refs==cross[family]
   cross[family]=refs
  prep=0
  for name in d['observations']:
   if name.endswith('.preparation'):
    rows2=[[int(v) for v in line.split(',')] for line in z.read(prefix+name).decode().splitlines()]
    assert len(rows2)==13 and [x[0] for x in rows2]==list(range(13)) and all(len(x)==6 for x in rows2)
    assert all(x[1]>=0 and x[2]>=x[1] and x[3]>=0 and x[4]>0 and x[5]>=0 for x in rows2)
    prep+=len(rows2)
  proof.append(dict(architecture=arch,zip_digest=a['digest'],status='verified',source_files_per_snapshot=len(expected),source_snapshots=2,builds_verified=4,raw_matrix_rows=rows,constructor_rows=prep,all_raw_log_rows_verified=True,all_observation_hashes_verified=True,full_state_matches_other_architecture=True))
(P/'integrity-proof.json').write_text(json.dumps(dict(frozen_source=LANDED,private_head=PRIVATE,architectures=proof,no_native_execution=True),indent=2)+'\n')
print(json.dumps(proof))
