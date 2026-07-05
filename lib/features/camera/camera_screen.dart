import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_session/audio_session.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import '../../core/design/tokens.dart';
import '../post/services/video_trim_service.dart';
import '../post/media_prepare_screen.dart';
import '../post/widgets/music_picker_sheet.dart';
import 'decorations/decoration_item.dart';
import 'decorations/decoration_picker.dart';
import 'presets/preset_picker_bar.dart';
import 'filters/filter_overlay.dart';
import 'filters/frame_effect.dart';
import 'filters/overlay_effect.dart';
import 'presets/camera_preset.dart';
import 'presets/camera_presets_catalog.dart';
import 'masks/ar_face_mask_view.dart';
import 'masks/mask_catalog.dart';
import 'widgets/camera_bottom_panel.dart';
import 'widgets/camera_painters.dart';
import 'widgets/camera_record_button.dart';
import 'widgets/camera_right_panel.dart';
import 'widgets/camera_top_bar.dart';
import 'widgets/camera_ui_kit.dart';
import 'widgets/music_start_sheet.dart';
import '../live/live_broadcast_service.dart';
import '../live/live_start_sheet.dart';

// ─── Re-export CameraMode ────────────────────────────────────────────────────
export 'widgets/camera_bottom_panel.dart' show CameraMode;

// ─── Constants ────────────────────────────────────────────────────────────

// Fallback recording cap (= kMaxVideoSeconds, 30 min). Used only if a mode
// reports no explicit maxSeconds.
const double _kMaxDuration = 1800.0;
const Color _kAccent = SeeUColors.accent;

// Vertical anchors for floating controls, measured from the bottom of the
// Positioned from the viewfinder bottom edge (= panel's top edge).
const double _kNextFabBottom = 12.0;
const double _kZoomIndicatorBottom = 8.0;
const double _kZoomPresetsBottom = 34.0;

// ─── CameraScreen ─────────────────────────────────────────────────────────

