import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/design/design.dart';
import '../core/api/api_client.dart';
import '../core/providers/scanner_provider.dart';

class ScannerLikesScreen extends ConsumerStatefulWidget {
  const ScannerLikesScreen({super.key});

  @override
  ConsumerState<ScannerLikesScreen> createState() => _ScannerLikesScreenState();
}

class _ScannerLikesScreenState extends ConsumerState<ScannerLikesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final api = ref.read(apiClientProvider);
      await markLikesSeen(api);
      ref.invalidate(unseenLikesProvider);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.seeuColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: Text('Лайки сканера',
            style: SeeUTypography.title.copyWith(color: colors.ink)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: SeeUColors.accent,
          labelColor: SeeUColors.accent,
          unselectedLabelColor: colors.ink3,
          tabs: const [
            Tab(text: 'Меня лайкнули'),
            Tab(text: 'Я лайкнул(а)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ReceivedLikesTab(),
          _SentLikesTab(),
        ],
      ),
    );
  }
}

// ─── Received ────────────────────────────────────────────────────────────────

class _ReceivedLikesTab extends ConsumerWidget {
  const _ReceivedLikesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receivedLikesProvider);

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return _ErrorView(
        message: state.error!,
        onRetry: () => ref.read(receivedLikesProvider.notifier).load(),
      );
    }

    if (state.items.isEmpty) {
      return _EmptyView(
        icon: PhosphorIconsRegular.heart,
        text: 'Тебя ещё никто не лайкнул\nв сканере',
      );
    }

    final colors = context.seeuColors;
    return RefreshIndicator(
      color: SeeUColors.accent,
      onRefresh: () => ref.read(receivedLikesProvider.notifier).load(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: state.items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1, color: colors.line, indent: 72),
        itemBuilder: (context, i) {
          final item = state.items[i];
          return ListTile(
            onTap: () => context.push('/profile/${item.username}'),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: colors.surface2,
              backgroundImage: item.avatarUrl.isNotEmpty
                  ? NetworkImage(item.avatarUrl)
                  : null,
              child: item.avatarUrl.isEmpty
                  ? Icon(PhosphorIconsRegular.user, color: colors.ink3)
                  : null,
            ),
            title: Row(children: [
              Text(item.username,
                  style: SeeUTypography.body.copyWith(
                      fontWeight: FontWeight.w600, color: colors.ink)),
              if (item.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(PhosphorIconsBold.sealCheck,
                    size: 14, color: SeeUColors.accent),
              ],
            ]),
            subtitle: Text(item.fullName.isNotEmpty ? item.fullName : ' ',
                style: SeeUTypography.caption.copyWith(color: colors.ink3)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(PhosphorIconsBold.heart, size: 16, color: SeeUColors.like),
                const SizedBox(height: 2),
                Text(_formatDate(item.likedAt),
                    style: SeeUTypography.micro.copyWith(color: colors.ink4)),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин';
    if (diff.inDays < 1) return '${diff.inHours} ч';
    if (diff.inDays < 7) return '${diff.inDays} д';
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
  }
}

// ─── Sent ─────────────────────────────────────────────────────────────────────

class _SentLikesTab extends ConsumerWidget {
  const _SentLikesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sentLikesProvider);

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return _ErrorView(
        message: state.error!,
        onRetry: () => ref.read(sentLikesProvider.notifier).load(),
      );
    }

    if (state.items.isEmpty) {
      return _EmptyView(
        icon: PhosphorIconsRegular.heartStraight,
        text: 'Ты ещё никого не лайкнул(а)\nв сканере',
      );
    }

    final colors = context.seeuColors;
    return RefreshIndicator(
      color: SeeUColors.accent,
      onRefresh: () => ref.read(sentLikesProvider.notifier).load(),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: state.items.length,
        itemBuilder: (context, i) {
          final item = state.items[i];
          return Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surface2,
                    border: Border.all(color: colors.line),
                  ),
                  child: item.scanAvatarUrl.isNotEmpty
                      ? ClipOval(child: Image.network(
                          item.scanAvatarUrl, fit: BoxFit.cover))
                      : Center(
                          child: Text(
                            item.scanAlias.isNotEmpty
                                ? item.scanAlias[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: colors.ink),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    item.scanAlias.isNotEmpty ? item.scanAlias : 'Аноним',
                    style: SeeUTypography.caption
                        .copyWith(fontWeight: FontWeight.w600, color: colors.ink),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(PhosphorIconsBold.heart,
                    size: 12, color: SeeUColors.like),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyView({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.seeuColors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: colors.ink4),
        const SizedBox(height: 16),
        Text(text,
            textAlign: TextAlign.center,
            style: SeeUTypography.body.copyWith(color: colors.ink3)),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.seeuColors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(PhosphorIconsRegular.wifiSlash, size: 48, color: colors.ink4),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: SeeUTypography.body.copyWith(color: colors.ink3)),
        const SizedBox(height: 16),
        SeeUButton(label: 'Повторить', onTap: onRetry),
      ]),
    );
  }
}
