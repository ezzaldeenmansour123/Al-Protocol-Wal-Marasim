#!/usr/bin/env python3
"""Builds assets/marasim.db (SQLite + FTS5) for the PROTOCOL (البروتوكول والمراسم) app.

usage:
  python3 tools/build_db.py <seed-dir> <out.db>     # build (db_version 2)
  python3 tools/build_db.py --check <db>            # quick_check: counts + sample searches

Seed inputs (all inside tools/seed/ so CI can build offline from the repo):
  articles.json, countries.json, templates.json (v1 seeds, unchanged),
  knowledge_base.json  (54 topics extracted from Asaad Mansour's book,
                        copied verbatim from book/knowledge_base/),
  corrections_log.json (correction-rule log for kb_corrections),
  sources.json         (INTERNATIONAL_SOURCES registry: 8 verified + 3 unverified),
  kb_en_keywords.json  (R1 English index vocabulary: per-topic English
                        keywords — title translations + distinguishing
                        concept terms + cross-references from the book's
                        own chapter structure and from verified sources
                        (VCDR 1961, UN Charter). SEARCH INDEX ONLY, never
                        displayed as content; see its _doc field),
  article_source_map.md (per-article axis / section / source mapping, parsed
                        programmatically — never hand-edited into the builder).

R1 English-index design (deliberate): kb_topics gains two plain columns
`en_keywords` and `ar_keywords` (space-joined terms; the Arabic ones are
verified mechanically against each topic's own extracted text — see the
validation in build()). The FTS5 schema is UNCHANGED (still
title/summary/definition/explanation): the indexed *title* value is
search_norm(title + ' ' + en_keywords + ' ' + ar_keywords), so English
terms and Arabic topic vocabulary absent from the title match through
the title column. This keeps the asset DB refreshable into already
installed v2 databases (lib/db.dart copies FTS shadow tables by common
columns and the FTS definition never changes). Consequence, documented:
a manual ('rebuild') on kb_topics_fts would re-index the raw Arabic
title only and LOSE the keyword terms — never run it; rebuild with
this script instead.

The builder FAILS LOUDLY on any validation error: article count != 49,
any of the 16 protocol sections missing, a bad rule_type, a country missing
a required field, a bad national-day format, duplicate template keys,
kb_topics != 54, kb word total != 36535, any topic without a title or with
invalid book/pdf pages, an article without an axis (or axis outside 1-7),
a source_code not present in the sources table, a source_url on any article
whose source_status is not 'verified', or any URL stored for an unverified
source. Nothing is invented: Vienna Convention citations in the seed use
only the article numbers the team verified (VCDR 1961 Arts. 13-14, 22, 29,
41); anything else is cited generally or labelled common practice.
Knowledge-base topics are copied verbatim from knowledge_base.json; the
'مصحح آلياً' status means the documented automatic-correction dictionary
was applied — it does NOT mean a full human review (see meta
kb_text_status_note). Proposed (🔍) sources are recorded as
source_status='proposed' with the first proposed code and NO source_url;
only the ten ✅ articles keep the verified source_url they already carry
in the seed. Article 48's URL (https://treaties.un.org/) is the generic
portal it already carried, not a specific VCLT-1969 document link — that
gap is recorded in the DB build report, not silently fixed here.
"""
import hashlib
import json
import os
import re
import sqlite3
import sys

SECTIONS = [
    'المبادئ العامة للبروتوكول',
    'العلاقات الدبلوماسية',
    'الأسبقية الدبلوماسية',
    'الألقاب الرسمية',
    'الأعلام والرموز الوطنية',
    'المراسم الرئاسية',
    'استقبال الوفود',
    'المراسم الملكية',
    'الزيارات الرسمية',
    'المؤتمرات الدولية',
    'الاجتماعات الثنائية',
    'توقيع الاتفاقيات',
    'المآدب الرسمية',
    'المراسلات الدبلوماسية',
    'الإتيكيت الدولي',
    'مراسم العزاء والتعازي الرسمية',
]

RULE_TYPES = {'ملزمة دوليًا', 'ممارسة شائعة', 'عرف محلي', 'خاص بدولة'}
MMDD = re.compile(r'^\d{2}-\d{2}$')

# Knowledge-base expectations (KB report §1/§4 + knowledge_base.json meta).
KB_TOPICS_EXPECTED = 54
KB_WORDS_EXPECTED = 36535
KB_MATCH_TYPES = {'مباشر', 'الأقرب', 'فجوة'}
KB_SOURCE_TYPES = {'كتاب', 'مرجع خارجي'}
# Wording from KNOWLEDGE_BASE_REPORT.md §4: 'مصحح آلياً' is an automatic
# dictionary correction, NOT a full human review.
KB_TEXT_STATUS_NOTE = (
    'حالة «مصحح آلياً» تعني أن قاموس التصحيح الآلي الموثّق طُبّق ولم تبقَ '
    'أي صورة من الأنماط الموثقة — ولا تعني مراجعة بشرية كاملة للنص؛ '
    'المراجعة البشرية صفحة صفحة ما زالت مطلوبة قبل اعتماد النص نهائياً.'
)

TASHKEEL = re.compile(r'[\u064B-\u065F\u06D6-\u06ED\u0640]')
ALEF = re.compile(r'[إأآٱ]')
NONWORD = re.compile(r'[^\u0621-\u064A\u0660-\u0669a-zA-Z0-9\s]')
SPACES = re.compile(r'\s+')