class CameraScreen extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onNext;
  final VoidCallback? onOpenMusic;
  /// true when opened from the story-creation flow (/story/create).
  /// Causes MediaPrepareScreen to default to История mode.
  final bool storyMode;

  const CameraScreen({
    super.key,
    this.onClose,
    this.onNext,
    this.onOpenMusic,
    this.storyMode = false,
  });

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── Camera state ──
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isFrontCamera = true;
  bool _isInitialized = false;
  bool _isSwitching = false;
  // Serializes _setupCamera — switch/lifecycle/restore/mic-retry can all enter
  // concurrently; without this two overlapping runs leak a CameraController.
  Future<void>? _setupInFlight;
  bool _micDenied = false; // mic permission denied → record without audio
  String? _errorMessage;

  // ── Zoom ──
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double _maxZoom = 1.0;
  double _minZoom = 1.0;
  bool _showZoomIndicator = false;
  String _zoomLabel = '1.0x';

  // ── Recording state ──
  bool _isRecording = false;
  List<double> _segments = [];
  // Recorded clip files, parallel to [_segments]. TikTok-style: each
  // record→pause is one clip; they're concatenated (ffmpeg) on finalize.
  List<String> _segmentFiles = [];
  // Whether each segment (parallel to [_segmentFiles]) was recorded with the
  // front camera — the native camera plugin never mirrors saved video bytes
  // (only the live preview is mirrored at the platform level), so front-camera
  // segments need an explicit ffmpeg hflip at finalize time.
  List<bool> _segmentIsFront = [];
  bool _isFinalizing = false;
  MaskDescriptor? _selectedMask;
  final ARFaceMaskController _maskController = ARFaceMaskController();

  // ── Music during recording (dance-to-music) ──
  AudioPlayer? _musicPlayer;
  bool _musicLoaded = false;

  // ── Active preset ──
  CameraPreset _activePreset = CameraPresetsCollection.none;
  bool _showPresetPicker = false;

  // ── Decorations (masks only) ──
  bool _showDecorationPicker = false;
  String? _selectedDecorationId;
  Set<String> _savedDecorationIds = {};
  double _currentSegDur = 0.0;

  // ── Timer ──
  int _timerSetting = 0;
  int _countdown = 0;
  Timer? _countdownTimer;

  // ── Settings ──
  int _flashMode = 0; // 0=off, 1=torch, 2=auto
  bool _showGrid = false;

  // ── Music ──
  AudioTrack? _selectedTrack;
  // Where in the track the music starts while recording (dance "from the drop")
  // — also pre-fills the publish trimmer.
  double _musicStartSec = 0;

  // ── Gallery preview ──
  Uint8List? _galleryThumbnailBytes;
  bool _handsFreeActive = false;
  bool _handsFreeCountdown = false;
  bool _isLiveActive = false;

  // ── Zoom auto-hide ──
  Timer? _zoomHideTimer;

  // ── Tap-to-focus ──
  Offset? _focusPoint;
  Timer? _focusHideTimer;

  // ── Animation controllers ──
  late AnimationController _switchController;
  late Animation<double> _switchRotation;
  late AnimationController _flashPulseController;
  late AnimationController _nextFabController;
  late AnimationController _segmentFlashCtrl;
  late AnimationController _blinkCtrl;

  // ── Ticker for segment progress ──
  Ticker? _ticker;
  Duration? _tickerStart;

  // Capture is now a single button: tap = photo, hold = video. Recording is
  // always capped at the video max; the 1-minute Story limit is enforced later.
  double get _effectiveMaxDuration => _kMaxDuration;

  // ─── Init ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _switchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _switchRotation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _switchController, curve: Curves.easeInOutCubic),
    );
    _flashPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _nextFabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _segmentFlashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0,
    );

    LiveBroadcastService.instance.isLive.addListener(_onLiveStateChanged);
    LiveBroadcastService.instance.onReleaseCamera = _releaseCamera;
    // Restore the Flutter preview if a broadcast fails to start after the
    // camera was already released (otherwise the viewfinder stays black).
    LiveBroadcastService.instance.onRestoreCamera = _restoreCamera;
    _initCamera();
  }

  void _onLiveStateChanged() {
    final live = LiveBroadcastService.instance.isLive.value;
    if (!mounted) return;
    setState(() => _isLiveActive = live);
    // Release Flutter camera when broadcasting starts so WebRTC can access
    // the hardware exclusively (iOS allows only one camera session at a time).
    // Restore it when the broadcast ends.
    if (live) {
      _releaseCamera();
    } else {
      _restoreCamera();
    }
  }

  // ─── Camera init ────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    if (kIsWeb) {
      if (mounted) setState(() => _errorMessage = 'Камера недоступна в браузере');
      return;
    }
    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      final msg = (e.code == 'CameraAccessDenied' ||
              e.code == 'CameraAccessDeniedWithoutPrompt' ||
              e.code == 'CameraAccessRestricted')
          ? 'Нет доступа к камере. Разрешите доступ в настройках.'
          : 'Не удалось получить список камер: ${e.description}';
      if (mounted) setState(() => _errorMessage = msg);
      return;
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Ошибка инициализации камеры');
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) setState(() => _errorMessage = 'Камера недоступна');
      return;
    }
    await _setupCamera(_getFrontCamera() ?? _cameras.first);
  }

  CameraDescription? _getFrontCamera() {
    try {
      return _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
    } catch (_) { return null; }
  }

  CameraDescription? _getBackCamera() {
    try {
      return _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    } catch (_) { return null; }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    // Chain after any in-flight setup so only one runs at a time.
    final previous = _setupInFlight;
    final completer = Completer<void>();
    _setupInFlight = completer.future;
    try {
      if (previous != null) { try { await previous; } catch (_) {} }
      await _setupCameraInternal(camera);
    } finally {
      completer.complete();
      if (identical(_setupInFlight, completer.future)) _setupInFlight = null;
    }
  }

  Future<void> _setupCameraInternal(CameraDescription camera) async {
    final prev = _controller;
    _controller = null;
    if (mounted) setState(() => _isInitialized = false);

    if (prev != null) {
      try { await prev.dispose(); } catch (e) {
        debugPrint('_setupCamera: error disposing previous controller: $e');
      }
    }

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: !_micDenied,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      final ps = controller.value.previewSize;
      debugPrint('_setupCamera: initialized ${camera.lensDirection.name} '
          'previewSize=$ps aspectRatio=${controller.value.aspectRatio}');

      _maxZoom = await controller.getMaxZoomLevel();
      _minZoom = await controller.getMinZoomLevel();
      _currentZoom = _minZoom;

      if (!mounted) { await controller.dispose(); return; }

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isSwitching = false;
        _errorMessage = null;
      });

      if (_flashMode > 0 && !_isFrontCamera) {
        final fm = const [FlashMode.off, FlashMode.torch, FlashMode.auto][_flashMode];
        try { await controller.setFlashMode(fm); } catch (_) {}
      }
    } on CameraException catch (e) {
      debugPrint('_setupCamera: CameraException: ${e.code} — ${e.description}');
      await controller.dispose();
      // Mic denied → retry once without audio so photos/video still work.
      if (!_micDenied &&
          (e.code == 'AudioAccessDenied' ||
              e.code == 'AudioAccessDeniedWithoutPrompt' ||
              e.code == 'AudioAccessRestricted')) {
        _micDenied = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нет доступа к микрофону — видео запишется без звука.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        // Stay inside the current serialized slot — calling the public wrapper
        // would deadlock awaiting our own in-flight future.
        await _setupCameraInternal(camera);
        return;
      }
      if (mounted) {
        setState(() { _errorMessage = 'Ошибка камеры: ${e.description}'; _isSwitching = false; });
      } else { _isSwitching = false; }
    } catch (e) {
      debugPrint('_setupCamera: unexpected error: $e');
      await controller.dispose();
      if (mounted) {
        setState(() { _errorMessage = 'Ошибка инициализации камеры'; _isSwitching = false; });
      } else { _isSwitching = false; }
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitching || _cameras.length < 2) return;
    // AR face tracking only works on the front TrueDepth camera — flipping is
    // disabled while a mask is active (the button is also hidden in that case).
    if (_selectedMask != null) return;
    HapticFeedback.lightImpact();
    setState(() => _isSwitching = true);
    _switchController.forward(from: 0);
    _isFrontCamera = !_isFrontCamera;

    final camera = _isFrontCamera
        ? (_getFrontCamera() ?? _cameras.first)
        : (_getBackCamera() ?? _cameras.last);
    await _setupCamera(camera);
  }

  // ─── Flash ──────────────────────────────────────────────────────────────

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.selectionClick();
    _flashPulseController.forward(from: 0);
    final next = (_flashMode + 1) % 3;
    final cameraFlash = const [FlashMode.off, FlashMode.torch, FlashMode.auto][next];
    try {
      await _controller!.setFlashMode(cameraFlash);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {}
  }

  // ─── Recording ──────────────────────────────────────────────────────────

  double get _totalCompleted => _segments.fold(0.0, (a, b) => a + b);
  double get _totalWithCurrent => _totalCompleted + _currentSegDur;
  double get _totalPct => (_totalWithCurrent / _effectiveMaxDuration).clamp(0.0, 1.0);

  // ── Single-button capture: tap = photo, hold = video ──────────────────────

  /// Tap the shutter → take a photo (after an optional self-timer countdown).
  /// When hands-free is active, tap starts a countdown then auto-records video.
  void _onShutterTap() {
    if (_isRecording || _countdown > 0) return;
    if (_handsFreeActive) {
      _handsFreeCountdown = true;
      _startCountdown(defaultSecs: 3);
    } else if (_timerSetting > 0) {
      _handsFreeCountdown = false;
      _startCountdown();
    } else {
      _takePicture();
    }
  }

  /// Press-and-hold the shutter → start recording a video segment.
  void _onRecordStart() {
    if (_isRecording || _countdown > 0 || _isFinalizing) return;
    // Video recording with a live 3D mask isn't supported yet (the Flutter
    // camera is released while ARKit owns it). Masks can be captured as photos.
    if (_selectedMask != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('С 3D-масками доступно только фото. Отпустите кнопку.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    _beginSegment();
  }

  /// Release the shutter → stop the current segment.
  void _onRecordStop() {
    if (!_isRecording) return;
    _pauseSegment();
  }

  void _startCountdown({int defaultSecs = 0}) {
    _countdownTimer?.cancel();
    final secs = _timerSetting > 0 ? _timerSetting : (defaultSecs > 0 ? defaultSecs : 3);
    setState(() => _countdown = secs);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      final next = _countdown - 1;
      if (next <= 0) {
        timer.cancel();
        setState(() => _countdown = 0);
        if (_handsFreeCountdown) {
          _handsFreeCountdown = false;
          _beginSegment();
        } else {
          _takePicture();
        }
      } else {
        setState(() => _countdown = next);
      }
    });
  }

  void _cancelCountdown() {
    if (_countdown <= 0) return;
    _countdownTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() { _countdown = 0; _handsFreeCountdown = false; });
  }

  // ── Music playback during recording ──────────────────────────────────────

  /// Configure the audio session so music can play through the speaker WHILE
  /// the mic records video (playAndRecord + mixWithOthers). Without this iOS
  /// would silence one of them.
  Future<void> _configureRecordingAudioSession() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.mixWithOthers,
      ));
      await session.setActive(true);
    } catch (e) {
      debugPrint('audio session configure: $e');
    }
  }

  Future<void> _ensureMusicLoaded() async {
    final track = _selectedTrack;
    if (track == null || track.playbackUrl.isEmpty) return;
    await _configureRecordingAudioSession();
    _musicPlayer ??= AudioPlayer();
    if (!_musicLoaded) {
      try {
        await _musicPlayer!.setUrl(track.playbackUrl);
        await _musicPlayer!
            .seek(Duration(milliseconds: (_musicStartSec * 1000).round()));
        _musicLoaded = true;
      } catch (e) {
        debugPrint('music load: $e');
      }
    }
  }

  Future<void> _resumeMusic() async {
    if (_selectedTrack == null) return;
    await _ensureMusicLoaded();
    try { await _musicPlayer?.play(); } catch (_) {}
  }

  Future<void> _pauseMusic() async {
    try { await _musicPlayer?.pause(); } catch (_) {}
  }

  Future<void> _resetMusic() async {
    try { await _musicPlayer?.stop(); } catch (_) {}
    _musicLoaded = false;
  }

  Future<void> _rewindMusic(double seconds) async {
    final p = _musicPlayer;
    if (p == null) return;
    final floor = Duration(milliseconds: (_musicStartSec * 1000).round());
    final back = p.position - Duration(milliseconds: (seconds * 1000).round());
    try { await p.seek(back < floor ? floor : back); } catch (_) {}
  }

  // ── Segment recording (record → pause → resume → finalize) ────────────────

  Future<void> _beginSegment() async {
    if (_isRecording || _isFinalizing) return;
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isRecordingVideo) return;
    HapticFeedback.mediumImpact();

    // Start the recorder FIRST, then begin the timer.
    try {
      await _controller!.startVideoRecording();
    } catch (e) {
      debugPrint('_beginSegment: startVideoRecording failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось начать запись. Попробуйте ещё раз.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    // Music keeps its position across segments → resume continues the song,
    // so the user stays in sync (TikTok-style).
    await _resumeMusic();

    setState(() { _isRecording = true; _currentSegDur = 0.0; });
    _nextFabController.reverse();

    _ticker?.dispose();
    _tickerStart = null;
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      _tickerStart ??= elapsed;
      final secs = (elapsed - _tickerStart!).inMilliseconds / 1000.0;
      final clamped = secs.clamp(0.0, _effectiveMaxDuration - _totalCompleted);
      setState(() => _currentSegDur = clamped);
      if (_totalCompleted + clamped >= _effectiveMaxDuration) _pauseSegment();
    })..start();
  }

  /// Stop the current clip and keep it as a segment (does NOT leave the
  /// camera). Music pauses in lockstep. Tap record again to add another clip.
  Future<void> _pauseSegment() async {
    if (!_isRecording) return;
    HapticFeedback.mediumImpact();
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;

    final dur = _currentSegDur;
    await _pauseMusic();

    XFile? clip;
    try {
      clip = await _controller?.stopVideoRecording();
    } catch (e) {
      debugPrint('_pauseSegment: stopVideoRecording failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      if (dur > 0.1 && clip != null) {
        _segments = [..._segments, dur];
        _segmentFiles = [..._segmentFiles, clip.path];
        _segmentIsFront = [..._segmentIsFront, _isFrontCamera];
      }
      _currentSegDur = 0.0;
    });

    if (_segments.isNotEmpty) {
      _nextFabController.forward();
      _segmentFlashCtrl.forward(from: 0);
    }
  }

  /// Concatenate all recorded segments into one clip and move to preview.
  Future<void> _finalizeSegments() async {
    if (_isFinalizing) return;
    if (_isRecording) await _pauseSegment();
    if (!mounted || _segmentFiles.isEmpty) return;

    setState(() => _isFinalizing = true);
    await _resetMusic();

    // Mirror any segment recorded with the front camera — the saved bytes are
    // never mirrored by the native camera plugin (only the live preview is),
    // so without this every front-camera segment comes out backwards.
    final processedFiles = <String>[];
    for (var i = 0; i < _segmentFiles.length; i++) {
      var path = _segmentFiles[i];
      final isFront = i < _segmentIsFront.length ? _segmentIsFront[i] : false;
      if (isFront) {
        final flipped = await VideoTrimService.hflip(path);
        if (flipped != null) path = flipped;
      }
      processedFiles.add(path);
    }

    String finalPath;
    if (processedFiles.length == 1) {
      finalPath = processedFiles.first;
    } else {
      final merged = await VideoTrimService.concat(processedFiles);
      finalPath = merged ?? processedFiles.last;
    }

    // Bake the active color preset into the recorded video — presets only
    // affect the live preview (FilterOverlay) otherwise and have zero effect
    // on the saved bytes.
    if (!_activePreset.isNone) {
      final graded = await VideoTrimService.applyColorGrade(
        inputPath: finalPath,
        brightness: _activePreset.filter.brightness,
        contrast: _activePreset.filter.contrast,
        saturation: _activePreset.filter.saturation,
        warmth: _activePreset.filter.warmth,
      );
      if (graded != null) finalPath = graded;
    }

    // Danced to a track → drop the ambient audio so only the chosen song plays.
    if (_selectedTrack != null) {
      final muted = await VideoTrimService.stripAudio(finalPath);
      if (muted != null) finalPath = muted;
    }

    if (!mounted) return;
    setState(() => _isFinalizing = false);
    await _setGallery(XFile(finalPath));
  }

  bool _isVideoPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'webm', 'avi', 'mkv'].contains(ext);
  }

  Future<void> _setGallery(XFile file) async {
    final isVid = _isVideoPath(file.path);
    // Only read bytes for photos — videos can be very large and preloadedBytes
    // is explicitly set to null for video in MediaPrepareScreen.
    Uint8List? bytes;
    if (!isVid) {
      try { bytes = await file.readAsBytes(); } catch (e) {
        debugPrint('camera readAsBytes: $e');
      }
    }
    if (!mounted) return;

    Uint8List? thumb;
    if (isVid) {
      if (!kIsWeb) {
        try {
          thumb = await vt.VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: vt.ImageFormat.JPEG,
            maxWidth: 112,
            quality: 75,
          );
        } catch (e) { debugPrint('video_thumbnail: $e'); }
      }
    } else {
      thumb = bytes;
    }

    if (!mounted) return;
    if (thumb != null) setState(() => _galleryThumbnailBytes = thumb);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPrepareScreen(
          file: file,
          isVideo: isVid,
          preselectedTrack: _selectedTrack,
          initialAudioStartSec: _musicStartSec,
          preloadedBytes: isVid ? null : bytes,
          initialPublishMode: widget.storyMode ? 0 : null,
          heroTag: (!isVid && thumb != null) ? 'media_prepare_preview' : null,
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        _segments = [];
        _segmentFiles = [];
        _segmentIsFront = [];
        _currentSegDur = 0.0;
        _galleryThumbnailBytes = null; // clear stale thumbnail
      });
      _nextFabController.reverse();
    });
  }

  Future<void> _undoLastSegment() async {
    if (_isRecording) await _pauseSegment();
    if (!mounted) return;
    if (_segments.isEmpty) return;
    HapticFeedback.selectionClick();
    final removedDur = _segments.last;
    setState(() {
      _segments = _segments.sublist(0, _segments.length - 1);
      if (_segmentFiles.isNotEmpty) {
        _segmentFiles = _segmentFiles.sublist(0, _segmentFiles.length - 1);
      }
      if (_segmentIsFront.isNotEmpty) {
        _segmentIsFront = _segmentIsFront.sublist(0, _segmentIsFront.length - 1);
      }
    });
    // Rewind the song so the next take stays in sync with the removed part.
    await _rewindMusic(removedDur);
    if (_segments.isEmpty) _nextFabController.reverse();
  }

  // ─── Photo capture ──────────────────────────────────────────────────────

  Future<void> _takePicture() async {
    // AR mask active — capture the native AR scene (camera + 3D mask),
    // since the Flutter camera controller is released while ARKit runs.
    if (_selectedMask != null) {
      await _captureMaskPhoto();
      return;
    }
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isTakingPicture) return;
    HapticFeedback.mediumImpact();
    try {
      final file = await _controller!.takePicture();
      final composed = await _composeCapture(file);
      if (mounted) await _setGallery(composed);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сделать фото. Попробуйте ещё раз.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Capture a still from the live AR mask scene (camera feed + 3D model
  /// composited natively) and route it into the gallery preview like any photo.
  Future<void> _captureMaskPhoto() async {
    HapticFeedback.mediumImpact();
    _blinkCtrl.forward(from: 0.78); // gentle dim, not a full flash (#10)
    final bytes = await _maskController.captureSnapshot();
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сделать фото с маской. Попробуйте ещё раз.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/mask_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(bytes);
      if (mounted) await _setGallery(XFile(path));
    } catch (e) {
      debugPrint('_captureMaskPhoto: save failed: $e');
    }
  }

  Future<XFile> _composeCapture(XFile raw) async {
    // Front camera always needs the mirror step baked in (the native plugin
    // mirrors only the live preview, never the saved bytes) — so a selfie
    // must go through compose even when no preset/mask is active.
    if (_activePreset.isNone && _selectedMask == null && !_isFrontCamera) {
      return raw;
    }
    if (kIsWeb) { return raw; }

    final filter = _activePreset.filter;
    final bytes = await raw.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final size = Size(w, h);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Mirror the source image for the front camera so the saved selfie
    // matches what the user saw in the (platform-mirrored) live preview.
    if (_isFrontCamera) {
      canvas.save();
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }

    if (filter.isIdentity) {
      canvas.drawImage(image, Offset.zero, Paint());
    } else {
      canvas.saveLayer(Rect.fromLTWH(0, 0, w, h),
          Paint()..colorFilter = ColorFilter.matrix(filter.toMatrix()));
      canvas.drawImage(image, Offset.zero, Paint());
      canvas.restore();
    }

    if (_isFrontCamera) canvas.restore();

    if (filter.vignette > 0) {
      final rect = Rect.fromLTWH(0, 0, w, h);
      canvas.drawRect(rect, Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: filter.vignette * 0.75),
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect));
    }

    if (_activePreset.hasGrain) bakeGrain(canvas, size, _activePreset.grainAmount);
    if (_activePreset.hasHalation) bakeHalation(canvas, size, _activePreset.halationAmount);

    _activePreset.overlay?.bake(canvas, size);
    _activePreset.frame?.bake(canvas, size);
    // 3D AR masks are captured separately via _captureMaskPhoto (native
    // ARSCNView.snapshot) — they can't be baked through this Canvas path.

    final picture = recorder.endRecording();
    final composedImg = await picture.toImage(w.toInt(), h.toInt());

    try {
      // Encode as JPEG (quality 90) instead of PNG — a full-res PNG of a camera
      // photo is several MB; JPEG is ~10× smaller with no visible loss.
      final rgba = await composedImg.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return raw;
      final jpg = img.encodeJpg(
        img.Image.fromBytes(
          width: w.toInt(),
          height: h.toInt(),
          bytes: rgba.buffer,
          numChannels: 4,
        ),
        quality: 90,
      );

      final outPath = '${raw.path.replaceAll(RegExp(r'\.[^.]+$'), '')}_composed.jpg';
      await File(outPath).writeAsBytes(jpg);
      return XFile(outPath);
    } finally {
      // Release native ui objects — otherwise filtered captures leak GPU/native
      // image memory → OOM after a few shots.
      image.dispose();
      composedImg.dispose();
      picture.dispose();
      codec.dispose();
    }
  }

  // ─── Gallery picker ─────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    // Multi-select for photos; single-select when mixed (video can't be multi)
    final files = await picker.pickMultipleMedia();
    if (files.isEmpty || !mounted) return;

    final hasVideo = files.any((f) => _isVideoPath(f.path));
    // Mixed selection or single → use existing single-file flow
    if (files.length == 1 || hasVideo) {
      await _setGallery(files.first);
      return;
    }

    // Multiple photos: read bytes for all, open multi-photo prepare screen
    final bytesList = await Future.wait(files.map((f) => f.readAsBytes()));
    if (!mounted) return;

    final primary = files.first;
    final extraFiles = files.sublist(1);
    final extraBytes = bytesList.sublist(1);
    final primaryBytes = bytesList.first;

    setState(() => _galleryThumbnailBytes = primaryBytes);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPrepareScreen(
          file: primary,
          isVideo: false,
          extraFiles: extraFiles,
          extraBytes: extraBytes,
          preselectedTrack: _selectedTrack,
          initialAudioStartSec: _musicStartSec,
          preloadedBytes: primaryBytes,
          initialPublishMode: widget.storyMode ? 0 : 1,
          heroTag: 'media_prepare_preview',
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        _segments = [];
        _segmentFiles = [];
        _segmentIsFront = [];
        _currentSegDur = 0.0;
        _galleryThumbnailBytes = null;
      });
      _nextFabController.reverse();
    });
  }

  // ─── Music picker ───────────────────────────────────────────────────────

  void _openMusicPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicPickerSheet(
        onSelect: (track) {
          setState(() {
            _selectedTrack = track;
            _musicStartSec = 0; // new track → start from the beginning
          });
          Navigator.of(context).pop();
          HapticFeedback.lightImpact();
          // Drop the previous track, then warm up the new one so the first
          // segment starts in sync.
          _resetMusic().then((_) => _ensureMusicLoaded());
        },
      ),
    );
  }

  /// Tapping the music chip when a track is already chosen: pick where the
  /// song starts during recording (dance "from the drop"), change, or remove.
  void _onMusicChipTap() {
    if (_selectedTrack == null) {
      _openMusicPicker();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicStartSheet(
        track: _selectedTrack!,
        initialStartSec: _musicStartSec,
        onConfirm: (startSec) {
          Navigator.of(context).pop();
          setState(() => _musicStartSec = startSec);
          HapticFeedback.lightImpact();
          // Re-seek the song to the new start on the next take.
          _resetMusic().then((_) => _ensureMusicLoaded());
        },
        onChangeTrack: () {
          Navigator.of(context).pop();
          _openMusicPicker();
        },
        onRemove: () {
          Navigator.of(context).pop();
          _resetMusic();
          setState(() {
            _selectedTrack = null;
            _musicStartSec = 0;
          });
        },
      ),
    );
  }

  // ─── Zoom ──────────────────────────────────────────────────────────────

  Future<void> _applyZoom(double zoom) async {
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    _currentZoom = clamped;
    try { await _controller?.setZoomLevel(clamped); } catch (_) {}
    if (!mounted) return;
    final label = '${clamped.toStringAsFixed(1)}x';
    setState(() { _zoomLabel = label; _showZoomIndicator = true; });
    _zoomHideTimer?.cancel();
    _zoomHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showZoomIndicator = false);
    });
  }

  void _onScaleStart(ScaleStartDetails d) => _baseZoom = _currentZoom;

  // Throttle zoom platform calls to ~20/sec to avoid flooding the channel.
  DateTime _lastZoomApply = DateTime.fromMillisecondsSinceEpoch(0);
  bool _zoomApplyInFlight = false;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_controller == null) return;
    final newZoom = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
    _currentZoom = newZoom;
    final now = DateTime.now();
    if (!_zoomApplyInFlight &&
        now.difference(_lastZoomApply).inMilliseconds >= 50) {
      _lastZoomApply = now;
      _zoomApplyInFlight = true;
      _controller!
          .setZoomLevel(newZoom)
          .whenComplete(() => _zoomApplyInFlight = false);
    }
    final label = '${newZoom.toStringAsFixed(1)}x';
    final shouldShow = newZoom > _minZoom;
    if (_showZoomIndicator != shouldShow || _zoomLabel != label) {
      setState(() { _showZoomIndicator = shouldShow; _zoomLabel = label; });
    }
    _zoomHideTimer?.cancel();
    if (shouldShow) {
      _zoomHideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showZoomIndicator = false);
      });
    }
  }

  // ─── Tap to focus / exposure ──────────────────────────────────────────────

  Future<void> _onTapToFocus(TapUpDetails details, Size viewSize) async {
    final ctrl = _controller;
    if (ctrl == null || !_isInitialized || _selectedMask != null) return;
    if (viewSize.width <= 0 || viewSize.height <= 0) return;

    final local = details.localPosition;
    final nx = (local.dx / viewSize.width).clamp(0.0, 1.0);
    final ny = (local.dy / viewSize.height).clamp(0.0, 1.0);

    setState(() => _focusPoint = local);
    _focusHideTimer?.cancel();
    _focusHideTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    HapticFeedback.selectionClick();

    final point = Offset(nx, ny);
    try {
      if (ctrl.value.focusPointSupported) {
        await ctrl.setFocusPoint(point);
        await ctrl.setFocusMode(FocusMode.auto);
      }
      if (ctrl.value.exposurePointSupported) {
        await ctrl.setExposurePoint(point);
      }
    } catch (e) {
      debugPrint('_onTapToFocus: $e');
    }
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When AR mask is active, native AR handles its own lifecycle —
    // don't touch the Flutter camera.
    if (_selectedMask != null) return;

    if (state == AppLifecycleState.inactive) {
      if (_isRecording) _pauseSegment();
      final ctrl = _controller;
      _controller = null;
      if (mounted) setState(() => _isInitialized = false);
      ctrl?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _reinitActiveCamera();
    }
  }

  Future<void> _reinitActiveCamera() async {
    if (kIsWeb) return;
    // Don't reinit Flutter camera while AR mask is active
    if (_selectedMask != null) return;
    if (_cameras.isEmpty) { await _initCamera(); return; }
    final camera = _isFrontCamera
        ? (_getFrontCamera() ?? _cameras.first)
        : (_getBackCamera() ?? _cameras.last);
    await _setupCamera(camera);
  }

  @override
  void dispose() {
    LiveBroadcastService.instance.isLive.removeListener(_onLiveStateChanged);
    LiveBroadcastService.instance.onReleaseCamera = null;
    LiveBroadcastService.instance.onRestoreCamera = null;
    WidgetsBinding.instance.removeObserver(this);
    _zoomHideTimer?.cancel();
    _countdownTimer?.cancel();
    _focusHideTimer?.cancel();
    _musicPlayer?.dispose();
    _ticker?.dispose();
    _controller?.dispose();
    _switchController.dispose();
    _flashPulseController.dispose();
    _nextFabController.dispose();
    _segmentFlashCtrl.dispose();
    _blinkCtrl.dispose();
    super.dispose();
  }

  /// Release the Flutter camera so ARKit/ARCore can access it exclusively.
  Future<void> _releaseCamera() async {
    final prev = _controller;
    _controller = null;
    if (mounted) setState(() => _isInitialized = false);
    if (prev != null) {
      try { await prev.dispose(); } catch (_) {}
    }
  }

  /// Re-initialize the Flutter camera after AR mask is cleared.
  Future<void> _restoreCamera() async {
    if (_cameras.isEmpty) return;
    final camera = _isFrontCamera
        ? (_getFrontCamera() ?? _cameras.first)
        : (_getBackCamera() ?? _cameras.last);
    await _setupCamera(camera);
  }

  void _applyDecoration(DecorationItem? item) {
    final wasMask = _selectedMask != null;
    final willBeMask = item?.mask != null;

    setState(() {
      _selectedDecorationId = item?.id;
      _selectedMask = item?.mask;
    });
    _blinkCtrl.forward(from: 0.78); // gentle dim, not a full flash (#10)

    // Release Flutter camera when AR mask activates (ARKit/ARCore need exclusive access).
    if (!wasMask && willBeMask) {
      _releaseCamera();
    }
    // Restore Flutter camera when AR mask is cleared.
    if (wasMask && !willBeMask) {
      _restoreCamera();
    }
  }

  void _applyPreset(CameraPreset preset) {
    setState(() => _activePreset = preset);
    _blinkCtrl.forward(from: 0.78); // gentle dim, not a full flash (#10)
  }

  void _togglePresetPicker() {
    HapticFeedback.selectionClick();
    setState(() {
      _showPresetPicker = !_showPresetPicker;
      // Presets and mask picker must never be open simultaneously.
      if (_showPresetPicker) _showDecorationPicker = false;
    });
  }


  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── Top chrome — close · music · flip ──────────────────────────
          CameraTopBar(
            selectedTrack: _selectedTrack,
            switchRotationAnim: _switchRotation,
            canSwitchCamera: _cameras.length >= 2 && !_isSwitching,
            showSwitchCamera: _selectedMask == null,
            onMusicTap: _onMusicChipTap,
            onSwitchCamera: _switchCamera,
            onClearTrack: () {
              _resetMusic();
              setState(() {
                _selectedTrack = null;
                _musicStartSec = 0;
              });
            },
          ),

          // ── Viewfinder — everything here is inside the capture frame ──
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewfinderSize = constraints.biggest;
                return ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera preview or AR view or loading
                      if (_errorMessage != null)
                        _buildErrorState(_errorMessage!)
                      else if (_selectedMask != null)
                        Positioned.fill(
                          child: ARFaceMaskView(
                            key: const ValueKey('ar_mask_view'),
                            mask: _selectedMask!,
                            controller: _maskController,
                            useFrontCamera: _isFrontCamera,
                            onError: (msg) => debugPrint('[ARFaceMask] $msg'),
                          ),
                        )
                      else if (_isInitialized && _controller != null)
                        GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onTapUp: (d) => _onTapToFocus(d, viewfinderSize),
                          child: FadeTransition(
                            opacity: _blinkCtrl,
                            child: FilterOverlay(
                              state: _activePreset.filter,
                              child: _buildCameraPreview(),
                            ),
                          ),
                        )
                      else
                        const Center(
                          child: BrandedLoader(label: 'Открываем камеру…'),
                        ),

                      // Effects (clipped to viewfinder area)
                      if (_activePreset.overlay != null)
                        Positioned.fill(
                          child: IgnorePointer(
                              child: EffectOverlay(effect: _activePreset.overlay!)),
                        ),
                      if (_activePreset.frame != null)
                        Positioned.fill(
                          child: IgnorePointer(
                              child: FrameOverlay(effect: _activePreset.frame!)),
                        ),
                      if (_showGrid)
                        Positioned.fill(
                          child: IgnorePointer(
                              child: CustomPaint(painter: CameraGridPainter())),
                        ),

                      // Tap-to-focus reticle
                      if (_focusPoint != null && _selectedMask == null)
                        Positioned(
                          left: _focusPoint!.dx - 36,
                          top: _focusPoint!.dy - 36,
                          child: const IgnorePointer(child: _FocusReticle()),
                        ),

                      // Gradient scrim (right-edge legibility)
                      _buildGradientOverlay(),

                      // Right tool rail — centered vertically in viewfinder
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: CameraRightPanel(
                          isFrontCamera: _isFrontCamera,
                          flashMode: _flashMode,
                          timerSetting: _timerSetting,
                          showGrid: _showGrid,
                          maskPickerActive: _showDecorationPicker,
                          handsFreeActive: _handsFreeActive,
                          isLive: _isLiveActive,
                          flashPulseAnim: _flashPulseController,
                          onToggleFlash: _toggleFlash,
                          onToggleTimer: () {
                            HapticFeedback.selectionClick();
                            _cancelCountdown();
                            setState(() {
                              _timerSetting = _timerSetting == 0
                                  ? 3
                                  : _timerSetting == 3
                                      ? 10
                                      : 0;
                            });
                          },
                          onToggleGrid: () {
                            HapticFeedback.selectionClick();
                            setState(() => _showGrid = !_showGrid);
                          },
                          onToggleMaskPicker: () => setState(() {
                            _showDecorationPicker = !_showDecorationPicker;
                            if (_showDecorationPicker) _showPresetPicker = false;
                          }),
                          onToggleHandsFree: () {
                            HapticFeedback.selectionClick();
                            setState(() => _handsFreeActive = !_handsFreeActive);
                          },
                          onToggleLive: () {
                            if (LiveBroadcastService.instance.isLive.value) return;
                            HapticFeedback.mediumImpact();
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => LiveStartSheet(
                                isFrontCamera: _isFrontCamera,
                              ),
                            ).then((_) {
                              if (mounted) {
                                setState(() {
                                  _isLiveActive =
                                      LiveBroadcastService.instance.isLive.value;
                                });
                              }
                            });
                          },
                        ),
                        ),
                      ),

                      // Next FAB (appears when segments recorded)
                      _buildNextFAB(),

                      // Zoom pill + preset buttons
                      _buildZoomIndicator(),
                      _buildZoomPresets(),

                      // Effects / mask picker — floats over the viewfinder,
                      // right above the bottom panel. No background of its
                      // own (только кружки), and it never resizes the frame
                      // or the panel below it since it lives in this Stack,
                      // not inside CameraBottomPanel's Column.
                      if (_showPresetPicker || _showDecorationPicker)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 8,
                          child: AnimatedSwitcher(
                            duration: SeeUMotion.normal,
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.15),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                    parent: anim, curve: Curves.easeOut)),
                                child: child,
                              ),
                            ),
                            child: _showPresetPicker
                                ? PresetPickerBar(
                                    key: const ValueKey('presets'),
                                    activePreset: _activePreset,
                                    onPresetSelected: _applyPreset,
                                  )
                                : DecorationPicker(
                                    key: const ValueKey('masks'),
                                    allItems: DecorationCatalog.all
                                        .where((i) =>
                                            i.category ==
                                            DecorationCategory.mask)
                                        .toList(),
                                    savedIds: _savedDecorationIds,
                                    selectedId: _selectedDecorationId,
                                    onChanged: _applyDecoration,
                                    onToggleSave: (id) => setState(() {
                                      if (_savedDecorationIds.contains(id)) {
                                        _savedDecorationIds =
                                            _savedDecorationIds
                                                .difference({id});
                                      } else {
                                        _savedDecorationIds = {
                                          ..._savedDecorationIds,
                                          id
                                        };
                                      }
                                    }),
                                  ),
                          ),
                        ),

                      // Camera switch fade overlay
                      if (_isSwitching)
                        AnimatedBuilder(
                          animation: _switchController,
                          builder: (_, __) => Container(
                            color: Colors.black.withValues(
                                alpha: 0.3 * (1 - _switchController.value)),
                          ),
                        ),

                      // Countdown
                      if (_countdown > 0) _buildCountdownOverlay(),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Bottom chrome — hint + record row ─────────────────────────
          CameraBottomPanel(
            isRecording: _isRecording,
            totalPct: _totalPct,
            totalWithCurrent: _totalWithCurrent,
            galleryThumbnailBytes: _galleryThumbnailBytes,
            hasSegments: _segments.isNotEmpty,
            showPresetPicker: _showPresetPicker,
            activePreset: _activePreset,
            onPickGallery: _pickFromGallery,
            onTakePicture: _onShutterTap,
            onRecordStart: _onRecordStart,
            onRecordStop: _onRecordStop,
            onTogglePresets: _togglePresetPicker,
            onUndo: _undoLastSegment,
          ),
        ],
      ),
    );
  }

  // ─── Error state ────────────────────────────────────────────────────────

  Widget _buildErrorState(String message) {
    return StatusView(
      icon: PhosphorIconsRegular.camera,
      message: message,
      actionLabel: 'Повторить',
      onAction: () {
        setState(() { _errorMessage = null; _isInitialized = false; });
        _initCamera();
      },
    );
  }

  // ─── Camera preview ─────────────────────────────────────────────────────

  Widget _buildCameraPreview() {
    final controller = _controller!;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  // ─── Gradient ───────────────────────────────────────────────────────────

  // Glass panels (top bar + bottom panel) handle their own blur backgrounds.
  // This overlay is a very subtle left/right edge vignette only — keeps
  // the right-side rail readable against any background colour without
  // adding the heavy black bands the old design had.
  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0.0, 0.04, 0.75, 1.0],
              colors: [
                Color(0x00000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0x22000000), // subtle right-edge scrim for rail legibility
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Next FAB ───────────────────────────────────────────────────────────

  Widget _buildNextFAB() {
    return Positioned(
      right: 20,
      bottom: _kNextFabBottom,
      child: AnimatedBuilder(
        animation: _nextFabController,
        builder: (_, __) {
          final t = Curves.easeOutBack.transform(_nextFabController.value);
          return Opacity(
            opacity: _nextFabController.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - t)),
              child: Transform.scale(
                scale: 0.7 + 0.3 * t,
                child: GestureDetector(
                  onTap: _isFinalizing ? null : _finalizeSegments,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                      ),
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                      boxShadow: [
                        BoxShadow(
                          color: _kAccent.withValues(alpha: 0.50),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: _isFinalizing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Далее',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(PhosphorIconsRegular.arrowRight,
                                  color: Colors.white, size: 18),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Zoom indicator ─────────────────────────────────────────────────────

  Widget _buildZoomIndicator() {
    final range = _maxZoom - _minZoom;
    final fraction =
        range > 0 ? ((_currentZoom - _minZoom) / range).clamp(0.0, 1.0) : 0.0;
    const trackW = 120.0;
    const trackH = 3.0;
    const thumbD = 14.0;
    final thumbX = fraction * trackW - thumbD / 2;

    return Positioned(
      bottom: _kZoomIndicatorBottom,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _showZoomIndicator ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: trackW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(thumbX - (trackW / 2 - thumbD / 2), 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _zoomLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: trackW,
                  height: thumbD,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: (thumbD - trackH) / 2, left: 0, right: 0,
                        child: Container(
                          height: trackH,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                      ),
                      Positioned(
                        top: (thumbD - trackH) / 2,
                        left: 0,
                        width: fraction * trackW,
                        child: Container(
                          height: trackH,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                      ),
                      // Tick marks at integer zoom levels (1x, 2x, …) for
                      // orientation along the track.
                      for (int z = _minZoom.ceil();
                          z <= _maxZoom.floor() && range > 0;
                          z++)
                        Positioned(
                          top: (thumbD - 6) / 2,
                          left: ((z - _minZoom) / range).clamp(0.0, 1.0) *
                                  trackW -
                              0.75,
                          child: Container(
                            width: 1.5,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 0,
                        left: thumbX,
                        child: Container(
                          width: thumbD,
                          height: thumbD,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Zoom presets ───────────────────────────────────────────────────────

  Widget _buildZoomPresets() {
    if (_isFrontCamera || !_isInitialized) return const SizedBox.shrink();

    final presets = <double>[
      if (_minZoom <= 0.6) 0.5,
      if (_minZoom <= 1.05) 1.0,
      if (_maxZoom >= 2.0) 2.0,
      if (_maxZoom >= 5.0) 5.0,
    ];
    if (presets.length < 2) return const SizedBox.shrink();

    return Positioned(
      bottom: _kZoomPresetsBottom,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _isRecording ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < presets.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _ZoomPresetButton(
                  value: presets[i],
                  isActive: (_currentZoom - presets[i]).abs() < 0.15,
                  onTap: () => _applyZoom(presets[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Countdown overlay ──────────────────────────────────────────────────

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _cancelCountdown,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.35),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CameraCountdownNumber(value: _countdown),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: const Text(
                  'Нажмите, чтобы отменить',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ── Zoom preset button (0.5× / 1× / 2× / 5×) ─────────────────────────────────

class _ZoomPresetButton extends StatelessWidget {
  final double value;
  final bool isActive;
  final VoidCallback onTap;

  const _ZoomPresetButton({
    required this.value,
    required this.isActive,
    required this.onTap,
  });

  String get _label {
    final isWhole = value == value.roundToDouble();
    return isWhole ? '${value.toInt()}×' : '$value×';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1)
              : Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
        ),
        child: Text(
          _label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

// ─── Tap-to-focus reticle ────────────────────────────────────────────────────

class _FocusReticle extends StatefulWidget {
  const _FocusReticle();

  @override
  State<_FocusReticle> createState() => _FocusReticleState();
}

class _FocusReticleState extends State<_FocusReticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // #4: iOS-style reticle — thin double stroke, brief amber tint that settles
    // to white, springy scale settle.
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = Curves.easeOut.transform(_ac.value);
        final settle = SeeUMotion.overshoot.transform(_ac.value);
        final scale = 1.5 - 0.5 * settle; // 1.5 → 1.0 with slight overshoot
        // Amber on tap → settles to near-white as it locks.
        final color = Color.lerp(SeeUColors.amber, Colors.white, t)!;
        return Opacity(
          opacity: (0.3 + 0.7 * t).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: color.withValues(alpha: 0.55), width: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

