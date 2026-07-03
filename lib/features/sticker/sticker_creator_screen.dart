import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/providers/sticker_provider.dart';
import 'sticker_editor_screen.dart';
import 'sticker_touchup_screen.dart';

class StickerCreatorResult {
  final String url;
  const StickerCreatorResult(this.url);
}

class StickerCreatorScreen extends ConsumerStatefulWidget {
  const StickerCreatorScreen({super.key});

  @override
  ConsumerState<StickerCreatorScreen> createState() =>
      _StickerCreatorScreenState();
}

enum _Mode { none, photo, video }

class _StickerCreatorScreenState extends ConsumerState<StickerCreatorScreen>
    with SingleTickerProviderStateMixin {
  _Mode _mode = _Mode.none;
  int _gallerySegment = 0; // 0 = photo, 1 = video

  Uint8List? _sourceBytes;
  bool _removingBg = false;
  String? _error;
  String? _bgRemovedUrl;
  bool _showOriginal = false; // before/after toggle

  // Video
  VideoPlayerController? _controller;
  String? _videoPath;
  bool _isRemoving = false;
  double _videoSliderValue = 0;
  bool _videoReady = false;
  int _removeRequestId = 0;

  // Pulse animation for processing screen
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.18, end: 0.52).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _controller?.removeListener(_syncVideoSlider);
    _controller?.dispose();
    super.dispose();
  }

  // ── Picker actions ─────────────────────────────────────────────

  Future<void> _pickPhoto({ImageSource source = ImageSource.gallery}) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;

    final Uint8List bytes = await file.readAsBytes();
    await _disposeVideo();
    if (!mounted) return;

    setState(() {
      _mode = _Mode.photo;
      _sourceBytes = bytes;
      _bgRemovedUrl = null;
      _removingBg = false;
      _error = null;
      _showOriginal = false;
    });
  }

  Future<void> _pickVideoFromCamera() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.camera);
    if (file == null || !mounted) return;
    setState(() {
      _mode = _Mode.video;
      _sourceBytes = null;
      _bgRemovedUrl = null;
      _removingBg = false;
      _videoPath = file.path;
      _videoSliderValue = 0;
      _videoReady = false;
      _isRemoving = false;
      _error = null;
      _showOriginal = false;
    });
    await _initVideoPlayer(file.path);
  }

  Future<void> _pickVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    setState(() {
      _mode = _Mode.video;
      _sourceBytes = null;
      _bgRemovedUrl = null;
      _removingBg = false;
      _videoPath = file.path;
      _videoSliderValue = 0;
      _videoReady = false;
      _isRemoving = false;
      _error = null;
      _showOriginal = false;
    });

    await _initVideoPlayer(file.path);
  }

  Future<void> _disposeVideo() async {
    _controller?.removeListener(_syncVideoSlider);
    await _controller?.dispose();
    _controller = null;
    _videoPath = null;
    _videoReady = false;
    _isRemoving = false;
    _removeRequestId++;
  }

  Future<void> _initVideoPlayer(String path) async {
    _controller?.removeListener(_syncVideoSlider);
    await _controller?.dispose();

    final VideoPlayerController controller =
        VideoPlayerController.file(File(path));
    _controller = controller;
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(0);
    controller.addListener(_syncVideoSlider);
    await controller.play();

    if (!mounted || _controller != controller) return;
    setState(() => _videoReady = true);
  }

  void _syncVideoSlider() {
    final VideoPlayerController? c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final int durationMs = c.value.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final double next =
        (c.value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    if ((next - _videoSliderValue).abs() < 0.002) return;
    if (mounted) setState(() => _videoSliderValue = next);
  }

  void _onVideoSliderChanged(double value) {
    final VideoPlayerController? c = _controller;
    if (c == null || !c.value.isInitialized) return;

    _removeRequestId++;

    final Duration position = Duration(
      milliseconds: (c.value.duration.inMilliseconds * value).round(),
    );
    c.pause();
    c.seekTo(position);

    setState(() {
      _videoSliderValue = value;
      _bgRemovedUrl = null;
      _isRemoving = false;
      _error = null;
      _showOriginal = false;
    });
  }

  Future<void> _extractAndRemoveBgAt(Duration position) async {
    final String? path = _videoPath;
    if (path == null) return;

    final int requestId = ++_removeRequestId;
    setState(() {
      _isRemoving = true;
      _error = null;
      _showOriginal = false;
    });

    try {
      final Uint8List? frameBytes = await VideoThumbnail.thumbnailData(
        video: path,
        timeMs: position.inMilliseconds,
        imageFormat: ImageFormat.PNG,
        quality: 95,
      );
      if (frameBytes == null) throw Exception('Не удалось извлечь кадр');

      final String url =
          await ref.read(stickerListProvider.notifier).removeBg(frameBytes);
      if (!mounted || requestId != _removeRequestId) return;

      setState(() {
        _bgRemovedUrl = url;
        _isRemoving = false;
      });
    } catch (e) {
      if (mounted && requestId == _removeRequestId) {
        setState(() {
          _error = e.toString();
          _isRemoving = false;
        });
      }
    }
  }

  Future<void> _startBgRemoval() async {
    if (_sourceBytes == null) return;
    setState(() {
      _removingBg = true;
      _bgRemovedUrl = null;
      _error = null;
      _showOriginal = false;
    });
    try {
      final String url =
          await ref.read(stickerListProvider.notifier).removeBg(_sourceBytes!);
      if (!mounted) return;
      setState(() => _bgRemovedUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _removingBg = false);
    }
  }

  Future<void> _openTouchup() async {
    final String? url = _bgRemovedUrl;
    if (url == null) return;
    final absUrl = AppConfig.absUrl(url);
    final String? newUrl = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => StickerTouchupScreen(imageUrl: absUrl),
      ),
    );
    if (newUrl != null && mounted) {
      setState(() => _bgRemovedUrl = newUrl);
    }
  }

  Future<void> _proceedPhotoToEditor() async {
    final String? url = _bgRemovedUrl;
    if (url == null) return;

    final String? result = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => StickerEditorScreen(imageUrl: url),
      ),
    );

    if (result != null && mounted) {
      Navigator.of(context).pop(StickerCreatorResult(result));
    }
  }

  Future<void> _proceedVideoToEditor() async {
    final String? url = _bgRemovedUrl;
    if (url == null) return;

    final String? result = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => StickerEditorScreen(imageUrl: url),
      ),
    );

    if (result != null && mounted) {
      Navigator.of(context).pop(StickerCreatorResult(result));
    }
  }

  void _goBackFromResult() {
    final isVideoFrame =
        _mode == _Mode.video && _bgRemovedUrl == null && !_isRemoving;
    if (isVideoFrame) {
      _disposeVideo().then((_) {
        if (mounted) setState(() => _mode = _Mode.none);
      });
    } else {
      setState(() {
        _bgRemovedUrl = null;
        _showOriginal = false;
      });
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final SeeUThemeColors c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(c),
            Divider(height: 1, color: c.line),
            if (_error != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: c.accentSoft,
                child: Text(
                  _error!,
                  style: SeeUTypography.caption.copyWith(color: c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Expanded(child: _buildBody(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c) {
    final bool isResult =
        _mode == _Mode.photo && _bgRemovedUrl != null && !_removingBg;
    final bool isVideoResult =
        _mode == _Mode.video && _bgRemovedUrl != null && !_isRemoving;
    final bool canGoBack = isResult || isVideoResult;
    final bool isProcessing = _removingBg || _isRemoving;
    final bool isVideoFrame =
        _mode == _Mode.video && !isVideoResult && !_isRemoving;
    final bool isPhotoSelected = _mode == _Mode.photo &&
        _sourceBytes != null &&
        _bgRemovedUrl == null &&
        !_removingBg;

    String title = 'Новый стикер';
    if (isPhotoSelected) title = 'Фото выбрано';
    if (isVideoFrame) title = 'Выбор кадра';
    if (_removingBg || _isRemoving) title = 'Удаление фона…';
    if (isResult || isVideoResult) title = 'Фон удалён';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          if (!isProcessing)
            GestureDetector(
              onTap: canGoBack || isVideoFrame
                  ? _goBackFromResult
                  : isPhotoSelected
                      ? () => setState(() {
                            _mode = _Mode.none;
                            _sourceBytes = null;
                          })
                      : () => Navigator.of(context).pop(),
              child: Icon(
                canGoBack || isVideoFrame || isPhotoSelected
                    ? PhosphorIcons.caretLeft(PhosphorIconsStyle.bold)
                    : PhosphorIcons.x(),
                size: 20,
                color: c.ink,
              ),
            )
          else
            const SizedBox(width: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          // Before/after toggle — shown only when result is displayed
          if (isResult || isVideoResult)
            GestureDetector(
              onTap: () => setState(() => _showOriginal = !_showOriginal),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _showOriginal ? c.surface2 : c.accentSoft,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                  border: Border.all(
                    color: _showOriginal
                        ? c.line
                        : SeeUColors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _showOriginal ? 'До' : 'После',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _showOriginal ? c.ink2 : SeeUColors.accent,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      PhosphorIconsRegular.arrowsLeftRight,
                      size: 11,
                      color: _showOriginal ? c.ink3 : SeeUColors.accent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    if (_mode == _Mode.video) return _buildVideoFlow(c);
    if (_removingBg) return _buildBgProcessing(c);
    if (_mode == _Mode.photo && _bgRemovedUrl != null) return _buildBgRemoval(c);
    if (_mode == _Mode.photo && _sourceBytes != null) {
      return _buildPhotoPreviewMode(c);
    }
    return _buildSourcePicker(c);
  }

  // ── 0. Photo preview mode (photo selected, not yet processed) ──

  Widget _buildPhotoPreviewMode(SeeUThemeColors c) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_sourceBytes!, fit: BoxFit.contain),
                  // "Другое фото" overlay button
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => _pickPhoto(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIconsRegular.images,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 5),
                            const Text(
                              'Другое',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: GestureDetector(
            onTap: _startBgRemoval,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: SeeUGradients.heroOrange,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                boxShadow: [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.magicWand,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Убрать фон',
                      style: SeeUTypography.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 1. Source picker ───────────────────────────────────────────

  Widget _buildSourcePicker(SeeUThemeColors c) {
    return Column(
      children: [
        _buildHintBar(c),
        _buildSegmented(c),
        Expanded(child: _buildGalleryGrid(c)),
      ],
    );
  }

  Widget _buildHintBar(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.magicWand,
              color: SeeUColors.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Фон уберём автоматически — выберите фото или кадр видео',
              style:
                  SeeUTypography.caption.copyWith(color: c.ink2, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmented(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child: Row(
          children: [
            _SegTab(
              label: 'Фото',
              icon: PhosphorIconsRegular.imageSquare,
              active: _gallerySegment == 0,
              onTap: () => setState(() => _gallerySegment = 0),
              c: c,
            ),
            _SegTab(
              label: 'Видео',
              icon: PhosphorIconsRegular.videoCamera,
              active: _gallerySegment == 1,
              onTap: () => setState(() => _gallerySegment = 1),
              c: c,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryGrid(SeeUThemeColors c) {
    final bool isVideo = _gallerySegment == 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        children: [
          _PickerCard(
            icon: PhosphorIconsRegular.camera,
            title: isVideo ? 'Снять видео' : 'Сфотографировать',
            subtitle: 'Открыть камеру',
            accent: true,
            onTap: isVideo
                ? _pickVideoFromCamera
                : () => _pickPhoto(source: ImageSource.camera),
            c: c,
          ),
          const SizedBox(height: 12),
          _PickerCard(
            icon: isVideo
                ? PhosphorIconsRegular.filmStrip
                : PhosphorIconsRegular.images,
            title: isVideo ? 'Видео из галереи' : 'Фото из галереи',
            subtitle: 'Выбрать из медиатеки',
            onTap: isVideo ? _pickVideo : () => _pickPhoto(),
            c: c,
          ),
        ],
      ),
    );
  }

  // ── 2a. BG Processing screen ───────────────────────────────────

  Widget _buildBgProcessing(SeeUThemeColors c) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Pulsing original image
                  if (_sourceBytes != null)
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, child) =>
                          Opacity(opacity: _pulseAnim.value, child: child),
                      child: Image.memory(_sourceBytes!, fit: BoxFit.contain),
                    )
                  else
                    Container(color: c.surface2),
                  // Animated orange scan line
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) {
                      final t = _pulseCtrl.value;
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(0, -1 + t * 2),
                            end: Alignment(0, -1 + t * 2 + 0.35),
                            colors: [
                              Colors.transparent,
                              SeeUColors.accent.withValues(alpha: 0.22),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 40, top: 20),
          child: Column(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: SeeUColors.accent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Убираем фон…',
                style: SeeUTypography.body.copyWith(
                  color: SeeUColors.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Обычно занимает пару секунд',
                style: SeeUTypography.caption.copyWith(color: c.ink3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 2b. BG Removal result screen ───────────────────────────────

  Widget _buildBgRemoval(SeeUThemeColors c) {
    final url = _bgRemovedUrl!;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_showOriginal)
                    // Show original image
                    _sourceBytes != null
                        ? Image.memory(_sourceBytes!, fit: BoxFit.contain)
                        : Container(color: c.surface2)
                  else ...[
                    CustomPaint(painter: _CheckerPainter()),
                    CachedNetworkImage(
                      imageUrl: AppConfig.absUrl(url),
                      fit: BoxFit.contain,
                      placeholder: (_, __) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (_, __, ___) => Icon(
                        PhosphorIconsRegular.image,
                        size: 40,
                        color: c.ink3,
                      ),
                    ),
                  ],
                  // "Фон удалён" badge (only on result)
                  if (!_showOriginal)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: SeeUColors.success.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(PhosphorIconsBold.checkCircle,
                                color: SeeUColors.success, size: 14),
                            const SizedBox(width: 5),
                            const Text(
                              'Фон удалён',
                              style: TextStyle(
                                color: SeeUColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(
            children: [
              Expanded(
                child: _SecondaryBtn(
                  icon: PhosphorIconsRegular.arrowClockwise,
                  label: 'Повторить',
                  onTap: _mode == _Mode.photo ? _startBgRemoval : null,
                  c: c,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecondaryBtn(
                  icon: PhosphorIconsRegular.eraser,
                  label: 'Подправить',
                  onTap: _openTouchup,
                  c: c,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: GestureDetector(
            onTap: _proceedPhotoToEditor,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: SeeUGradients.heroOrange,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                boxShadow: [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.pencilSimple,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Добавить текст и эффекты',
                      style: SeeUTypography.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 3. Video flow ──────────────────────────────────────────────

  Widget _buildVideoFlow(SeeUThemeColors c) {
    if (!_videoReady ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isRemoving) return _buildBgProcessingVideo(c);
    if (_bgRemovedUrl != null) return _buildBgRemovalVideo(c);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: _buildVideoPreview(c),
          ),
        ),
        _buildVideoPanel(c),
      ],
    );
  }

  Widget _buildBgProcessingVideo(SeeUThemeColors c) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: _buildVideoPreview(c),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.line, width: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: SeeUColors.accent),
              ),
              const SizedBox(width: 10),
              Text(
                'Обрабатываем кадр…',
                style: SeeUTypography.body.copyWith(
                  color: SeeUColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBgRemovalVideo(SeeUThemeColors c) {
    final url = _bgRemovedUrl!;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _CheckerPainter()),
                  CachedNetworkImage(
                    imageUrl: AppConfig.absUrl(url),
                    fit: BoxFit.contain,
                    placeholder: (_, __) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) => Icon(
                      PhosphorIconsRegular.image,
                      size: 40,
                      color: c.ink3,
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: SeeUColors.success.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.checkCircle,
                              color: SeeUColors.success, size: 14),
                          SizedBox(width: 5),
                          Text(
                            'Фон удалён',
                            style: TextStyle(
                              color: SeeUColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: _SecondaryBtn(
            icon: PhosphorIconsRegular.eraser,
            label: 'Подправить',
            onTap: _openTouchup,
            c: c,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: GestureDetector(
            onTap: _proceedVideoToEditor,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: SeeUGradients.heroOrange,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                boxShadow: [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.pencilSimple,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Добавить текст и эффекты',
                      style: SeeUTypography.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPreview(SeeUThemeColors c) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.medium),
      ),
      clipBehavior: Clip.hardEdge,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPanel(SeeUThemeColors c) {
    final Duration duration = _controller!.value.duration;
    final Duration position = Duration(
      milliseconds:
          (duration.inMilliseconds * _videoSliderValue).round(),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SeeURadii.sheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Перетащите к нужному кадру',
                  style: SeeUTypography.body.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'кадр ${_formatDuration(position)}',
                  style: SeeUTypography.caption.copyWith(
                    color: c.ink3,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildVideoTimeline(c),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _bgRemovedUrl == null && !_isRemoving
                  ? () => _extractAndRemoveBgAt(position)
                  : null,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                  boxShadow: [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsRegular.scissors,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Взять этот кадр',
                        style: SeeUTypography.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoTimeline(SeeUThemeColors c) {
    final duration = _controller!.value.duration;
    final position = Duration(
      milliseconds: (duration.inMilliseconds * _videoSliderValue).round(),
    );
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: SeeUColors.accent,
            inactiveTrackColor: c.line,
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayColor: SeeUColors.accent.withValues(alpha: 0.12),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value: _videoSliderValue,
            onChanged: _onVideoSliderChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0:00', style: TextStyle(fontSize: 11, color: c.ink4)),
              Text(
                _formatDuration(position),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SeeUColors.accent,
                ),
              ),
              Text(_formatDuration(duration),
                  style: TextStyle(fontSize: 11, color: c.ink4)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Segmented tab ─────────────────────────────────────────────────

class _SegTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _SegTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: active ? c.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(SeeURadii.small - 2),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? c.ink : c.ink3),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: active ? c.ink : c.ink3,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Secondary button ──────────────────────────────────────────────

class _SecondaryBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final SeeUThemeColors c;

  const _SecondaryBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: onTap != null ? c.ink : c.ink4, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: SeeUTypography.body.copyWith(
                  color: onTap != null ? c.ink : c.ink4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Picker card ─────────────────────────────────────────────────

class _PickerCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final SeeUThemeColors c;
  final bool accent;

  const _PickerCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.c,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 84,
        decoration: BoxDecoration(
          color: accent ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accent
                ? SeeUColors.accent.withValues(alpha: 0.25)
                : c.line,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: accent
                    ? SeeUGradients.heroOrange
                    : null,
                color: accent ? null : c.surface2,
                borderRadius: BorderRadius.circular(13),
                boxShadow: accent
                    ? [
                        BoxShadow(
                          color: SeeUColors.accent.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                size: 22,
                color: accent ? Colors.white : c.ink,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: accent ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIcons.caretRight(),
              size: 16,
              color: accent ? SeeUColors.accent : c.ink4,
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Checkerboard background ──────────────────────────────────────

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cellSize = 16;
    final paint = Paint();
    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        final isLight = ((x ~/ cellSize) + (y ~/ cellSize)) % 2 == 0;
        paint.color = isLight ? Colors.white : const Color(0xFFECE5DA);
        canvas.drawRect(Rect.fromLTWH(x, y, cellSize, cellSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
