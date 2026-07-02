import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';
import '../../post/widgets/waveform_range_trimmer.dart';

/// Bottom sheet for choosing WHERE in a track the music starts while recording
/// (so creators can dance "from the drop"). Reuses [WaveformRangeTrimmer] with
/// a short locked window to position the start, previews it live, and offers
/// changing or removing the track.
class MusicStartSheet extends StatefulWidget {
  final AudioTrack track;
  final double initialStartSec;
  final ValueChanged<double> onConfirm;
  final VoidCallback onChangeTrack;
  final VoidCallback onRemove;

  const MusicStartSheet({
    super.key,
    required this.track,
    required this.initialStartSec,
    required this.onConfirm,
    required this.onChangeTrack,
    required this.onRemove,
  });

  @override
  State<MusicStartSheet> createState() => _MusicStartSheetState();
}

class _MusicStartSheetState extends State<MusicStartSheet> {
  late double _startSec;

  @override
  void initState() {
    super.initState();
    _startSec = widget.initialStartSec;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    // A short window just to position the start; recording plays from here on.
    final window =
        widget.track.durationSeconds >= 15 ? 15.0 : widget.track.durationSeconds.toDouble();

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 12, 18, MediaQuery.of(context).viewInsets.bottom + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grabber
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Track header
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: widget.track.coverUrl.isNotEmpty
                    ? Image.network(widget.track.coverUrl,
                        width: 46, height: 46, fit: BoxFit.cover)
                    : Container(
                        width: 46,
                        height: 46,
                        color: c.surface2,
                        child: Icon(PhosphorIconsFill.musicNote,
                            color: c.ink3, size: 18),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SeeUTypography.body
                            .copyWith(fontWeight: FontWeight.w700)),
                    Text(widget.track.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SeeUTypography.caption.copyWith(color: c.ink3)),
                  ],
                ),
              ),
              // #62: explicit "Убрать" instead of an ambiguous trash icon.
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onRemove();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  child: Text('Убрать',
                      style: SeeUTypography.caption
                          .copyWith(color: c.ink2, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // #61/#63: clear section title + window length.
          Row(
            children: [
              Text('С какого момента играет музыка',
                  style: SeeUTypography.subtitle
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                ),
                child: Text('${window.round()} сек',
                    style: SeeUTypography.micro.copyWith(
                        color: SeeUColors.accent, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          WaveformRangeTrimmer(
            track: widget.track,
            lockedWindowSeconds: window,
            initialStartSec: _startSec,
            onChanged: (sel) => _startSec = sel.startSec,
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              // #64: secondary action takes less width than the primary.
              Expanded(
                flex: 4,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onChangeTrack();
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                      border: Border.all(color: c.line),
                    ),
                    child: Text('Сменить',
                        style: SeeUTypography.body
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onConfirm(_startSec);
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                      ),
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                    ),
                    child: const Text('Готово',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
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
