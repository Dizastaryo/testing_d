import 'package:cached_network_image/cached_network_image.dart';
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('История звонков'),
      ),
      body: RefreshIndicator(
        color: SeeUColors.accent,
        onRefresh: _load,
        child: _buildBody(me?.id ?? '', c),
      ),
    );
  }

  Widget _buildBody(String myId, SeeUThemeColors c) {
    if (_loading) {
      return const SeeUListSkeleton();
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Ошибка: $_error',
              style: TextStyle(color: c.ink2)),
        ),
      );
    }
    if (_calls.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.phone, size: 48, color: c.ink3),
              const SizedBox(height: 12),
              Text('Звонков пока нет',
                  style: SeeUTypography.body.copyWith(color: c.ink2)),
            ],
          ),
        ),
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
        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.surface2,
                backgroundImage: call.peerAvatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(call.peerAvatarUrl)
                    : null,
                child: call.peerAvatarUrl.isEmpty
                    ? Icon(PhosphorIcons.user(), color: c.ink3, size: 18)
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: c.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isVoice
                        ? PhosphorIconsFill.phone
                        : PhosphorIconsFill.videoCamera,
                    size: 12,
                    color: dirColor,
                  ),
                ),
              ),
            ],
          ),
          title: Row(
            children: [
              Icon(dirIcon, size: 12, color: dirColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  call.peerFullName.isNotEmpty
                      ? call.peerFullName
                      : '@${call.peerUsername}',
                  style: SeeUTypography.subtitle.copyWith(
                    color: missed ? SeeUColors.error : c.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            [
              timeago.format(call.startedAt, locale: 'ru'),
              if (call.durationSeconds != null && call.durationSeconds! > 0)
                _fmtDuration(call.durationSeconds),
              if (missed) 'пропущенный',
            ].where((s) => s.isNotEmpty).join(' · '),
            style: SeeUTypography.caption.copyWith(color: c.ink3),
          ),
          trailing: IconButton(
            icon: Icon(
              isVoice
                  ? PhosphorIconsRegular.phone
                  : PhosphorIconsRegular.videoCamera,
              color: SeeUColors.accent,
            ),
            onPressed: () => _redial(call, asVoice: isVoice),
            tooltip: 'Перезвонить',
          ),
          onTap: () {
            HapticFeedback.selectionClick();
            // Tap на запись — открыть chat с этим юзером (или начать новый).
            context.push('/profile/${call.peerUsername}');
          },
        );
      },
    );
  }
}
