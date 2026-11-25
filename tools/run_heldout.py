#!/usr/bin/env python3
"""Held-out retrieval measurer for the PROTOCOL AI held-out test set.

usage:
  python3 tools/run_heldout.py --db assets/marasim.db \
      --questions test_data/held_out_questions.json \
      --out test_data/heldout_results.json

What it measures (retrieval only — there is no generative model yet):
  * For the 60 answerable questions (basic/applied/complex/sources):
    hit@3 — is the expected `topic_id` among the top 3 FTS5 results?
    Broken down per category and per language.
  * For the 20 hallucination questions: `refusal_correct` is a
    RETRIEVAL-LEVEL PROXY — true only when the search returns NO results
    at all, i.e. a grounded RAG pipeline would have nothing to cite and
    should refuse. A non-empty result does NOT prove a hallucination (a
    good generator could still refuse), it only flags retrieval noise
    that a generator must resist. True refusal can only be measured once
    a generative model exists; see test_data/HELDOUT_REPORT.md and
    test_data/GENERATIVE_RUBRIC.md.
  * For the 10 writing tasks: retrieval grounding only — is the expected
    `topic_id` among the top 3 results? Reported separately as
    `grounding_hit_at_3`; writing tasks are NEVER counted in the main
    hit@3, and no generative score is claimed for them (no model yet).

Identity of the retrieval logic with tools/run_baseline.py is enforced
by IMPORT, not by copying: `search_kb`, `vienna_article_out_of_range`,
`detect_db_kind` and the normalisation source string are imported from
run_baseline, so any future change to the baseline counter changes this
counter identically. If that import fails, this script exits with an
error rather than running a divergent copy.

The script never deletes or modifies questions: every failing question
is recorded in the output file under `failed` (and in full under
`per_question`). The held-out set must stay held out: its questions
must not be used to tune synonyms, keywords or ranking.
"""
import argparse
import datetime
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

try:
    from run_baseline import (  # noqa: F401 — identical retrieval logic
        NORM_SOURCE,
        detect_db_kind,
        search_kb,
        vienna_article_out_of_range,
    )
except Exception as exc:  # pragma: no cover - import must succeed
    print(f'ERROR: could not import retrieval logic from run_baseline.py: '
          f'{exc}')
    print('run_heldout.py deliberately refuses to run a copied divergent '
          'implementation; fix the import instead.')
    sys.exit(2)

REFUSAL_TEXT = ('لا تتوفر في قاعدة المعرفة الحالية معلومات موثوقة وكافية '
                'للإجابة عن هذا السؤال.')
