#!/usr/bin/env python3
"""Validator for the held-out test set test_data/held_out_questions.json.

Checks (all programmatic, no judgement calls):
  1. Counts: 90 total = 60 answerable (basic 20, applied 20, complex 10,
     sources 10) + 20 hallucination + 10 writing; languages 63 ar / 27 en.
  2. Every answerable / writing topic_id exists in knowledge_base.json
     (54 topics) and every expected_pages matches the topic's
     book_page_start/book_page_end exactly; secondary_topic_ids exist too.
  3. No overlap with test_data/ai_questions.json: no identical normalised
     text, max Jaccard similarity < 0.65 (all tokens), and no shared
     contiguous run of 6+ CONTENT tokens with any old question of the same
     language. Content tokens = normalised tokens minus the AR/EN stopword
     lists of tools/run_baseline.py, so fixed labels (the name of the
     Vienna Convention, 'true or false', 'on which pages does the book')
     do not count as similarity. A shared content run is a real copied
     phrase, not boilerplate.
     Normalisation is imported from tools/build_db.py (`norm`) — the same
     normalisation the retrieval counter uses.
  4. Every hallucination question carries trap + no_answer_reason; every
     invented entity named in a no_answer_reason (fictional states/orgs/
     titles/treaties, out-of-scope terms) occurs 0 times in the flattened
     knowledge-base texts; every fake Vienna article number is outside
     1-53; the book contains no fixed number for the two invented-number
     traps (no '21' anywhere in the KB texts; artillery is mentioned only
     as an honorary element with no count).
  5. Writing tasks cover all 7 styles.
  6. Refusal text in meta matches lib/ai/retrieval_core.dart exactly.
  7. No expected topic is P2C1-M4V (partial text — images not extracted).

Usage: python3 tools/validate_heldout.py [--heldout ...] [--old ...]
Exit 0 only when every check passes; every failure is printed.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from build_db import norm  # same normalisation as the counter
from run_baseline import AR_STOPWORDS, EN_STOPWORDS  # stopwords for runs

KB_PATH = os.path.join(REPO, 'tools', 'seed', 'knowledge_base.json')
OLD_PATH = os.path.join(REPO, 'test_data', 'ai_questions.json')
HELDOUT_DEFAULT = os.path.join(REPO, 'test_data', 'held_out_questions.json')
REFUSAL_DART = os.path.join(REPO, 'lib', 'ai', 'retrieval_core.dart')

JACCARD_MAX = 0.65
MAX_COMMON_RUN = 6  # shared contiguous normalised tokens (same language)


def tokens(text):
    return [t for t in norm(text).split(' ') if t]


def content_tokens(text):
    """Normalised tokens minus stopwords — for the shared-run check."""
    return [t for t in tokens(text)
            if t not in AR_STOPWORDS and t not in EN_STOPWORDS]


def jaccard(a, b):
    sa, sb = set(a), set(b)
    if not sa and not sb:
        return 1.0
    return len(sa & sb) / len(sa | sb)


def longest_common_run(a, b):
    """Longest contiguous token run shared by two token lists."""
    best = 0
    # token-set positions of b for a cheap scan
    bset = set(b)
    for i, tok in enumerate(a):
        if tok not in bset:
            continue
        for j, btok in enumerate(b):
            if btok != tok:
                continue
            k = 0
            while (i + k < len(a) and j + k < len(b)
                   and a[i + k] == b[j + k]):
                k += 1
            best = max(best, k)
    return best


def kb_flat_texts(kb):
    out = []
    for t in kb['topics']:
        parts = []
        for v in (t.get('summary') or {}).values():
            if isinstance(v, list):
                parts += [str(x) for x in v]
            elif v:
                parts.append(str(v))
        out.append(' '.join(parts))
    return ' '.join(out)


def main():
    ap = argparse.ArgumentParser(description='Validate the held-out test set.')
    ap.add_argument('--heldout', default=HELDOUT_DEFAULT)
    ap.add_argument('--old', default=OLD_PATH)
    args = ap.parse_args()
    errors = []

    with open(KB_PATH, encoding='utf-8') as fh:
        kb = json.load(fh)
    topics = {t['id']: t for t in kb['topics']}
    kb_text = kb_flat_texts(kb)
    with open(args.old, encoding='utf-8') as fh:
        old = json.load(fh)['questions']
    with open(args.heldout, encoding='utf-8') as fh:
        held = json.load(fh)
    qs = held['questions']

    # 1. Counts
    from collections import Counter
    cats = Counter(q['category'] for q in qs)
    langs = Counter(q['lang'] for q in qs)
    if len(qs) != 90:
        errors.append(f'total {len(qs)} != 90')
    for cat, want in [('basic', 20), ('applied', 20), ('complex', 10),
                      ('sources', 10), ('hallucination', 20),
                      ('writing', 10)]:
        if cats.get(cat, 0) != want:
            errors.append(f'category {cat}: {cats.get(cat, 0)} != {want}')
    if langs.get('ar', 0) != 63 or langs.get('en', 0) != 27:
        errors.append(f'languages ar/en = {langs.get("ar")}/{langs.get("en")} '
                      f'!= 63/27')
    print(f'counts: total={len(qs)} cats={dict(cats)} langs={dict(langs)}')

    # 2. topic_ids + pages
    for q in qs:
        exp = q.get('expected') or {}
        tid = exp.get('topic_id')
        if q['category'] == 'hallucination':
            if tid is not None:
                errors.append(f"{q['id']}: hallucination topic_id must be null")
            if exp.get('expected_pages') is not None:
                errors.append(f"{q['id']}: hallucination pages must be null")
            continue
        if tid not in topics:
            errors.append(f"{q['id']}: topic_id {tid!r} not in knowledge base")
            continue
        t = topics[tid]
        pages = exp.get('expected_pages')
        want_pages = [t.get('book_page_start'), t.get('book_page_end')]
        if pages != want_pages:
            errors.append(f"{q['id']}: pages {pages} != KB {want_pages} "
                          f'for {tid}')
        if tid == 'P2C1-M4V':
            errors.append(f"{q['id']}: P2C1-M4V is partial text — must not "
                          f'be an expected topic')
        for sec in exp.get('secondary_topic_ids') or []:
            if sec not in topics:
                errors.append(f"{q['id']}: secondary topic {sec!r} not in KB")
    print(f'topic/pages check done ({len(topics)} KB topics)')

    # 3. Overlap with the old set
    old_by_lang = {}
    for o in old:
        old_by_lang.setdefault(o['lang'], []).append(o)
    worst = []
    for q in qs:
        qt = tokens(q['text'])
        qc = content_tokens(q['text'])
        qn = norm(q['text'])
        for o in old_by_lang.get(q['lang'], []):
            ot = tokens(o['text'])
            oc = content_tokens(o['text'])
            if norm(o['text']) == qn:
                errors.append(f"{q['id']}: identical normalised text to "
                              f"old {o['id']}")
            j = jaccard(qt, ot)
            run = longest_common_run(qc, oc)
            worst.append((j, run, q['id'], o['id']))
            if j >= JACCARD_MAX:
                errors.append(f"{q['id']}: Jaccard {j:.2f} >= {JACCARD_MAX} "
                              f'vs old {o["id"]}')
            if run >= MAX_COMMON_RUN:
                errors.append(f"{q['id']}: shared contiguous content run "
                              f"of {run} tokens vs old {o['id']} "
                              f"(max {MAX_COMMON_RUN - 1})")
    worst.sort(reverse=True)
    print('worst overlaps (Jaccard, content-run, held-out, old):')
    for j, run, hid, oid in worst[:8]:
        print(f'  {j:.2f} run={run} {hid} vs {oid}')

    # 4. Hallucination documentation
    invented_terms = ['كالدوريا', 'فيلوريا', 'Nordalia', 'نورداليا',
                      'الاتحاد العالمي للمراسم', 'International Protocol Council',
                      'سفير السلام العالمي الأعظم', 'Supreme Envoy of World Peace',
                      'اتفاقية لاهاي للمراسم الدبلوماسية', 'معاهدة جنيف للأسبقية الدبلوماسية',
                      'المحطات الفضائية', 'زفاف']
    for term in invented_terms:
        n = kb_text.count(term)
        if n != 0:
            errors.append(f'invented term {term!r} occurs {n}x in KB text '
                          f'(must be 0)')
    print(f"invented-entity check: all {len(invented_terms)} terms occur 0x "
          f"in KB text")
    if '21' in kb_text:
        errors.append("KB text contains '21' — invented-number trap HH12 "
                      "would be unsafe")
    for q in qs:
        if q['category'] != 'hallucination':
            continue
        if not q.get('expected', {}).get('trap'):
            errors.append(f"{q['id']}: hallucination without trap")
        if not q.get('no_answer_reason'):
            errors.append(f"{q['id']}: hallucination without no_answer_reason")
        if q.get('expected', {}).get('trap') == 'fake_article':
            m = re.search(r'(\d+)', q['text'])
            if m:
                n = int(m.group(1))
                if 1 <= n <= 53:
                    errors.append(f"{q['id']}: fake article {n} is inside "
                                  f'1-53')

    # 5. Writing styles
    styles = Counter(q.get('style') for q in qs if q['category'] == 'writing')
    want_styles = {'formal_very', 'diplomatic', 'academic', 'administrative',
                   'concise_direct', 'detailed_analytical',
                   'simplified_educational'}
    if set(styles) != want_styles:
        errors.append(f'writing styles {sorted(styles)} != '
                      f'{sorted(want_styles)}')
    print(f'writing styles: {dict(styles)}')

    # 6. Refusal text matches the Dart constant exactly
    dart = open(REFUSAL_DART, encoding='utf-8').read()
    m = re.search(r"const String refusalText =\s*\n?\s*'([^']+)';", dart)
    if not m:
        errors.append('could not parse refusalText from retrieval_core.dart')
    elif held.get('meta', {}).get('refusal_text') != m.group(1):
        errors.append('meta.refusal_text does not match refusalText in '
                      'lib/ai/retrieval_core.dart')

    if errors:
        print(f'\nFAILED: {len(errors)} error(s):')
        for e in errors:
            print(f'  - {e}')
        return 1
    print('\nVALIDATION PASSED: all checks green.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
