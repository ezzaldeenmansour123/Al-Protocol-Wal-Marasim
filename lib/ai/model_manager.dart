// مدير تنزيل النموذج المحلي (P6).
//
// ينزّل ملف GGUF من Hugging Face عند أول إعداد فقط، إلى مجلد
// مستندات التطبيق (path_provider) — أبداً داخل APK ولا داخل assets.
// التنزيل: HttpClient من dart:io مع ترويسة Range للاستئناف، وتقدم،
// وإيقاف، وتحقق SHA-256 (من بيانات LFS في Hugging Face API عند
// توفره) أو من الحجم عند غيابه.
//
// لا مفاتيح API ولا خدمة سحابية هنا: التنزيل من مستودع Hugging Face
// عام عبر HTTPS فقط، والتوليد لاحقاً محلي بالكامل.
//
// حدود صريحة (انظر PHASE6_TEAM1_NOTES.md):
// - لا يفحص التطبيق المساحة الحرة على القرص بنفسه: Dart/Flutter لا
//   يوفران API محمولاً لذلك على Android؛ الواجهة تعرض الحجم المطلوب
//   (model_catalog.hasEnoughFreeSpace تحسب الشرط فقط عند توفر رقم).
// - لا يفحص ذاكرة RAM المتاحة برمجياً؛ يعرض الحد الأدنى الموصى به.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'model_catalog.dart';

/// حالة ملف النموذج على الجهاز.
enum ModelFileStatus {
  /// لا ملف (أو ملف جزئي فقط).
  notDownloaded,

  /// ملف مكتمل موجود (الحجم يطابق التقريبي بهامش، أو التحقق ناجح).
  downloaded,

  /// ملف موجود لكن حجمه لا يطابق المتوقع (تنزيل ناقص أو تالف).
  invalid,
}

/// تقدّم التنزيل: بايتات مستلمة من إجمالي معروف (أو null إن جهله
/// الخادم).
class DownloadProgress {
  final int receivedBytes;
  final int? totalBytes;

  const DownloadProgress({required this.receivedBytes, this.totalBytes});

  /// نسبة مئوية 0–100، أو null عندما يكون الإجمالي مجهولاً.
  double? get percent =>
      totalBytes == null || totalBytes == 0
          ? null
          : (receivedBytes / totalBytes! * 100).clamp(0, 100);
}

/// رمز إيقاف تنزيل: يمرَّره المتصل ويستدعي [cancel] لإيقاف التنزيل
/// الجاري. الاستئناف لاحقاً يكمل من الملف الجزئي (.part).
class DownloadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// استثناء تنزيل/تحقق برسالة عربية صالحة للعرض.
class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);
  @override
  String toString() => message;
}

/// مدير ملفات النماذج المحلية في مجلد مستندات التطبيق.
///
/// [modelsDirOverride] و[httpClientFactory] حقن اختباري فقط: في
/// الإنتاج يُحسب المجلد من path_provider ويُنشأ HttpClient جديد
/// لكل تنزيل.
class ModelManager {
  static const String _modelsSubdir = 'models';
  static const String _partSuffix = '.part';
  static const String _stateFilename = 'models_state.json';

  final Directory? modelsDirOverride;
  final HttpClient Function()? httpClientFactory;

  ModelManager({this.modelsDirOverride, this.httpClientFactory});

  HttpClient _newClient() =>
      httpClientFactory != null ? httpClientFactory!() : HttpClient();

