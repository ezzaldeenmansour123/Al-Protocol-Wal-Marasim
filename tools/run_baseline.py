#!/usr/bin/env python3
"""Baseline retrieval measurer for the PROTOCOL AI 100-question test set.

usage:
  python3 tools/run_baseline.py --db assets/marasim.db \
      --questions test_data/ai_questions.json --out test_data/baseline_results.json

What it measures (retrieval only — there is no generative model yet):
  * For the 80 answerable questions (basic/applied/complex/sources):
    hit@3 — is the expected `topic_id` among the top 3 FTS5 results?
  * For the 20 hallucination-resistance questions: `refusal_correct` is a
    RETRIEVAL-LEVEL PROXY — true only when the search returns NO results at
    all, i.e. a grounded RAG pipeline would have nothing to cite and should
    refuse. A non-empty result does NOT prove a hallucination (a good
    generator could still refuse), it only flags retrieval noise that a
    generator must resist. True refusal can only be measured once a
    generative model exists; see test_data/BASELINE_REPORT.md.

Retrieval mirrors the app's assistant search (lib/ai/retrieval_service.dart
+ lib/ai/retrieval_core.dart):
  * Arabic normalisation is imported from tools/build_db.py (`norm`,
    `search_norm`, `search_expr`) — the same normalisation as `normalizeAr`
    in lib/db.dart. If that import fails, the functions are copied below
    (marked COPY) and must be kept identical to build_db.py.
  * Stopwords (Arabic + English, R1) and singular/plural variants are
    copied from lib/db.dart (`arStopwords`, `enStopwords`, `_wordVariants`)
    — marked COPY — because FTS prefix matching alone cannot connect
    e.g. وفد/وفود or سفير/سفراء. R1 also adds topical synonyms
    (مطار/وصول، وفد/ضيف …), verb→noun pairs, tanwin forms, English
    plurals, and one-prefix / trailing-pronoun stripping (see
    `term_variants`).
  * Three stages, in order: strict AND of the meaningful terms, then OR
    across them, then the single longest term. The stage that produced the
    results is recorded per question.
  * R1 reranking (formula F1, identical to RetrievalService._merge):
    up to 20 candidates are fetched from the producing stage, then
    re-ranked by title matches first (distinct query terms matched in
    the title + en_keywords + ar_keywords), then FTS5 rank; the top 3
    are scored.
  * R1 guard measurement (hallucination category only): besides the
    retrieval proxy (`refusal_correct`, unchanged), each H question
    records `guard_refusal` — whether the Vienna-article-range rule of
    lib/ai/refusal_guard.dart refuses it (article number outside 1–53
    for the Vienna Convention on Diplomatic Relations 1961). The guard
    is a Dart-side decision; the counter mirrors its rule in Python so
    the H improvement is measurable without a generative model.

The database must already contain `kb_topics` and `kb_topics_fts`
(schema: KNOWLEDGE_BASE_REPORT.md §5). The script never builds the DB and
never deletes or modifies questions: every failing question is recorded in
the output file under `failed` (and in full under `per_question`).

DB kind is detected from the `meta` table when present: a `kb_mirror=1`
entry means a temporary mirror DB built from knowledge_base.json (see
BASELINE_REPORT.md); otherwise the DB is reported as `built` (or
`unknown` when no meta table exists).
"""
import argparse
import datetime
import json
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

try:
    # Same normalisation as normalizeAr in lib/db.dart.
    from build_db import norm, search_norm, search_expr  # noqa: F401
    NORM_SOURCE = "imported from tools/build_db.py (norm/search_norm/search_expr)"
