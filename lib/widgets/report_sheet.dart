import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/api/api_client.dart';
import '../core/design/design.dart';

/// Reasons supported by the backend (`internal/domain/report.go`).
class _Reason {
  final String value;
  final String label;
  const _Reason(this.value, this.label);
}

const List<_Reason> _reasons = [
  _Reason('spam', 'Спам'),
  _Reason('harassment', 'Травля или оскорбления'),
  _Reason('illegal', 'Незаконный контент'),
  _Reason('nsfw', 'Непристойный контент'),
  _Reason('self_harm', 'Самоповреждение'),
  _Reason('other', 'Другое'),
];

/// Opens a bottom sheet that lets the user file a moderation report.
/// `targetType` must be one of: `post`, `comment`, `story`, `user`.
Future<void> showReportSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String targetType,
  required String targetId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      api: ref.read(apiClientProvider),
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  final String targetType;
  final String targetId;
  final ApiClient api;

  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.api,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _selected;
  final _detailsCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.post('/reports', data: {
        'target_type': widget.targetType,
        'target_id': widget.targetId,
        'reason': _selected,
        'details': _detailsCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Жалоба отправлена. Спасибо!')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PhosphorIcons.flag(), color: SeeUColors.like, size: 22),
                const SizedBox(width: 8),
                Text('Пожаловаться', style: SeeUTypography.title),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Расскажите что не так. Мы рассмотрим в течение 24 часов.',
              style: SeeUTypography.caption.copyWith(color: c.ink2),
            ),
            const SizedBox(height: 16),
            RadioGroup<String?>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v),
              child: Column(
                children: [
                  for (final r in _reasons)
                    RadioListTile<String>(
                      title: Text(r.label),
                      value: r.value,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: SeeUColors.accent,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Уточнения (необязательно)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SeeUButton(
                    label: 'Отмена',
                    variant: SeeUButtonVariant.secondary,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SeeUButton(
                    label: 'Отправить',
                    variant: SeeUButtonVariant.primary,
                    isLoading: _submitting,
                    onTap: (_selected == null || _submitting) ? null : _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
