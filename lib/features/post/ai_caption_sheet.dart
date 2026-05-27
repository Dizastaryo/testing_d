import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';

/// Результат выбора в AI-caption sheet'е.
class CaptionPicked {
  final String caption;
  final List<String> hashtags;
  const CaptionPicked({required this.caption, required this.hashtags});
}

/// Bottom-sheet: GPT-4o-vision генерирует 3 caption'а + 5 хэштегов по
/// загруженному фото. Юзер тапает один caption + любое подмножество тегов
/// и нажимает «Применить». Получатель решает как использовать (set'нуть
/// в textfield + добавить теги в массив).
Future<CaptionPicked?> showAICaptionSheet({
  required BuildContext context,
  required Uint8List sourceBytes,
  required String sourceFilename,
}) {
  return showModalBottomSheet<CaptionPicked?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _CaptionSheetBody(
      sourceBytes: sourceBytes,
      sourceFilename: sourceFilename,
    ),
  );
}

class _CaptionSheetBody extends ConsumerStatefulWidget {
  final Uint8List sourceBytes;
  final String sourceFilename;
  const _CaptionSheetBody({
    required this.sourceBytes,
    required this.sourceFilename,
  });

  @override
  ConsumerState<_CaptionSheetBody> createState() => _CaptionSheetBodyState();
}

class _CaptionSheetBodyState extends ConsumerState<_CaptionSheetBody> {
  String _vibe = 'casual'; // casual | poetic | funny
  bool _loading = false;
  String? _error;
  List<String> _captions = [];
  List<String> _hashtags = [];
  int? _selectedCaptionIdx;
  final Set<String> _selectedHashtags = {};

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _captions = [];
      _hashtags = [];
      _selectedCaptionIdx = null;
      _selectedHashtags.clear();
    });
    try {
      final api = ref.read(apiClientProvider);
      // Upload source one-time, reuse URL для caption.
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          widget.sourceBytes,
          filename: widget.sourceFilename,
        ),
      });
      final upload = await api.post(ApiEndpoints.mediaUpload, data: form);
      final sourceUrl = upload.data['data']['url'] as String;

      final r = await api.post(
        '/ai/caption',
        data: {'image_url': sourceUrl, 'vibe': _vibe},
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final caps = (data['captions'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [];
      final tags = (data['hashtags'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [];
      setState(() {
        _captions = caps;
        _hashtags = tags;
        _loading = false;
      });
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      final msg = (e.response?.data is Map &&
              (e.response!.data as Map)['error'] is String)
          ? (e.response!.data as Map)['error'] as String
          : 'AI временно недоступен';
      setState(() {
        _loading = false;
        _error = code == 503 ? 'AI не настроен на сервере' : msg;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _setVibe(String v) {
    if (_vibe == v) return;
    HapticFeedback.selectionClick();
    setState(() => _vibe = v);
    _generate();
  }

  void _toggleHashtag(String h) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedHashtags.contains(h)) {
        _selectedHashtags.remove(h);
      } else {
        _selectedHashtags.add(h);
      }
    });
  }

  void _selectCaption(int i) {
    HapticFeedback.selectionClick();
    setState(() => _selectedCaptionIdx = i);
  }

  void _apply() {
    if (_selectedCaptionIdx == null) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(
      CaptionPicked(
        caption: _captions[_selectedCaptionIdx!],
        hashtags: _selectedHashtags.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: SeeUColors.cameraDarkOverlay,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SeeUGradients.heroOrange,
                    ),
                    child: const Icon(PhosphorIconsFill.sparkle,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI-подпись',
                            style: SeeUTypography.title
                                .copyWith(color: Colors.white)),
                        Text('GPT-4o подбирает caption и хэштеги',
                            style: SeeUTypography.caption
                                .copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(PhosphorIcons.arrowsClockwise(),
                        color: Colors.white70, size: 20),
                    onPressed: _loading ? null : _generate,
                    tooltip: 'Сгенерировать заново',
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Vibe selector
              Row(
                children: [
                  _vibeChip('casual', 'Простой'),
                  const SizedBox(width: 8),
                  _vibeChip('poetic', 'Поэтично'),
                  const SizedBox(width: 8),
                  _vibeChip('funny', 'С юмором'),
                ],
              ),

              const SizedBox(height: 18),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: SeeUColors.accent,
                    ),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Ошибка: $_error',
                    style: const TextStyle(
                      color: SeeUColors.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else ...[
                Text('Подписи',
                    style: SeeUTypography.caption
                        .copyWith(color: Colors.white60)),
                const SizedBox(height: 6),
                ...List.generate(_captions.length, (i) {
                  final isSelected = _selectedCaptionIdx == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () => _selectCaption(i),
                      child: AnimatedContainer(
                        duration: SeeUMotion.quick,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? SeeUColors.accent.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? SeeUColors.accent
                                : Colors.white.withValues(alpha: 0.10),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _captions[i],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(PhosphorIconsFill.checkCircle,
                                  color: SeeUColors.accent, size: 18),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Text('Хэштеги — тап чтобы добавить',
                    style: SeeUTypography.caption
                        .copyWith(color: Colors.white60)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _hashtags.map((h) {
                    final picked = _selectedHashtags.contains(h);
                    return GestureDetector(
                      onTap: () => _toggleHashtag(h),
                      child: AnimatedContainer(
                        duration: SeeUMotion.quick,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient:
                              picked ? SeeUGradients.heroOrange : null,
                          color: picked
                              ? null
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: picked
                                ? Colors.transparent
                                : Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          '#$h',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: picked
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _selectedCaptionIdx == null || _loading
                      ? null
                      : _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: EdgeInsets.zero,
                  ).copyWith(
                    backgroundColor:
                        WidgetStateProperty.all(Colors.transparent),
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: _selectedCaptionIdx == null || _loading
                          ? null
                          : SeeUGradients.heroOrange,
                      color: _selectedCaptionIdx == null || _loading
                          ? Colors.white.withValues(alpha: 0.08)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Применить',
                        style: SeeUTypography.subtitle.copyWith(
                          color: _selectedCaptionIdx == null || _loading
                              ? Colors.white70
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _vibeChip(String value, String label) {
    final active = _vibe == value;
    return GestureDetector(
      onTap: _loading ? null : () => _setVibe(value),
      child: AnimatedContainer(
        duration: SeeUMotion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? SeeUGradients.heroOrange : null,
          color: active ? null : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