except Exception:  # pragma: no cover - fallback if build_db.py is unavailable
    import re
    _TASHKEEL = re.compile(r'[\u064B-\u065F\u06D6-\u06ED\u0640]')
    _ALEF = re.compile(r'[إأآٱ]')
    _NONWORD = re.compile(r'[^\u0621-\u064A\u0660-\u0669a-zA-Z0-9\s]')
    _SPACES = re.compile(r'\s+')

    def norm(s):  # COPY of build_db.norm — keep identical to tools/build_db.py
        if s is None:
            return ''
        s = str(s).lower()
        s = s.replace('\u0648\u0670', 'ا').replace('\u0649\u0670', 'ى').replace('\u0670', 'ا')
        s = _TASHKEEL.sub('', s)
        s = _ALEF.sub('ا', s).replace('ى', 'ي').replace('ة', 'ه')
        s = _NONWORD.sub(' ', s)
        return _SPACES.sub(' ', s).strip()

    def _strip_prefix(w):  # COPY of build_db._strip_prefix
        for p in ('وال', 'فال', 'بال', 'لل', 'كال'):
            if w.startswith(p) and len(w) - len(p) >= 2:
                return w[len(p):]
        if w.startswith('ال') and len(w) - 2 >= 3:
            return w[2:]
        for p in ('و', 'ف', 'ب', 'ل', 'ك'):
            if w.startswith(p) and len(w) - 1 >= 2:
                return w[1:]
        return None

    def search_norm(s):  # COPY of build_db.search_norm
        words = norm(s).split(' ')
        out = []
        for w in words:
            if not w:
                continue
            out.append(w)
            stripped = _strip_prefix(w)
            if stripped and stripped != w:
                out.append(stripped)
        return ' '.join(out)

    def search_expr(normed):  # COPY of build_db.search_expr
        groups = []
        for t in normed.split(' '):
            if not t:
                continue
            variants = {t}
            if t.startswith('ال') and len(t) > 4:
                variants.add(t[2:])
            else:
                variants.add('ال' + t)
            groups.append('(' + ' OR '.join(f'"{v}"*' for v in variants) + ')')
        return ' AND '.join(groups)

    NORM_SOURCE = "COPY of tools/build_db.py functions (import failed)"

