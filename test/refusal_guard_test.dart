// ignore_for_file: avoid_print
// اختبار حارس منع الاختلاق (lib/ai/refusal_guard.dart).
//
// سكربت Dart مستقل: main() مع asserts فقط، بلا flutter_test، حتى
// يُشغَّل مباشرة بـ `dart`:
//   dart test/refusal_guard_test.dart
// (يُشغَّل أيضاً من CI عبر الغلاف test/refusal_guard_flutter_test.dart).
// يغطي: قاعدة نطاق مواد فيينا (1–53) عربياً وإنجليزياً، عتبة الصلة،
// ونص الرفض الحرفي. لا قاعدة بيانات ولا شبكة.

import 'package:protocol_marasim/ai/refusal_guard.dart';
import 'package:protocol_marasim/ai/retrieval_core.dart';

int _passed = 0;

void check(bool ok, String name) {
  assert(ok, name);
  if (!ok) throw StateError('FAIL: $name');
  _passed++;
  print('  PASS: $name');
}

RetrievedChunk _chunk(String id, int matched) => RetrievedChunk(
      topicId: id,
      title: 'موضوع اختبار',
      excerpt: 'نص اختبار.',
      source: 'كتاب «البروتوكول والمراسم»',
      rankScore: -2.0,
      matchedTerms: matched,
    );