def norm(s):
    """Arabic normalization. MUST stay identical to normalizeAr in lib/db.dart.

    R1: Latin letters are lower-cased here (and in normalizeAr) so English
    stopwords, variants and title matching work regardless of question
    capitalisation ('What' == 'what'). Arabic is unaffected; FTS5
    unicode61 folds ASCII case anyway, so indexed behaviour is unchanged.
    """
    if s is None:
        return ''
    s = str(s).lower()
    s = s.replace('\u0648\u0670', 'ا').replace('\u0649\u0670', 'ى').replace('\u0670', 'ا')
    s = TASHKEEL.sub('', s)
    s = ALEF.sub('ا', s).replace('ى', 'ي').replace('ة', 'ه')
    s = NONWORD.sub(' ', s)
    return SPACES.sub(' ', s).strip()


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


def search_norm(s):
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


def fail(msg):
    print(f'ERROR: {msg}')
    sys.exit(1)


def load_json(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def resolve_seed_file(seed_dir, name, *relative_fallbacks):
    """Seed files live in tools/seed/; fall back to the canonical locations
    under ~/workspace/protocol/ for local development only."""
    primary = os.path.join(seed_dir, name)
    if os.path.exists(primary):
        return primary
    for rel in relative_fallbacks:
        cand = os.path.normpath(os.path.join(seed_dir, rel))
        if os.path.exists(cand):
            return cand
    fail(f'seed file not found: {name} (looked in {primary} and fallbacks)')


# ── ARTICLE_SOURCE_MAP.md parsing ──────────────────────────────────────────
MAP_ROW = re.compile(r'^\|\s*(\d+)\s*\|')
AXIS_RE = re.compile(r'المحور\s*(\d+)')
# e.g. 'ب1 ف1 — م2: تعريف البروتوكولات' -> 'ب1 ف1 م2'; also matches the
# 'الأقرب: ب2 ف3 — م4: ...' form used when no mabhas matches directly.
SEC_RE = re.compile(r'ب(\d)\s*ف(\d)\s*(?:—\s*م(\d+))?')
CODE_RE = re.compile(r'[A-Z][A-Z0-9]+(?:-[A-Z0-9]+)+')
STATUS_EMOJI = {'✅': 'verified', '🔍': 'proposed', '⚠️': 'none'}


def parse_source_map(path):
    """Returns {article_id: {axis, section_code, source_code, source_status}}.

    Parsed from the Markdown table, never hand-coded: column 4 is the axis
    ('المحور N — ...'), column 5 the mabhas ('بN فN — مN: ...'), column 8
    the proposed source(s) (first code wins), column 9 the status emoji
    (✅ verified incl. '✅ جزئياً', 🔍 proposed, ⚠️ none).
    """
    mapping = {}
    with open(path, encoding='utf-8') as fh:
        for ln in fh:
            m = MAP_ROW.match(ln.strip())
            if not m:
                continue
            cells = [c.strip() for c in ln.strip().strip('|').split('|')]
            if len(cells) < 10:
                fail(f'source map: malformed row: {ln.strip()[:120]}')
            aid = int(m.group(1))
            if aid in mapping:
                fail(f'source map: duplicate article {aid}')
            axis_m = AXIS_RE.search(cells[3])
            if not axis_m:
                fail(f'source map: article {aid}: no axis in {cells[3]!r}')
            axis = int(axis_m.group(1))
            if not 1 <= axis <= 7:
                fail(f'source map: article {aid}: axis {axis} outside 1-7')
            sec_m = SEC_RE.search(cells[4])
            if not sec_m:
                fail(f'source map: article {aid}: no section code in {cells[4]!r}')
            section_code = f"ب{sec_m.group(1)} ف{sec_m.group(2)}"
            if sec_m.group(3):
                section_code += f" م{sec_m.group(3)}"
            status = None
            for emoji, value in STATUS_EMOJI.items():
                if cells[8].startswith(emoji):
                    status = value
                    break
            if status is None:
                fail(f'source map: article {aid}: unknown status {cells[8]!r}')
            codes = CODE_RE.findall(cells[7])
            source_code = codes[0] if codes else None
            if status == 'none' and source_code is not None:
                fail(f'source map: article {aid}: status none but code {source_code}')
            mapping[aid] = {
                'axis': axis,
                'section_code': section_code,
                'source_code': source_code,
                'source_status': status,
            }
    if sorted(mapping) != list(range(1, 50)):
        fail(f'source map: expected articles 1-49, got {sorted(mapping)}')
    return mapping


def build(seed_dir, out):
    articles = load_json(os.path.join(seed_dir, 'articles.json'))
    countries = load_json(os.path.join(seed_dir, 'countries.json'))
    templates = load_json(os.path.join(seed_dir, 'templates.json'))

    kb_path = resolve_seed_file(
        seed_dir, 'knowledge_base.json',
        '../../../book/knowledge_base/knowledge_base.json')
    kb = load_json(kb_path)
    topics = kb.get('topics')
    if not isinstance(topics, list):
        fail('knowledge_base.json: no "topics" list')

    corr_path = resolve_seed_file(
        seed_dir, 'corrections_log.json',
        '../../../book/knowledge_base/corrections_log.json')
    corr_log = load_json(corr_path)

    src_path = resolve_seed_file(
        seed_dir, 'sources.json',
        '../../../sources/INTERNATIONAL_SOURCES.json')
    src_reg = load_json(src_path)
    sources = src_reg.get('sources')
    if not isinstance(sources, list):
        fail('sources.json: no "sources" list')

    map_path = resolve_seed_file(
        seed_dir, 'article_source_map.md',
        '../../../sources/ARTICLE_SOURCE_MAP.md')
    art_map = parse_source_map(map_path)

    # ── Validation: English index keywords (R1) ──
    # Search index only: title translations + distinguishing concept terms
    # + cross-references from the book's chapter structure / verified
    # sources (see kb_en_keywords.json _doc). Must cover every topic id
    # exactly once; every keyword must be a lowercase ASCII token.
    en_kw_path = os.path.join(seed_dir, 'kb_en_keywords.json')
    if not os.path.exists(en_kw_path):
        fail(f'seed file not found: kb_en_keywords.json (looked in {en_kw_path})')
    en_kw_doc = load_json(en_kw_path)
    en_keywords = en_kw_doc.get('keywords')
    if not isinstance(en_keywords, dict):
        fail('kb_en_keywords.json: no "keywords" object')
    topic_ids = {t['id'] for t in topics}
    if set(en_keywords) != topic_ids:
        fail('kb_en_keywords.json: keys must be exactly the 54 kb topic ids; '
             f"missing={sorted(topic_ids - set(en_keywords))} "
             f"extra={sorted(set(en_keywords) - topic_ids)}")
    EN_TOKEN = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)?$')
    en_terms_total = 0
    for tid, kws in en_keywords.items():
        if not isinstance(kws, list) or not kws:
            fail(f'kb_en_keywords.json: topic {tid}: empty keyword list')
        if len(set(kws)) != len(kws):
            fail(f'kb_en_keywords.json: topic {tid}: duplicate keywords')
        for kw in kws:
            if not isinstance(kw, str) or not EN_TOKEN.match(kw):
                fail(f'kb_en_keywords.json: topic {tid}: bad keyword {kw!r} '
                     '(lowercase ASCII letters/digits, one optional hyphen)')
        en_terms_total += len(kws)
    print(f'en_keywords: {len(en_keywords)} topics, {en_terms_total} terms')

    # ── Validation: Arabic index keywords (R1) ──
    # Same search-index-only status as en_keywords, but Arabic terms that
    # occur in the topic's own extracted text yet are absent from its
    # title (so title-first ranking missed natural phrasings, e.g. مطار
    # for the reception topic). GROUNDING RULE, enforced here: every
    # keyword must occur (after norm) in the topic's full extracted text
    # (title + summary + definition + explanation + rules + procedures +
    # examples + mistakes + key points + subsections). A keyword absent
    # from the topic's text is refused — it would be invented vocabulary.
    ar_kw_path = os.path.join(seed_dir, 'kb_ar_keywords.json')
    if not os.path.exists(ar_kw_path):
        fail(f'seed file not found: kb_ar_keywords.json (looked in {ar_kw_path})')
    ar_kw_doc = load_json(ar_kw_path)
    ar_keywords = ar_kw_doc.get('keywords')
    if not isinstance(ar_keywords, dict):
        fail('kb_ar_keywords.json: no "keywords" object')
    if not set(ar_keywords) <= topic_ids:
        fail('kb_ar_keywords.json: unknown topic ids: '
             f"{sorted(set(ar_keywords) - topic_ids)}")
    AR_TOKEN = re.compile(r'^[\u0621-\u064A0-9]+$')
    ar_terms_total = 0
    for tid, kws in ar_keywords.items():
        if not isinstance(kws, list) or not kws:
            fail(f'kb_ar_keywords.json: topic {tid}: empty keyword list')
        if len(set(kws)) != len(kws):
            fail(f'kb_ar_keywords.json: topic {tid}: duplicate keywords')
        topic = next(t for t in topics if t['id'] == tid)
        summ = topic['summary']
        blob_parts = [topic['title'], summ.get('summary') or '',
                      summ.get('definition') or '', summ.get('explanation') or '']
        for f in ('rules', 'procedures', 'examples', 'common_mistakes',
                  'key_points'):
            blob_parts += [str(x) for x in (summ.get(f) or [])]
        blob_parts += [str(x) for x in (topic.get('subsections') or [])]
        blob = norm(' '.join(blob_parts))
        for kw in kws:
            if not isinstance(kw, str) or not AR_TOKEN.match(kw):
                fail(f'kb_ar_keywords.json: topic {tid}: bad keyword {kw!r} '
                     '(Arabic letters/digits only, already normalised: ة→ه)')
            if norm(kw) not in blob:
                fail(f'kb_ar_keywords.json: topic {tid}: keyword {kw!r} does '
                     'NOT occur in the topic extracted text — refusing to '
                     'index invented vocabulary')
        ar_terms_total += len(kws)
    print(f'ar_keywords: {len(ar_keywords)} topics, {ar_terms_total} terms')

    # ── Validation: sources registry ──
    categories = set(src_reg.get('categories') or [])
    src_by_code = {}
    n_verified = n_unverified = 0
    for s in sources:
        code = s.get('id')
        if not code or code in src_by_code:
            fail(f"sources.json: bad/duplicate source code {code!r}")
        for f in ('name_ar', 'name_en', 'publisher', 'category', 'scope',
                  'review_date'):
            if not str(s.get(f, '')).strip():
                fail(f'sources.json: source {code}: empty field {f}')
        if categories and s['category'] not in categories:
            fail(f"sources.json: source {code}: unknown category {s['category']!r}")
        verified = s.get('verification_status') == 'verified'
        raw_url = s.get('url') or s.get('url_ar') or ''
        if verified:
            n_verified += 1
            if not str(raw_url).strip():
                fail(f'sources.json: verified source {code} has no URL')
        else:
            n_unverified += 1
            # NEVER store a URL for an unverified source.
            if str(raw_url or '').strip():
                fail(f'sources.json: unverified source {code} carries a URL '
                     f'({raw_url!r}) — refusing to store it')
        src_by_code[code] = {
            'code': code, 'name_ar': s['name_ar'], 'name_en': s['name_en'],
            'publisher': s['publisher'],
            'url': str(raw_url).strip() if verified else '',
            'classification': s['category'], 'scope': s['scope'],
            'verified': 1 if verified else 0,
            'review_date': s['review_date'],
        }
    summary = src_reg.get('summary') or {}
    if summary:
        if summary.get('verified') != n_verified:
            fail(f"sources.json: summary verified={summary.get('verified')} "
                 f"but counted {n_verified}")
        if summary.get('unverified') != n_unverified:
            fail(f"sources.json: summary unverified={summary.get('unverified')} "
                 f"but counted {n_unverified}")
    print(f'sources: {len(sources)} ({n_verified} verified, {n_unverified} unverified)')

    # ── Validation: articles / countries / templates (v1 rules, exact counts) ──
    if len(articles) != 49:
        fail(f'expected exactly 49 articles, got {len(articles)}')
    seen_sections = set()
    for a in articles:
        for f in ('title', 'section', 'body', 'rule_type', 'source_name', 'source_org'):
            if not str(a.get(f, '')).strip():
                fail(f"article {a.get('id')}: empty field {f}")
        if a['section'] not in SECTIONS:
            fail(f"article {a.get('id')}: unknown section {a['section']!r}")
        if a['rule_type'] not in RULE_TYPES:
            fail(f"article {a.get('id')}: bad rule_type {a['rule_type']!r}")
        seen_sections.add(a['section'])
        # Map-derived fields: every article must have an axis (fail loudly).
        aid = a['id']
        if aid not in art_map:
            fail(f'article {aid}: no entry in ARTICLE_SOURCE_MAP.md (no axis)')
        entry = art_map[aid]
        code = entry['source_code']
        if code is not None:
            if code not in src_by_code:
                fail(f'article {aid}: source_code {code} not in sources table')
            if not src_by_code[code]['verified']:
                fail(f'article {aid}: source_code {code} is not a verified source')
        seed_url = str(a.get('source_url', '') or '').strip()
        if entry['source_status'] == 'verified':
            if not seed_url:
                fail(f"article {aid}: status verified but seed source_url is empty")
        else:
            # Proposed (🔍) and none (⚠️) articles never carry a source_url:
            # a proposed source is a suggestion for human review, not a citation.
            if seed_url:
                fail(f"article {aid}: status {entry['source_status']} but seed "
                     f"carries source_url {seed_url!r}")
    missing = [s for s in SECTIONS if s not in seen_sections]
    if missing:
        fail(f'sections with no article: {missing}')

    if len(countries) != 30:
        fail(f'expected exactly 30 countries, got {len(countries)}')
    for c in countries:
        for f in ('name_ar', 'name_en', 'capital', 'languages', 'currency',
                  'timezones', 'system', 'national_day_name', 'protocol_note',
                  'titles_note', 'flag'):
            if not str(c.get(f, '')).strip():
                fail(f"country {c.get('id')}: empty field {f}")
        nd = c.get('national_day')
        if nd is not None and not MMDD.match(str(nd)):
            fail(f"country {c.get('id')}: bad national_day {nd!r}")

    if len(templates) != 7:
        fail(f'expected exactly 7 templates, got {len(templates)}')
    keys = [t.get('key') for t in templates]
    if len(set(keys)) != len(keys):
        fail('duplicate template keys')
    for t in templates:
        for f in ('key', 'title_ar', 'title_en', 'category', 'body_ar', 'body_en'):
            if not str(t.get(f, '')).strip():
                fail(f"template {t.get('id')}: empty field {f}")

    # ── Validation: knowledge base (copied verbatim, never edited here) ──
    kb_meta = kb.get('meta') or {}
    if kb_meta.get('topics_total') not in (None, KB_TOPICS_EXPECTED):
        fail(f"knowledge_base.json meta topics_total={kb_meta.get('topics_total')}")
    if len(topics) != KB_TOPICS_EXPECTED:
        fail(f'expected exactly {KB_TOPICS_EXPECTED} kb_topics, got {len(topics)}')
    total_words = 0
    total_corr = 0
    kb_links = []
    seen_ids = set()
    for t in topics:
        tid = t.get('id')
        if not tid or tid in seen_ids:
            fail(f'kb topic: bad/duplicate id {tid!r}')
        seen_ids.add(tid)
        for f in ('part', 'chapter', 'mabhas', 'title', 'source',
                  'source_file', 'source_type', 'text_status', 'match_type'):
            if not str(t.get(f, '')).strip():
                fail(f'kb topic {tid}: empty field {f}')
        if t['source_type'] not in KB_SOURCE_TYPES:
            fail(f"kb topic {tid}: bad source_type {t['source_type']!r}")
        if t['match_type'] not in KB_MATCH_TYPES:
            fail(f"kb topic {tid}: bad match_type {t['match_type']!r}")
        ps, pe = t.get('pdf_page_start'), t.get('pdf_page_end')
        if not isinstance(ps, int) or not isinstance(pe, int) or pe < ps or ps < 1:
            fail(f'kb topic {tid}: invalid pdf pages {ps}-{pe}')
        bs, be = t.get('book_page_start'), t.get('book_page_end')
        if (bs is None) != (be is None):
            fail(f'kb topic {tid}: book pages half-null ({bs}, {be})')
        if bs is not None and (not isinstance(bs, int) or not isinstance(be, int)
                               or be < bs or bs < 1):
            fail(f'kb topic {tid}: invalid book pages {bs}-{be}')
        if bs is None and not str(t.get('book_page_label', '')).strip():
            fail(f'kb topic {tid}: null book pages without a book_page_label')
        if not isinstance(t.get('word_count'), int) or t['word_count'] < 0:
            fail(f"kb topic {tid}: bad word_count {t.get('word_count')!r}")
        if not isinstance(t.get('char_count'), int) or t['char_count'] < 0:
            fail(f"kb topic {tid}: bad char_count {t.get('char_count')!r}")
        total_words += t['word_count']
        total_corr += int(t.get('corrections_applied') or 0)
        summ = t.get('summary') or {}
        if not str(summ.get('summary') or '').strip():
            fail(f'kb topic {tid}: empty summary.summary')
        for f in ('rules', 'procedures', 'examples', 'common_mistakes', 'key_points'):
            if not isinstance(summ.get(f), list):
                fail(f'kb topic {tid}: summary.{f} is not a list')
        if not isinstance(t.get('subsections'), list):
            fail(f'kb topic {tid}: subsections is not a list')
        direct = t.get('matched_articles_direct') or []
        nearest = t.get('matched_articles_nearest') or []
        if set(direct) & set(nearest):
            fail(f'kb topic {tid}: article in both direct and nearest lists')
        for a_no in list(direct) + list(nearest):
            if not isinstance(a_no, int) or not 1 <= a_no <= 49:
                fail(f'kb topic {tid}: bad linked article {a_no!r}')
            kb_links.append((tid, a_no,
                             'direct' if a_no in direct else 'nearest'))
    if total_words != KB_WORDS_EXPECTED:
        fail(f'kb word total {total_words} != expected {KB_WORDS_EXPECTED}')
    if total_corr != int(corr_log.get('total_applications', -1)):
        fail(f'kb corrections sum {total_corr} != corrections_log total '
             f"{corr_log.get('total_applications')}")

    # ── Validation: corrections log ──
    by_rule = corr_log.get('by_rule')
    if not isinstance(by_rule, list) or not by_rule:
        fail('corrections_log.json: empty/missing by_rule list')
    rule_sum = 0
    for r in by_rule:
        if not str(r.get('rule', '')).strip():
            fail('corrections_log.json: rule with empty name')
        if not isinstance(r.get('count'), int) or r['count'] < 1:
            fail(f"corrections_log.json: bad count for rule {r.get('rule')!r}")
        rule_sum += r['count']
    if rule_sum != int(corr_log.get('total_applications', -1)):
        fail(f"corrections_log: by_rule sum {rule_sum} != total "
             f"{corr_log.get('total_applications')}")

    # ── Build ──
    if os.path.exists(out):
        os.remove(out)
    con = sqlite3.connect(out)
    cur = con.cursor()
    cur.executescript('''
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE articles(id INTEGER PRIMARY KEY, title TEXT, section TEXT,
        body TEXT, rule_type TEXT, source_name TEXT, source_org TEXT,
        source_url TEXT, reviewed TEXT,
        source_code TEXT, axis INTEGER, section_code TEXT, source_status TEXT);
    CREATE TABLE sources(id INTEGER PRIMARY KEY, code TEXT UNIQUE,
        name_ar TEXT, name_en TEXT, publisher TEXT, url TEXT,
        classification TEXT, scope TEXT, verified INTEGER, review_date TEXT);
    CREATE TABLE countries(id INTEGER PRIMARY KEY, name_ar TEXT, name_en TEXT,
        capital TEXT, languages TEXT, currency TEXT, timezones TEXT,
        system TEXT, national_day TEXT, national_day_name TEXT,
        protocol_note TEXT, titles_note TEXT, flag TEXT,
        source_name TEXT, source_org TEXT, source_url TEXT, reviewed TEXT);
    CREATE TABLE templates(id INTEGER PRIMARY KEY, key TEXT UNIQUE,
        title_ar TEXT, title_en TEXT, category TEXT, body_ar TEXT,
        body_en TEXT, source_name TEXT, reviewed TEXT);
    CREATE TABLE national_days(country_id INTEGER, mmdd TEXT, name TEXT);
    CREATE TABLE favorites(kind TEXT, ref_id INTEGER, created_at TEXT,
        PRIMARY KEY(kind, ref_id));
    CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT,
        type TEXT, date TEXT, place TEXT, guests_expected INTEGER,
        notes TEXT, created_at TEXT);
    CREATE TABLE event_guests(id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER, name TEXT, title TEXT, country TEXT,
        rank_category TEXT, credential_date TEXT, sort_order INTEGER);
    CREATE TABLE event_program(id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER, time TEXT, title TEXT, notes TEXT, sort_order INTEGER);
    CREATE TABLE checklist_items(id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER, text TEXT, done INTEGER DEFAULT 0, sort_order INTEGER);
    CREATE TABLE seating_plans(id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT, shape TEXT, seats INTEGER, created_at TEXT, updated_at TEXT);
    CREATE TABLE seating_assignments(id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER, seat_index INTEGER, guest_name TEXT,
        guest_title TEXT, country TEXT, rank_category TEXT);
    CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT);
    -- Knowledge base (KNOWLEDGE_BASE_REPORT.md §5, verbatim schema).
    CREATE TABLE kb_topics (
      id            TEXT PRIMARY KEY,
      part          TEXT NOT NULL,
      chapter       TEXT NOT NULL,
      mabhas        TEXT NOT NULL,
      title         TEXT NOT NULL,
      subsections   TEXT,
      summary       TEXT,
      definition    TEXT,
      explanation   TEXT,
      rules_json    TEXT,
      procedures_json TEXT,
      examples_json TEXT,
      mistakes_json TEXT,
      key_points_json TEXT,
      book_page_start INTEGER,
      book_page_end   INTEGER,
      book_page_label TEXT,
      pdf_page_start  INTEGER NOT NULL,
      pdf_page_end    INTEGER NOT NULL,
      source_file   TEXT NOT NULL,
      source        TEXT NOT NULL,
      source_type   TEXT NOT NULL DEFAULT 'كتاب',
      text_status   TEXT NOT NULL,
      corrections_applied INTEGER NOT NULL DEFAULT 0,
      residual_garble_count INTEGER NOT NULL DEFAULT 0,
      content_limitation TEXT,
      match_type    TEXT NOT NULL,
      match_note    TEXT,
      char_count    INTEGER,
      word_count    INTEGER,
      en_keywords   TEXT,
      ar_keywords   TEXT
    );
    CREATE TABLE kb_topic_articles (
      topic_id     TEXT NOT NULL REFERENCES kb_topics(id),
      article_no   INTEGER NOT NULL,
      relation     TEXT NOT NULL,
      PRIMARY KEY (topic_id, article_no)
    );
    CREATE TABLE kb_corrections (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      rule        TEXT NOT NULL,
      applications INTEGER NOT NULL,
      example_replacement TEXT
    );
    CREATE VIRTUAL TABLE articles_fts USING fts5(
        title, body, section, tokenize='unicode61 remove_diacritics 0');
    CREATE VIRTUAL TABLE countries_fts USING fts5(
        name_ar, name_en, capital, tokenize='unicode61 remove_diacritics 0');
    CREATE VIRTUAL TABLE templates_fts USING fts5(
        title_ar, title_en, body_ar, tokenize='unicode61 remove_diacritics 0');
    -- FTS5 over the knowledge base (KB report §5). External-content table:
    -- indexed terms are the search-normalized text inserted below (same
    -- normalization as articles_fts, so the app's normalizeAr queries
    -- match); column values at query time come from kb_topics itself.
    -- Do NOT run ('rebuild') on this table: it would re-index the raw
    -- (unnormalized) kb_topics text and break normalized search.
    CREATE VIRTUAL TABLE kb_topics_fts USING fts5(
        title, summary, definition, explanation,
        content='kb_topics', content_rowid='rowid', tokenize='unicode61');
    ''')

    for a in articles:
        entry = art_map[a['id']]
        url = str(a.get('source_url', '') or '').strip() \
            if entry['source_status'] == 'verified' else ''
        cur.execute(
            'INSERT INTO articles VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
            (a['id'], a['title'], a['section'], a['body'], a['rule_type'],
             a['source_name'], a['source_org'], url,
             a.get('reviewed', '2026-11-24'),
             entry['source_code'], entry['axis'], entry['section_code'],
             entry['source_status']))
        cur.execute('INSERT INTO articles_fts(rowid, title, body, section) VALUES(?,?,?,?)',
                    (a['id'], search_norm(a['title']), search_norm(a['body']),
                     search_norm(a['section'])))
    print(f'articles: {len(articles)} ({len(seen_sections)} sections)')

    for s in sources:
        v = src_by_code[s['id']]
        cur.execute(
            'INSERT INTO sources(code, name_ar, name_en, publisher, url, '
            'classification, scope, verified, review_date) '
            'VALUES(?,?,?,?,?,?,?,?,?)',
            (v['code'], v['name_ar'], v['name_en'], v['publisher'], v['url'],
             v['classification'], v['scope'], v['verified'], v['review_date']))
    print(f'sources: {len(sources)}')

    nd_count = 0
    for c in countries:
        cur.execute('INSERT INTO countries VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                    (c['id'], c['name_ar'], c['name_en'], c['capital'],
                     c['languages'], c['currency'], c['timezones'], c['system'],
                     c.get('national_day'), c['national_day_name'],
                     c['protocol_note'], c['titles_note'], c['flag'],
                     c['source_name'], c['source_org'], c.get('source_url', ''),
                     c.get('reviewed', '2026-11-24')))
        cur.execute('INSERT INTO countries_fts(rowid, name_ar, name_en, capital) VALUES(?,?,?,?)',
                    (c['id'], search_norm(c['name_ar']), search_norm(c['name_en']),
                     search_norm(c['capital'])))
        if c.get('national_day'):
            cur.execute('INSERT INTO national_days VALUES(?,?,?)',
                        (c['id'], c['national_day'], c['national_day_name']))
            nd_count += 1
    print(f'countries: {len(countries)} (national days: {nd_count})')

    for t in templates:
        cur.execute('INSERT INTO templates VALUES(?,?,?,?,?,?,?,?,?)',
                    (t['id'], t['key'], t['title_ar'], t['title_en'], t['category'],
                     t['body_ar'], t['body_en'], t['source_name'],
                     t.get('reviewed', '2026-11-24')))
        cur.execute('INSERT INTO templates_fts(rowid, title_ar, title_en, body_ar) VALUES(?,?,?,?)',
                    (t['id'], search_norm(t['title_ar']), search_norm(t['title_en']),
                     search_norm(t['body_ar'])))
    print(f'templates: {len(templates)}')

    for t in topics:
        summ = t['summary']
        cur.execute(
            'INSERT INTO kb_topics VALUES(' + ','.join('?' * 32) + ')',
            (t['id'], t['part'], t['chapter'], t['mabhas'], t['title'],
             json.dumps(t.get('subsections') or [], ensure_ascii=False),
             summ.get('summary'),
             summ.get('definition'), summ.get('explanation'),
             json.dumps(summ.get('rules') or [], ensure_ascii=False),
             json.dumps(summ.get('procedures') or [], ensure_ascii=False),
             json.dumps(summ.get('examples') or [], ensure_ascii=False),
             json.dumps(summ.get('common_mistakes') or [], ensure_ascii=False),
             json.dumps(summ.get('key_points') or [], ensure_ascii=False),
             t.get('book_page_start'), t.get('book_page_end'),
             t.get('book_page_label'),
             t['pdf_page_start'], t['pdf_page_end'],
             t['source_file'], t['source'], t['source_type'],
             t['text_status'], int(t.get('corrections_applied') or 0),
             int(t.get('residual_garble_count') or 0),
             t.get('content_limitation'),
             t['match_type'], t.get('match_note'),
             t.get('char_count'), t.get('word_count'),
             ' '.join(en_keywords[t['id']]),
             ' '.join(ar_keywords.get(t['id']) or [])))
    for tid, a_no, rel in kb_links:
        cur.execute('INSERT INTO kb_topic_articles VALUES(?,?,?)',
                    (tid, a_no, rel))
    print(f'kb_topics: {len(topics)} ({total_words} words, '
          f'{len(kb_links)} topic-article links)')

    for r in by_rule:
        cur.execute('INSERT INTO kb_corrections(rule, applications, '
                    'example_replacement) VALUES(?,?,?)',
                    (r['rule'], r['count'], r.get('example_replacement')))
    print(f'kb_corrections: {len(by_rule)} rules ({rule_sum} applications)')

    # Index normalized KB text into the external-content FTS table.
    # R1: the indexed TITLE is title + en_keywords + ar_keywords, so
    # English terms and Arabic topic vocabulary absent from the title
    # match through the (unchanged) title column; kb_topics.title itself
    # stays Arabic-only. Never run ('rebuild') on this table: it would
    # re-index the raw kb_topics text and drop the keyword terms.
    for row in cur.execute(
            'SELECT rowid, title, summary, definition, explanation, '
            'en_keywords, ar_keywords FROM kb_topics'
    ).fetchall():
        cur.execute(
            'INSERT INTO kb_topics_fts(rowid, title, summary, definition, explanation) '
            'VALUES(?,?,?,?,?)',
            (row[0], search_norm(f"{row[1] or ''} {row[5] or ''} {row[6] or ''}"),
             search_norm(row[2]),
             search_norm(row[3]), search_norm(row[4])))
    n_fts = cur.execute('SELECT COUNT(*) FROM kb_topics_fts').fetchone()[0]
    if n_fts != len(topics):
        fail(f'kb_topics_fts indexed {n_fts} rows, expected {len(topics)}')

    for fts in ('articles_fts', 'countries_fts', 'templates_fts', 'kb_topics_fts'):
        cur.execute(f"INSERT INTO {fts}({fts}) VALUES('optimize')")

    import datetime
    cur.executemany('INSERT INTO meta VALUES(?,?)', [
        ('db_version', '2'),
        ('built', datetime.date.today().isoformat()),
        ('articles', str(len(articles))),
        ('countries', str(len(countries))),
        ('templates', str(len(templates))),
        ('national_days', str(nd_count)),
        ('kb_topics', str(len(topics))),
        ('kb_words', str(total_words)),
        ('kb_text_status_note', KB_TEXT_STATUS_NOTE),
        ('kb_corrections', str(rule_sum)),
        ('kb_sources_verified', str(n_verified)),
        ('kb_sources_unverified', str(n_unverified)),
        ('kb_en_keywords_topics', str(len(en_keywords))),
        ('kb_en_keywords_terms', str(en_terms_total)),
        ('kb_ar_keywords_topics', str(len(ar_keywords))),
        ('kb_ar_keywords_terms', str(ar_terms_total)),
        ('kb_source', str(kb_meta.get('book', ''))),
        ('credits', 'Protocol knowledge: curated by the PROTOCOL team from the '
                    'Vienna Convention on Diplomatic Relations 1961, the Vienna '
                    'Convention on Consular Relations 1963, UN documents and '
                    'published foreign-ministry protocol guides; every article '
                    'cites its source. Country facts: UN member-state directory '
                    'and CIA World Factbook (public facts).'),
    ])
    con.commit()
    con.execute('VACUUM')
    con.close()
    h = hashlib.sha256(open(out, 'rb').read()).hexdigest()
    open(out + '.sha256', 'w').write(h)
    print(f'OK size={os.path.getsize(out)/1e6:.2f}MB sha256={h[:12]}…')


