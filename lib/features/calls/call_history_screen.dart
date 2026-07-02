import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/call.dart';
import '../../core/providers/auth_provider.dart';
import 'call_service.dart';

/// История звонков (C-1). Tap на запись — повторный звонок peer'у.
class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Call> _calls = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.myCalls);
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data.map((e) => Call.fromJson(e as Map<String, dynamic>)).toList()
          : <Call>[];
      if (mounted) {
        setState(() {
          _calls = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _fmtDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final mm = m % 60;
      return '$h:${mm.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    // ignore: unnecessary_brace_in_string_interps
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  void _redial(Call c, {required bool asVoice}) {
    HapticFeedback.mediumImpact();
    final me = ref.read(authProvider).user;
    if (me == null) return;
    final peerId = c.isIncoming(me.id) ? c.fromUserId : c.toUserId;
    CallService.instance.startCall(
      peerId: peerId,
      peerUsername: c.peerUsername,
      peerAvatarUrl: c.peerAvatarUrl,
      kind: asVoice ? CallKind.voice : CallKind.video,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final me = ref.watch(authProvider).user;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Editorial glass-шапка (см. notifications_screen).
          SeeUGlassBar(
            kicker: 'ЗВОНКИ',
            titleText: 'История',
            leading: Tappable.scaled(
              onTap: () => context.pop(),
              scaleFactor: 0.9,
              child: SizedBox(
                width: 40,
                height: 40,
                child:
                    Icon(PhosphorIcons.caretLeft(), color: c.ink, size: 22),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: SeeUColors.accent,
              onRefresh: _load,
              child: _buildBody(me?.id ?? '', c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(String myId, SeeUThemeColors c) {
    if (_loading) {
      return const SeeUListSkeleton();
    }
    if (_error != null) {
      return SeeUErrorState(error: _error, onRetry: _load);
    }
    if (_calls.isEmpty) {
      return const SeeUEmptyState(
        icon: PhosphorIconsRegular.phone,
        title: 'Звонков пока нет',
        subtitle: 'История звонков появится здесь',
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      itemCount: _calls.length,
      itemBuilder: (_, i) {
        final call = _calls[i];
        final incoming = call.isIncoming(myId);
        final isVoice = call.kind == 'voice';
        final missed = call.isMissed;
        // Icon: ⬇ для incoming, ⬆ для outgoing. Цвет — accent или error.
        final dirIcon = incoming
            ? PhosphorIconsBold.phoneIncoming
            : PhosphorIconsBold.phoneOutgoing;
        final dirColor = missed ? SeeUColors.error : SeeUColors.accent;
        return SeeUListRow(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SeeUOnlineAvatar(
                  imageUrl: call.peerAvatarUrl,
                  fallbackText: call.peerUsername,
                  size: 44,
                  paletteSeed: call.peerUsername.hashCode,
                ),
                // Бейдж направления звонка (⬇/⬆, error — для пропущенных).
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: c.bg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(dirIcon, size: 12, color: dirColor),
                  ),
                ),
              ],
            ),
          ),
          title: call.peerFullName.isNotEmpty
              ? call.peerFullName
              : '@${call.peerUsername}',
          subtitle: [
            isVoice ? 'Аудио' : 'Видео',
            timeago.format(call.startedAt, locale: 'ru'),
            if (call.durationSeconds != null && call.durationSeconds! > 0)
              _fmtDuration(call.durationSeconds),
            if (missed) 'пропущенный',
          ].where((s) => s.isNotEmpty).join(' · '),
          trailing: Tappable.scaled(
            onTap: () => _redial(call, asVoice: isVoice),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SeeUColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVoice
                    ? PhosphorIconsRegular.phone
                    : PhosphorIconsRegular.videoCamera,
                color: SeeUColors.accent,
                size: 20,
              ),
            ),
          ),
          onTap: () {
            HapticFeedback.selectionClick();
            // Tap на запись — открыть профиль peer'а.
            context.push('/profile/${call.peerUsername}');
          },
        );
      },
    );
  }
}
