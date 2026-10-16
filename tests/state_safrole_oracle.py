"""Independent T(state) chapters 6/7/8/9/11; published fields are derived state-value cases."""
import hashlib
import json
import random
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import chapter_key,token,MAX
from state_trie_oracle import tree
from test_support import ROOT


# Roster population validation is independent of any key cryptographic interpretation.
def extent(count,prefix,config):
    cores,limit,budget=config
    # Protocol eligibility is separate from stricter caller resource ceilings.
    if cores<2:
        return 'invalidconfig'
    if count<6 or count%3 or count//3>cores:
        return 'invalidcount'
    if count>limit:
        return 'limitexceeded'
    if count>(2**63-1-prefix)//336:
        return 'lengthoverflow'
    if prefix+count*336>budget:
        return 'limitexceeded'
    return prefix+count*336


# Canonical natural framing and full payload bounds precede independent fixed field observation.
def decode(data,config):
    if config[0]<2:
        return 'invalidconfig' # Invalid policy takes precedence over malformed input.
    parsed=reference_decode(data)
    if parsed in ('truncated','noncanonical'):
        return parsed # Preserve primitive framing errors rather than interpreting a partial population.
    count,prefix=map(int,parsed.split());size=extent(count,prefix,config)
    if isinstance(size,str):
        return size # Counts cannot allocate or expose partial progress after failure.
    if len(data)<size:
        return 'truncated'
    return f'{size} {count} '+token(data[prefix:size])


# Exact upstream JSON source fields become explicitly derived component encodings, not claimed standalone binary fixtures.
def published():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors'];result=[]
    # Both chain profiles and before/after state exercise named published entropy/time/key fields.
    for chain in ('tiny','full'):
        path=f'vendor/jamtestvectors/stf/safrole/{chain}/enact-epoch-change-with-no-tickets-1.json'
        raw=(ROOT/path).read_bytes();assert hashlib.sha256(raw).hexdigest()==pins['files'][path]
        value=json.loads(raw)
        # JSON record order is preserved; no sorting of validator identities is permitted.
        for phase in ('pre_state','post_state'):
            state=value[phase];eta=b''.join(bytes.fromhex(x[2:]) for x in state['eta'])
            rosters=[]
            # Iota/kappa/lambda correspond to staging/active/previous state components.
            for name in ('iota','kappa','lambda'):
                roster=b''.join(bytes.fromhex(record[field][2:]) for record in state[name]
                                for field in ('bandersnatch','ed25519','bls','metadata'))
                assert len(roster)==336*len(state[name]);rosters.append(roster)
            result.append((chain,eta,state['tau'],rosters))
    return result


# Deterministic literal, malformed, resource-bound and random requests precede native execution.
def requests():
    lines=[];expected=[]
    broad=(MAX,MAX,MAX)
    # Fixed-prefix reads never invent padding or consume unrelated trailing bytes.
    def fixed(kind,data):
        width=128 if kind=='ED' else 4
        lines.append(kind+' '+token(data))
        expected.append('truncated' if len(data)<width else f'{width} '+(data[:width].hex() if kind=='ED' else str(int.from_bytes(data[:width],'little'))))
    # Native sources are raw fixed records rather than wire decoded through the production API.
    def encode_roster(chapter,source,config):
        count=len(source)//336;prefix=natural(count);size=extent(count,len(prefix),config)
        lines.append(f'V {chapter} '+' '.join(map(str,config))+' '+token(source))
        expected.append(size if isinstance(size,str) else chapter_key(chapter).hex()+' '+(prefix+source).hex())
    # Raw wire can express impossible counts and noncanonical prefixes without allocating fake native sequences.
    def dec(data,config=broad):
        lines.append('VD '+' '.join(map(str,config))+' '+token(data));expected.append(decode(data,config))
    eta=bytes(range(128))
    lines.append('E '+eta.hex());expected.append(chapter_key(6).hex()+' '+eta.hex())
    # Every proper entropy/time truncation is rejected; unrelated suffixes are untouched.
    for cut in range(129):
        fixed('ED',eta[:cut])
    fixed('ED',eta+b'extra')
    for time in (0,1,127,128,255,256,65535,65536,0x01020304,2**32-1):
        data=time.to_bytes(4,'little');lines.append(f'T {time}');expected.append(chapter_key(11).hex()+' '+data.hex())
        # Truncation cannot expose a zero/default timeslot.
        for cut in range(4):
            fixed('TD',data[:cut])
        fixed('TD',data+b'extra')
    rng=random.Random(0x5354415445534146)
    # Exact allowed populations straddle natural-prefix boundaries and both profile maxima.
    for count in (0,1,3,5,6,7,9,12,126,129,255,1023,1026):
        source=rng.randbytes(count*336);wire=natural(count)+source
        # All three chapter keys use the same value format while preserving independent identities.
        for chapter in (7,8,9):
            encode_roster(chapter,source,(341,MAX,MAX))
        dec(wire,(341,MAX,MAX))
        # Small allowed maps exhaust every truncation; larger maps check prefix/record/final boundaries.
        cuts=range(len(wire)) if count==6 else sorted({0,1,max(0,len(natural(count))-1),len(natural(count)),max(0,len(wire)-1)})
        for cut in cuts:
            dec(wire[:cut],(341,MAX,MAX))
        # Independent configuration, count and byte ceilings have exact/below-bound observations.
        for config in ((0,MAX,MAX),(1,MAX,MAX),(2,MAX,MAX),(MAX,0,MAX),
                       (MAX,count,MAX),(MAX,max(0,count-1),MAX),
                       (MAX,MAX,len(wire)),(MAX,MAX,len(wire)-1)):
            encode_roster(8,source,config);dec(wire,config)
        dec(wire+b'suffix',(341,MAX,MAX))
    # Massive but syntactically valid counts fail before narrowing, multiplication or allocation.
    for count in (2**32,2**56,MAX,MAX-1,MAX-2):
        dec(natural(count))
    # Overlong naturals are rejected even when they nominally represent an allowed six-record population.
    for data in (b'\x80\x06',b'\xff'+(6).to_bytes(8,'little'),b'\x80',b'\xff'):
        dec(data)
    # Random framing probes include malformed counts and truncated payloads, with no fixture-derived expectations.
    for _ in range(500):
        dec(rng.randbytes(rng.randrange(350)),(341,1023,400_000))
    # Published state components supply named field inputs; the state values are derived against T, not STF transition claims.
    for chain,eta,time,rosters in published():
        cores=2 if chain=='tiny' else 341
        lines.append('E '+eta.hex());expected.append(chapter_key(6).hex()+' '+eta.hex());fixed('ED',eta)
        lines.append(f'T {time}');expected.append(chapter_key(11).hex()+' '+time.to_bytes(4,'little').hex())
        for chapter,source in zip((7,8,9),rosters):
            encode_roster(chapter,source,(cores,1023,400_000));dec(natural(len(source)//336)+source,(cores,1023,400_000))
    # Integration forms a partial five-entry mapping, explicitly not a complete JAM state commitment.
    for count in (6,9,129):
        source=rng.randbytes(count*336);eta=rng.randbytes(128);time=rng.randrange(2**32)
        entries=[(chapter_key(6),eta),(chapter_key(11),time.to_bytes(4,'little'))]
        entries.extend((chapter_key(chapter),natural(count)+source) for chapter in (7,8,9))
        root,nodes=tree(entries)
        lines.append(f'R {eta.hex()} {time} {source.hex()}');expected.append(root.hex()+f' {nodes}')
    return lines,expected
