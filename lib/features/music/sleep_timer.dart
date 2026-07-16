import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/design/design.dart';
import 'audio_design.dart';

/// Таймер сна — для книги и медитации: включил, положил телефон, звук
/// выключится сам.
///
/// Живёт целиком на клиенте: серверу знать, когда человек уснул, незачем.
/// Отдельный вариант «до конца трека» — потому что обрывать главу на середине
/// хуже, чем доиграть лишние три минуты.
class SleepTimerState {
  /// Когда сработает. null — «в конце текущего трека».
  final DateTime? firesAt;

  /// Досмотреть текущий трек до конца и остановиться.
  final bool untilTrackEnd;

  /// Выбранный пресет в минутах — для подсветки активного чипа. null у режима
  /// «до конца трека».
  final int? minutes;

  const SleepTimerState({this.firesAt, this.untilTrackEnd = false, this.minutes});

  Duration? get remaining {
    if (firesAt == null) return null;
    final left = firesAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  String get label {
    if (untilTrackEnd) return 'до конца';
    final left = remaining;
    if (left == null) return '';
    final m = left.inMinutes;
    if (m >= 1) return '$m мин';
    return '${left.inSeconds} сек';
  }
}

class SleepTimerNotifier extends StateNotifier<SleepTimerState?> {
  SleepTimerNotifier(this._ref) : super(null);

  final Ref _ref;
  Timer? _timer;
  ProviderSubscription<MiniPlayerState>? _trackSub;
  StreamSubscription<ProcessingState>? _procSub;

  /// Трек, на завершение которого мы сейчас нацелены в режиме «до конца».
  /// Обновляется при ручном скипе — таймер целится на новый текущий трек.
  String? _armedId;

  /// Выключить звук через [minutes].
  void setMinutes(int minutes) {
    _cancelInternal();
    state = SleepTimerState(
      firesAt: DateTime.now().add(Duration(minutes: minutes)),
      minutes: minutes,
    );
    // Тикаем раз в секунду: экран показывает, сколько осталось.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = state;
      if (s?.firesAt == null) return;
      if (DateTime.now().isAfter(s!.firesAt!)) {
        _fire();
      } else {
        // Пересобираем состояние, чтобы подписчики обновили «осталось N мин».
        state = SleepTimerState(firesAt: s.firesAt, minutes: s.minutes);
      }
    });
  }

  /// Доиграть текущий трек и остановиться.
  ///
  /// Раньше срабатывало на любую смену track.id — то есть и на ручной скип
  /// (обрывал уже НОВЫЙ трек), а на последнем/единственном треке или при
  /// repeat-one id никогда не менялся, и таймер не срабатывал вовсе. Теперь:
  ///   • естественный конец всего источника (одиночный/последний трек) ловим
  ///     через ProcessingState.completed;
  ///   • в многотрековой очереди конец текущего = автопереход: срабатываем,
  ///     только если прошлый трек доигран почти до конца (а не ручной скип);
  ///   • ручной скип не гасит звук — просто перецеливаемся на новый текущий.
  void setUntilTrackEnd() {
    _cancelInternal();
    final startId = _ref.read(miniPlayerProvider).track?.id;
    if (startId == null) {
      state = null;
      return;
    }
    _armedId = startId;
    state = const SleepTimerState(untilTrackEnd: true);

    _procSub = _ref
        .read(audioPlayerServiceProvider)
        .processingStateStream
        .listen((s) {
      if (s == ProcessingState.completed) _fire();
    });

    _trackSub = _ref.listen<MiniPlayerState>(miniPlayerProvider, (prev, next) {
      final prevId = prev?.track?.id;
      final nextId = next.track?.id;
      if (prevId != _armedId || nextId == _armedId) return;
      // Наш трек сменился. Естественный конец → прошлый доигран почти до конца.
      final dur = prev?.duration?.inSeconds ?? 0;
      final pos = prev?.position.inSeconds ?? 0;
      final naturalEnd = dur > 0 && dur - pos <= 3;
      if (naturalEnd) {
        _fire();
      } else {
        // Ручной скип — перецеливаемся на новый текущий, звук не трогаем.
        _armedId = nextId;
      }
    });
  }

  void cancel() {
    _cancelInternal();
    state = null;
  }

  void _fire() {
    _cancelInternal();
    state = null;
    _ref.read(miniPlayerProvider.notifier).pause();
  }

  void _cancelInternal() {
    _timer?.cancel();
    _timer = null;
    _trackSub?.close();
    _trackSub = null;
    _procSub?.cancel();
    _procSub = null;
    _armedId = null;
  }

  @override
  void dispose() {
    _cancelInternal();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState?>(
  (ref) => SleepTimerNotifier(ref),
);

// ─── Шторка ─────────────────────────────────────────────────────────────────

Future<void> showSleepTimerSheet(BuildContext context) {
  return showSeeUBottomSheet<void>(
    context: context,
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  static const _options = [10, 20, 30, 45, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final timer = ref.watch(sleepTimerProvider);
    const mode = ListenMode.book;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: mode.soft(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(PhosphorIcons.moon(), size: 19, color: mode.color),
                ),
                const SizedBox(width: 10),
                Text(
                  'Таймер сна',
                  style: SeeUTypography.displayS
                      .copyWith(fontSize: 22, color: c.ink),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              timer == null
                  ? 'Звук выключится сам — можно не следить за телефоном.'
                  : 'Выключится через ${timer.label}.',
              style: TextStyle(fontSize: 13, height: 1.45, color: c.ink3),
            ),
            const SizedBox(height: 18),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _options)
                  _chip(
                    context,
                    label: '$m мин',
                    active: timer?.minutes == m,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(sleepTimerProvider.notifier).setMinutes(m);
                      Navigator.of(context).pop();
                    },
                  ),
                // Обрывать главу на середине хуже, чем доиграть до конца.
                _chip(
                  context,
                  label: 'До конца трека',
                  active: timer?.untilTrackEnd ?? false,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(sleepTimerProvider.notifier).setUntilTrackEnd();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),

            if (timer != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: Tappable.scaled(
                  onTap: () {
                    ref.read(sleepTimerProvider.notifier).cancel();
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Выключить таймер',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final c = context.seeuColors;
    const mode = ListenMode.book;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? mode.color : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? mode.color : c.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? Colors.white : c.ink,
          ),
        ),
      ),
    );
  }
}
