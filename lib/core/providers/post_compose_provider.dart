import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_track.dart';

/// One-shot transit slot for "open post composer with this track preselected".
///
/// Used by Music screen ("Использовать в посте") → CameraScreen → MediaPrepare.
/// MediaPrepare reads this on initState, applies it, and clears so subsequent
/// posts don't accidentally pick up an old track.
///
/// Renamed 2026-05-09 from `pendingReelTrackProvider` after the reels→posts
/// unification (migration 23) made "reel" terminology a misnomer — every
/// publication is a post now, audio overlay still works on video posts.
final pendingPostTrackProvider = StateProvider<AudioTrack?>((ref) => null);
