import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/video_provider.dart';

/// VIDEO-3: загрузка long-form-видео из галереи. Шаги:
///   1. Pick video file (image_picker, source=gallery, no maxDuration).
///   2. Preview + extract duration через VideoPlayerController.initialize.
///   3. Title/description/category — обязательные fields.
///   4. Upload via api `/media/upload` с Dio.onSendProgress (large files → 5min timeout).
///   5. POST video metadata в video service `/videos`.
///   6. Invalidate video providers → возврат на watch_screen.
class VideoUploadScreen extends ConsumerStatefulWidget {
  const VideoUploadScreen({super.key});

  @override
  ConsumerState<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

class _VideoUploadScreenState extends ConsumerState<VideoUploadScreen> {
  XFile? _file;
  VideoPlayerController? _previewCtrl;
  int _durationSec = 0;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _categoryId;
  bool _uploading = false;
  double _progress = 0.0;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _previewCtrl?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _file = picked);
    // Preview controller — извлекаем duration. На web bytes, на mobile path.
    _previewCtrl?.dispose();
    final ctrl = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(picked.path))
        : VideoPlayerController.file(File(picked.path));
    _previewCtrl = ctrl;
    try {
      await ctrl.initialize();
      setState(() => _durationSec = ctrl.value.duration.inSeconds);
      ctrl.setLooping(true);
      ctrl.play();
    } catch (e) {
      setState(() => _error = 'Не удалось прочитать видео: $e');
    }
  }

  Future<void> _submit() async {
    if (_file == null) {
      setState(() => _error = 'Выберите видео из галереи');
      return;
    }
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Введите название');
      return;
    }
    if (_durationSec <= 0) {
      setState(() => _error = 'Видео не загрузилось — попробуйте ещё раз');
      return;
    }
    setState(() {
      _uploading = true;
      _progress = 0.0;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      // 1) Upload binary через api /media/upload. Bytes universal cross-platform.
      final bytes = await _file!.readAsBytes();
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: _file!.name),
      });
      final upResp = await api.post(
        ApiEndpoints.mediaUpload,
        data: form,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 1),
        ),
        onSendProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = sent / total);
          }
        },
      );
      final mediaUrl = upResp.data['data']['url'] as String;

      // 2) POST metadata в video-service (порт 8002).
      final videoDio = Dio(BaseOptions(
        baseUrl: ApiEndpoints.videoBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final tok = await api.getAccessToken();
      if (tok != null && tok.isNotEmpty) {
        videoDio.options.headers['Authorization'] = 'Bearer $tok';
      }
      await videoDio.post('/videos', data: {
        'title': title,
        'description': _descCtrl.text.trim(),
        'video_url': mediaUrl,
        'duration_seconds': _durationSec,
        if (_categoryId != null && _categoryId!.isNotEmpty)
          'category_id': _categoryId,
      });

      // Refresh providers — новое видео появится в watch_screen.
      ref.invalidate(videosProvider);
      ref.invalidate(videosFeaturedProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Видео опубликовано'),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } on DioException catch (e) {
      setState(() {
        _uploading = false;
        _error = apiErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _uploading = false;
        _error = 'Ошибка: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final categoriesAsync = ref.watch(videoCategoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новое видео'),
        actions: [
          TextButton(
            onPressed: _uploading ? null : _submit,
            child: Text(
              // ignore: unnecessary_brace_in_string_interps
              _uploading
                  ? '${(_progress * 100).toInt()}%'
                  : 'Опубликовать',
              style: TextStyle(
                color: _uploading ? c.ink3 : SeeUColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _uploading,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Preview
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _previewCtrl != null && _previewCtrl!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _previewCtrl!.value.aspectRatio,
                        child: VideoPlayer(_previewCtrl!),
                      )
                    : InkWell(
                        onTap: _pickVideo,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIcons.filmStrip(),
                                  size: 56, color: c.ink3),
                              const SizedBox(height: 8),
                              Text(
                                'Выбрать видео из галереи',
                                style: TextStyle(color: c.ink2),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            if (_file != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(PhosphorIconsBold.clock,
                      size: 14, color: c.ink2),
                  const SizedBox(width: 4),
                  Text(_formatDuration(_durationSec),
                      style: TextStyle(fontSize: 12, color: c.ink2)),
                  const Spacer(),
                  TextButton(
                    onPressed: _pickVideo,
                    child: const Text('Сменить видео'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            TextField(
              controller: _titleCtrl,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Название',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLength: 2000,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Описание',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Category picker
            categoriesAsync.when(
              data: (cats) => DropdownButtonFormField<String?>(
                value: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Без категории'),
                  ),
                  ...cats.map((cat) => DropdownMenuItem<String?>(
                        value: cat.id,
                        child: Text(cat.name),
                      )),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox(),
            ),
            const SizedBox(height: 16),

            if (_uploading) ...[
              LinearProgressIndicator(
                value: _progress,
                valueColor: const AlwaysStoppedAnimation(SeeUColors.accent),
              ),
              const SizedBox(height: 6),
              Text(
                'Загружаем… ${(_progress * 100).toInt()}%',
                style: TextStyle(color: c.ink2, fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(int sec) {
    if (sec <= 0) return '';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '${h}ч ${m.toString().padLeft(2, '0')}м'; // ignore: unnecessary_brace_in_string_interps
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
