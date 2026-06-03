import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/providers/sticker_provider.dart';

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

class _StickerCreatorScreenState extends ConsumerState<StickerCreatorScreen> {
  _Mode _mode = _Mode.none;

  Uint8List? _sourceBytes;
  String? _processedUrl;
  bool _removingBg = false;
  bool _saving = false;
  String? _error;

  VideoPlayerController? _controller;
  String? _videoPath;
  Timer? _debounceTimer;
  bool _isRemoving = false;
  String? _bgRemovedUrl;
  bool _inTextEditor = false;
  double _videoSliderValue = 0;
  bool _videoReady = false;
  int _removeRequestId = 0;

  final _textCtrl = TextEditingController();
  Color _textColor = Colors.white;
  double _fontSize = 32;
  bool _bold = false;
  bool _shadow = true;
  String _textPreset = 'Обычный';
  Offset _textOffset = const Offset(0, 0);
  final _boundaryKey = GlobalKey();
  bool _imageLoaded = false;

  String _textContent = '';

  final _picker = ImagePicker();

  static const double _previewSize = 300.0;
  static const List<Color> _colorPalette = [
    Colors.white,
    Colors.black,
    SeeUColors.accent,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() {
      if (mounted) {
        setState(() => _textContent = _textCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textCtrl.dispose();
    _controller?.removeListener(_syncVideoSlider);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;

    final Uint8List bytes = await file.readAsBytes();
    await _disposeVideo();
    if (!mounted) return;

    setState(() {
      _mode = _Mode.photo;
      _sourceBytes = bytes;
      _processedUrl = null;
      _bgRemovedUrl = null;
      _inTextEditor = false;
      _imageLoaded = false;
      _error = null;
      _resetTextState();
    });
  }

  Future<void> _pickVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    setState(() {
      _mode = _Mode.video;
      _sourceBytes = null;
      _processedUrl = null;
      _bgRemovedUrl = null;
      _inTextEditor = false;
      _videoPath = file.path;
      _videoSliderValue = 0;
      _videoReady = false;
      _imageLoaded = false;
      _error = null;
      _resetTextState();
    });

    await _initVideoPlayer(file.path);
  }

  Future<void> _disposeVideo() async {
    _debounceTimer?.cancel();
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

    final VideoPlayerController controller = VideoPlayerController.file(
      File(path),
    );
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
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final int durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) return;

    final double nextValue =
        (controller.value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    if ((nextValue - _videoSliderValue).abs() < 0.002) return;
    if (mounted) {
      setState(() => _videoSliderValue = nextValue);
    }
  }

  void _onVideoSliderChanged(double value) {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    _debounceTimer?.cancel();
    _removeRequestId++;

    final Duration duration = controller.value.duration;
    final Duration position = Duration(
      milliseconds: (duration.inMilliseconds * value).round(),
    );

    controller.pause();
    controller.seekTo(position);

    setState(() {
      _videoSliderValue = value;
      _bgRemovedUrl = null;
      _processedUrl = null;
      _inTextEditor = false;
      _imageLoaded = false;
      _isRemoving = false;
      _error = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 650), () {
      _extractAndRemoveBgAt(position);
    });
  }

  Future<void> _extractAndRemoveBgAt(Duration position) async {
    final String? path = _videoPath;
    if (path == null) return;

    final int requestId = ++_removeRequestId;
    setState(() {
      _isRemoving = true;
      _error = null;
    });

    try {
      final Uint8List? frameBytes = await VideoThumbnail.thumbnailData(
        video: path,
        timeMs: position.inMilliseconds,
        imageFormat: ImageFormat.PNG,
        quality: 95,
      );
      if (frameBytes == null) {
        throw Exception('Не удалось извлечь кадр');
      }

      final String url =
          await ref.read(stickerListProvider.notifier).removeBg(frameBytes);
      if (!mounted || requestId != _removeRequestId) return;

      setState(() {
        _bgRemovedUrl = url;
        _processedUrl = url;
        _imageLoaded = false;
        _textOffset = const Offset(0, 0);
      });
    } catch (e) {
      if (mounted && requestId == _removeRequestId) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && requestId == _removeRequestId) {
        setState(() => _isRemoving = false);
      }
    }
  }

  Future<void> _removeBgFromPhoto() async {
    if (_sourceBytes == null) return;
    setState(() {
      _removingBg = true;
      _error = null;
    });
    try {
      await _doRemoveBg(_sourceBytes!);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _removingBg = false);
    }
  }