# ── COPY from lib/db.dart: arStopwords + enStopwords + _wordVariants
# (normalised forms; R1 additions documented in retrieval_core.dart) ──
AR_STOPWORDS = {
    'كيف', 'ما', 'ماذا', 'هل', 'لماذا', 'متي', 'اين', 'من', 'اريد', 'اعطني',
    'ابحث', 'ارني', 'اظهر', 'اعرض', 'هات', 'احضر', 'اذكر', 'اورد', 'هو', 'هي',
    'في', 'الي', 'عن', 'علي', 'مع', 'هذا', 'هذه', 'ذلك', 'تلك', 'كان', 'يكون',
    'تتم', 'يتم', 'يضم', 'خمس', 'اربع', 'ثلاث', 'ست', 'سبع', 'ثمان', 'تسع',
    'عشر', 'واحد', 'اثنان', 'اثنين', 'بين', 'بعد', 'قبل', 'عند', 'لدي', 'ان',
    'انه', 'انها', 'او', 'ام', 'بل', 'لكن', 'ثم', 'كما', 'اي', 'كل', 'بعض',
    'غير', 'دون', 'ضد', 'نحو', 'حول', 'داخل', 'خارج', 'فوق', 'تحت', 'امام',
    'خلف', 'خلال', 'اثناء', 'منذ', 'حتي', 'لكي', 'لان', 'اذا', 'عندما', 'بينما',
    'حيث', 'الذي', 'التي', 'الذين', 'ارتب', 'اعد', 'اكتب', 'اشرح', 'عرف',
    'لي', 'ليس', 'قد', 'لقد', 'سوف', 'سي', 'بان', 'فان', 'انما', 'اما', 'ايضا',
    'فقط', 'جدا', 'نفس', 'ذات', 'الان', 'اليوم', 'غدا', 'ايه', 'ايها', 'ايتها',
    'اولا', 'ثانيا', 'ثالثا', 'مثلا', 'ممكن', 'يمكن', 'ارغب', 'احتاج', 'اسال',
}
EN_STOPWORDS = {
    'what', 'which', 'who', 'whom', 'whose', 'when', 'where', 'why', 'how',
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am', 'do', 'does',
    'did', 'can', 'could', 'should', 'would', 'may', 'might', 'shall', 'will',
    'the', 'a', 'an', 'and', 'or', 'but', 'if', 'then', 'than', 'so', 'of',
    'in', 'on', 'at', 'to', 'for', 'by', 'with', 'from', 'about', 'into',
    'over', 'under', 'between', 'through', 'during', 'before', 'after',
    'above', 'below', 'up', 'down', 'out', 'off', 'as', 'it', 'its', 'this',
    'that', 'these', 'those', 'there', 'here', 'he', 'she', 'they', 'we',
    'you', 'i', 'his', 'her', 'their', 'our', 'your', 'my', 'me', 'him',
    'us', 'them', 'not', 'no', 'yes', 'compare', 'explain', 'describe',
    'discuss', 'outline', 'list', 'give', 'state', 'name', 'tell', 'write',
    'quote', 'true', 'false', 'according', 'book', 'say', 'says', 'one',
    'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
    'twenty', 'first', 'second', 'vs', 'versus',
}
WORD_VARIANTS = {
    'وفد': ['وفود', 'ضيف', 'ضيوف'], 'وفود': ['وفد'],
    'سفير': ['سفراء'], 'سفراء': ['سفير'],
    'وزير': ['وزراء'], 'وزراء': ['وزير'],
    'رئيس': ['رؤساء'], 'رؤساء': ['رئيس'],
    'علم': ['اعلام'], 'اعلام': ['علم'],
    'لقب': ['القاب'], 'القاب': ['لقب'],
    'ملك': ['ملوك'], 'ملوك': ['ملك'],
    'امير': ['امراء'], 'امراء': ['امير'],
    'ضيف': ['ضيوف', 'وفد', 'وفود'], 'ضيوف': ['ضيف', 'وفد', 'وفود'],
    'قاعده': ['قواعد'], 'قواعد': ['قاعده'],
    'وثيقه': ['وثائق'], 'وثائق': ['وثيقه'],
    'مذكره': ['مذكرات'], 'مذكرات': ['مذكره'],
    'برنامج': ['برامج'], 'برامج': ['برنامج'],
    'دوله': ['دول'], 'دول': ['دوله'],
    'اتفاقيه': ['اتفاقيات'], 'اتفاقيات': ['اتفاقيه'],
    'دعوه': ['دعوات'], 'دعوات': ['دعوه'],
    'زياره': ['زيارات'], 'زيارات': ['زياره'],
    'مناسبه': ['مناسبات'], 'مناسبات': ['مناسبه'],
    'مطار': ['وصول'], 'وصول': ['مطار'],
    'استقبال': ['ترحيب'], 'ترحيب': ['استقبال'],
    'مادبه': ['مادب', 'عشاء'], 'مادب': ['مادبه', 'عشاء'],
    'عشاء': ['مادبه', 'مادب'],
    'جلوس': ['مقاعد', 'مقعد'], 'مقاعد': ['جلوس'], 'مقعد': ['جلوس', 'مقاعد'],
    'اجتماع': ['مؤتمر'], 'مؤتمر': ['اجتماع'],
    'هدايا': ['هديه'], 'هديه': ['هدايا'],
    'نشيد': ['اناشيد'], 'اناشيد': ['نشيد'],
    'هيكل': ['اداره', 'تنظيم'], 'يدير': ['اداره'],
    'ترتيب': ['اسبقيه'],
    'مؤتمرا': ['مؤتمر'], 'دوليا': ['دوليه', 'دولي'],
    'رسميا': ['رسميه', 'رسمي'], 'سفيرا': ['سفير'], 'وفدا': ['وفد'],
    'ضيفا': ['ضيف'], 'موقفا': ['موقف'],
    'تكريم': ['تشريفات'], 'تشريفات': ['تكريم'],
    'ينظم': ['تنظيم'], 'يستقبل': ['استقبال'], 'يقدم': ['تقديم'],
    'يودع': ['توديع'], 'يوقع': ['توقيع'], 'يرتب': ['ترتيب'],
    'ceremony': ['ceremonies'], 'ceremonies': ['ceremony'],
    'country': ['countries'], 'countries': ['country'],
    'embassy': ['embassies'], 'embassies': ['embassy'],
    'city': ['cities'], 'cities': ['city'],
    'party': ['parties'], 'parties': ['party'],
    'body': ['bodies'], 'bodies': ['body'],
}


def query_terms(q):
    """Mirror of lib/db.dart queryTerms: normalised, stopwords removed."""
    all_terms = [t for t in norm(q).split(' ') if t]
    kept = [t for t in all_terms
            if t not in AR_STOPWORDS and t not in EN_STOPWORDS]
    return kept if kept else all_terms


