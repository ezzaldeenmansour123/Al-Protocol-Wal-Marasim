// أساليب الإجابة وأطوالها (P6 — Pure Dart فقط، dart:core).
//
// نُقلت الأساليب السبعة وطول الإجابة إلى هنا من lib/ai/llm_provider.dart
// حتى تستطيع طبقة الموجهات (lib/ai/prompts.dart) استخدامها دون استيراد
// طبقة الاسترجاع/قاعدة البيانات. llm_provider.dart يعيد تصدير هذا
// الملف، فلا يتغير شيء على مستورديها.

/// الأساليب السبعة للكتابة والإجابة (CHARTER_V2 §5).
enum AnswerStyle {
  veryFormal, // رسمي جداً
  diplomatic, // دبلوماسي
  academic, // أكاديمي
  administrative, // إداري
  concise, // مختصر ومباشر
  detailed, // تفصيلي وتحليلي
  simplified, // مبسط وتعليمي
}

/// طول الإجابة (معامل مستقل عن الأسلوب).
enum AnswerLength { short, medium, detailed }

/// التسمية العربية المعروضة لكل أسلوب (لواجهة اختيار الأسلوب).
const Map<AnswerStyle, String> answerStyleLabelsAr = {
  AnswerStyle.veryFormal: 'رسمي جداً',
  AnswerStyle.diplomatic: 'دبلوماسي',
  AnswerStyle.academic: 'أكاديمي',
  AnswerStyle.administrative: 'إداري',
  AnswerStyle.concise: 'مختصر ومباشر',
  AnswerStyle.detailed: 'تفصيلي وتحليلي',
  AnswerStyle.simplified: 'مبسط وتعليمي',
};

/// التسمية الإنجليزية المعروضة لكل أسلوب.
const Map<AnswerStyle, String> answerStyleLabelsEn = {
  AnswerStyle.veryFormal: 'Very formal',
  AnswerStyle.diplomatic: 'Diplomatic',
  AnswerStyle.academic: 'Academic',
  AnswerStyle.administrative: 'Administrative',
  AnswerStyle.concise: 'Concise',
  AnswerStyle.detailed: 'Detailed & analytical',
  AnswerStyle.simplified: 'Simplified',
};

/// التسمية العربية المعروضة لكل طول إجابة.
const Map<AnswerLength, String> answerLengthLabelsAr = {
  AnswerLength.short: 'قصيرة',
  AnswerLength.medium: 'متوسطة',
  AnswerLength.detailed: 'مفصلة',
};

/// التسمية الإنجليزية المعروضة لكل طول إجابة.
const Map<AnswerLength, String> answerLengthLabelsEn = {
  AnswerLength.short: 'Short',
  AnswerLength.medium: 'Medium',
  AnswerLength.detailed: 'Detailed',
};

/// الحد الأقصى لرموز التوليد لكل طول إجابة. تُمرَّر كما هي إلى
/// OpenAiRequest.maxTokens في مزود النموذج المحلي.
int maxTokensForLength(AnswerLength length) {
  switch (length) {
    case AnswerLength.short:
      return 512;
    case AnswerLength.medium:
      return 1024;
    case AnswerLength.detailed:
      return 1536;
  }
}
