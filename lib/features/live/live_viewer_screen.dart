import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/design/design.dart';
import '../../core/models/live_stream.dart';
import '../camera/widgets/camera_ui_kit.dart';
import 'live_viewer_service.dart';

/// Fullscreen live stream viewer (LiveKit subscriber). Opened from the Explore
/// "Прямой эфир" list or a live_stream.started notification.
class LiveViewerScreen extends ConsumerStatefulWidget {
  final String streamId;
  const LiveViewerScreen({super.key, required this.streamId});

  @override
  ConsumerState<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends ConsumerState<LiveViewerScreen> {
  bool _endedShown = false;
  LiveStream? _stream;
  String? _error;
  // Cached early so ref is never read inside dispose().
  ApiClient? _cachedApi;

  @override
  void initState() {
    super.initState();
    _init();
    LiveViewerService.instance.remoteVideoTrack.addListener(_rebuild);
    LiveViewerService.instance.status.addListener(_onStatusChanged);
    LiveViewerService.instance.viewerCount.addListener(_rebuild);
  }

  Future<void> _init() async {
    try {
      final api = ref.read(apiClientProvider);
      _cachedApi = api;
      final stream =
          await LiveViewerService.instance.joinStream(api, widget.streamId);
      if (mounted) setState(() => _stream = stream);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось подключиться к эфиру');
      }
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onStatusChanged() {
    final s = LiveViewerService.instance.status.value;
    if (s == LiveViewerStatus.ended && mounted && !_endedShown) {
      _endedShown = true;
      _showEndedDialog();
    } else if (s == LiveViewerStatus.failed && mounted) {
      setState(() =>
          _error = 'Не удалось подключиться к эфиру. Проверьте соединение.');
    }
  }

  void _shareStream() {
    final stream = _stream;
    final who = stream == null
        ? ''
        : (stream.username.isNotEmpty ? '@${stream.username}' : stream.fullName);
    final title = stream?.title ?? '';
    final buffer = StringBuffer('Прямой эфир');
    if (who.isNotEmpty) buffer.write(' $who');
    if (title.isNotEmpty) buffer.write(' — «$title»');
    buffer.write(' в SeeU');
    Share.share(buffer.toString());
  }

  void _showEndedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SeeURadii.card),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: SeeUColors.darkSurface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(SeeURadii.card),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: SeeUColors.live.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(PhosphorIconsRegular.broadcast,
                    color: SeeUColors.live, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                'ЭФИР',
                style: SeeUTypography.kicker.copyWith(color: Colors.white54),
              ),
              const SizedBox(height: 6),
              Text(
                'Эфир завершён',
                style: SeeUTypography.displayS.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Трансляция закончилась',
                style: SeeUTypography.body.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop(); // pop dialog
                  Navigator.of(context).pop(); // pop viewer screen
                },
                child: Container(
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Закрыть',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Glass overlay chrome ─────────────────────────────────────────────────

  /// Стеклянный инфо-pill вещателя (avatar + имя + тема) над видео.
  Widget _broadcasterPill(LiveStream stream) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.24),
              ],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(url: stream.avatarUrl, size: 32),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stream.fullName.isNotEmpty
                          ? stream.fullName
                          : stream.username,
                      style: SeeUTypography.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (stream.title.isNotEmpty)
                      Text(
                        stream.title,
                        style: SeeUTypography.micro
                            .copyWith(color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Стеклянный статус-pill: LIVE-точка + mono «LIVE» + счётчик зрителей.
  Widget _liveStatusPill(int viewerCount) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.24),
              ],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: SeeUColors.live,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'LIVE',
                style: SeeUTypography.kicker.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Icon(PhosphorIconsFill.eye,
                  color: Colors.white70, size: 12),
              const SizedBox(width: 3),
              Text(
                '$viewerCount',
                style: SeeUTypography.mono.copyWith(
                  color: Colors.white70,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    LiveViewerService.instance.remoteVideoTrack.removeListener(_rebuild);
    LiveViewerService.instance.status.removeListener(_onStatusChanged);
    LiveViewerService.instance.viewerCount.removeListener(_rebuild);
    // Use cached api — never read ref inside dispose.
    final api = _cachedApi;
    if (api != null) LiveViewerService.instance.leaveStream(api);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = LiveViewerService.instance.status.value;
    final viewerCount = LiveViewerService.instance.viewerCount.value;
    final track = LiveViewerService.instance.remoteVideoTrack.value;
    final stream = _stream;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video (LiveKit broadcaster track)
          if (status == LiveViewerStatus.connected && track != null)
            Positioned.fill(
              child: VideoTrackRenderer(
                track,
                fit: VideoViewFit.cover,
              ),
            )
          else if (_error != null)
            StatusView(
              icon: PhosphorIconsRegular.wifiSlash,
              message: _error!,
              actionLabel: 'Назад',
              onAction: () => Navigator.of(context).pop(),
            )
          else
            const Center(
              child: BrandedLoader(label: 'Подключение к эфиру…'),
            ),

          // Top gradient
          Positioned(
            top: 0, left: 0, right: 0,
            height: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                ),
              ),
            ),
          ),

          // Top bar — broadcaster info + LIVE badge + close button in one Row
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Broadcaster avatar + name — grouped into one glass info pill.
                if (stream != null)
                  Flexible(child: _broadcasterPill(stream))
                else
                  const Spacer(),
                const SizedBox(width: 8),
                // LIVE + viewer count — one glass status pill.
                _liveStatusPill(viewerCount),
                const SizedBox(width: 10),
                // Close button — glass circle over media.
                SeeUGlassCircleButton(
                  size: 40,
                  blur: 22,
                  onTap: () => Navigator.of(context).pop(),
                  icon: const Icon(PhosphorIconsRegular.x,
                      color: Colors.white, size: 18),
                ),
              ],
            ),
          ),

          // Bottom gradient
          Positioned(
            bottom: 0, left: 0, right: 0,
            height: 100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent],
                ),
              ),
            ),
          ),

          // Bottom bar — share action
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionBtn(
                  icon: PhosphorIconsRegular.paperPlaneRight,
                  label: 'Поделиться',
                  onTap: _shareStream,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final double size;
  const _Avatar({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: SeeUColors.accent, width: 2),
        color: Colors.grey.shade800,
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
            : const Icon(PhosphorIconsRegular.user, color: Colors.white54, size: 20),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SeeUGlassCircleButton(
          size: 46,
          blur: 22,
          onTap: onTap,
          icon: Icon(icon, color: Colors.white, size: 22),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(label.toUpperCase(),
              style: SeeUTypography.kicker
                  .copyWith(color: Colors.white70)),
        ],
      ],
    );
  }
}
