// قسم إعدادات النموذج المحلي في صفحة الإعدادات (P6).
//
// يعرض: اختيار النموذج (3B الأساسي / 1.5B الأخف) مع حجمه ومتطلباته
// قبل التنزيل، وحالته (غير منزّل / جارٍ التنزيل مع تقدم / جاهز /
// غير سليم)، وأزرار تنزيل/إيقاف/استئناف/حذف. التنزيل إلى مجلد
// مستندات التطبيق فقط (ModelManager) — أبداً داخل APK أو assets.
//
// يُضمَّن في SettingsPage (lib/main.dart) بعد قسم الوضع التوليدي.

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'ai/model_catalog.dart';
import 'ai/model_manager.dart';
import 'app_state.dart';
import 'widgets.dart';

class ModelSettingsSection extends StatefulWidget {
  const ModelSettingsSection({super.key});
  @override
  State<ModelSettingsSection> createState() => _ModelSettingsSectionState();
}

class _ModelSettingsSectionState extends State<ModelSettingsSection> {
  final _manager = ModelManager();
  LocalModelSpec _spec = qwen3bSpec;
  bool _enabled = true;
  bool _downloaded = false;
  bool _invalid = false;
  bool _busy = false;
  bool _verifying = false;
  DownloadProgress? _progress;
  DownloadCancelToken? _cancelToken;
  String? _note;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final spec = await _manager.selectedModel();
    final enabled = await _manager.isModelSelected();
    final status = await _manager.fileStatus(spec);
    if (!mounted) return;
    setState(() {
      _spec = spec;
      _enabled = enabled;
      _downloaded = status == ModelFileStatus.downloaded;
      _invalid = status == ModelFileStatus.invalid;
    });
  }

  Future<void> _selectModel(LocalModelSpec spec) async {
    if (_busy) return;
    await _manager.setSelectedModel(spec.id);
    await _refresh();
  }

  Future<void> _setEnabled(bool v) async {
    await _manager.setModelSelected(v);
    if (mounted) setState(() => _enabled = v);
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
      _progress = null;
    });
    final token = DownloadCancelToken();
    _cancelToken = token;
    try {
      // SHA-256 المتوقع من المصدر قبل التنزيل (best-effort).
      final expected = await _manager.fetchExpectedSha256(_spec);
      await _manager.download(
        _spec,
        cancelToken: token,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _note = expected == null
            ? tr(context.read<AppState>(), 'model_sha_unknown')
            : tr(context.read<AppState>(), 'model_downloaded_ok');
      });
    } on ModelDownloadException catch (e) {
      if (!mounted) return;
      final cancelled = e.message.contains('أُلغي');
      setState(() {
        _note = cancelled
            ? tr(context.read<AppState>(), 'model_download_cancelled')
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _note = tr(context.read<AppState>(), 'model_download_failed');
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _cancelToken = null;
        });
      }
      await _refresh();
    }
  }

  Future<void> _delete() async {
    final state = Provider.of<AppState>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(state, 'model_delete')),
        content: Text(tr(state, 'model_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(state, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(state, 'delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _manager.deleteModel(_spec);
    if (!mounted) return;
    setState(() => _note = tr(state, 'model_deleted'));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final statusText = _verifying
        ? tr(state, 'model_status_verifying')
        : _busy
            ? tr(state, 'model_status_downloading')
            : _invalid
                ? tr(state, 'model_status_invalid')
                : _downloaded
                    ? tr(state, 'model_status_downloaded')
                    : tr(state, 'model_status_not_downloaded');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: tr(state, 'settings_model')),
        const SizedBox(height: 6),
        Text(
          tr(state, 'settings_model_desc'),
          style: const TextStyle(color: AppColors.stone, height: 1.7),
        ),
        SwitchListTile(
          title: Text(tr(state, 'model_enable')),
          value: _enabled,
          onChanged: _setEnabled,
        ),
        ...localModelSpecs.map(
          (spec) => RadioListTile<LocalModelSpec>(
            title: Text(
              state.language == 'ar'
                  ? spec.displayNameAr
                  : spec.displayNameEn,
            ),
            subtitle: Text(
              '${tr(state, 'model_size')}: ${formatBytes(spec.approxBytes)}'
              ' — ${tr(state, 'model_ram')}: ${formatBytes(spec.minRamBytes)}',
            ),
            value: spec,
            groupValue: _spec,
            onChanged: _busy ? null : (v) => v != null ? _selectModel(v) : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${tr(state, 'model_requirements')}: '
          '${tr(state, 'model_size')} ${formatBytes(_spec.approxBytes)}، '
          '${tr(state, 'model_ram')} ${formatBytes(_spec.minRamBytes)} — '
          '${tr(state, 'model_needs_space')}',
          style: const TextStyle(color: AppColors.stone, height: 1.7),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              statusText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_busy)
              OutlinedButton(
                onPressed: () => _cancelToken?.cancel(),
                child: Text(tr(state, 'model_cancel_download')),
              )
            else if (!_downloaded || _invalid)
              ElevatedButton(
                onPressed: _download,
                child: Text(tr(state, 'model_download')),
              ),
            if (_downloaded && !_busy) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _delete,
                child: Text(tr(state, 'model_delete')),
              ),
            ],
          ],
        ),
        if (_progress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progress!.percent == null
                ? null
                : _progress!.percent! / 100,
          ),
          const SizedBox(height: 4),
          Text(
            _progress!.totalBytes == null
                ? formatBytes(_progress!.receivedBytes)
                : '${formatBytes(_progress!.receivedBytes)} / '
                    '${formatBytes(_progress!.totalBytes!)}'
                    ' (${_progress!.percent!.toStringAsFixed(0)}%)',
            style: const TextStyle(color: AppColors.stone),
          ),
        ],
        if (_note != null) ...[
          const SizedBox(height: 8),
          Text(_note!, style: const TextStyle(height: 1.7)),
        ],
        if (_downloaded && !_busy) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () async {
              setState(() => _verifying = true);
              final ok = await _manager.verifyFile(_spec);
              if (!mounted) return;
              setState(() {
                _verifying = false;
                _invalid = !ok;
                _note = ok ? tr(state, 'model_status_downloaded') : tr(state, 'model_status_invalid');
              });
            },
            child: Text(tr(state, 'model_verify')),
          ),
        ],
      ],
    );
  }
}
