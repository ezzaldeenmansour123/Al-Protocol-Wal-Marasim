// حارس منع الاختلاق (R1) — Pure Dart فقط (dart:core)، بلا Flutter
// ولا شبكة ولا توليد.
//
// يقرر رفض السؤال وعرض جملة الرفض الثابتة [refusalText] حرفياً في
// حالتين موثقتين، قبل أي توليد:
//   1. نطاق مواد فيينا: السؤال عن مادة من اتفاقية فيينا للعلاقات
//      الدبلوماسية 1961 برقم خارج 1–53 (الاتفاقية 53 مادة فقط —
//      حقيقة موثقة في الكتاب: الملحق الأول يغطي المواد 1–53).
//      مثال: المادة 77 أو 54 أو 100 → رفض
//      ('vienna_article_out_of_range').
//   2. عتبة الصلة: أعلى مقطع مسترجع يطابق أقل من مصطلحين مميزين
//      من السؤال بينما يحمل السؤال مصطلحين أو أكثر، أو لا توجد
//      مقاطع إطلاقاً → رفض ('weak_relevance' / 'no_results').
//      العتبة هي نفسها minMatchedTermsForAcceptance في النواة (2).
//
// ما لا يفعله الحارس (بصراحة): لا يكشف الاتفاقيات الوهمية
// (مثل «اتفاقية جنيف للمراسم 1985» — لا وجود لها في السجل) ولا
// الدول والألقاب المخترعة ولا الأرقام المخترعة غير المرتبطة بمادة
// فيينا؛ تلك تحتاج تحققاً من الكيانات غير موجود بعد، وتُقاس في
// فئة منع الاختلاق بأن الحارس يرفض 4/20 فقط (المواد خارج النطاق).
// الحارس قرار رفض فقط — لا يولّد نصاً ولا يخمّن إجابة.
//
// الاستخدام: يستدعيه RetrievalService.retrieve بعد دمج المقاطع،
// وقبل evaluateRetrieval؛ ويُختبر وحده في
// test/refusal_guard_test.dart (بلا قاعدة بيانات).

import 'retrieval_core.dart';

/// اتفاقية فيينا للعلاقات الدبلوماسية 1961: 53 مادة (1–53).
/// الملحق الأول في الكتاب يغطي المواد 1–53 (APP1-A: 1–12،
/// APP1-B: 13–33، APP1-C: 34–53).
const int viennaConventionMinArticle = 1;
const int viennaConventionMaxArticle = 53;

/// قرار الرفض: هل يُرفض السؤال، وبأي سبب، مع نص الرفض الثابت.
class RefusalDecision {
  /// true عندما يجب عرض جملة الرفض بدلاً من أي مقطع.
  final bool refused;

  /// أحد الأسباب: null (مقبول)، 'vienna_article_out_of_range'،
  /// 'no_results'، 'weak_relevance'.
  final String? reason;

  /// تفصيل بشري للسبب (للسجلات فقط — لا يُعرض للمستخدم بدلاً من
  /// جملة الرفض).
  final String? detail;

  const RefusalDecision({required this.refused, this.reason, this.detail});

  /// نص الرفض الواحد الثابت حرفياً في كل المسارات.
  String get refusalMessage => refusalText;
}

/// يحوّل الأرقام العربية المشرقية (٠–٩) إلى غربية (0–9) حتى يُقرأ
/// رقم المادة مهما كُتب.
String _westernDigits(String s) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  var out = s;
  for (var i = 0; i < eastern.length; i++) {
    out = out.replaceAll(eastern[i], '$i');
  }
  return out;
}

/// رقم مادة فيينا المذكور في السؤال، أو null إن لم يذكر السؤال
/// اتفاقية فيينا مع رقم مادة.
/// يُطبَّق التطبيع أولاً (المادة→الماده، وتصغير الإنجليزية)، ثم
/// يُشترط ذكر فيينا (فيينا/vienna) مع نمط «ماده N» أو «article N».
/// سؤال عن مادة في اتفاقية أخرى (مثل جنيف) لا يطابق هنا عمداً:
/// نطاق تلك الاتفاقية ليس من اختصاص هذه القاعدة.
int? viennaArticleNumber(String query) {
  final q = _westernDigits(normalizeAr(query));
  final mentionsVienna = q.contains('فيينا') || q.contains('vienna');
  if (!mentionsVienna) return null;
  final ar = RegExp(r'ماده\s*(\d+)').firstMatch(q);
  if (ar != null) return int.tryParse(ar.group(1)!);
  final en = RegExp(r'article\s*(\d+)').firstMatch(q);
  if (en != null) return int.tryParse(en.group(1)!);
  return null;
}

/// هل رقم المادة خارج نطاق اتفاقية فيينا 1961 (1–53)؟
bool isViennaArticleOutOfRange(String query) {
  final n = viennaArticleNumber(query);
  if (n == null) return false;
  return n < viennaConventionMinArticle || n > viennaConventionMaxArticle;
}

/// قرار الرفض الكامل لسؤال ومقاطعه المسترجعة.
/// الترتيب: نطاق فيينا أولاً (رفض قاطع بغض النظر عن المقاطع)، ثم
/// غياب النتائج، ثم عتبة الصلة على أعلى مقطع.
RefusalDecision decideRefusal({
  required String query,
  required List<RetrievedChunk> chunks,
  required int queryTermCount,
}) {
  final article = viennaArticleNumber(query);
  if (article != null &&
      (article < viennaConventionMinArticle ||
          article > viennaConventionMaxArticle)) {
    return RefusalDecision(
      refused: true,
      reason: 'vienna_article_out_of_range',
      detail:
          'المادة $article خارج نطاق اتفاقية فيينا للعلاقات الدبلوماسية '
          '1961 (المواد $viennaConventionMinArticle–$viennaConventionMaxArticle فقط).',
    );
  }
  if (chunks.isEmpty) {
    return const RefusalDecision(refused: true, reason: 'no_results');
  }
  if (queryTermCount >= minMatchedTermsForAcceptance &&
      chunks.first.matchedTerms < minMatchedTermsForAcceptance) {
    return RefusalDecision(
      refused: true,
      reason: 'weak_relevance',
      detail:
          'أعلى مقطع يطابق ${chunks.first.matchedTerms} مصطلحاً فقط من '
          '$queryTermCount مصطلحات ذات معنى (العتبة '
          '$minMatchedTermsForAcceptance).',
    );
  }
  return const RefusalDecision(refused: false);
}
