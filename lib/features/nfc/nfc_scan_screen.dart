import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/design/design.dart';
import '../../core/providers/pair_provider.dart';
import '../../core/providers/scanner_provider.dart';
import '../../services/nfc_band_service.dart';

/// Экран «Поднеси телефон к браслету» (Фазы 4–5).
/// Одно касание делает сразу два дела:
///   • Фаза 4 — резолвит владельца браслета и открывает его профиль (знакомство).
///   • Фаза 5 — шлёт касание на /pairs/tap; если второй человек коснулся твоего
///     браслета в пределах окна, сервер пришлёт обоим промпт «Стать парой?».
class NfcScanScreen extends ConsumerStatefulWidget {
  const NfcScanScreen({super.key});

  @override
  ConsumerState<NfcScanScreen> createState() => _NfcScanScreenState();
}

/// Стадия сканирования — определяет глиф, цвет и наличие «дыхания».
enum _NfcStage { scanning, error, unsupported, success }

class _NfcScanScreenState extends ConsumerState<NfcScanScreen>
    with SingleTickerProviderStateMixin {
  String _status = 'Поднеси телефон к браслету';
  _NfcStage _stage = _NfcStage.scanning;
  bool _busy = false;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: SeeUMotion.storyPulse,
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _pulse.dispose();
    NfcBandService.stop();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _stage = _NfcStage.scanning;
      _status = 'Поднеси телефон к браслету';
    });

    if (!await NfcBandService.isAvailable()) {
      if (!mounted) return;
      setState(() {
        _stage = _NfcStage.unsupported;
        _busy = false;
        _status = 'NFC недоступен на этом устройстве';
      });
      return;
    }

    final hash = await NfcBandService.readBandHash();
    if (!mounted) return;

    if (hash == null) {
      setState(() {
        _stage = _NfcStage.error;
        _busy = false;
        _status = 'Тег не распознан. Попробуй ещё раз.';
      });
      return;
    }

    setState(() {
      _stage = _NfcStage.success;
      _status = 'Браслет найден…';
    });

    // Фаза 5: фиксируем касание (для пары) — не блокируем переход профилем.
    recordNfcTap(ref, hash).catchError((_) => 'ignored');

    // Фаза 4: резолвим владельца и открываем профиль.
    final api = ref.read(apiClientProvider);
    final profiles = await resolveScanProfiles(api, [hash]);
    if (!mounted) return;

    if (profiles.isEmpty) {
      setState(() {
        _stage = _NfcStage.error;
        _busy = false;
        _status = 'Браслет пока не привязан к аккаунту.';
      });
      return;
    }

    final profile = profiles.values.first;
    if (profile.username.isEmpty) {
      setState(() {
        _stage = _NfcStage.error;
        _busy = false;
        _status = 'Не удалось открыть профиль владельца.';
      });
      return;
    }

    // Заменяем экран сканера профилем владельца.
    context.pushReplacement('/profile/${profile.username}');
  }

  Color get _stageColor => switch (_stage) {
        _NfcStage.unsupported => SeeUColors.textTertiary,
        _NfcStage.error => SeeUColors.amber,
        _NfcStage.success => SeeUColors.success,
        _NfcStage.scanning => SeeUColors.accent,
      };

  IconData get _stageGlyph => switch (_stage) {
        _NfcStage.unsupported => PhosphorIconsFill.warning,
        _NfcStage.error => PhosphorIconsFill.arrowsClockwise,
        _NfcStage.success => PhosphorIconsFill.check,
        _NfcStage.scanning => PhosphorIconsFill.wifiHigh,
      };

  IconData get _statusGlyph => switch (_stage) {
        _NfcStage.unsupported => PhosphorIconsRegular.warning,
        _NfcStage.error => PhosphorIconsRegular.info,
        _NfcStage.success => PhosphorIconsRegular.checkCircle,
        _NfcStage.scanning => PhosphorIconsRegular.deviceMobile,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final pulsing = _stage == _NfcStage.scanning;

    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Мягкий brand-glow сверху за глифом.
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 420,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.9,
                    colors: [
                      _stageColor.withValues(alpha: 0.12),
                      _stageColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Editorial-хедер: kicker + серифный заголовок.
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SeeUGlassCircleButton(
                        icon: PhosphorIcon(PhosphorIconsRegular.caretLeft,
                            size: 20, color: c.ink),
                        onTap: () => context.pop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ЗНАКОМСТВО ПО NFC',
                                style: SeeUTypography.kicker
                                    .copyWith(color: SeeUColors.accent),
                              ),
                              const SizedBox(height: 4),
                              Text('Поднеси телефон',
                                  style: SeeUTypography.displayM
                                      .copyWith(color: c.ink)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Hero: пульсирующий NFC-глиф.
                Expanded(
                  child: Center(
                    child: _NfcPulse(
                      pulse: _pulse,
                      active: pulsing,
                      color: _stageColor,
                      glyph: _stageGlyph,
                    ),
                  ),
                ),

                // Плавающая стеклянная status-карта.
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: _StatusCard(
                    icon: _statusGlyph,
                    color: _stageColor,
                    message: _status,
                    hint:
                        'Достаточно поднести телефон к браслету другого человека.',
                  ),
                ),

                // Bottom-pinned CTA (не снимаем с монтажа — inline-спиннер).
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      24, 12, 24, 16 + MediaQuery.of(context).padding.bottom),
                  child: _stage == _NfcStage.unsupported
                      ? SeeUButton(
                          label: 'Назад',
                          variant: SeeUButtonVariant.secondary,
                          onTap: () => context.pop(),
                        )
                      : SeeUButton(
                          label: 'Сканировать',
                          icon: PhosphorIconsRegular.arrowsClockwise,
                          isLoading: _busy,
                          onTap: _busy ? null : _scan,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Концентрический «дышащий» pulse за NFC-глифом. В активном состоянии из
/// центра расходятся мягкие кольца (radar-gradient), в остальных — статичный
/// глиф в стеклянном диске.
class _NfcPulse extends StatelessWidget {
  final Animation<double> pulse;
  final bool active;
  final Color color;
  final IconData glyph;

  const _NfcPulse({
    required this.pulse,
    required this.active,
    required this.color,
    required this.glyph,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (active)
                for (var i = 0; i < 3; i++)
                  _Ripple(t: (pulse.value + i / 3.0) % 1.0, color: color),
              // Центральный стеклянный диск с глифом.
              AnimatedContainer(
                duration: SeeUMotion.normal,
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: 0.22),
                      color.withValues(alpha: 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: color.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: PhosphorIcon(glyph, size: 52, color: color),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Ripple extends StatelessWidget {
  final double t; // 0..1
  final Color color;
  const _Ripple({required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    final size = 128 + 128 * t;
    final opacity = (1.0 - t) * 0.5;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 1.4,
        ),
      ),
    );
  }
}

/// Плавающая стеклянная status-карта: настоящий BackdropFilter + hairline +
/// иконка/цвет по стадии.
class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String hint;

  const _StatusCard({
    required this.icon,
    required this.color,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.card),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(SeeURadii.card),
            border: Border.all(color: c.line, width: 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                ),
                child: Center(
                    child: PhosphorIcon(icon, size: 20, color: color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message,
                        style: SeeUTypography.subtitle
                            .copyWith(color: c.ink, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(hint,
                        style:
                            SeeUTypography.caption.copyWith(color: c.ink3, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
