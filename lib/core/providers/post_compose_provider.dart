import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_track.dart';

/// One-shot transit slot for "open post composer with this track preselected".
///
/// Used by Music screen ("Использовать в посте") → CameraScreen → MediaPrepare.
/// MediaPrepare reads this on initState, applies it, and clears so subsequent
/// posts don't accidentally pick up an old track.
final pendingPostTrackProvider = StateProvider<AudioTrack?>((ref) => null);
