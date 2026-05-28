import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/models/sbor.dart';
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
  bool _joining = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_sborDetailProvider(widget.sborId));

    return async.when(
      loading: () => Scaffold(
        backgroundColor: context.seeuColors.bg,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: context.seeuColors.bg,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(child: Text('Ошибка: $e')),
      ),
      data: (sbor) => _buildScreen(context, sbor),
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
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
                    _HeroAction(icon: PhosphorIcons.shareFat(), onTap: () {}),
                    const SizedBox(width: 6),
                    _HeroAction(icon: PhosphorIcons.bookmarkSimple(), onTap: () {}),
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
        PhosphorIcons.currencyRub(),
        'Стоимость',
        s.price == 0 ? 'Бесплатно' : '${s.price} ₸',
        s.price == 0 ? 'своё снаряжение' : '',
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
          childAspectRatio: 2.0,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final (icon, label, value, sub) = items[i];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: c.ink3),
                const SizedBox(height: 4),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600,
                    letterSpacing: 0.6, color: c.ink3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('О чём сбор', c),
          const SizedBox(height: 8),
          Text(
            s.description!,
            style: TextStyle(fontSize: 14, height: 1.5, color: c.ink2),
          ),
        ],
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
          _SectionLabel('Идут', c),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: s.memberNames.length + (s.max != null && s.remaining > 0 ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                if (i == s.memberNames.length) {
                  return _EmptySlot(remaining: s.remaining, c: c);
                }
                final name = s.memberNames[i];
                final username = i < s.memberUsernames.length ? s.memberUsernames[i] : null;
                final isHost = i == 0;
                return _ParticipantCell(
                  name: name,
                  isHost: isHost,
                  onTap: username != null && username.isNotEmpty
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
              GestureDetector(
                onTap: _joining || s.isFull && !s.isJoined
                    ? null
                    : () => _joinOrOpenChat(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 52,
                  decoration: BoxDecoration(
                    color: s.isJoined
                        ? SeeUColors.accent
                        : s.isFull
                            ? c.surface2
                            : SeeUColors.accent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: s.isFull && !s.isJoined
                        ? null
                        : [
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
                          s.isJoined
                              ? PhosphorIcons.chatCircleDots(PhosphorIconsStyle.fill)
                              : s.isFull
                                  ? PhosphorIcons.lockSimple()
                                  : PhosphorIcons.handWaving(PhosphorIconsStyle.fill),
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          s.isJoined
                              ? isOrganizer ? 'Открыть чат сбора' : 'Я иду · Открыть чат'
                              : s.isFull
                                  ? 'Мест нет'
                                  : 'Я иду',
                          style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (isOrganizer) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _cancelSbor(s),
                  child: Text(
                    'Отменить сбор',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: c.ink3,
                      decoration: TextDecoration.underline,
                      decorationColor: c.ink3,
                    ),
                  ),
                ),
              ] else if (s.isJoined) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _leaveSbor(s),
                  child: Text(
                    'Выйти из сбора',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: c.ink3,
                      decoration: TextDecoration.underline,
                      decorationColor: c.ink3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _joinOrOpenChat(Sbor s) async {
    HapticFeedback.mediumImpact();

    // Уже участник — открываем чат или запрашиваем свежие данные (chatId мог появиться)
    if (s.isJoined) {
      if (s.chatId != null) {
        context.push('/chat/${s.chatId}');
        return;
      }
      // chatId ещё нет (старый сбор) — дёргаем join idempotent, получаем chatId
    }

    // Вступаем в сбор
    setState(() => _joining = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(ApiEndpoints.joinSbor(s.id));
      if (!mounted) return;

      // Получаем chat_id из ответа и сразу открываем чат
      final data = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data'] as Map<String, dynamic>
          : resp.data as Map<String, dynamic>? ?? {};
      final chatId = data['chat_id'] as String?;

      ref.invalidate(_sborDetailProvider(widget.sborId));

      if (chatId != null && mounted) {
        context.push('/chat/$chatId');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вступил в сбор')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
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
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: Colors.white),
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
  final bool isHost;
  final VoidCallback? onTap;

  const _ParticipantCell({required this.name, required this.isHost, this.onTap});

  @override
  Widget build(BuildContext context) {
    final seed = (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];
    final c = context.seeuColors;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: pal),
                shape: BoxShape.circle,
                border: onTap != null
                    ? Border.all(color: SeeUColors.accent, width: 2)
                    : null,
              ),
              child: Center(
                child: Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20,
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
