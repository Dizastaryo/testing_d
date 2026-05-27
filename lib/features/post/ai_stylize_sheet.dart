import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/design/design.dart';

/// Результат стилизации — байты нового PNG (для замены preview) + URL
/// (для сохранения в случае reuse'а).
class StylizeResult {
  final Uint8List bytes;
  final String resultUrl;
  const StylizeResult({required this.bytes, required this.resultUrl});
}

/// Список preset'ов стилизации. id'ы совпадают с backend `stylePromptTemplates`.
class _StylePreset {
  final String id;
  final String label;
  final IconData icon;
  const _StylePreset(this.id, this.label, this.icon);
}

const _stylePresets = <_StylePreset>[
  _StylePreset('ghibli', 'Студия Гибли', PhosphorIconsRegular.tree),
  _StylePreset('pixar', 'Pixar', PhosphorIconsRegular.filmStrip),
  _StylePreset('anime', 'Аниме', PhosphorIconsRegular.lightning),
  _StylePreset('watercolor', 'Акварель', PhosphorIconsRegular.drop),
  _StylePreset('cyberpunk', 'Cyberpunk', PhosphorIconsRegular.lightning),
  _StylePreset('oilpainting', 'Масло', PhosphorIconsRegular.paintBrush),
];

/// Bottom-sheet выбора стиля + custom prompt. Внутри сам грузит source-файл
/// (если ещё не загружен) и вызывает /ai/stylize.
///
/// Возвращает StylizeResult если успех, null если отмена/ошибка.
Future<StylizeResult?> showAIStylizeSheet({
  required BuildContext context,
  required Uint8List sourceBytes,
  required String sourceFilename,
}) {
  return showModalBottomSheet<StylizeResult?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _StylizeSheetBody(
      sourceBytes: sourceBytes,
      sourceFilename: sourceFilename,
    ),
  );
}

class _StylizeSheetBody extends ConsumerStatefulWidget {
  final Uint8List sourceBytes;
  final String sourceFilename;
  const _StylizeSheetBody({
    required this.sourceBytes,
    required this.sourceFilename,
  });

  @override
  ConsumerState<_StylizeSheetBody> createState() => _StylizeSheetBodyState();
}

class _StylizeSheetBodyState extends ConsumerState<_StylizeSheetBody> {
  final _customCtrl = TextEditingController();
  String _selectedPresetId = 'ghibli';
  bool _customMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final api = ref.read(apiClientProvider);

      // 1. Upload source to /media/upload (если уже загружен где-то — можно
      // переиспользовать URL, но проще каждый раз заново — нет stale-state'а).
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          widget.sourceBytes,
          filename: widget.sourceFilename,
        ),
      });
      final upload = await api.post(ApiEndpoints.mediaUpload, data: form);
      final sourceUrl = upload.data['data']['url'] as String;

      // 2. POST /ai/stylize
      final styleId = _customMode ? 'custom' : _selectedPresetId;
      final prompt = _customMode ? _customCtrl.text.trim() : '';
      if (_customMode && prompt.length < 3) {
        throw const _UserVisibleException('Введите prompt от 3 символов');
      }
      final r = await api.post(
        '/ai/stylize',
        data: {
          'image_url': sourceUrl,
          'style': styleId,
          if (_customMode) 'prompt': prompt,
        },
        options: Options(receiveTimeout: const Duration(seconds: 180)),
      );
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final resultUrl = data['result_url'] as String;

      // 3. Download stylized bytes — preview'у нужны bytes.
      final bytesResp = await api.get<List<int>>(
        AppConfig.apiOrigin + resultUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(bytesResp.data!);

      HapticFeedback.heavyImpact();
      if (mounted) {
        Navigator.of(context).pop(
            StylizeResult(bytes: bytes, resultUrl: resultUrl));
      }
    } on _UserVisibleException catch (e) {
      _showError(e.message);
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      final msg = (e.response?.data is Map &&
              (e.response!.data as Map)['error'] is String)
          ? (e.response!.data as Map)['error'] as String
          : 'не удалось стилизовать';
      if (code == 429) {
        _showError('Лимит сегодня исчерпан: $msg');
      } else if (code == 503) {
        _showError('AI временно недоступен');
      } else {
        _showError(msg);
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    if (mounted) {
      setState(() {
        _busy = false;
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
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
                        Text('AI-стилизация',
                            style: SeeUTypography.title
                                .copyWith(color: Colors.white)),
                        Text('Превратить кадр в любую эстетику',
                            style: SeeUTypography.caption
                                .copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Preset grid 3×2
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.5,
                ),
                itemCount: _stylePresets.length,
                itemBuilder: (_, i) {
                  final p = _stylePresets[i];
                  final isSelected =
                      !_customMode && _selectedPresetId == p.id;
                  return GestureDetector(
                    onTap: _busy
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedPresetId = p.id;
                              _customMode = false;
                            });
                          },
                    child: AnimatedContainer(
                      duration: SeeUMotion.quick,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? SeeUGradients.heroOrange
                            : null,
                        color: isSelected
                            ? null
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(p.icon,
                              color: Colors.white,
                              size: 22),
                          const SizedBox(height: 6),
                          Text(
                            p.label,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 14),

              // Custom prompt toggle + input
              GestureDetector(
                onTap: _busy
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        setState(() => _customMode = !_customMode);
                      },
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: SeeUMotion.quick,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _customMode
                            ? SeeUGradients.heroOrange
                            : null,
                        border: _customMode
                            ? null
                            : Border.all(
                                color: Colors.white.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                      ),
                      child: _customMode
                          ? const Icon(PhosphorIconsBold.check,
                              color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    const Text('Свой prompt',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
              if (_customMode) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customCtrl,
                  enabled: !_busy,
                  maxLines: 2,
                  maxLength: 300,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Например, «как Ван Гог, Звёздная ночь»',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    counterStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: SeeUColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
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
                      gradient:
                          _busy ? null : SeeUGradients.heroOrange,
                      color: _busy
                          ? Colors.white.withValues(alpha: 0.08)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: _busy
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text('Стилизую кадр…',
                                    style: SeeUTypography.subtitle.copyWith(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIcons.sparkle(),
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text('Применить стиль',
                                    style: SeeUTypography.subtitle.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    )),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Лимит: 3 стилизации в сутки · ≈ 15-30 сек на ответ',
                textAlign: TextAlign.center,
                style: SeeUTypography.caption
                    .copyWith(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UserVisibleException implements Exception {
  final String message;
  const _UserVisibleException(this.message);
}
