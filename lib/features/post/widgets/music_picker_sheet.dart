import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/utils/format.dart';

/// Re-export AudioTrack so callers can use it directly.
export '../../../core/providers/user_provider.dart' show AudioTrack;

class MusicPickerSheet extends ConsumerStatefulWidget {
  final ValueChanged<AudioTrack> onSelect;
  const MusicPickerSheet({super.key, required this.onSelect});

  @override
  ConsumerState<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends ConsumerState<MusicPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<AudioTrack>? _filtered;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final tracksAsync = ref.watch(audioTracksProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2))),
        ),
        Text('Выберите музыку', style: SeeUTypography.subtitle),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(SeeURadii.pill)),
            child: Row(children: [
              Icon(PhosphorIcons.magnifyingGlass(), size: 16, color: c.ink3),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _searchCtrl,
                style: SeeUTypography.body.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  border: InputBorder.none, hintText: 'Найти трек...',
                  hintStyle: SeeUTypography.body.copyWith(fontSize: 13, color: c.ink3),
                  contentPadding: EdgeInsets.zero, isDense: true),
                onChanged: (q) {
                  final tracks = tracksAsync.valueOrNull ?? [];
                  if (q.trim().isEmpty) { setState(() => _filtered = null); }
                  else {
                    final lq = q.toLowerCase();
                    setState(() { _filtered = tracks.where((t) =>
                        t.title.toLowerCase().contains(lq) || t.artist.toLowerCase().contains(lq)).toList(); });
                  }
                },
              )),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: tracksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: SeeUColors.accent)),
          error: (_, __) => Center(child: Text('Ошибка загрузки', style: SeeUTypography.body.copyWith(color: c.ink3))),
          data: (allTracks) {
            final tracks = _filtered ?? allTracks;
            if (tracks.isEmpty) return Center(child: Text('Ничего не найдено', style: SeeUTypography.body.copyWith(color: c.ink3)));
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tracks.length,
              itemBuilder: (_, i) => _buildTrackTile(tracks[i], c));
          },
        )),
      ]),
    );
  }

  Widget _buildTrackTile(AudioTrack track, SeeUThemeColors c) {
    return GestureDetector(
      onTap: () => widget.onSelect(track),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(SeeURadii.medium)),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 46, height: 46,
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(imageUrl: track.coverUrl, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: c.line, child: Icon(PhosphorIcons.musicNotes(), color: c.ink3, size: 20)),
                        errorWidget: (_, __, ___) => Container(color: c.line, child: Icon(PhosphorIcons.musicNotes(), color: c.ink3, size: 20)))
                    : Container(color: c.line, child: Icon(PhosphorIcons.musicNotes(), color: c.ink3, size: 20)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.title, style: SeeUTypography.subtitle.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${track.artist}  ·  ${formatDuration(Duration(seconds: track.durationSeconds))}',
                  style: SeeUTypography.caption.copyWith(color: c.ink3, fontSize: 12)),
            ])),
            Column(children: [
              Icon(PhosphorIcons.play(PhosphorIconsStyle.fill), size: 12, color: c.ink3),
              const SizedBox(height: 2),
              Text(formatCount(track.usesCount), style: SeeUTypography.micro.copyWith(color: c.ink3, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class MusicWaveformPainter extends CustomPainter {
  final Color color;
  final int barCount;
  MusicWaveformPainter({required this.color, this.barCount = 60});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeCap = StrokeCap.round;
    final barW = 2.0;
    final gap = (size.width - barCount * barW) / (barCount + 1);
    for (int i = 0; i < barCount; i++) {
      final seed = (i * 7 + 3) % 13;
      final h = size.height * (0.2 + 0.6 * (seed / 13.0));
      final x = gap + i * (barW + gap) + barW / 2;
      final top = (size.height - h) / 2;
      paint.strokeWidth = barW;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant MusicWaveformPainter old) =>
      old.color != color || old.barCount != barCount;
}
