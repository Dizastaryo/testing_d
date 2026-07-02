import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/design/design.dart';
import 'live_broadcast_service.dart';
import 'live_broadcast_overlay.dart';

enum _Phase { idle, preparing, launching, failed }

/// Bottom sheet shown when the user taps LIVE on the camera right panel.
class LiveStartSheet extends ConsumerStatefulWidget {
  /// Which camera was active on the camera screen (front = selfie / back = main).
  final bool isFrontCamera;

  const LiveStartSheet({super.key, this.isFrontCamera = true});

  @override
  ConsumerState<LiveStartSheet> createState() => _LiveStartSheetState();
}

class _LiveStartSheetState extends ConsumerState<LiveStartSheet> {
  final _ctrl = TextEditingController();
  _Phase _phase = _Phase.idle;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _phase = _Phase.preparing; _error = null; });

    try {
      // Phase 1 — preparing: release camera, acquire mic/cam via WebRTC
      debugPrint('[LiveStartSheet] Starting broadcast…');

      final api = ref.read(apiClientProvider);

      // NOTE: setSender is already wired globally in CallListener (call_listener.dart).
      // No need to set it here again.

      // Phase 2 — launching: create backend stream record
      setState(() => _phase = _Phase.launching);

      await LiveBroadcastService.instance.startBroadcast(
        api,
        _ctrl.text.trim(),
        isFrontCamera: widget.isFrontCamera,
      );

      if (!mounted) return;

      // Success: close sheet and open the broadcast overlay.
      Navigator.of(context).pop();
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.transparent,
          pageBuilder: (_, __, ___) => const LiveBroadcastOverlay(),
        ),
      );
    } catch (e) {
      debugPrint('[LiveStartSheet] Error: $e');
      setState(() {
        _phase = _Phase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  // Maps a thrown error to a user-facing message.
  //
  // IMPORTANT: a DioException must be classified by its TYPE / HTTP status —
  // not by a substring match. Раньше любая ошибка от Dio (даже 500/410 при
  // доступном сервере) ловилась как `contains('dio')` и показывалась как
  // «Нет соединения с сервером», что маскировало настоящую причину.
  String _friendlyError(Object e) {
    // ── HTTP / network layer ────────────────────────────────────────────────
    if (e is DioException) {
      // No HTTP response = genuine connectivity problem.
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Нет соединения с сервером. Проверьте интернет.';
        default:
          break;
      }
      final code = e.response?.statusCode;
      switch (code) {
        case 401:
        case 403:
          return 'Сессия истекла. Перезайдите в аккаунт.';
        case 409:
          return 'Уже ведётся эфир с вашего аккаунта.';
        case 404:
          return 'Сервис эфиров недоступен. Обновите приложение.';
      }
      if (code != null && code >= 500) {
        return 'Сервер не смог запустить эфир (ошибка $code). Попробуйте позже.';
      }
      // Other response with a body message — surface it.
      final serverMsg = _extractServerMessage(e.response?.data);
      if (serverMsg != null && serverMsg.isNotEmpty) return serverMsg;
      return code != null
          ? 'Не удалось запустить эфир (код $code).'
          : 'Не удалось запустить эфир.';
    }

    // ── Camera / mic (getUserMedia) ─────────────────────────────────────────
    final s = e.toString().toLowerCase();
    if (s.contains('permission') || s.contains('notallowederror') ||
        s.contains('denied') || s.contains('доступ')) {
      return 'Нет доступа к камере или микрофону. Разрешите в настройках устройства.';
    }
    if (s.contains('notreadableerror') || s.contains('already in use') ||
        s.contains('camera device') || s.contains('cameraaccess') ||
        s.contains('failed to open')) {
      return 'Камера занята или недоступна. Попробуйте ещё раз через секунду.';
    }
    if (s.contains('overconstrainederror') || s.contains('overconstrained') ||
        s.contains('constraint')) {
      return 'Камера не поддерживает нужный режим. Попробуйте ещё раз.';
    }
    if (s.contains('уже идёт эфир') || s.contains('already broadcast') ||
        s.contains('already streaming')) {
      return 'Вы уже ведёте эфир.';
    }

    // Fallback: show the raw error but stripped of Dart boilerplate.
    final raw = e.toString()
        .replaceFirst(RegExp(r'^(Exception|PlatformException|StateError|DioException):\s*'), '')
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .trim();
    return raw.isNotEmpty ? raw : 'Не удалось запустить эфир.';
  }

  /// Pulls a human message out of an API error body ({"error": "...",
  /// "message": "..."}). Returns null when nothing useful is present.
  String? _extractServerMessage(dynamic data) {
    if (data is Map) {
      for (final key in ['message', 'error', 'msg']) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return null;
  }

  String get _buttonLabel {
    return switch (_phase) {
      _Phase.preparing => 'Подготавливаем...',
      _Phase.launching => 'Запускаем эфир...',
      _Phase.idle || _Phase.failed => 'Начать эфир',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.seeuColors;
    final loading = _phase == _Phase.preparing || _phase == _Phase.launching;

    // Стеклянная обёртка шита — свой blur внутри виджета (call-site показывает
    // его с backgroundColor: Colors.transparent, стекло блюрит камеру под ним).
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.9),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SeeURadii.sheet)),
            border: Border.all(color: colors.line, width: 0.5),
          ),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(PhosphorIconsFill.broadcast,
                    color: SeeUColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LIVE · ЭФИР',
                      style: SeeUTypography.kicker
                          .copyWith(color: SeeUColors.accent)),
                  const SizedBox(height: 2),
                  Text('Прямой эфир',
                      style: SeeUTypography.displayS
                          .copyWith(color: colors.ink)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Пока идёт запуск — блокируем ввод (у SeeUInput нет enabled).
          AbsorbPointer(
            absorbing: loading,
            child: SeeUInput(
              controller: _ctrl,
              maxLength: 80,
              hintText: 'Тема эфира (необязательно)',
            ),
          ),
          // Phase indicator while loading
          if (loading) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.ink3,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _phase == _Phase.preparing
                      ? 'Подготавливаем камеру...'
                      : 'Запускаем трансляцию...',
                  style: SeeUTypography.caption.copyWith(color: colors.ink3),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIconsRegular.warningCircle,
                    color: SeeUColors.error, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: SeeUTypography.caption
                        .copyWith(color: SeeUColors.error),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SeeUButton(
            label: _buttonLabel,
            onTap: loading ? null : _start,
          ),
            ],
          ),
        ),
      ),
    );
  }
}
