import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/models/highlight.dart';
import '../../../core/models/story.dart';
import '../../../core/providers/user_provider.dart';
import '../../feed/widgets/stories_row.dart';
import '../create_highlight_sheet.dart';

class ProfileHighlightsRow extends ConsumerWidget {
  final List<Highlight> highlights;
  final String? currentUserId;
  final bool isOwnProfile;
  final String username;

  const ProfileHighlightsRow({
    super.key,
    required this.highlights,
    required this.username,
    this.currentUserId,
    this.isOwnProfile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final addTileCount = isOwnProfile ? 1 : 0;
    // §05: кружок 56 + зазор 6 + подпись 10px — итого ~78.
    return SizedBox(
      height: 78,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: highlights.length + addTileCount,
        itemBuilder: (context, index) {
          if (isOwnProfile && index == 0) {
            return Padding(
              padding: EdgeInsets.only(right: highlights.isEmpty ? 0 : 16),
              child: ProfileAddHighlightTile(username: username),
            );
          }
          final h = highlights[index - addTileCount];
          final isLast = index == highlights.length + addTileCount - 1;
          return Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 16),
            child: GestureDetector(
              onLongPress: isOwnProfile
                  ? () => _showHighlightActions(context, ref, h)
                  : null,
              onTap: () {
                if (h.stories.isNotEmpty) {
                  final group = StoryGroup(
                    author: h.author, stories: h.stories, allSeen: false);
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => StoryViewerRoute(
                        groups: [group], initialGroupIndex: 0,
                        currentUserId: currentUserId),
                    ),
                  );
                }
              },
              // §05: кружок 56 — кольцо border 1.5 c.line + padding 3,
              // обложка круглая внутри кольца.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56, height: 56,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line, width: 1.5),
                    ),
                    child: ClipOval(
                      child: h.coverUrl.isNotEmpty
                          ? CachedNetworkImage(imageUrl: h.coverUrl, fit: BoxFit.cover)
                          : Container(
                              color: c.surface2,
                              child: Center(child: Icon(PhosphorIcons.image(), size: 20, color: c.ink3)),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 64,
                    child: Text(
                      h.title,
                      // §05: подпись 500 10, у обычных хайлайтов — c.ink.
                      style: SeeUTypography.caption.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showHighlightActions(BuildContext context, WidgetRef ref, Highlight h) {
    HapticFeedback.mediumImpact();
    showSeeUBottomSheet<void>(
      context: context,
      builder: (sheetCtx) {
        final c = sheetCtx.seeuColors;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PhosphorIcons.pencilSimple(), color: c.ink),
                title: const Text('Переименовать'),
                onTap: () { Navigator.of(sheetCtx).pop(); _renameHighlight(context, ref, h); },
              ),
              Divider(height: 1, color: c.line),
              ListTile(
                leading: Icon(PhosphorIcons.trash(), color: SeeUColors.danger),
                title: const Text('Удалить',
                    style: TextStyle(color: SeeUColors.danger)),
                onTap: () { Navigator.of(sheetCtx).pop(); _deleteHighlight(context, ref, h); },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameHighlight(BuildContext context, WidgetRef ref, Highlight h) async {
    final controller = TextEditingController(text: h.title);
    final newTitle = await showSeeUBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final c = sheetCtx.seeuColors;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('КОЛЛЕКЦИЯ',
                      style: SeeUTypography.kicker.copyWith(color: c.ink3)),
                  const SizedBox(height: 4),
                  Text('Переименовать',
                      style: SeeUTypography.displayS.copyWith(color: c.ink)),
                  const SizedBox(height: 16),
                  SeeUInput(
                    controller: controller,
                    autofocus: true,
                    maxLength: 50,
                    hintText: 'Новое название',
                    onSubmitted: (v) =>
                        Navigator.of(sheetCtx).pop(v.trim()),
                  ),
                  const SizedBox(height: 16),
                  SeeUButton(
                    label: 'Сохранить',
                    onTap: () =>
                        Navigator.of(sheetCtx).pop(controller.text.trim()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == h.title) return;
    if (!context.mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.highlightById(h.id), data: {'title': newTitle});
      ref.invalidate(userProfileProvider(username));
      if (!context.mounted) return;
      showSeeUSnackBar(context, 'Коллекция переименована',
          tone: SeeUTone.success);
    } on DioException catch (e) {
      if (!context.mounted) return;
      showSeeUSnackBar(context, 'Не удалось: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    }
  }

  Future<void> _deleteHighlight(BuildContext context, WidgetRef ref, Highlight h) async {
    final ok = await showSeeUConfirm(
      context,
      title: 'Удалить коллекцию?',
      message: 'Коллекция «${h.title}» будет удалена. Сами сторис останутся в архиве.',
      confirmLabel: 'Удалить',
      destructive: true,
      icon: PhosphorIcons.trash(),
    );
    if (!ok || !context.mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.highlightById(h.id));
      ref.invalidate(userProfileProvider(username));
      if (!context.mounted) return;
      showSeeUSnackBar(context, 'Коллекция удалена', tone: SeeUTone.success);
    } on DioException catch (e) {
      if (!context.mounted) return;
      showSeeUSnackBar(context, 'Не удалось: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    }
  }
}

class ProfileAddHighlightTile extends ConsumerWidget {
  final String username;
  const ProfileAddHighlightTile({super.key, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () async {
        final created = await showCreateHighlightSheet(context: context, username: username);
        if (created) ref.invalidate(userProfileProvider(username));
      },
      // §05: плитка «Новый» — dashed-круг 56 (пунктир ink4) с plus 20 ink3.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            painter: _DashedCirclePainter(color: c.ink4),
            child: SizedBox(
              width: 56, height: 56,
              child: Center(child: Icon(PhosphorIcons.plus(), color: c.ink3, size: 20)),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 64,
            child: Text('Новый',
                style: SeeUTypography.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: c.ink3,
                ),
                textAlign: TextAlign.center,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Пунктирная окружность для плитки «Новый» (§05: dashed-круг 56).
/// По образцу dashed-круга «Твоя» в story_circle.dart.
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1;
    const dashCount = 14;
    final step = 2 * math.pi / dashCount;
    final dashAngle = step * 0.55;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        i * step,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
