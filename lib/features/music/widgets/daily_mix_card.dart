import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/audio/audio_player_service.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';

/// MUSIC-4: hero-карточка «Твой день» — daily mix. Тап = play первого
/// трека (последующие очередью идут через _service). Если backend ничего
/// не отдал — карточка скрыта.
class DailyMixCard extends ConsumerStatefulWidget {
  const DailyMixCard({super.key});

  @override
  ConsumerState<DailyMixCard> createState() => _DailyMixCardState();
}

class _DailyMixCardState extends ConsumerState<DailyMixCard> {
  List<AudioTrack> _tracks = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.dailyMixTracks,
          queryParameters: {'limit': '20'});
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data
              .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
              .toList()
          : <AudioTrack>[];
      if (mounted) {
        setState(() {
          _tracks = list;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _tracks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: GestureDetector(
        onTap: () {
          ref.read(miniPlayerProvider.notifier).playWithQueue(
            track: _tracks.first,
            queue: _tracks,
            index: 0,
            source: 'daily_mix',
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: SeeUGradients.heroOrange,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: SeeUColors.accent.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(PhosphorIconsRegular.sun,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Твой день',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_tracks.length} треков по твоим интересам',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(PhosphorIconsRegular.play,
                  color: Colors.white, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}