  /// مجلد النماذج: <مستندات التطبيق>/models (يُنشأ عند الحاجة).
  Future<Directory> get modelsDir async {
    if (modelsDirOverride != null) return modelsDirOverride!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_modelsSubdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// ملف النموذج النهائي.
  Future<File> modelFile(LocalModelSpec spec) async {
    final dir = await modelsDir;
    return File('${dir.path}/${spec.localFilename}');
  }

  /// الملف الجزئي أثناء التنزيل (يُستأنف منه، ويُحذف عند الاكتمال).
  Future<File> _partFile(LocalModelSpec spec) async {
    final dir = await modelsDir;
    return File('${dir.path}/${spec.localFilename}$_partSuffix');
  }

  /// ملف حالة صغير JSON: النموذج المختار + SHA-256 المتوقع المحفوظ.
  Future<File> _stateFile() async {
    final dir = await modelsDir;
    return File('${dir.path}/$_stateFilename');
  }

  Future<Map<String, dynamic>> _readState() async {
    try {
      final text = await (await _stateFile()).readAsString();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeState(Map<String, dynamic> state) async {
    try {
      await (await _stateFile())
          .writeAsString(jsonEncode(state), flush: true);
    } catch (_) {
      // فشل حفظ الحالة لا يمنع التنزيل أو التوليد.
    }
  }

  /// النموذج المختار في الإعدادات (الافتراضي: الأساسي 3B).
  Future<LocalModelSpec> selectedModel() async {
    final state = await _readState();
    final id = state['selected_model'] as String?;
    if (id == 'qwen15b') return qwen15bSpec;
    return qwen3bSpec;
  }

  /// يحفظ اختيار النموذج.
  Future<void> setSelectedModel(LocalModelId id) async {
    final state = await _readState();
    state['selected_model'] =
        id == LocalModelId.qwen15b ? 'qwen15b' : 'qwen3b';
    await _writeState(state);
  }

  /// هل اختار المستخدم تفعيل النموذج المحلي؟ (افتراضياً: نعم عند
  /// وجود ملف منزّل؛ الإعداد يبقى مفعّلاً حتى يلغي المستخدم اختياره
  /// من قسم النموذج في الإعدادات).
  Future<bool> isModelSelected() async {
    final state = await _readState();
    final v = state['model_enabled'];
    if (v is bool) return v;
    return true;
  }

  Future<void> setModelSelected(bool enabled) async {
    final state = await _readState();
    state['model_enabled'] = enabled;
    await _writeState(state);
  }

  /// حالة ملف النموذج: موجود ومكتمل أم لا.
  /// «مكتمل» = الحجم ضمن 2% من الحجم التقريبي المعلن (الناشر قد
  /// يعيد النشر فيتغير الحجم قليلاً)؛ التحقق الدقيق بـ[verifyFile].
  Future<ModelFileStatus> fileStatus(LocalModelSpec spec) async {
    final file = await modelFile(spec);
    if (!await file.exists()) {
      final part = await _partFile(spec);
      if (await part.exists()) return ModelFileStatus.notDownloaded;
      return ModelFileStatus.notDownloaded;
    }
    final size = await file.length();
    final diff = (size - spec.approxBytes).abs();
    if (diff <= spec.approxBytes * 0.02) return ModelFileStatus.downloaded;
    return ModelFileStatus.invalid;
  }

  /// هل الملف منزّل ومكتمل (بحسب الحجم)؟
  Future<bool> isDownloaded(LocalModelSpec spec) async =>
      await fileStatus(spec) == ModelFileStatus.downloaded;

  /// بايتات الملف الجزئي المنزّلة حتى الآن (0 إن لم يوجد).
  Future<int> downloadedPartBytes(LocalModelSpec spec) async {
    final part = await _partFile(spec);
    if (await part.exists()) return part.length();
    final file = await modelFile(spec);
    if (await file.exists()) return file.length();
    return 0;
  }

  /// SHA-256 المتوقع للملف من Hugging Face API (بيانات LFS:
  /// siblings[].lfs.oid)، أو null عند تعذّر جلبه.
  /// يُستدعى قبل التنزيل ويُحفظ في ملف الحالة؛ غيابه لا يمنع
  /// التنزيل — يُوثَّق ويُكتفى بالتحقق من الحجم.
  Future<String?> fetchExpectedSha256(LocalModelSpec spec) async {
    final client = _newClient();
    try {
      final request = await client
          .getUrl(Uri.parse(huggingFaceApiUrl(spec)))
          .timeout(const Duration(seconds: 15));
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final siblings = decoded['siblings'];
      if (siblings is! List) return null;
      for (final entry in siblings) {
        if (entry is! Map<String, dynamic>) continue;
        if (entry['rfilename'] != spec.filename) continue;
        final lfs = entry['lfs'];
        if (lfs is Map<String, dynamic>) {
          final oid = lfs['oid'];
          if (oid is String && oid.length == 64) {
            final state = await _readState();
            state['expected_sha256_${spec.filename}'] = oid;
            await _writeState(state);
            return oid;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// SHA-256 المتوقع المحفوظ من جلب سابق (أو null).
  Future<String?> savedExpectedSha256(LocalModelSpec spec) async {
    final state = await _readState();
    final v = state['expected_sha256_${spec.filename}'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// يتحقق من سلامة ملف النموذج: SHA-256 عند توفر المتوقع،
  /// وإلا مقارنة الحجم بالتقريبي. يعيد true عند السلامة.
  Future<bool> verifyFile(
    LocalModelSpec spec, {
    String? expectedSha256,
  }) async {
    final file = await modelFile(spec);
    if (!await file.exists()) return false;
    final expected = expectedSha256 ?? await savedExpectedSha256(spec);
    if (expected == null) {
      return await fileStatus(spec) == ModelFileStatus.downloaded;
    }
    final digest = await _sha256Of(file);
    return digest.toLowerCase() == expected.toLowerCase();
  }

  Future<String> _sha256Of(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    final stream = file.openRead();
    await for (final chunk in stream) {
      input.add(chunk);
    }
    input.close();
    return output.events.single.toString();
  }

  /// ينزّل النموذج (مع استئناف من الملف الجزئي عند وجوده).
  ///
  /// - يُظهر التقدم عبر [onProgress] (بايتات مستلمة/إجمالي).
  /// - يتوقف نظيفاً عند [cancelToken]?.cancel() محتفظاً بالملف
  ///   الجزئي للاستئناف، ويرمي [ModelDownloadException] برسالة
  ///   «أُلغي التنزيل».
  /// - عند الاكتمال يعيد تسمية .part إلى الملف النهائي ويتحقق من
  ///   سلامته (SHA-256 عند توفره، وإلا الحجم).
  /// - يفشل باستثناء مكتوب (لا إجابة وهمية ولا ملف ناقص باسم النهائي).
  Future<File> download(
    LocalModelSpec spec, {
    void Function(DownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final part = await _partFile(spec);
    var downloaded = await part.exists() ? await part.length() : 0;
    final client = _newClient();
    try {
      final request = await client.getUrl(
        Uri.parse(huggingFaceDownloadUrl(spec)),
      );
      if (downloaded > 0) {
        request.headers.set('Range', 'bytes=$downloaded-');
      }
      final response = await request.close();
      if (downloaded > 0 && response.statusCode == 200) {
        // الخادم تجاهل Range وأعاد الملف كاملاً: نبدأ من جديد.
        downloaded = 0;
        if (await part.exists()) await part.delete();
      } else if (response.statusCode != 200 &&
          response.statusCode != 206) {
        throw ModelDownloadException(
          'تعذّر تنزيل النموذج (رمز HTTP ${response.statusCode}). '
          'تحقق من الاتصال وحاول مجدداً.',
        );
      }
      final contentLength = response.contentLength;
      final total = contentLength > 0 ? downloaded + contentLength : null;
      final sink = part.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in response) {
          if (cancelToken?.isCancelled == true) {
            throw const ModelDownloadException('أُلغي التنزيل.');
          }
          sink.add(chunk);
          downloaded += chunk.length;
          onProgress?.call(
            DownloadProgress(receivedBytes: downloaded, totalBytes: total),
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (cancelToken?.isCancelled == true) {
        throw const ModelDownloadException('أُلغي التنزيل.');
      }
      final finalFile = await modelFile(spec);
      if (await finalFile.exists()) await finalFile.delete();
      final renamed = await part.rename(finalFile.path);
      final ok = await verifyFile(spec);
      if (!ok) {
        await renamed.delete().catchError((_) async => renamed);
        throw const ModelDownloadException(
          'اكتمل التنزيل لكن التحقق من سلامة الملف فشل — '
          'احذف الملف وأعد التنزيل.',
        );
      }
      return renamed;
    } on ModelDownloadException {
      rethrow;
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        throw const ModelDownloadException('أُلغي التنزيل.');
      }
      throw ModelDownloadException('تعذّر تنزيل النموذج: $e');
    } finally {
      client.close();
    }
  }

  /// يحذف ملف النموذج (والجزئي إن وُجد). يعيد true عند الحذف.
  Future<bool> deleteModel(LocalModelSpec spec) async {
    var deleted = false;
    final file = await modelFile(spec);
    if (await file.exists()) {
      await file.delete();
      deleted = true;
    }
    final part = await _partFile(spec);
    if (await part.exists()) await part.delete();
    return deleted;
  }
}
