import sys, json, math, random, re
sys.path.insert(0, 'qs')
import sport, geo, nature, transports, terr, histoire, sciences, arts

MODS = [sport, geo, nature, transports, terr, histoire, sciences, arts]
THEMES = [m.D for m in MODS]
PRE = ['SP', 'GE', 'NA', 'TR', 'TE', 'HI', 'SC', 'AR']

def nice_floor(x):
    e = math.floor(math.log10(x)); b = 10 ** e
    for m in (5, 2, 1):
        if m * b <= x * 1.0000001: return m * b
    return b
def nice_ceil(x):
    e = math.floor(math.log10(x)); b = 10 ** e
    for m in (1, 2, 5, 10):
        if m * b >= x * 0.9999999: return m * b
    return 10 * b
def clean(x):
    return float(f"{x:.6g}")

def year_scale(q, rnd):
    t = q['v']
    if t >= 1700: sc, spans = 60, [100, 120, 150]
    elif t >= 1200: sc, spans = 100, [250, 300]
    else: sc, spans = 200, [500, 600, 800]
    span = rnd.choice(spans)
    u = rnd.uniform(.22, .78)
    mn = t - u * span
    step = 10 if span <= 150 else 50
    mn = round(mn / step) * step
    mx = mn + span
    if mx > 2030: mx = 2030; mn = mx - span
    if mn < 0: mn = 0; mx = span
    # tick step
    for ts in (10, 20, 25, 50, 100, 200):
        ticks = [v for v in range(int(math.ceil(mn / ts) * ts), int(mx) + 1, ts)]
        if 3 <= len(ticks) <= 6: break
    return dict(a=mn, b=mx, c=sc, tk=ticks)

def log_scale(q, rnd):
    t = q['v']
    small = t <= 100
    F = rnd.choice([30, 100, 300]) if small else rnd.choice([100, 300, 1000])
    u = rnd.uniform(.25, .75)
    mn = t / (F ** u)
    mn = nice_floor(mn)
    mx = nice_ceil(mn * F)
    # make sure the truth is comfortably inside
    while t < mn * (mx / mn) ** .08: mn = nice_floor(mn * .7)
    while t > mx / (mx / mn) ** .08: mx = nice_ceil(mx * 1.4)
    cands = []
    for pat in ((1, 3), (1, 2, 5)):
        c = []
        e0 = math.floor(math.log10(mn)) - 1
        e1 = math.ceil(math.log10(mx)) + 1
        for e in range(e0, e1 + 1):
            for m in pat:
                v = m * 10 ** e
                if mn * 1.05 < v < mx / 1.05: c.append(clean(v))
        cands.append(c)
        if len(c) >= 3: break
    ticks = cands[-1] if len(cands[-1]) >= 2 else [clean(mn), clean(mx)]
    if len(ticks) > 6: ticks = ticks[::2]
    return dict(a=clean(mn), b=clean(mx), c=1, tk=ticks)

out = []; seen = set(); issues = []
for ti, m in enumerate(MODS):
    for n, q in enumerate(m.Q):
        key = re.sub(r'\W+', ' ', q['q'].lower()).strip()
        if key in seen: issues.append(('dup', q['q'])); continue
        seen.add(key)
        qid = f"{PRE[ti]}{n+1:03d}"
        rnd = random.Random(qid)
        s = year_scale(q, rnd) if q['k'] == 'y' else log_scale(q, rnd)
        t = q['v']
        if q['k'] == 'y': f = 'y'
        elif float(t).is_integer() and t < 1000: f = 'i'
        else: f = 'd'
        e = dict(i=qid, d=ti, t=q['q'], v=t, k=q['k'], u=q['u'], a=s['a'], b=s['b'], c=s['c'], f=f, tk=s['tk'], x=q['fact'])
        if f == 'i': e['n'] = 1
        # checks
        if not (s['a'] < t < s['b']): issues.append(('range', qid, t, s['a'], s['b']))
        pos = (math.log(t / s['a']) / math.log(s['b'] / s['a'])) if q['k'] == 'n' else (t - s['a']) / (s['b'] - s['a'])
        if not (.05 < pos < .95): issues.append(('edge', qid, round(pos, 3)))
        if q['k'] == 'n' and t <= 0: issues.append(('neg', qid))
        out.append(e)

by = {}
for e in out: by[THEMES[e['d']]] = by.get(THEMES[e['d']], 0) + 1
print(len(out), by)
print('issues:', issues[:20], len(issues))
json.dump({'themes': THEMES, 'q': out}, open('questions.json', 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
import os; print(os.path.getsize('questions.json'), 'bytes')