def _strip_prefix(w):
    for p in ('وال', 'فال', 'بال', 'لل', 'كال'):
        if w.startswith(p) and len(w) - len(p) >= 2:
            return w[len(p):]
    if w.startswith('ال') and len(w) - 2 >= 3:
        return w[2:]
    for p in ('و', 'ف', 'ب', 'ل', 'ك'):
        if w.startswith(p) and len(w) - 1 >= 2:
            return w[1:]
    return None


_PRONOUN_SUFFIXES = ('هما', 'هم', 'هن', 'كما', 'كن', 'ها', 'ه', 'ك', 'ي',
                      'نا', 'ني')


def _base_forms(t):
    """Mechanical morphology only: ONE leading strip (exactly the
    index-time _strip_prefix) + trailing attached pronouns / dual-plural
    endings. Chained stripping is forbidden (it eats real words)."""
    forms = {t}
    stripped = _strip_prefix(t)
    if stripped is not None:
        forms.add(stripped)
    extra = set()
    for f in list(forms):
        for suf in _PRONOUN_SUFFIXES:
            if f.endswith(suf) and len(f) - len(suf) >= 4:
                extra.add(f[:-len(suf)])
        for suf in ('ات', 'ان', 'ين', 'ون'):
            if f.endswith(suf) and len(f) - len(suf) >= 3:
                extra.add(f[:-len(suf)])
    forms |= extra
    return forms


def term_variants(t):
    """All variants of one term for FTS groups and title matching:
    base forms + wordVariants of each base + ال form. The term itself is
    always kept; generated variants are dropped when they are a stopword
    or shorter than 3 letters. Mirror of termVariants in
    lib/ai/retrieval_core.dart."""
    vs = {t}
    for b in _base_forms(t):
        vs.add(b)
        vs.update(WORD_VARIANTS.get(b, []))
        if b.startswith('ال') and len(b) > 4:
            vs.add(b[2:])
        else:
            vs.add('ال' + b)
    return {v for v in vs
            if v == t or (len(v) >= 3 and v not in AR_STOPWORDS
                          and v not in EN_STOPWORDS)}


def term_group(t):
    return '(' + ' OR '.join(f'"{v}"*' for v in sorted(term_variants(t))) + ')'


def count_title_matches(title, en_keywords, ar_keywords, terms):
    """R1 title-first key (mirror of countTitleMatchedTerms in
    retrieval_core.dart): distinct query terms matched in the title +
    en/ar index keywords, via term_variants."""
    text = norm(f'{title or ""} {en_keywords or ""} {ar_keywords or ""}')
    count = 0
    for t in dict.fromkeys(terms):
        if any(v in text for v in term_variants(t)):
            count += 1
    return count


# ── R1 guard mirror: Vienna Convention article range 1–53 ──
# Mirrors viennaArticleNumber/isViennaArticleOutOfRange in
# lib/ai/refusal_guard.dart (same regexes on the same normalised text).
_ARABIC_DIGITS = str.maketrans('٠١٢٣٤٥٦٧٨٩', '0123456789')


def vienna_article_number(query):
    q = norm(query).translate(_ARABIC_DIGITS)
    if 'فيينا' not in q and 'vienna' not in q:
        return None
    m = re.search(r'ماده\s*(\d+)', q)
    if m:
        return int(m.group(1))
    m = re.search(r'article\s*(\d+)', q)
    if m:
        return int(m.group(1))
    return None


def vienna_article_out_of_range(query):
    n = vienna_article_number(query)
    return n is not None and not (1 <= n <= 53)


