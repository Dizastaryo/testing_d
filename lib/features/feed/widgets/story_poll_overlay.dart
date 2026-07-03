import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/models/story.dart';

class StoryPollOverlay extends ConsumerStatefulWidget {
  final String storyId;
  final StoryPoll poll;
  final bool readOnly;
  final void Function(StoryPoll updated) onVoted;

  const StoryPollOverlay({
    super.key,
    required this.storyId,
    required this.poll,
    required this.readOnly,
    required this.onVoted,
  });

  @override
  ConsumerState<StoryPollOverlay> createState() => _StoryPollOverlayState();
}

class _StoryPollOverlayState extends ConsumerState<StoryPollOverlay> {
  bool _voting = false;

  Future<void> _vote(int optionIndex) async {
    if (widget.readOnly || _voting) return;
    setState(() => _voting = true);
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.post(ApiEndpoints.storyPollVote(widget.storyId),
          data: {'option_index': optionIndex});
      final pollJson = r.data is Map && r.data['data'] is Map
          ? (r.data['data']['poll'] as Map<String, dynamic>?) : null;
      if (pollJson != null) widget.onVoted(StoryPoll.fromJson(pollJson));
    } catch (_) {
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось проголосовать',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.poll;
    final hasVoted = p.hasVoted || widget.readOnly;
    // Стеклянная overlay-карта поверх медиа: свой blur 18 + верхний блик →
    // нижний тинт + тонкий светлый бордюр. Вложенные чипы вариантов — плоские.
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.card),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          width: 240,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.black.withValues(alpha: 0.30),
              ],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.card),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p.question, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.subtitle.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _PollButton(label: p.optionA, percent: hasVoted ? p.percentA : null,
                    selected: p.myVote == 0, highlighted: !hasVoted, onTap: hasVoted ? null : () => _vote(0))),
                const SizedBox(width: 6),
                Expanded(child: _PollButton(label: p.optionB, percent: hasVoted ? p.percentB : null,
                    selected: p.myVote == 1, highlighted: false, onTap: hasVoted ? null : () => _vote(1))),
              ]),
              if (hasVoted && p.totalVotes > 0) ...[
                const SizedBox(height: 6),
                Text('${p.totalVotes} ${_pluralize(p.totalVotes)}'.toUpperCase(),
                    style: SeeUTypography.kicker.copyWith(color: Colors.white70)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _pluralize(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'голос';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return 'голоса';
    return 'голосов';
  }
}

class _PollButton extends StatelessWidget {
  final String label;
  final double? percent;
  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;
  const _PollButton({required this.label, required this.percent, required this.selected, required this.highlighted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // Вложенный-в-стекло чип: без своего blur — плоский полупрозрачный
      // white + тонкий бордюр; выбранный вариант — акцентный тинт/бордюр.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? SeeUColors.accent.withValues(alpha: 0.22)
              : (highlighted
                  ? SeeUColors.accent.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.10)),
          border: selected
              ? Border.all(color: SeeUColors.accent, width: 1.5)
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.22), width: 0.8),
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: SeeUTypography.caption.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          if (percent != null) ...[
            const SizedBox(height: 2),
            Text('${percent!.toInt()}%',
                style: SeeUTypography.mono.copyWith(color: Colors.white70)),
          ],
        ]),
      ),
    );
  }
}
