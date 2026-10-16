"""Génère server/02_questions_N.sql à partir de questions.json (à coller dans Supabase > SQL Editor)."""
import json, os
d = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'questions.json'), encoding='utf-8'))
TH = d['themes']
def lit(s):
    s = str(s)
    assert '$q$' not in s
    return '$q$' + s + '$q$'
rows = []
for e in d['q']:
    rows.append('(%s,%s,%s,%s,%s,%r,%r,%r,%r,%s::jsonb,%s,%s,%s)' % (
        lit(e['i']), lit(TH[e['d']]), lit(e['t']), lit(e.get('u', '')),
        "'lin'" if e['k'] == 'y' else "'log'", float(e['a']), float(e['b']), float(e['v']), float(e['c']),
        lit(json.dumps(e['tk'])), lit(e['f']), lit(e.get('x', '')), 'true' if e.get('n') else 'false'))
CH = 350
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'server')
for f in os.listdir(out):
    if f.startswith('02_questions_'): os.remove(os.path.join(out, f))
parts = [rows[i:i + CH] for i in range(0, len(rows), CH)]
for k, part in enumerate(parts, 1):
    sql = ('-- Banque de questions, partie %d sur %d (%d questions). Coller dans SQL Editor puis Run.\n'
           'insert into public.questions(id, theme, t, unit, kind, vmin, vmax, truth, sc, ticks, fmt, fact, is_int) values\n'
           % (k, len(parts), len(part)))
    sql += ',\n'.join(part)
    sql += ('\non conflict (id) do update set theme=excluded.theme, t=excluded.t, unit=excluded.unit, kind=excluded.kind,'
            ' vmin=excluded.vmin, vmax=excluded.vmax, truth=excluded.truth, sc=excluded.sc, ticks=excluded.ticks,'
            ' fmt=excluded.fmt, fact=excluded.fact, is_int=excluded.is_int, active=true;\n')
    open(os.path.join(out, '02_questions_%d.sql' % k), 'w', encoding='utf-8').write(sql)
print(len(rows), 'questions en', len(parts), 'fichiers')