def search_kb(cur, q, limit=3):
    """Three-stage FTS5 search mirroring RetrievalService.retrieve in
    lib/ai/retrieval_service.dart, with the R1 title-first rerank
    (formula F1): up to 20 candidates are fetched from the producing
    stage, re-ranked by title matches then FTS5 rank, and the top
    `limit` are scored.

    Returns (rows, stage) where rows are [{topic_id, title,
    title_matches}] and stage is one of 'and' / 'or' / 'longest' / 'none'.
    """
    terms = query_terms(q)
    if not terms:
        return [], 'none'
    sql = ('SELECT t.id, t.title, t.en_keywords, t.ar_keywords, f.rank '
           'FROM kb_topics t '
           'JOIN kb_topics_fts f ON f.rowid = t.rowid '
           'WHERE kb_topics_fts MATCH ? ORDER BY rank LIMIT ?')
    fetch = 20  # R1: core.ftsFetchLimit — rerank before cutting to top 3
    and_expr = ' AND '.join(term_group(t) for t in terms)
    rows = cur.execute(sql, (and_expr, fetch)).fetchall()
    stage = 'and'
    if not rows and len(terms) > 1:
        or_expr = ' OR '.join(term_group(t) for t in terms)
        rows = cur.execute(sql, (or_expr, fetch)).fetchall()
        stage = 'or'
    if not rows:
        longest = max(terms, key=len)
        rows = cur.execute(sql, (term_group(longest), fetch)).fetchall()
        stage = 'longest'
    if not rows:
        return [], 'none'
    cands = [{
        'topic_id': r[0],
        'title': r[1],
        'title_matches': count_title_matches(r[1], r[2], r[3], terms),
        'rank': r[4],
    } for r in rows]
    cands.sort(key=lambda c: (-c['title_matches'], c['rank']))
    top = cands[:limit]
    return [{'topic_id': c['topic_id'], 'title': c['title'],
             'title_matches': c['title_matches']} for c in top], stage


