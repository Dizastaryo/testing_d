import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_track.dart';

/// One-shot transit slot for "open reel composer with this track preselected".
///
/// Used by Music screen ("Использовать в рилсе") → CameraScreen → MediaPrepare.
/// MediaPrepare reads this on initState, applies it, and clears so subsequent
/// reels don't accidentally pick up an old track.
final pendingReelTrackProvider = StateProvider<AudioTrack?>((ref) => null);