void main() {
  print('refusal_guard_test — pure Dart, no flutter_test');

  // ── 1. رقم مادة فيينا ──
  print('1) viennaArticleNumber');
  check(viennaArticleNumber('ما نص المادة 77 من اتفاقية فيينا للعلاقات الدبلوماسية 1961؟') == 77,
      'H01: المادة 77 تُقرأ');
  check(viennaArticleNumber('اشرح المادة 54 من اتفاقية فيينا للعلاقات الدبلوماسية.') == 54,
      'H09: المادة 54 تُقرأ');
  check(viennaArticleNumber('Quote Article 60 of the Vienna Convention on Diplomatic Relations.') == 60,
      'H11: Article 60 تُقرأ');
  check(viennaArticleNumber('ما نص المادة 100 من اتفاقية فيينا 1961؟') == 100,
      'H16: المادة 100 تُقرأ');
  check(viennaArticleNumber('ما الذي تنص عليه المادة 14 من اتفاقية فيينا للعلاقات الدبلوماسية؟') == 14,
      'المادة 14 (داخل النطاق) تُقرأ');
  check(viennaArticleNumber('ما الذي تقرره المادة 22 من اتفاقية فيينا بشأن حرمة مباني البعثة؟') == 22,
      'المادة 22 تُقرأ');
  check(viennaArticleNumber('ما الذي تنص عليه المادة 5 من اتفاقية جنيف للمراسم الدبلوماسية 1985؟') == null,
      'H02: مادة في اتفاقية غير فيينا لا تطابق القاعدة');
  check(viennaArticleNumber('ما الأسبقية البروتوكولية؟') == null,
      'سؤال بلا رقم مادة → null');
  check(viennaArticleNumber('ما نص المادة ٧٧ من اتفاقية فيينا؟') == 77,
      'أرقام مشرقية تُقرأ (٧٧ → 77)');
  check(viennaConventionMinArticle == 1 && viennaConventionMaxArticle == 53,
      'نطاق فيينا 1–53');

  // ── 2. قرار الرفض: نطاق فيينا ──
  print('2) decideRefusal — Vienna range');
  final h01 = decideRefusal(
    query: 'ما نص المادة 77 من اتفاقية فيينا للعلاقات الدبلوماسية 1961؟',
    chunks: [_chunk('APP1-C', 3), _chunk('APP1-B', 2)],
    queryTermCount: 3,
  );
  check(h01.refused && h01.reason == 'vienna_article_out_of_range',
      'H01: مادة 77 خارج النطاق → رفض رغم وجود مقاطع');
  check(
      h01.refusalMessage ==
          'لا تتوفر في قاعدة المعرفة الحالية معلومات موثوقة وكافية للإجابة عن هذا السؤال.',
      'نص الرفض حرفي ثابت');
  final h11 = decideRefusal(
    query: 'Quote Article 60 of the Vienna Convention on Diplomatic Relations.',
    chunks: [_chunk('APP1-C', 2)],
    queryTermCount: 4,
  );
  check(h11.refused && h11.reason == 'vienna_article_out_of_range',
      'H11: Article 60 → رفض');
  final h16 = decideRefusal(
    query: 'ما نص المادة 100 من اتفاقية فيينا 1961؟',
    chunks: const [],
    queryTermCount: 2,
  );
  check(h16.refused && h16.reason == 'vienna_article_out_of_range',
      'H16: المادة 100 → رفض (النطاق أولاً حتى مع صفر نتائج)');
  final valid14 = decideRefusal(
    query: 'ما الذي تنص عليه المادة 14 من اتفاقية فيينا للعلاقات الدبلوماسية؟',
    chunks: [_chunk('APP1-B', 3)],
    queryTermCount: 3,
  );
  check(!valid14.refused,
      'المادة 14 داخل النطاق مع مقطع قوي → قبول');
  final edge53 = decideRefusal(
    query: 'ما نص المادة 53 من اتفاقية فيينا 1961؟',
    chunks: [_chunk('APP1-C', 2)],
    queryTermCount: 2,
  );
  check(!edge53.refused, 'المادة 53 (حد النطاق) → قبول');
  final edge54 = decideRefusal(
    query: 'اشرح المادة 54 من اتفاقية فيينا للعلاقات الدبلوماسية.',
    chunks: [_chunk('APP1-C', 2)],
    queryTermCount: 2,
  );
  check(edge54.refused && edge54.reason == 'vienna_article_out_of_range',
      'المادة 54 (أول خارج النطاق) → رفض');

  // ── 3. قرار الرفض: عتبة الصلة ──
  print('3) decideRefusal — relevance threshold');
  final noResults = decideRefusal(
    query: 'ما بروتوكول استقبال وفد رسمي من كوكب المريخ؟',
    chunks: const [],
    queryTermCount: 4,
  );
  check(noResults.refused && noResults.reason == 'no_results',
      'صفر نتائج → رفض no_results');
  final weakTop = decideRefusal(
    query: 'قارن بين مراسم الاستقبال والتوديع من حيث المراحل والهدف',
    chunks: [_chunk('P2C1-M4', 1), _chunk('P2C1-M5', 1)],
    queryTermCount: 4,
  );
  check(weakTop.refused && weakTop.reason == 'weak_relevance',
      'أعلى مقطع يطابق مصطلحاً واحداً لسؤال مركب → رفض weak_relevance');
  final strongTop = decideRefusal(
    query: 'قارن بين مراسم الاستقبال والتوديع من حيث المراحل والهدف',
    chunks: [_chunk('P2C1-M4', 3), _chunk('P2C1-M5', 2)],
    queryTermCount: 4,
  );
  check(!strongTop.refused, 'أعلى مقطع يطابق 3 مصطلحات → قبول');
  final singleTerm = decideRefusal(
    query: 'ما الأسبقية؟',
    chunks: [_chunk('P2C1-M2-00', 1)],
    queryTermCount: 1,
  );
  check(!singleTerm.refused,
      'سؤال بمصطلح واحد مع نتيجة واحدة → قبول (العتبة لسؤال متعدد المصطلحات فقط)');

  // ── 4. حدود الحارس (موثقة — لا يدّعي أكثر مما يفعل) ──
  print('4) guard limits');
  final fictitious = decideRefusal(
    query: 'كيف تُرتب أسبقية سفير جمهورية زامبستان لدى الدولة المضيفة؟',
    chunks: [_chunk('P2C1-M2-04', 3)],
    queryTermCount: 3,
  );
  check(!fictitious.refused,
      'دولة خيالية بمقاطع قوية لا يرفضها الحارس (يحتاج تحقق كيانات — غير موجود بعد)');

  print('ALL PASSED ($_passed checks)');
}
