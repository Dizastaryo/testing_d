import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import 'ai_mask_models.dart';
import 'ai_masks_provider.dart';

/// Bottom-sheet: prompt-input + кнопка «✨ Сгенерировать».
/// Возвращает свежесозданную AIMask или null если юзер отменил/ошибка.
Future<AIMask?> showAIMaskPromptSheet(BuildContext context) {
  return showModalBottomSheet<AIMask?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => const _PromptSheetBody(),
  );
}

class _PromptSheetBody extends ConsumerStatefulWidget {
  const _PromptSheetBody();

  @override
  ConsumerState<_PromptSheetBody> createState() => _PromptSheetBodyState();
}

class _PromptSheetBodyState extends ConsumerState<_PromptSheetBody> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  // Подсказки-примеры — клик подставляет в input.
  static const _examples = [
    'кошачьи уши с блёстками',
    'космический шлем с неоновой подсветкой',
    'корона из плюшевых медвежат',
    'венок из роз',
    'голограмма-сердечки парят над головой',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final prompt = _ctrl.text.trim();
    if (prompt.length < 3) {
      setState(() => _error = 'Введите хотя бы 3 символа');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final mask = await ref.read(aiMasksProvider.notifier).generate(prompt);
      HapticFeedback.heavyImpact();
      if (mounted) Navigator.of(context).pop(mask);
    } on AIMaskException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.4,
      maxChildSize: 0.9,
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
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI-маска',
                            style: SeeUTypography.title
                                .copyWith(color: Colors.white)),
                        Text('Опиши какую маску хочешь',
                            style: SeeUTypography.caption
                                .copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _ctrl,
                enabled: !_busy,
                maxLines: 3,
                maxLength: 300,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Например, «кошачьи уши с блёстками»',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: const TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 4),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: SeeUColors.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Примеры',
                style: SeeUTypography.caption.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _examples
                    .map((e) => GestureDetector(
                          onTap: _busy
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  _ctrl.text = e;
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              e,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
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
                      gradient: _busy
                          ? null
                          : SeeUGradients.heroOrange,
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
                                Text(
                                  'Генерирую…',
                                  style: SeeUTypography.subtitle.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIcons.sparkle(),
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Сгенерировать',
                                  style: SeeUTypography.subtitle.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Лимит: 5 генераций в сутки',
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