def search_expr(normed):
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


KB_PROBE_QUERIES = (
    'الأسبقية',
    'تقديم أوراق اعتماد السفراء',
    'مراسم توديع كبار الشخصيات',
    'الأعلام والنشيد',
    'الزيارات الرسمية',
)


def check(db_path):
    con = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
    cur = con.cursor()
    for tbl in ('articles', 'countries', 'templates', 'national_days',
                'kb_topics', 'kb_topic_articles', 'kb_corrections', 'sources'):
        print(f'{tbl}: {cur.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()[0]}')
    print('sections:',
          cur.execute('SELECT COUNT(DISTINCT section) FROM articles').fetchone()[0])
    print('meta:', dict(cur.execute('SELECT key, value FROM meta').fetchall()))
    for tbl in ('favorites', 'events', 'seating_plans', 'settings'):
        print(f'user table {tbl} (expect 0):',
              cur.execute(f'SELECT COUNT(*) FROM {tbl}').fetchone()[0])
    for q in ('الأسبقية', 'الأعلام', 'دعوة رسمية', 'زيارة رسمية', 'توقيع اتفاقية'):
        expr = search_expr(search_norm(q))
        a = cur.execute(
            'SELECT COUNT(*) FROM articles_fts WHERE articles_fts MATCH ?',
            (expr,)).fetchone()[0]
        c = cur.execute(
            'SELECT COUNT(*) FROM countries_fts WHERE countries_fts MATCH ?',
            (expr,)).fetchone()[0]
        t = cur.execute(
            'SELECT COUNT(*) FROM templates_fts WHERE templates_fts MATCH ?',
            (expr,)).fetchone()[0]
        print(f'search {q!r}: articles={a} countries={c} templates={t}')
    row = cur.execute(
        "SELECT id, title FROM articles WHERE section='الأسبقية الدبلوماسية' LIMIT 2"
    ).fetchall()
    print('sample precedence articles:', row)
    row = cur.execute(
        "SELECT name_ar, capital, national_day FROM countries WHERE id IN (1, 2, 3)"
    ).fetchall()
    print('sample countries:', row)
    print('--- kb_topics_fts probes (top 3, with book page) ---')
    for q in KB_PROBE_QUERIES:
        expr = search_expr(search_norm(q))
        rows = cur.execute(
            'SELECT k.id, k.title, k.book_page_start, k.book_page_end '
            'FROM kb_topics_fts f JOIN kb_topics k ON k.rowid = f.rowid '
            'WHERE kb_topics_fts MATCH ? LIMIT 3', (expr,)).fetchall()
        print(f'kb search {q!r}: {len(rows)} shown')
        for r in rows:
            print(f'   {r[0]} | {r[1]} | book pp. {r[2]}-{r[3]}')
    # R1: English + Arabic index coverage + one English probe (flag/anthem/emblem).
    try:
        n_en = cur.execute(
            "SELECT COUNT(*) FROM kb_topics WHERE en_keywords IS NOT NULL "
            "AND TRIM(en_keywords) <> ''").fetchone()[0]
        n_ar = cur.execute(
            "SELECT COUNT(*) FROM kb_topics WHERE ar_keywords IS NOT NULL "
            "AND TRIM(ar_keywords) <> ''").fetchone()[0]
        print(f'en_keywords coverage: {n_en}/54 topics; '
              f'ar_keywords coverage: {n_ar}/54 topics')
        rows = cur.execute(
            'SELECT k.id FROM kb_topics_fts f JOIN kb_topics k '
            'ON k.rowid = f.rowid WHERE kb_topics_fts MATCH ? LIMIT 3',
            ('"flag"* OR "anthem"* OR "emblem"*',)).fetchall()
        print('en probe flag/anthem/emblem:', [r[0] for r in rows])
    except Exception as e:  # pre-R1 database without the columns
        print(f'keyword check skipped (pre-R1 db?): {e}')
    con.close()


if __name__ == '__main__':
    if len(sys.argv) >= 3 and sys.argv[1] == '--check':
        check(sys.argv[2])
    elif len(sys.argv) >= 3:
        build(sys.argv[1], sys.argv[2])
    else:
        print('usage: build_db.py <seed-dir> <out.db> | build_db.py --check <db>')
        sys.exit(2)