def detect_db_kind(cur):
    tables = {r[0] for r in cur.execute(
        "SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
    if 'kb_topics' not in tables:
        return None, tables
    if 'kb_topics_fts' not in tables:
        return None, tables
    kind = 'built'
    if 'meta' in tables:
        meta = dict(cur.execute('SELECT key, value FROM meta').fetchall())
        if meta.get('kb_mirror') == '1':
            kind = 'mirror'
    return kind, tables


def main():
    ap = argparse.ArgumentParser(description='Baseline retrieval measurer (hit@3) for the PROTOCOL AI 100-question set.')
    ap.add_argument('--db', required=True, help='SQLite DB containing kb_topics + kb_topics_fts')
    ap.add_argument('--questions', required=True, help='ai_questions.json')
    ap.add_argument('--out', required=True, help='output JSON path')
    args = ap.parse_args()

    if not os.path.exists(args.db):
        print(f'ERROR: database not found: {args.db}')
        print('The built DB (assets/marasim.db) does not exist yet; build a mirror '
              'from knowledge_base.json (see BASELINE_REPORT.md) or wait for tools/build_db.py.')
        sys.exit(2)
    with open(args.questions, encoding='utf-8') as fh:
        qdata = json.load(fh)
    questions = qdata['questions']
    assert len(questions) == 100, f'expected 100 questions, got {len(questions)}'

    con = sqlite3.connect(f'file:{args.db}?mode=ro', uri=True)
    cur = con.cursor()
    kind, tables = detect_db_kind(cur)
    if kind is None:
        missing = [t for t in ('kb_topics', 'kb_topics_fts') if t not in tables]
        print(f'ERROR: database {args.db} lacks required table(s): {missing}')
        sys.exit(2)
    kb_count = cur.execute('SELECT COUNT(*) FROM kb_topics').fetchone()[0]

    per_question = []
    for item in questions:
        top3, stage = search_kb(cur, item['text'], limit=3)
        top3_ids = [r['topic_id'] for r in top3]
        exp = item['expected']
        rec = {
            'id': item['id'],
            'category': item['category'],
            'lang': item['lang'],
            'text': item['text'],
            'expected_topic_id': exp['topic_id'],
            'expected_pages': exp['expected_pages'],
            'expected_answer_type': exp['expected_answer_type'],
            'stage': stage,
            'top3': top3,
            'top3_ids': top3_ids,
        }
        if item['category'] == 'hallucination':
            # Retrieval-level proxy only (see module docstring).
            rec['hit_at_3'] = None
            rec['refusal_correct'] = len(top3) == 0
            rec['failed'] = not rec['refusal_correct']
        else:
            rec['hit_at_3'] = exp['topic_id'] in top3_ids
            rec['refusal_correct'] = None
            rec['failed'] = not rec['hit_at_3']
        # R1: title matches of the top 3 (the rerank key), and the
        # Vienna-range guard decision (mirrors refusal_guard.dart).
        rec['top3_title_matches'] = [r.get('title_matches', 0) for r in top3]
        rec['guard_refusal'] = vienna_article_out_of_range(item['text'])
        rec['guard_reason'] = ('vienna_article_out_of_range'
                               if rec['guard_refusal'] else None)
        per_question.append(rec)
    con.close()

    cats = ['basic', 'applied', 'complex', 'sources']
    per_category = {}
    for c in cats:
        rows = [r for r in per_question if r['category'] == c]
        hits = sum(1 for r in rows if r['hit_at_3'])
        per_category[c] = {'n': len(rows), 'hits': hits,
                           'hit_at_3': round(hits / len(rows), 4) if rows else 0.0}
    answerable = [r for r in per_question if r['category'] != 'hallucination']
    ans_hits = sum(1 for r in answerable if r['hit_at_3'])
    hall = [r for r in per_question if r['category'] == 'hallucination']
    ref_ok = sum(1 for r in hall if r['refusal_correct'])
    guard_ok = sum(1 for r in hall if r['guard_refusal'])
    guard_fp = sum(1 for r in answerable if r['guard_refusal'])
    per_language = {}
    for lang in ('ar', 'en'):
        rows = [r for r in answerable if r['lang'] == lang]
        hits = sum(1 for r in rows if r['hit_at_3'])
        per_language[lang] = {'n': len(rows), 'hits': hits,
                              'hit_at_3': round(hits / len(rows), 4) if rows else 0.0}
    failed = [r for r in per_question if r['failed']]

    result = {
        'meta': {
            'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'db_path': os.path.abspath(args.db),
            'db_kind': kind,
            'db_kb_topics': kb_count,
            'db_size_bytes': os.path.getsize(args.db),
            'questions_file': os.path.abspath(args.questions),
            'normalisation': NORM_SOURCE,
            'retrieval': "FTS5 on kb_topics_fts, mirroring "
                         "RetrievalService.retrieve (lib/ai): queryTerms "
                         "(AR+EN stopwords removed) + 3 stages AND -> OR -> "
                         "longest term fetching 20 candidates, reranked "
                         "title-matches-first (F1) then FTS5 rank, top 3",
            'refusal_definition': "Retrieval-level proxy only: refusal_correct = search returned "
                                  "zero results. True refusal needs a generative model (not yet present). "
                                  "guard_refusal (R1) = the Vienna-article-range rule of "
                                  "lib/ai/refusal_guard.dart refuses the question (article number "
                                  "outside 1-53); it is measured for all 100 questions.",
        },
        'summary': {
            'total_questions': len(questions),
            'answerable_questions': len(answerable),
            'hallucination_questions': len(hall),
            'overall_hit_at_3': round(ans_hits / len(answerable), 4),
            'overall_hits': ans_hits,
            'per_category': per_category,
            'per_language': per_language,
            'refusal_correct_count': ref_ok,
            'refusal_correct_rate': round(ref_ok / len(hall), 4) if hall else 0.0,
            'guard_refusal_correct_count': guard_ok,
            'guard_refusal_correct_rate': round(guard_ok / len(hall), 4) if hall else 0.0,
            'guard_refusal_false_positives': guard_fp,
            'failed_count': len(failed),
            'failed_answerable': sum(1 for r in failed if r['category'] != 'hallucination'),
            'failed_hallucination_retrieval_noise': sum(1 for r in failed if r['category'] == 'hallucination'),
        },
        'per_question': per_question,
        'failed': failed,  # every failing question is kept here — never deleted
    }
    out_path = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
    s = result['summary']
    print(f"db: {args.db} (kind={kind}, kb_topics={kb_count})")
    print(f"overall hit@3 (80 answerable): {s['overall_hits']}/80 = {s['overall_hit_at_3']:.1%}")
    for c in cats:
        pc = per_category[c]
        print(f"  {c}: {pc['hits']}/{pc['n']} = {pc['hit_at_3']:.1%}")
    print(f"refusal-correct (retrieval proxy, 20 H): {ref_ok}/20 = {s['refusal_correct_rate']:.1%}")
    print(f"guard refusal (Vienna-range rule, 20 H): {guard_ok}/20 = {s['guard_refusal_correct_rate']:.1%} "
          f"(false positives on answerable: {guard_fp})")
    for lang, pl in s['per_language'].items():
        print(f"  lang {lang}: {pl['hits']}/{pl['n']} = {pl['hit_at_3']:.1%}")
    print(f"failed: {len(failed)} (answerable misses: {s['failed_answerable']}, "
          f"H retrieval noise: {s['failed_hallucination_retrieval_noise']})")
    print(f"wrote {out_path}")


if __name__ == '__main__':
    main()
