import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/room_invites_provider.dart';
import '../../core/providers/room_provider.dart';

/// Bottom sheet showing pending room invites.
/// Opened from the Rooms tab header badge.
class RoomInvitesSheet extends ConsumerStatefulWidget {
  const RoomInvitesSheet({super.key});

  @override
  ConsumerState<RoomInvitesSheet> createState() => _RoomInvitesSheetState();
}

class _RoomInvitesSheetState extends ConsumerState<RoomInvitesSheet> {
  final Set<String> _processing = {};

  Future<void> _accept(RoomInvite invite) async {
    if (_processing.contains(invite.id)) return;
    HapticFeedback.selectionClick();
    setState(() => _processing.add(invite.id));
    try {
      await ref.read(roomInvitesProvider.notifier).accept(invite.id);
      ref.read(roomListProvider.notifier).load(silent: true);
    } catch (_) {
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось принять приглашение',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _processing.remove(invite.id));
    }
  }

  Future<void> _decline(RoomInvite invite) async {
    if (_processing.contains(invite.id)) return;
    HapticFeedback.selectionClick();
    setState(() => _processing.add(invite.id));
    try {
      await ref.read(roomInvitesProvider.notifier).decline(invite.id);
    } catch (_) {
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось отклонить приглашение',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _processing.remove(invite.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final invitesAsync = ref.watch(roomInvitesProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: c.line, borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    PhosphorIcons.envelope(PhosphorIconsStyle.fill),
                    size: 18,
                    color: SeeUColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Приглашения в комнаты',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 0),
          // Body
          Flexible(
            child: invitesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text('Ошибка загрузки',
                      style: TextStyle(color: c.ink3)),
                ),
              ),
              data: (invites) {
                if (invites.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: c.surface2,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            PhosphorIcons.envelopeOpen(PhosphorIconsStyle.fill),
                            size: 32,
                            color: c.ink4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Нет приглашений',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.ink2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Когда кто-то пригласит вас в комнату,\nприглашение появится здесь',
                          style: TextStyle(fontSize: 13, color: c.ink3),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: invites.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: c.line),
                  itemBuilder: (_, i) =>
                      _InviteTile(
                        invite: invites[i],
                        processing: _processing.contains(invites[i].id),
                        onAccept: () => _accept(invites[i]),
                        onDecline: () => _decline(invites[i]),
                        c: c,
                      ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final RoomInvite invite;
  final bool processing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final SeeUThemeColors c;

  const _InviteTile({
    required this.invite,
    required this.processing,
    required this.onAccept,
    required this.onDecline,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    // Room avatar: cover or gradient initial
    final roomInitial =
        invite.roomName.isNotEmpty ? invite.roomName[0].toUpperCase() : 'R';
    final palIdx = invite.roomName.isNotEmpty
        ? (invite.roomName.codeUnitAt(0) + invite.roomName.length) %
            SeeUColors.avatarPalettes.length
        : 0;
    final pal = SeeUColors.avatarPalettes[palIdx];

    // Inviter avatar
    final inviterInitial = invite.inviterName.isNotEmpty
        ? invite.inviterName[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Room cover / initial
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: invite.roomCover.isEmpty
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: pal,
                    )
                  : null,
              color: invite.roomCover.isNotEmpty ? c.surface2 : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: invite.roomCover.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(
                      imageUrl: invite.roomCover,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(roomInitial,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  )
                : Center(
                    child: Text(roomInitial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ),
          ),
          const SizedBox(width: 12),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.roomName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    // Mini inviter avatar
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.surface2,
                      ),
                      child: invite.inviterAvatar.isNotEmpty
                          ? ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: invite.inviterAvatar,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(inviterInitial,
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: c.ink2)),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(inviterInitial,
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: c.ink2)),
                            ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${invite.inviterName} приглашает вас',
                        style: TextStyle(fontSize: 12, color: c.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Actions
          if (processing)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SeeUColors.accent,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Decline
                Tappable.scaled(
                  onTap: onDecline,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      PhosphorIcons.x(PhosphorIconsStyle.bold),
                      size: 16,
                      color: c.ink3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Accept
                Tappable.scaled(
                  onTap: onAccept,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      PhosphorIconsBold.check,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
