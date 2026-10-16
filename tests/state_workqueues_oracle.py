"""Independent GP T(14/15) fixed rings, ordered reports and canonical dependency/package sets."""
import hashlib
import json
import random
import subprocess
from test_codec import reference_encode as natural,reference_decode
from report_oracle import decode as report_decode,encode as report_wire,from_json
from state_availability_oracle import record
from state_layout_oracle import chapter_key,token,MAX
from state_trie_oracle import tree
from test_support import ROOT

DEFAULT=(2,2,MAX,MAX,MAX,MAX,MAX,MAX)
ERRORS={'truncated','noncanonical','limitexceeded','invalidtag','lengthoverflow'}


# Exact fixed rings have one count per slot and no outer epoch count or per-hash prefix.
def wire(kind,rows):
    if kind=='A':
        return b''.join(natural(len(row)//32)+row for row in rows)
    return b''.join(natural(len(row))+b''.join(report+natural(len(deps)//32)+deps for report,deps in row) for row in rows)


# Strict octet ordering gives a canonical set, independently for each dependency/accumulated row.
def ordered(raw):
    values=[raw[i:i+32] for i in range(0,len(raw),32)]
    return all(a<b for a,b in zip(values,values[1:]))


# Configuration work/native bounds precede input traversal or source-shape selection.
def valid(config):
    slots,cores,*_=config
    if not slots or not 2<=cores<=341:
        return 'invalidconfig'
    if slots>(2**63-1)//16:
        return 'lengthoverflow'
    if slots>config[7]:
        return 'limitexceeded'
    return None


# Check row/aggregate caller policy before typed storage extents, with unbounded reference arithmetic.
def charge(n,total,per,aggregate,width):
    if n>per or n>aggregate-total:
        return 'limitexceeded'
    if n>(2**63-1)//width or n>2**63-1-total:
        return 'lengthoverflow'
    return None


# Count framing and fixed payload extent each consume the complete parent's byte policy.
def grow(cursor,n,width,config):
    end=cursor+n*width
    if end>2**63-1:
        return 'lengthoverflow'
    if end>config[7]:
        return 'limitexceeded'
    return end


# Source reports are captured by the trusted adapter under the broad existing profile, then rechecked narrowly.
def source_report(raw,config):
    parsed=report_decode(raw,341)
    if parsed in ERRORS:
        return 'invalidreport'
    parts=parsed.split();consumed=int(parts[-1]);header=bytes.fromhex(parts[0])
    if int(parts[2])>=config[1] or int.from_bytes(header[68:70],'little')//3>config[1] or consumed>config[6]:
        return 'limitexceeded'
    return raw[:consumed]


# Preflight complete stable source rows before producing entry bytes; never sort hostile source sets.
def encode(kind,rows,config):
    error=valid(config)
    if error:
        return error
    if len(rows)!=config[0]:
        return 'invalidcount'
    cursor=items=dependencies=0;captured=[]
    # Slot and report order are retained, including repeated reports across independent positions.
    for row in rows:
        n=len(row)//32 if kind=='A' else len(row)
        cursor=grow(cursor,len(natural(n)),1,config)
        if isinstance(cursor,str):
            return cursor
        error=charge(n,items,config[2],config[3],32 if kind=='A' else 24)
        if error:
            return error
        items+=n
        if kind=='A':
            cursor=grow(cursor,n,32,config)
            if isinstance(cursor,str):
                return cursor
            if not ordered(row):
                return 'noncanonical'
            captured.append(row)
        else:
            complete=[]
            for raw,deps in row:
                report=source_report(raw,config)
                if isinstance(report,str):
                    return report
                cursor=grow(cursor,len(report),1,config)
                if isinstance(cursor,str):
                    return cursor
                n=len(deps)//32;cursor=grow(cursor,len(natural(n)),1,config)
                if isinstance(cursor,str):
                    return cursor
                error=charge(n,dependencies,config[4],config[5],32)
                if error:
                    return error
                dependencies+=n;cursor=grow(cursor,n,32,config)
                if isinstance(cursor,str):
                    return cursor
                if not ordered(deps):
                    return 'noncanonical'
                complete.append((report,deps))
            captured.append(complete)
    return chapter_key(14 if kind=='Q' else 15).hex()+' '+wire(kind,captured).hex()


# Parse every fixed slot/child/set before publishing any retained fields or complete consumed metadata.
def parse(kind,data,config):
    error=valid(config)
    if error:
        return error
    cursor=items=dependencies=0;rows=[]
    # Canonical count framing is checked before count policy, then charged to parent bytes.
    def count():
        nonlocal cursor
        result=reference_decode(data[cursor:])
        if result in ('truncated','noncanonical'):
            return result
        n,size=map(int,result.split());cursor=grow(cursor,size,1,config)
        return cursor if isinstance(cursor,str) else n
    # Complete fixed-hash sets must fit before any ordering reads.
    def hashes(n):
        nonlocal cursor
        end=grow(cursor,n,32,config)
        if isinstance(end,str):
            return end
        if end>len(data):
            return 'truncated'
        raw=data[cursor:end];cursor=end
        return raw if ordered(raw) else 'noncanonical'
    for _ in range(config[0]):
        n=count()
        if isinstance(n,str):
            return n
        error=charge(n,items,config[2],config[3],32 if kind=='A' else 24)
        if error:
            return error
        items+=n
        if kind=='A':
            row=hashes(n)
            if isinstance(row,str):
                return row
        else:
            row=[]
            for _ in range(n):
                report=report_decode(data[cursor:],config[1])
                if report in ERRORS:
                    return report
                size=int(report.split()[-1])
                if size>config[6]:
                    return 'limitexceeded'
                raw=data[cursor:cursor+size];cursor=grow(cursor,size,1,config)
                if isinstance(cursor,str):
                    return cursor
                n=count()
                if isinstance(n,str):
                    return n
                error=charge(n,dependencies,config[4],config[5],32)
                if error:
                    return error
                dependencies+=n;deps=hashes(n)
                if isinstance(deps,str):
                    return deps
                row.append((raw,deps))
        rows.append(row)
    return rows,cursor,items,dependencies


# Logical owner observations expose each complete report byte string and each private set independently.
def observe(kind,rows,consumed,items,dependencies):
    out=[str(consumed),str(len(rows)),str(items),str(dependencies)]
    for row in rows:
        if kind=='A':
            out.append(str(len(row)//32)+':'+token(row))
        else:
            out.append(str(len(row)))
            for report,deps in row:
                out.extend((token(report),str(len(deps)//32)+':'+token(deps)))
    return ' '.join(out)


# Failures have reasons alone; prefix successes expose complete fields and exact consumed extents.
def decode(kind,data,config):
    parsed=parse(kind,data,config)
    return parsed if isinstance(parsed,str) else observe(kind,*parsed)


# Read exact immutable fixture objects without executing upstream generators or altering checkouts.
def blob(path):
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
    assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
    return json.loads(raw)


# JSON arrays transport mathematical sets: sorting is explicit derivation, not production source repair.
def published():
    result=[]
    for chain in ('tiny','full'):
        for name in ('accumulate_ready_queued_reports-1','enqueue_and_unlock_chain-1','enqueue_and_unlock_chain_wraps-1'):
            data=blob(f'stf/accumulate/{chain}/{name}.json')
            for phase in ('pre_state','post_state'):
                source=data[phase];ready=[]
                for row in source['ready_queue']:
                    values=[]
                    for item in row:
                        assert set(item)=={'report','dependencies'}
                        report=item['report']
                        assert report['segment_root_lookup']==[] and all('ok' in d['result'] for d in report['results'])
                        deps=[bytes.fromhex(x[2:]) for x in item['dependencies']]
                        assert len(set(deps))==len(deps) and all(len(x)==32 for x in deps)
                        values.append((report_wire(from_json(report)),b''.join(sorted(deps))))
                    ready.append(values)
                accumulated=[]
                for row in source['accumulated']:
                    values=[bytes.fromhex(x[2:]) for x in row]
                    assert len(set(values))==len(values) and all(len(x)==32 for x in values)
                    accumulated.append(b''.join(sorted(values)))
                slots=12 if chain=='tiny' else 600;cores=2 if chain=='tiny' else 341
                assert len(ready)==slots and len(accumulated)==slots
                config=(slots,cores,MAX,MAX,MAX,MAX,MAX,MAX)
                result.extend((('Q',ready,config),('A',accumulated,config)))
    return result


# Existing pinned tiny-profile traces supply complete published C(14/15) bytes, tested without normalization.
def published_traces():
    result=[];config=(12,2,MAX,MAX,MAX,MAX,MAX,MAX)
    for n in (1,2,3):
        data=blob(f'traces/fuzzy/{n:08}.json')
        for phase in ('pre_state','post_state'):
            for kind,chapter in (('Q',14),('A',15)):
                values=[bytes.fromhex(x['value'][2:]) for x in data[phase]['keyvals'] if x['key']=='0x'+chapter_key(chapter).hex()]
                assert len(values)==1
                result.append((kind,values[0],config))
    return result


# Deterministic field sources, hostile wire/counts, bounds, mutations and trie integrations precede native execution.
def requests():
    lines=[];expected=[];rng=random.Random(0x5155455545533134)
    # Report owners are trusted source capture; malformed raw report sources remain default handles for rejection.
    def enc(kind,rows,config=DEFAULT,op='V'):
        fields=[str(len(rows))]
        for row in rows:
            if kind=='A':
                fields.append(token(row))
            else:
                fields.append(str(len(row)))
                for report,deps in row:
                    fields.extend((token(report),token(deps)))
        lines.append(op+' '+kind+' '+' '.join(map(str,config))+' '+' '.join(fields))
        expected.append(encode(kind,rows,config) if op=='V' else tree([(chapter_key(14 if kind=='Q' else 15),wire(kind,rows))])[0].hex())
    # Raw announcements need no fake Python/native owner arrays for impossible counts.
    def dec(kind,data,config=DEFAULT):
        lines.append('D '+kind+' '+' '.join(map(str,config))+' '+token(data));expected.append(decode(kind,data,config))
    r0=record(0)['report'];r1=record(1)['report'];h0=bytes(32);h1=bytes(31)+b'\1';h2=b'\1'+bytes(31)
    bases={'Q':[[(r0,h0+h1)],[(r1,h2),(r0,b'')]],'A':[h0+h1,h2]}
    for kind,rows in bases.items():
        data=wire(kind,rows);enc(kind,rows);dec(kind,data);dec(kind,data+b'suffix');enc(kind,rows,op='R')
        for cut in range(len(data)):
            dec(kind,data[:cut])
        # Exact/one-below byte, row and aggregate budgets fail independently at late positions.
        for index,value in ((2,0),(2,1),(3,0),(3,2),(4,0),(4,1),(5,2),(6,len(r0)-1),(6,len(r0)),(7,len(data)-1),(7,len(data))):
            config=list(DEFAULT);config[index]=value;enc(kind,rows,tuple(config));dec(kind,data,tuple(config))
        # Source shape is exact, while raw decoders preserve their prefix contract for unrelated suffix rows.
        for changed in (rows[:-1],rows+[rows[0]]):
            enc(kind,changed);dec(kind,wire(kind,changed))
        for config in ((0,2,MAX,MAX,MAX,MAX,MAX,MAX),(2,1,MAX,MAX,MAX,MAX,MAX,MAX),
                       (2,342,MAX,MAX,MAX,MAX,MAX,MAX),(MAX,2,MAX,MAX,MAX,MAX,MAX,MAX),(2**59,2,MAX,MAX,MAX,MAX,MAX,MAX),
                       (2,2,MAX,MAX,MAX,MAX,MAX,1)):
            enc(kind,rows,config);dec(kind,b'',config)
    # Empty 1/12/600-slot rings and late populated slots preserve all holes, without epoch count or rotation.
    for slots in (1,12,127,128,600):
        config=(slots,2,MAX,MAX,MAX,MAX,MAX,MAX)
        for kind in ('Q','A'):
            rows=[[] for _ in range(slots)] if kind=='Q' else [b'']*slots
            enc(kind,rows,config);dec(kind,wire(kind,rows),config);enc(kind,rows,config,op='R')
            rows[-1]=[(r0,h0)] if kind=='Q' else h0
            enc(kind,rows,config);dec(kind,wire(kind,rows),config)
    # Row/report order is preserved, including repeated report/package identities in different ring positions.
    enc('Q',[[(r1,b''),(r0,b''),(r1,b'')],[]]);dec('Q',wire('Q',[[(r1,b''),(r0,b''),(r1,b'')],[]]))
    enc('A',[h0,h0]);dec('A',wire('A',[h0,h0]))
    # Every octet can determine set order, independently in dependencies and accumulated rows.
    for position in range(32):
        a=bytes(32);b=bytes(position)+b'\1'+bytes(31-position)
        for members in (a+b,b+a,a+a):
            for kind in ('Q','A'):
                rows=[[(r0,members)],[]] if kind=='Q' else [members,b'']
                enc(kind,rows);dec(kind,wire(kind,rows))
    # Canonical count boundaries cover accumulated members, dependency counts and ready report counts independently.
    for n in (0,1,2,127,128,129,255,256):
        hashes=b''.join(i.to_bytes(32,'big') for i in range(n))
        for kind,rows in (('A',[hashes,b'']),('Q',[[(r0,hashes)],[]])):
            enc(kind,rows);dec(kind,wire(kind,rows))
        if n<=129:
            rows=[[(r0,b'')]*n,[]];enc('Q',rows);dec('Q',wire('Q',rows))
    # Missing/overlong/huge row/dependency counts reject without allocating announced objects.
    for bad in (b'',b'\x80',b'\xff',b'\x80\0',b'\xff'+bytes(8),natural(MAX),natural(2**60)):
        for kind in ('Q','A'):
            dec(kind,bad);dec(kind,b'\0'+bad)
        dec('Q',b'\1'+r0+bad);dec('Q',b'\0\1'+r0+bad)
    # Default source report owners, broader-profile children and malformed late reports retain existing report policy.
    for bad in (b'',r0[:68],bytes(272),r0[:-1]):
        enc('Q',[[],[(bad,b'')]]);dec('Q',b'\0\1'+bad)
    broad=record(3)['report'];enc('Q',[[(broad,b'')],[]]);dec('Q',b'\1'+broad+b'\0\0')
    # Reproducible multi-slot valid sources and mutations provide independent error and retained-value observations.
    for _ in range(100):
        slots=rng.choice((1,2,4,12));config=(slots,2,MAX,MAX,MAX,MAX,MAX,MAX)
        for kind in ('Q','A'):
            rows=[]
            for _ in range(slots):
                if kind=='A':
                    rows.append(b''.join(sorted(rng.randbytes(32) for _ in range(rng.randrange(6)))))
                else:
                    rows.append([(rng.choice((r0,r1)),b''.join(sorted(rng.randbytes(32) for _ in range(rng.randrange(5))))) for _ in range(rng.randrange(3))])
            data=wire(kind,rows);enc(kind,rows,config);dec(kind,data,config)
            changed=bytearray(data);changed[rng.randrange(len(changed))]^=rng.randrange(1,256)
            dec(kind,bytes(changed),config);dec(kind,rng.randbytes(rng.randrange(350)),config)
    # Exact JSON fields are preserved, with set sorting explicitly derived before framing.
    for kind,rows,config in published():
        enc(kind,rows,config);dec(kind,wire(kind,rows),config)
        if encode(kind,rows,config).startswith(chapter_key(14 if kind=='Q' else 15).hex()):
            enc(kind,rows,config,op='R') # Successful derived state entries supply partial roots only.
    for kind,data,config in published_traces():
        parsed=parse(kind,data,config)
        assert not isinstance(parsed,str),parsed
        rows,consumed,_,_=parsed
        assert consumed==len(data) and wire(kind,rows)==data
        dec(kind,data,config);enc(kind,rows,config);enc(kind,rows,config,op='R') # Exact wire re-emission is checked independently of JSON fixtures.
    return lines,expected
