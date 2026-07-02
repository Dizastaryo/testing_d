import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/pair.dart';
import '../../core/providers/pair_provider.dart';

/// Входящие промпты «Стать парой?» (Фаза 5). Появляются после встречного
/// двойного NFC-касания между людьми с открытым доступом. Ответ тихий:
/// «Нет»/игнор второму не сообщается (спека 6.3).
class PairPromptsScreen extends ConsumerWidget {
  const PairPromptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final state = ref.watch(pairPromptsProvider);

    final topInset = MediaQuery.of(context).padding.top + 56;
    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          state.when(
            loading: () => Center(
                child: CircularProgressIndicator(color: SeeUColors.accent)),
            error: (e, _) => SeeUErrorState(
              error: e.toString(),
              onRetry: () => ref.read(pairPromptsProvider.notifier).load(),
            ),
            data: (items) {
              if (items.isEmpty) {
                return SeeUEmptyState(
                  icon: PhosphorIconsRegular.fireSimple,
                  title: 'Нет предложений стать парой',
                  subtitle:
                      'Коснитесь браслетами друг друга по NFC почти одновременно — '
                      'и здесь появится предложение.',
                );
              }
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 24),
                itemCount: items.length,
                itemBuilder: (ctx, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _SparkCard(prompt: items[i]),
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SeeUGlassBar(
              kicker: 'Искра',
              titleText: 'Стать парой',
              leading: Tappable(
                onTap: () => context.pop(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(PhosphorIconsRegular.arrowLeft,
                      size: 20, color: c.ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkCard extends ConsumerStatefulWidget {
  final PairPrompt prompt;
  const _SparkCard({required this.prompt});

  @override
  ConsumerState<_SparkCard> createState() => _SparkCardState();
}

class _SparkCardState extends ConsumerState<_SparkCard>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: SeeUMotion.storyPulse,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _respond(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(pairPromptsProvider.notifier)
          .respond(widget.prompt.id, accept);
      if (!mounted) return;
      if (accept) {
        showSeeUSnackBar(
          context,
          'Если оба согласны — вы пара',
          icon: PhosphorIconsFill.fireSimple,
          tone: SeeUTone.success,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.prompt.user;
    final name = u.fullName.isNotEmpty ? u.fullName : u.username;

    return Container(
      decoration: BoxDecoration(
        gradient: SeeUGradients.sunsetCard,
        borderRadius: BorderRadius.circular(SeeURadii.card),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.like.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Пульсирующий огонёк — эмоциональный акцент.
                ScaleTransition(
                  scale: Tween(begin: 0.9, end: 1.12).animate(
                    CurvedAnimation(parent: _pulse, curve: SeeUMotion.breathe),
                  ),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    child: const Center(
                      child: PhosphorIcon(PhosphorIconsFill.fireSimple,
                          size: 22, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('ИСКРА',
                    style: SeeUTypography.kicker.copyWith(
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6), width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: u.avatarUrl.isNotEmpty
                        ? CachedNetworkImageProvider(u.avatarUrl)
                        : null,
                    child: u.avatarUrl.isEmpty
                        ? Text(
                            u.username.isNotEmpty
                                ? u.username[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 20))
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: SeeUTypography.displayS
                              .copyWith(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('Хотите стать парой?',
                          style: SeeUTypography.subtitle.copyWith(
                              color: Colors.white.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_busy)
              const SizedBox(
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _SparkAction(
                      label: 'Не сейчас',
                      filled: false,
                      onTap: () => _respond(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SparkAction(
                      label: 'Да, искра!',
                      filled: true,
                      onTap: () => _respond(true),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Пилюля-действие на градиентной spark-карте: «Да» — белая заливка с акцентным
/// текстом, «Нет» — полупрозрачный белый outline.
class _SparkAction extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _SparkAction({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
        ),
        child: Text(
          label,
          style: SeeUTypography.subtitle.copyWith(
            color: filled ? SeeUColors.accent : Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
