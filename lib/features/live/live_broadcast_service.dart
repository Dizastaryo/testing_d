import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/models/live_stream.dart';

/// Broadcaster side of a live stream, backed by **LiveKit (SFU)**.
///
/// The broadcaster publishes camera+mic to a LiveKit room (`room == stream id`)
/// exactly once; the server fans the media out to every viewer. There is no
/// per-viewer peer connection or manual SDP/ICE here anymore — LiveKit does the
/// signaling and relaying.
class LiveBroadcastService {
  LiveBroadcastService._();
  static final instance = LiveBroadcastService._();

  final ValueNotifier<bool> isLive = ValueNotifier(false);
  final ValueNotifier<String?> streamId = ValueNotifier(null);
  final ValueNotifier<int> viewerCount = ValueNotifier(0);
  final ValueNotifier<bool> micEnabled = ValueNotifier(true);

  /// The broadcaster's own camera track, for local preview in the overlay.
  final ValueNotifier<LocalVideoTrack?> localVideoTrack = ValueNotifier(null);

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _frontCamera = true;
  bool _tearingDown = false;

  /// camera_screen releases its CameraController before LiveKit grabs the
  /// camera (mobile hardware allows a single camera consumer at a time).
  Future<void> Function()? onReleaseCamera;

  /// Restores the Flutter preview if the broadcast fails to start after the
  /// camera was already released (otherwise the viewfinder stays black).
  Future<void> Function()? onRestoreCamera;

  // Android Camera2 frees the device asynchronously after dispose(); give the
  // OS a moment before LiveKit (or Flutter) re-acquires it.
  static const _cameraReleaseDelay = Duration(milliseconds: 400);

  // ── Start ───────────────────────────────────────────────────────────────

  Future<LiveStream> startBroadcast(
    ApiClient api,
    String title, {
    bool isFrontCamera = true,
  }) async {
    if (isLive.value) throw StateError('Уже идёт эфир');
    _frontCamera = isFrontCamera;

    debugPrint('[Live] Releasing Flutter camera before LiveKit…');
    await onReleaseCamera?.call();
    if (!kIsWeb) await Future<void>.delayed(_cameraReleaseDelay);

    // 1) Create the stream on the backend and get a LiveKit publisher token.
    final LiveStream stream;
    final String url;
    final String token;
    try {
      final resp = await api.post(ApiEndpoints.streams, data: {'title': title});
      final data = resp.data['data'] as Map<String, dynamic>;
      stream = LiveStream.fromJson(data['stream'] as Map<String, dynamic>);
      url = data['livekit_url'] as String? ?? '';
      token = data['token'] as String? ?? '';
    } catch (e) {
      debugPrint('[Live] POST /streams FAILED: $e');
      await _restoreCameraSafely();
      rethrow;
    }
    if (url.isEmpty || token.isEmpty) {
      await _restoreCameraSafely();
      throw StateError('Сервер не выдал доступ к эфиру (LiveKit не настроен)');
    }

    // 2) Connect to the LiveKit room and publish camera + mic.
    final room = Room();
    _room = room;
    _listener = room.createListener();
    _wireEvents();
    try {
      debugPrint('[Live] Connecting to LiveKit $url …');
      await room.connect(url, token);
      await room.localParticipant?.setCameraEnabled(
        true,
        cameraCaptureOptions: CameraCaptureOptions(
          cameraPosition:
              isFrontCamera ? CameraPosition.front : CameraPosition.back,
        ),
      );
      await room.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      debugPrint('[Live] LiveKit connect/publish FAILED: $e');
      await _disposeRoom();
      try {
        await api.delete(ApiEndpoints.streamById(stream.id));
      } catch (_) {}
      await _restoreCameraSafely();
      rethrow;
    }

    _captureLocalVideo();
    micEnabled.value = true;
    streamId.value = stream.id;
    viewerCount.value = stream.viewerCount;
    isLive.value = true;
    debugPrint('[Live] Broadcast live — stream=${stream.id}');
    return stream;
  }

  // ── LiveKit events ────────────────────────────────────────────────────────

  void _wireEvents() {
    _listener
      ?..on<LocalTrackPublishedEvent>((_) => _captureLocalVideo())
      ..on<ParticipantConnectedEvent>((_) => _updateViewerCount())
      ..on<ParticipantDisconnectedEvent>((_) => _updateViewerCount())
      ..on<RoomDisconnectedEvent>((_) {
        // Server/network dropped the broadcaster — tear down the live UI.
        if (isLive.value && !_tearingDown) {
          Future.microtask(_teardownLocal);
        }
      });
  }

  void _captureLocalVideo() {
    final pubs = _room?.localParticipant?.videoTrackPublications ?? const [];
    for (final p in pubs) {
      final t = p.track;
      if (t is LocalVideoTrack) {
        localVideoTrack.value = t;
        return;
      }
    }
  }

  void _updateViewerCount() {
    viewerCount.value = _room?.remoteParticipants.length ?? 0;
  }

  // ── In-broadcast controls ───────────────────────────────────────────────

  Future<void> toggleMic() async {
    final enabled = !micEnabled.value;
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
    micEnabled.value = enabled;
  }

  Future<void> switchCamera() async {
    final track = localVideoTrack.value;
    if (track == null) return;
    try {
      _frontCamera = !_frontCamera;
      await track.setCameraPosition(
        _frontCamera ? CameraPosition.front : CameraPosition.back,
      );
    } catch (e) {
      debugPrint('[Live] switchCamera error (ignored): $e');
    }
  }

  // ── End ──────────────────────────────────────────────────────────────────

  Future<void> endBroadcast(ApiClient api) async {
    final sid = streamId.value;
    debugPrint('[Live] Ending broadcast — stream=$sid');
    await _room?.disconnect();
    try {
      if (sid != null) await api.delete(ApiEndpoints.streamById(sid));
    } catch (e) {
      debugPrint('[Live] DELETE /streams/$sid error (ignored): $e');
    }
    await _teardownLocal();
  }

  Future<void> _teardownLocal() async {
    if (_tearingDown) return;
    _tearingDown = true;
    try {
      await _disposeRoom();
      localVideoTrack.value = null;
      micEnabled.value = true;
      viewerCount.value = 0;
      streamId.value = null;
      // Give the OS a moment before Flutter re-acquires the camera.
      if (!kIsWeb) await Future<void>.delayed(_cameraReleaseDelay);
      isLive.value = false; // → camera_screen restores the Flutter camera
      debugPrint('[Live] Broadcast ended ✓');
    } finally {
      _tearingDown = false;
    }
  }

  Future<void> _disposeRoom() async {
    try {
      await _listener?.dispose();
    } catch (_) {}
    _listener = null;
    try {
      await _room?.dispose();
    } catch (_) {}
    _room = null;
  }

  Future<void> _restoreCameraSafely() async {
    try {
      await onRestoreCamera?.call();
    } catch (e) {
      debugPrint('[Live] onRestoreCamera error (ignored): $e');
    }
  }
}
