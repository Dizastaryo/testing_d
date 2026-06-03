import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/models/sbor.dart';
import '../../core/providers/chat_provider.dart';
import 'sbory_screen.dart' show sborRefreshProvider;

// ─── Provider ────────────────────────────────────────────────────

final _sborDetailProvider =
    FutureProvider.autoDispose.family<Sbor, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.sborById(id));
  final data = r.data is Map && r.data.containsKey('data')
      ? r.data['data']
      : r.data;
  return Sbor.fromJson(data as Map<String, dynamic>);
});

// ─── Screen ──────────────────────────────────────────────────────

class SborDetailScreen extends ConsumerStatefulWidget {
  final String sborId;
  const SborDetailScreen({super.key, required this.sborId});

  @override
  ConsumerState<SborDetailScreen> createState() => _SborDetailScreenState();
}

class _SborDetailScreenState extends ConsumerState<SborDetailScreen> {
  bool _joining = false;     // covers both submit-request and cancel-request loading
  bool? _bookmarked; // null = not yet initialised from server
  bool _bookmarkLoading = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_sborDetailProvider(widget.sborId));

    return async.when(
      loading: () => Scaffold(
        backgroundColor: context.seeuColors.bg,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) {
        final isNotFound = e is DioException && e.response?.statusCode == 404;
        return Scaffold(
          backgroundColor: context.seeuColors.bg,
          appBar: AppBar(backgroundColor: Colors.transparent),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                isNotFound
                    ? 'Сбор не найден или был отменён'
                    : 'Ошибка: $e',
                style: TextStyle(color: context.seeuColors.ink2, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
      data: (sbor) {
        // Initialise bookmark state from server on first load.
        _bookmarked ??= sbor.isBookmarked;
        return _buildScreen(context, sbor);
      },
    );
  }

  Widget _buildScreen(BuildContext context, Sbor s) {
    final c = context.seeuColors;
    final meta = s.categoryMeta;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SafeArea(child: _buildHero(context, s, meta, c))),
              SliverToBoxAdapter(child: _buildInfoGrid(c, s)),
              SliverToBoxAdapter(child: _buildDescription(c, s)),
              SliverToBoxAdapter(child: _buildParticipants(c, s)),
              // Отступ снизу под sticky-кнопкой. Минимум 220 px + safe-area
              // чтобы участники при скролле выходили выше кнопки «Войти / Хочу вступить».
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.bottom + 220),
              ),
            ],
          ),
          _buildStickyBottom(context, c, s),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, Sbor s, SborCategoryMeta meta, SeeUThemeColors c) {
    final resolvedCover = (s.coverUrl == null || s.coverUrl!.isEmpty)
        ? null
        : s.coverUrl!.startsWith('/')
            ? AppConfig.apiOrigin + s.coverUrl!
            : s.coverUrl!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
        constraints: const BoxConstraints(minHeight: 220),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [meta.color, meta.soft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 2.2],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            if (resolvedCover != null)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: resolvedCover,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (resolvedCover != null)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -30, bottom: -40,
              child: Opacity(
                opacity: resolvedCover != null ? 0.0 : 0.2,
                child: Icon(meta.icon, size: 200, color: Colors.white),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HeroAction(
                      icon: PhosphorIcons.caretLeft(PhosphorIconsStyle.bold),
                      onTap: () => context.pop(),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${meta.name} · ${s.type == SborType.online ? "онлайн" : "оффлайн"}',
                        style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _HeroAction(
                      icon: PhosphorIcons.paperPlaneTilt(),
                      onTap: () => _sendToChatDirect(s),
                    ),
                    const SizedBox(width: 6),
                    _HeroAction(
                      icon: PhosphorIcons.shareFat(),
                      onTap: () => _showShareSheet(s),
                    ),
                    const SizedBox(width: 6),
                    _bookmarkLoading
                        ? Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : _HeroAction(
                            icon: (_bookmarked ?? false)
                                ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                                : PhosphorIcons.bookmarkSimple(),
                            onTap: () => _toggleBookmark(s),
                          ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  s.title,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 26, fontWeight: FontWeight.w500,
                    letterSpacing: -0.4, height: 1.15, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _miniAvatar(s.hostName),
                    const SizedBox(width: 6),
                    Text(
                      '${s.hostName} организует',
                      style: const TextStyle(
                        fontSize: 13, color: Colors.white, height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _miniAvatar(String name) {
    if (name.isEmpty) return const SizedBox.shrink();
    final seed = (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];
    return Container(
      width: 16, height: 16,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: pal),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name[0].toUpperCase(),
          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildInfoGrid(SeeUThemeColors c, Sbor s) {
    final items = [
      (PhosphorIcons.calendarBlank(), 'Когда', s.when, s.whenSub ?? ''),
      (
        PhosphorIcons.mapPinLine(),
        'Где',
        s.place,
        s.distance ?? '',
      ),
      (
        PhosphorIcons.usersThree(),
        'Состав',
        s.max != null ? '${s.joined}/${s.max}' : '${s.joined} чел.',
        s.isFull ? 'мест нет' : s.max != null ? 'нужно ещё ${s.remaining}' : '',
      ),
      (
        PhosphorIcons.wallet(),
        'Стоимость',
        s.price == 0 ? 'Бесплатно' : '${s.price} ₸',
        s.price == 0 ? '' : 'взнос',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.75,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final (icon, label, value, sub) = items[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: s.categoryMeta.color.withValues(alpha: 0.75)),
                const SizedBox(height: 5),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600,
                    letterSpacing: 0.6, color: c.ink3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: c.ink3),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDescription(SeeUThemeColors c, Sbor s) {
    if (s.description == null || s.description!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('О чём сбор', c),
          const SizedBox(height: 8),
          Text(
            s.description!,
            style: TextStyle(fontSize: 14, height: 1.55, color: c.ink2),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildParticipants(SeeUThemeColors c, Sbor s) {
    if (s.memberNames.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel('Идут', c),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${s.joined}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s.max != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: s.max! > 0 ? (s.joined / s.max!).clamp(0.0, 1.0) : 0,
                minHeight: 4,
                backgroundColor: c.line,
                valueColor: AlwaysStoppedAnimation<Color>(
                  s.isFull ? c.ink3 : SeeUColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: s.memberNames.length
                  + (s.joined > s.memberNames.length ? 1 : 0)
                  + (s.max != null && s.remaining > 0 ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) {
                final hasMore = s.joined > s.memberNames.length;
                final moreIdx = s.memberNames.length;
                final emptySlotIdx = moreIdx + (hasMore ? 1 : 0);
                if (i == moreIdx && hasMore) {
                  return GestureDetector(
                    onTap: () => _showAllMembers(s),
                    child: _MoreMembersSlot(count: s.joined - s.memberNames.length, c: c),
                  );
                }
                if (i == emptySlotIdx && s.max != null && s.remaining > 0) {
                  return GestureDetector(
                    onTap: () => _showAllMembers(s),
                    child: _EmptySlot(remaining: s.remaining, c: c),
                  );
                }
                final name = s.memberNames[i];
                final username = i < s.memberUsernames.length ? s.memberUsernames[i] : '';
                final memberId = i < s.memberIds.length ? s.memberIds[i] : null;
                final avatarUrl = i < s.memberAvatarUrls.length ? s.memberAvatarUrls[i] : '';
                final isHost = memberId != null && memberId == s.hostId;
                return _ParticipantCell(
                  name: name,
                  avatarUrl: avatarUrl,
                  isHost: isHost,
                  onTap: username.isNotEmpty
                      ? () => context.push('/profile/$username')
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAllMembers(Sbor s) {
    final c = context.seeuColors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Row(
                children: [
                  Text('Участники · ${s.joined}',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Icon(PhosphorIcons.x(), size: 20, color: c.ink3),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: s.memberNames.length,
                itemBuilder: (_, i) {
                  final name = s.memberNames[i];
                  final username = i < s.memberUsernames.length ? s.memberUsernames[i] : '';
                  final memberId = i < s.memberIds.length ? s.memberIds[i] : null;
                  final avatarUrl = i < s.memberAvatarUrls.length ? s.memberAvatarUrls[i] : '';
                  final isHost = memberId != null && memberId == s.hostId;
                  final resolvedUrl = avatarUrl.isEmpty
                      ? null
                      : avatarUrl.startsWith('http')
                          ? avatarUrl
                          : AppConfig.apiOrigin + avatarUrl;
                  final seed = name.isNotEmpty
                      ? (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length
                      : 0;
                  final pal = SeeUColors.avatarPalettes[seed];

                  return ListTile(
                    onTap: username.isNotEmpty
                        ? () {
                            Navigator.pop(ctx);
                            context.push('/profile/$username');
                          }
                        : null,
                    leading: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: resolvedUrl == null ? LinearGradient(colors: pal) : null,
                      ),
                      child: ClipOval(
                        child: resolvedUrl != null
                            ? CachedNetworkImage(
                                imageUrl: resolvedUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  decoration: BoxDecoration(gradient: LinearGradient(colors: pal)),
                                  child: Center(
                                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
                              ),
                      ),
                    ),
                    title: Text(name, style: TextStyle(fontSize: 15, color: c.ink, fontWeight: FontWeight.w500)),
                    subtitle: username.isNotEmpty
                        ? Text('@$username', style: TextStyle(fontSize: 13, color: c.ink3))
                        : isHost
                            ? Text('организатор', style: TextStyle(fontSize: 13, color: SeeUColors.accent))
                            : null,
                    trailing: isHost
                        ? Text('★', style: TextStyle(fontSize: 16, color: SeeUColors.accent))
                        : username.isNotEmpty
                            ? Icon(PhosphorIcons.caretRight(), size: 16, color: c.ink4)
                            : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyBottom(BuildContext context, SeeUThemeColors c, Sbor s) {
    final isOrganizer = s.myRole == SborRole.organizer;

    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [c.bg, c.bg.withValues(alpha: 0)],
            stops: const [0.6, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.isJoined) ...[
                // ── Joined: "Открыть чат" primary button ──
                GestureDetector(
                  onTap: () => _openChat(s),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: SeeUColors.accent.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIcons.chatCircleDots(PhosphorIconsStyle.fill),
                          size: 18, color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Открыть чат',
                          style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // ── Joined: secondary action row ──
                if (isOrganizer)
                  Row(
                    children: [
                      // Заявки на вступление
                      if (s.pendingRequestsCount > 0) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await context.push('/sbory/${s.id}/requests');
                              if (mounted) ref.invalidate(_sborDetailProvider(widget.sborId));
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: SeeUColors.accent.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: SeeUColors.accent.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(PhosphorIcons.usersThree(), size: 15, color: SeeUColors.accent),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Заявки · ${s.pendingRequestsCount}',
                                    style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600,
                                      color: SeeUColors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      // Редактировать
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            await context.push('/sbory/${s.id}/edit');
                            if (mounted) ref.invalidate(_sborDetailProvider(widget.sborId));
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: c.line),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(PhosphorIcons.pencilSimple(), size: 15, color: c.ink2),
                                const SizedBox(width: 6),
                                Text(
                                  'Редактировать',
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600, color: c.ink2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Отменить сбор
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _cancelSbor(s),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: SeeUColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: SeeUColors.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  PhosphorIcons.prohibit(),
                                  size: 15, color: SeeUColors.error,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Отменить сбор',
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    color: SeeUColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  // Participant: "Выйти из сбора" secondary button
                  GestureDetector(
                    onTap: () => _leaveSbor(s),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: SeeUColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: SeeUColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            PhosphorIcons.signOut(),
                            size: 15, color: SeeUColors.error,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Выйти из сбора',
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: SeeUColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ] else ...[
                // ── Not joined: request flow ──
                _buildJoinRequestButton(c, s),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJoinRequestButton(SeeUThemeColors c, Sbor s) {
    final status = s.myRequestStatus; // '' | 'pending' | 'approved' | 'rejected'

    if (s.isPast) {
      return _disabledButton(c, PhosphorIcons.clockCountdown(), 'Сбор уже прошёл');
    }
    if (s.isFull && status.isEmpty) {
      return _disabledButton(c, PhosphorIcons.lockSimple(), 'Мест нет');
    }

    if (status == 'pending') {
      return GestureDetector(
        onTap: _joining ? null : () => _cancelRequest(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_joining)
                const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                Icon(PhosphorIcons.hourglassMedium(), size: 18, color: c.ink2),
                const SizedBox(width: 8),
                Text(
                  'Заявка отправлена · отозвать',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.ink2,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (status == 'rejected') {
      return GestureDetector(
        onTap: _joining ? null : () => _submitRequest(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            color: SeeUColors.accent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: SeeUColors.accent.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_joining)
                const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              else ...[
                Icon(PhosphorIcons.arrowCounterClockwise(), size: 18, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'Подать заявку снова',
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Default: not requested yet
    return GestureDetector(
      onTap: _joining ? null : () => _submitRequest(s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: SeeUColors.accent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_joining)
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            else ...[
              Icon(
                PhosphorIcons.handWaving(PhosphorIconsStyle.fill),
                size: 18, color: Colors.white,
              ),
              const SizedBox(width: 8),
              const Text(
                'Хочу вступить',
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _disabledButton(SeeUThemeColors c, IconData icon, String label) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: c.ink3),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: c.ink3,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBookmark(Sbor s) async {
    if (_bookmarkLoading) return;
    setState(() => _bookmarkLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(ApiEndpoints.bookmarkSbor(s.id));
      bool saved = !(_bookmarked ?? false);
      if (resp.data is Map) {
        final d = resp.data['data'];
        if (d is Map<String, dynamic> && d['saved'] is bool) {
          saved = d['saved'] as bool;
        }
      }
      if (!mounted) return;
      setState(() => _bookmarked = saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved ? 'Добавлено в сохранённые' : 'Убрано из сохранённых'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _bookmarkLoading = false);
    }
  }

  Future<void> _sendToChatDirect(Sbor s) async {
    final c = context.seeuColors;
    final chats = ref.read(chatListProvider).chats;

    if (chats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступных чатов')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.60,
          ),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: c.line, borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  children: [
                    Text(
                      'Отправить в чат',
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600, color: c.ink,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Icon(PhosphorIcons.x(), size: 20, color: c.ink3),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: chats.length,
                  itemBuilder: (_, i) {
                    final chat = chats[i];
                    final name = chat.isGroup
                        ? chat.title
                        : chat.otherUser?.fullName ?? chat.otherUser?.username ?? '';
                    return ListTile(
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _sendSborToChat(chat.id, s);
                      },
                      leading: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600,
                              color: c.ink2,
                            ),
                          ),
                        ),
                      ),
                      title: Text(name, style: TextStyle(fontSize: 15, color: c.ink)),
                      subtitle: chat.isGroup
                          ? Text('${chat.participantsCount} участников',
                              style: TextStyle(fontSize: 12, color: c.ink3))
                          : chat.otherUser?.username != null
                              ? Text('@${chat.otherUser!.username}',
                                  style: TextStyle(fontSize: 12, color: c.ink3))
                              : null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showShareSheet(Sbor s) async {
    final c = context.seeuColors;
    final chats = ref.read(chatListProvider).chats;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: c.line, borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  children: [
                    Text(
                      'Поделиться',
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600, color: c.ink,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Icon(PhosphorIcons.x(), size: 20, color: c.ink3),
                    ),
                  ],
                ),
              ),
              // Внешний шаринг
              ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  Share.share('Сбор «${s.title}» в приложении SeeU\n${s.place}');
                },
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: c.surface2, borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(PhosphorIcons.export(), size: 20, color: c.ink2),
                ),
                title: Text('Поделиться вовне', style: TextStyle(fontSize: 15, color: c.ink)),
                subtitle: Text('Telegram, WhatsApp и другие', style: TextStyle(fontSize: 12, color: c.ink3)),
              ),
              const SizedBox(height: 6),
              if (chats.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ОТПРАВИТЬ В ЧАТ',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        letterSpacing: 0.8, color: c.ink3,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: chats.length,
                    itemBuilder: (_, i) {
                      final chat = chats[i];
                      final name = chat.isGroup
                          ? chat.title
                          : chat.otherUser?.fullName ?? chat.otherUser?.username ?? '';
                      return ListTile(
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _sendSborToChat(chat.id, s);
                        },
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: c.surface2,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600,
                                color: c.ink2,
                              ),
                            ),
                          ),
                        ),
                        title: Text(name, style: TextStyle(fontSize: 15, color: c.ink)),
                        subtitle: chat.isGroup
                            ? Text('${chat.participantsCount} участников', style: TextStyle(fontSize: 12, color: c.ink3))
                            : chat.otherUser?.username != null
                                ? Text('@${chat.otherUser!.username}', style: TextStyle(fontSize: 12, color: c.ink3))
                                : null,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendSborToChat(String chatId, Sbor s) async {
    try {
      final api = ref.read(apiClientProvider);
      final text = '📍 Сбор «${s.title}»\n'
          '${s.type == SborType.online ? "Онлайн" : s.place} · ${s.when}\n'
          'seeu://sbory/${s.id}';
      await api.post(
        ApiEndpoints.chatMessages(chatId),
        data: {'text': text},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сбор отправлен в чат')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  void _openChat(Sbor s) {
    HapticFeedback.mediumImpact();
    if (s.chatId != null) {
      context.go('/chat/${s.chatId}');
    }
  }

  Future<void> _submitRequest(Sbor s) async {
    HapticFeedback.mediumImpact();
    setState(() => _joining = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.sborRequests(s.id));
      if (!mounted) return;
      ref.invalidate(_sborDetailProvider(widget.sborId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка отправлена — ждём подтверждения')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data?['error'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Ошибка: $e')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _cancelRequest(Sbor s) async {
    HapticFeedback.lightImpact();
    setState(() => _joining = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.sborRequests(s.id));
      if (!mounted) return;
      ref.invalidate(_sborDetailProvider(widget.sborId));
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data?['error'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Ошибка: $e')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _leaveSbor(Sbor s) async {
    final c = context.seeuColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Выйти из сбора?', style: TextStyle(color: c.ink, fontSize: 17)),
        content: Text(
          'Ты покинешь сбор и групповой чат.',
          style: TextStyle(color: c.ink2, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Нет', style: TextStyle(color: c.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.leaveSbor(s.id));
      if (!mounted) return;
      ref.read(sborRefreshProvider.notifier).state++;
      ref.read(chatListProvider.notifier).load();
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _cancelSbor(Sbor s) async {
    final c = context.seeuColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Отменить сбор?', style: TextStyle(color: c.ink, fontSize: 17)),
        content: Text(
          'Все участники будут уведомлены об отмене.',
          style: TextStyle(color: c.ink2, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Нет', style: TextStyle(color: c.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.cancelSbor(s.id));
      if (!mounted) return;
      ref.read(sborRefreshProvider.notifier).state++;
      ref.read(chatListProvider.notifier).load();
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }
}

// ─── Helpers ─────────────────────────────────────────────────────

class _HeroAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeroAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.5),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final SeeUThemeColors c;

  const _SectionLabel(this.text, this.c);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600,
        letterSpacing: 0.8, color: c.ink3,
      ),
    );
  }
}

class _ParticipantCell extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final bool isHost;
  final VoidCallback? onTap;

  const _ParticipantCell({required this.name, this.avatarUrl = '', required this.isHost, this.onTap});

  @override
  Widget build(BuildContext context) {
    final seed = name.isNotEmpty
        ? (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length
        : 0;
    final pal = SeeUColors.avatarPalettes[seed];
    final c = context.seeuColors;
    final resolvedUrl = avatarUrl.isEmpty
        ? null
        : avatarUrl.startsWith('http')
            ? avatarUrl
            : AppConfig.apiOrigin + avatarUrl;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: onTap != null
                    ? Border.all(color: SeeUColors.accent, width: 2)
                    : null,
              ),
              child: ClipOval(
                child: resolvedUrl != null
                    ? CachedNetworkImage(
                        imageUrl: resolvedUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          decoration: BoxDecoration(gradient: LinearGradient(colors: pal)),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
                            ),
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(gradient: LinearGradient(colors: pal)),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (isHost)
              Text(
                '★ ведёт',
                style: TextStyle(fontSize: 10, color: SeeUColors.accent, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}

class _MoreMembersSlot extends StatelessWidget {
  final int count;
  final SeeUThemeColors c;

  const _MoreMembersSlot({required this.count, required this.c});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface2,
              border: Border.all(color: c.line, width: 1.5),
            ),
            child: Center(
              child: Text(
                '+$count',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink2),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('ещё $count', style: TextStyle(fontSize: 10, color: c.ink3)),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final int remaining;
  final SeeUThemeColors c;

  const _EmptySlot({required this.remaining, required this.c});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: c.ink4,
                width: 1.5,
                style: BorderStyle.solid,
              ),
            ),
            child: Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold), size: 18, color: c.ink3),
          ),
          const SizedBox(height: 6),
          Text('+$remaining места', style: TextStyle(fontSize: 10, color: c.ink3)),
        ],
      ),
    );
  }
}