  Future<void> _doRemoveBg(Uint8List bytes) async {
    final String url = await ref.read(stickerListProvider.notifier).removeBg(
          bytes,
        );
    if (!mounted) return;
    setState(() {
      _processedUrl = url;
      _imageLoaded = false;
      _textOffset = const Offset(0, 0);
    });
  }

  void _openTextEditor() {
    if (_bgRemovedUrl == null || _isRemoving) return;
    setState(() {
      _processedUrl = _bgRemovedUrl;
      _inTextEditor = true;
      _imageLoaded = false;
    });
  }

  Future<void> _save() async {
    final String? url = _processedUrl;
    if (url == null || !_imageLoaded || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final RenderRepaintBoundary boundary = _boundaryKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw Exception('Не удалось сохранить изображение');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final StickerModel sticker =
          await ref.read(stickerListProvider.notifier).saveSticker(pngBytes);

      if (mounted) {
        Navigator.of(context).pop(StickerCreatorResult(sticker.url));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _applyPreset(String preset) {
    setState(() {
      _textPreset = preset;
      switch (preset) {
        case 'Жирный':
          _bold = true;
          _shadow = true;
          break;
        case 'Контур':
          _bold = true;
          _shadow = false;
          _textColor = Colors.white;
          break;
        case 'Обычный':
        default:
          _bold = false;
          _shadow = false;
          break;
      }
    });
  }

  void _resetTextState() {
    _textCtrl.clear();
    _textContent = '';
    _textColor = Colors.white;
    _fontSize = 32;
    _bold = false;
    _shadow = false;
    _textPreset = 'Обычный';
    _textOffset = const Offset(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final SeeUThemeColors c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIconsRegular.x, color: c.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Создать стикер',
          style: SeeUTypography.subtitle.copyWith(color: c.ink),
        ),
        centerTitle: true,
        actions: [
          if (_inTextEditor || (_mode == _Mode.photo && _processedUrl != null))
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: _imageLoaded ? _save : null,
                    child: Text(
                      'Сохранить',
                      style: SeeUTypography.subtitle.copyWith(
                        color: _imageLoaded
                            ? SeeUColors.accent
                            : SeeUColors.accent.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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

  Widget _buildBody(SeeUThemeColors c) {
    switch (_mode) {
      case _Mode.none:
        return _buildSourcePicker(c);
      case _Mode.photo:
        return _buildPhotoEditor(c);
      case _Mode.video:
        return _buildVideoFlow(c);
    }
  }

  Widget _buildSourcePicker(SeeUThemeColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Выберите источник',
              style: SeeUTypography.subtitle.copyWith(color: c.ink),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: _sourceCard(
                    icon: PhosphorIconsRegular.image,
                    label: 'Фото',
                    onTap: _pickPhoto,
                    c: c,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _sourceCard(
                    icon: PhosphorIconsRegular.videoCamera,
                    label: 'Видео',
                    onTap: _pickVideo,
                    c: c,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required SeeUThemeColors c,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: SeeUColors.accent),
            const SizedBox(height: 10),
            Text(
              label,
              style: SeeUTypography.body.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoEditor(SeeUThemeColors c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildStickerCanvas(c, imageUrl: _processedUrl),
          const SizedBox(height: 16),
          if (_processedUrl == null)
            _removingBg
                ? _buildInlineLoading(c, 'Убираем фон...')
                : SeeUButton(
                    label: 'Убрать фон',
                    onTap: _removeBgFromPhoto,
                    icon: PhosphorIconsRegular.eraser,
                  )
          else
            _buildTextEditor(c),
        ],
      ),
    );
  }

  Widget _buildVideoFlow(SeeUThemeColors c) {
    if (!_videoReady ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_inTextEditor) ...[
            _buildStickerCanvas(c, imageUrl: _processedUrl),
            const SizedBox(height: 16),
            _buildTextEditor(c),
          ] else ...[
            _buildVideoPreview(c),
            const SizedBox(height: 12),
            _buildVideoSlider(c),
            const SizedBox(height: 8),
            _buildVideoStatus(c),
            const SizedBox(height: 16),
            SeeUButton(
              label: 'Добавить текст →',
              onTap: !_isRemoving && _bgRemovedUrl != null
                  ? _openTextEditor
                  : null,
              icon: PhosphorIconsRegular.textT,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoPreview(SeeUThemeColors c) {
    final String? previewUrl = _bgRemovedUrl;
    return Center(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: _previewSize),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        clipBehavior: Clip.hardEdge,
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (previewUrl == null)
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else
                CachedNetworkImage(
                  imageUrl: AppConfig.absUrl(previewUrl),
                  fit: BoxFit.contain,
                  imageBuilder: (context, imageProvider) {
                    if (!_imageLoaded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _imageLoaded = true);
                      });
                    }
                    return Image(
                      image: imageProvider,
                      fit: BoxFit.contain,
                    );
                  },
                  placeholder: (context, url) =>
                      Container(color: Colors.transparent),
                  errorWidget: (context, url, error) => Icon(
                    PhosphorIconsRegular.image,
                    size: 40,
                    color: c.ink3,
                  ),
                ),
              if (_isRemoving)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.18),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoStatus(SeeUThemeColors c) {
    final String label;
    final Color color;

    if (_isRemoving) {
      label = 'Обрабатываем кадр...';
      color = c.ink3;
    } else if (_bgRemovedUrl != null) {
      label = 'Готово — можно добавить текст ✓';
      color = SeeUColors.accent;
    } else {
      label = 'Выберите нужный кадр ползунком';
      color = c.ink3;
    }

    return Text(
      label,
      textAlign: TextAlign.center,
      style: SeeUTypography.caption.copyWith(color: color),
    );
  }

  Widget _buildVideoSlider(SeeUThemeColors c) {
    final Duration duration = _controller!.value.duration;
    final Duration position = Duration(
      milliseconds: (duration.inMilliseconds * _videoSliderValue).round(),
    );

    return Row(
      children: [
        Icon(PhosphorIconsRegular.clock, size: 16, color: c.ink3),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            value: _videoSliderValue.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            activeColor: SeeUColors.accent,
            inactiveColor: c.line,
            onChanged: _onVideoSliderChanged,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatDuration(position),
          style: SeeUTypography.caption.copyWith(color: c.ink3),
        ),
      ],
    );
  }

  Widget _buildStickerCanvas(SeeUThemeColors c, {required String? imageUrl}) {
    final String? absUrl = imageUrl != null ? AppConfig.absUrl(imageUrl) : null;

    return Center(
      child: Container(
        width: _previewSize,
        height: _previewSize,
        decoration: BoxDecoration(
          color: absUrl != null ? Colors.transparent : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        clipBehavior: Clip.hardEdge,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (_sourceBytes != null && absUrl == null)
                Positioned.fill(
                  child: Image.memory(_sourceBytes!, fit: BoxFit.contain),
                ),
              if (absUrl != null)
                Positioned.fill(
                  child: Image.network(
                    absUrl,
                    fit: BoxFit.contain,
                    frameBuilder: (context, child, frame, wasSyncLoaded) {
                      if ((frame != null || wasSyncLoaded) && !_imageLoaded) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _imageLoaded = true);
                        });
                      }
                      return child;
                    },
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsRegular.image,
                            size: 40,
                            color: c.ink3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Не удалось загрузить',
                            style: SeeUTypography.caption.copyWith(
                              color: c.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_textContent.isNotEmpty) _buildDraggableText(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableText() {
    final TextStyle style = TextStyle(
      color: _textColor,
      fontSize: _fontSize,
      fontWeight: _bold ? FontWeight.w900 : FontWeight.w600,
      shadows: _shadow
          ? const [
              Shadow(
                color: Colors.black54,
                offset: Offset(2, 2),
                blurRadius: 4,
              ),
            ]
          : null,
    );

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Offset pixelOffset = Offset(
            _textOffset.dx * constraints.maxWidth,
            _textOffset.dy * constraints.maxHeight,
          );

          return GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _textOffset = Offset(
                  (_textOffset.dx + details.delta.dx / constraints.maxWidth)
                      .clamp(-0.5, 0.5),
                  (_textOffset.dy + details.delta.dy / constraints.maxHeight)
                      .clamp(-0.5, 0.5),
                );
              });
            },
            child: Transform.translate(
              offset: pixelOffset,
              child: Center(
                child: _textPreset == 'Контур'
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.translate(
                            offset: const Offset(2, 2),
                            child: Text(
                              _textContent,
                              textAlign: TextAlign.center,
                              style: style.copyWith(color: Colors.black),
                            ),
                          ),
                          Text(
                            _textContent,
                            textAlign: TextAlign.center,
                            style: style.copyWith(color: Colors.white),
                          ),
                        ],
                      )
                    : Text(
                        _textContent,
                        textAlign: TextAlign.center,
                        style: style,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextEditor(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _textCtrl,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: 'Добавить текст',
            hintStyle: SeeUTypography.body.copyWith(
              color: c.ink3,
              fontSize: 14,
            ),
            filled: true,
            fillColor: c.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
          ),
          style: SeeUTypography.body.copyWith(color: c.ink, fontSize: 14),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _presetChip(c, 'Обычный'),
            _presetChip(c, 'Жирный'),
            _presetChip(c, 'Контур'),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Цвет текста',
          style: SeeUTypography.caption.copyWith(
            color: c.ink3,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _colorPalette.map((Color color) {
            final bool selected = _textColor.toARGB32() == color.toARGB32();
            return GestureDetector(
              onTap: () => setState(() => _textColor = color),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? SeeUColors.accent : c.line,
                        width: selected ? 3 : 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(PhosphorIconsRegular.textT, size: 14, color: c.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _fontSize,
                min: 14,
                max: 72,
                activeColor: SeeUColors.accent,
                inactiveColor: c.line,
                onChanged: (double value) => setState(() => _fontSize = value),
              ),
            ),
            Text(
              '${_fontSize.round()}pt',
              style: SeeUTypography.caption.copyWith(
                color: c.ink3,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _toggleChip(
              c: c,
              label: 'B',
              selected: _bold,
              onTap: () => setState(() => _bold = !_bold),
              boldLabel: true,
            ),
            const SizedBox(width: 8),
            _toggleChip(
              c: c,
              label: 'Тень',
              selected: _shadow,
              icon: PhosphorIconsRegular.textStrikethrough,
              onTap: () => setState(() => _shadow = !_shadow),
            ),
            const Spacer(),
            Icon(PhosphorIconsRegular.arrowsOut, size: 14, color: c.ink3),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _presetChip(SeeUThemeColors c, String label) {
    final bool selected = _textPreset == label;
    return GestureDetector(
      onTap: () => _applyPreset(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? SeeUColors.accent : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: selected ? SeeUColors.accent : c.line),
        ),
        child: Text(
          label,
          style: SeeUTypography.caption.copyWith(
            color: selected ? Colors.white : c.ink2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _toggleChip({
    required SeeUThemeColors c,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    bool boldLabel = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? SeeUColors.accent : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? Colors.white : c.ink2),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: SeeUTypography.caption.copyWith(
                color: selected ? Colors.white : c.ink2,
                fontWeight: boldLabel ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineLoading(SeeUThemeColors c, String label) {
    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          label,
          style: SeeUTypography.caption.copyWith(color: c.ink3),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final String minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