ANSWERABLE_CATS = ['basic', 'applied', 'complex', 'sources']


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(
        description='Held-out retrieval measurer (hit@3 + refusal proxy) '
                    'for the PROTOCOL AI held-out test set.')
    ap.add_argument('--db', default=os.path.join(REPO, 'assets', 'marasim.db'),
                    help='SQLite DB containing kb_topics + kb_topics_fts')
    ap.add_argument('--questions',
                    default=os.path.join(REPO, 'test_data',
                                         'held_out_questions.json'),
                    help='held_out_questions.json')
    ap.add_argument('--out',
                    default=os.path.join(REPO, 'test_data',
                                         'heldout_results.json'),
                    help='output JSON path')
    args = ap.parse_args()

    if not os.path.exists(args.db):
        print(f'ERROR: database not found: {args.db}')
        sys.exit(2)
    with open(args.questions, encoding='utf-8') as fh:
        qdata = json.load(fh)
    questions = qdata['questions']
    assert len(questions) == 90, f'expected 90 questions, got {len(questions)}'
    assert qdata['meta'].get('refusal_text') == REFUSAL_TEXT, (
        'held-out meta.refusal_text does not match the literal refusal '
        'sentence in lib/ai/retrieval_core.dart')

    import sqlite3
    con = sqlite3.connect(f'file:{args.db}?mode=ro', uri=True)
    cur = con.cursor()
    kind, tables = detect_db_kind(cur)
    if kind is None:
        missing = [t for t in ('kb_topics', 'kb_topics_fts')
                   if t not in tables]
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
            'top3_title_matches': [r.get('title_matches', 0) for r in top3],
            'guard_refusal': vienna_article_out_of_range(item['text']),
            'guard_reason': ('vienna_article_out_of_range'
                             if vienna_article_out_of_range(item['text'])
                             else None),
        }
        if item['category'] == 'hallucination':
            rec['hit_at_3'] = None
            rec['grounding_hit_at_3'] = None
            # Retrieval-level proxy only (see module docstring).
            rec['refusal_correct'] = len(top3) == 0
            rec['failed'] = not rec['refusal_correct']
            rec['trap'] = exp.get('trap')
            rec['no_answer_reason'] = item.get('no_answer_reason')
        elif item['category'] == 'writing':
            # Grounding only — excluded from the main hit@3.
            rec['hit_at_3'] = None
            rec['grounding_hit_at_3'] = exp['topic_id'] in top3_ids
            rec['refusal_correct'] = None
            rec['generative_score'] = None
            rec['generative_score_note'] = (
                'not scored: no generative model exists yet; see '
                'test_data/GENERATIVE_RUBRIC.md')
            rec['style'] = item.get('style')
            rec['failed'] = not rec['grounding_hit_at_3']
        else:
            rec['hit_at_3'] = exp['topic_id'] in top3_ids
            rec['grounding_hit_at_3'] = None
            rec['refusal_correct'] = None
            rec['failed'] = not rec['hit_at_3']
        per_question.append(rec)
    con.close()

    per_category = {}
    for c in ANSWERABLE_CATS:
        rows = [r for r in per_question if r['category'] == c]
        hits = sum(1 for r in rows if r['hit_at_3'])
        per_category[c] = {'n': len(rows), 'hits': hits,
                           'hit_at_3': round(hits / len(rows), 4) if rows
                           else 0.0}
    answerable = [r for r in per_question
                  if r['category'] in ANSWERABLE_CATS]
    ans_hits = sum(1 for r in answerable if r['hit_at_3'])
    hall = [r for r in per_question if r['category'] == 'hallucination']
    ref_ok = sum(1 for r in hall if r['refusal_correct'])
    guard_ok = sum(1 for r in hall if r['guard_refusal'])
    guard_fp = sum(1 for r in answerable if r['guard_refusal'])
    writing = [r for r in per_question if r['category'] == 'writing']
    wr_hits = sum(1 for r in writing if r['grounding_hit_at_3'])
    per_language = {}
    for lang in ('ar', 'en'):
        rows = [r for r in answerable if r['lang'] == lang]
        hits = sum(1 for r in rows if r['hit_at_3'])
        per_language[lang] = {'n': len(rows), 'hits': hits,
                              'hit_at_3': round(hits / len(rows), 4) if rows
                              else 0.0}
    per_language_hall = {}
    for lang in ('ar', 'en'):
        rows = [r for r in hall if r['lang'] == lang]
        ok = sum(1 for r in rows if r['refusal_correct'])
        per_language_hall[lang] = {
            'n': len(rows), 'refusal_correct': ok,
            'refusal_correct_rate': round(ok / len(rows), 4) if rows else 0.0}
    failed = [r for r in per_question if r['failed']]

    result = {
        'meta': {
            'generated_at': datetime.datetime.now(
                datetime.timezone.utc).isoformat(),
            'db_path': os.path.abspath(args.db),
            'db_kind': kind,
            'db_kb_topics': kb_count,
            'db_size_bytes': os.path.getsize(args.db),
            'db_sha256': sha256(args.db),
            'questions_file': os.path.abspath(args.questions),
            'questions_sha256': sha256(args.questions),
            'normalisation': NORM_SOURCE,
            'retrieval': "Identical to tools/run_baseline.py by import "
                         "(search_kb / vienna_article_out_of_range / "
                         "detect_db_kind): FTS5 on kb_topics_fts, queryTerms "
                         "(AR+EN stopwords removed) + 3 stages AND -> OR -> "
                         "longest term fetching 20 candidates, reranked "
                         "title-matches-first (F1) then FTS5 rank, top 3",
            'refusal_definition': "Retrieval-level proxy only: "
                                  "refusal_correct = search returned zero "
                                  "results. True refusal needs a generative "
                                  "model (not yet present). guard_refusal "
                                  "(R1) = the Vienna-article-range rule of "
                                  "lib/ai/refusal_guard.dart refuses the "
                                  "question (article number outside 1-53); "
                                  "it is measured for all 90 items.",
            'refusal_text': REFUSAL_TEXT,
            'held_out_note': "This set was never used to design any "
                             "retrieval improvement (R1 targeted only the "
                             "failures of the old 100-question set). It must "
                             "stay held out: do not tune synonyms, keywords "
                             "or ranking against it.",
        },
        'summary': {
            'total_questions': len(questions),
            'answerable_questions': len(answerable),
            'hallucination_questions': len(hall),
            'writing_tasks': len(writing),
            'overall_hit_at_3': round(ans_hits / len(answerable), 4),
            'overall_hits': ans_hits,
            'per_category': per_category,
            'per_language': per_language,
            'refusal_correct_count': ref_ok,
            'refusal_correct_rate': round(ref_ok / len(hall), 4) if hall
            else 0.0,
            'refusal_correct_per_language': per_language_hall,
            'guard_refusal_correct_count': guard_ok,
            'guard_refusal_correct_rate': round(guard_ok / len(hall), 4)
            if hall else 0.0,
            'guard_refusal_false_positives': guard_fp,
            'writing_grounding_hits': wr_hits,
            'writing_grounding_hit_at_3': round(wr_hits / len(writing), 4)
            if writing else 0.0,
            'writing_generative_scored': 0,
            'failed_count': len(failed),
            'failed_answerable': sum(
                1 for r in failed if r['category'] in ANSWERABLE_CATS),
            'failed_hallucination_retrieval_noise': sum(
                1 for r in failed if r['category'] == 'hallucination'),
            'failed_writing_grounding': sum(
                1 for r in failed if r['category'] == 'writing'),
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
    print(f"overall hit@3 (60 answerable): {s['overall_hits']}/60 = "
          f"{s['overall_hit_at_3']:.1%}")
    for c in ANSWERABLE_CATS:
        pc = per_category[c]
        print(f"  {c}: {pc['hits']}/{pc['n']} = {pc['hit_at_3']:.1%}")
    print(f"refusal-correct (retrieval proxy, 20 H): {ref_ok}/20 = "
          f"{s['refusal_correct_rate']:.1%}")
    print(f"guard refusal (Vienna-range rule, 20 H): {guard_ok}/20 = "
          f"{s['guard_refusal_correct_rate']:.1%} "
          f"(false positives on answerable: {guard_fp})")
    print(f"writing grounding hit@3 (10 tasks): {wr_hits}/10 = "
          f"{s['writing_grounding_hit_at_3']:.1%} (generative: not scored)")
    for lang, pl in s['per_language'].items():
        print(f"  lang {lang}: {pl['hits']}/{pl['n']} = {pl['hit_at_3']:.1%}")
    print(f"failed: {len(failed)} (answerable misses: "
          f"{s['failed_answerable']}, H retrieval noise: "
          f"{s['failed_hallucination_retrieval_noise']}, writing grounding: "
          f"{s['failed_writing_grounding']})")
    print(f"wrote {out_path}")


if __name__ == '__main__':
    main()
