import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';

/// Bottom sheet that lets the user upload a personal audio track.
///
/// Flow:
/// 1. user picks an mp3/wav/m4a file (file_picker, audio filter)
/// 2. user picks an optional cover image (image_picker)
/// 3. user fills title / artist / genre
/// 4. on submit: POST /media/upload twice (audio + cover) → POST /audio-tracks
///    with returned URLs. Track lands in `pending` status awaiting moderation.
Future<bool> showTrackUploadSheet(BuildContext context, WidgetRef ref) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: const _TrackUploadForm(),
    ),
  );
  return result ?? false;
}

class _TrackUploadForm extends ConsumerStatefulWidget {
  const _TrackUploadForm();

  @override
  ConsumerState<_TrackUploadForm> createState() => _TrackUploadFormState();
}

class _TrackUploadFormState extends ConsumerState<_TrackUploadForm> {
  PlatformFile? _audio;
  XFile? _cover;
  Uint8List? _coverBytes;
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _genre = TextEditingController();
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _genre.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    setState(() => _audio = res.files.first);
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final f = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() {
      _cover = f;
      _coverBytes = bytes;
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final artist = _artist.text.trim();
    if (title.isEmpty || artist.isEmpty) {
      setState(() => _error = 'Заполните название и артиста');
      return;
    }
    if (_audio == null || _audio!.bytes == null) {
      setState(() => _error = 'Выберите аудиофайл');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);

      final audioForm = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          _audio!.bytes!,
          filename: _audio!.name,
        ),
      });
      final audioResp = await api.post(ApiEndpoints.mediaUpload, data: audioForm);
      final audioUrl = audioResp.data['data']['url'] as String;

      // Probe duration from uploaded file
      int durationSeconds = 0;
      try {
        final probePlayer = AudioPlayer();
        final absUrl = audioUrl.startsWith('/')
            ? ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + audioUrl
            : audioUrl;
        final d = await probePlayer.setUrl(absUrl);
        durationSeconds = d?.inSeconds ?? 0;
        await probePlayer.dispose();
      } catch (_) {}

      String coverUrl = '';
      if (_cover != null && _coverBytes != null) {
        final coverForm = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            _coverBytes!,
            filename: _cover!.name,
          ),
        });
        final coverResp = await api.post(ApiEndpoints.mediaUpload, data: coverForm);
        coverUrl = coverResp.data['data']['url'] as String;
      }

      await api.post(ApiEndpoints.audioTracks, data: {
        'title': title,
        'artist': artist,
        'genre': _genre.text.trim(),
        'audio_url': audioUrl,
        'cover_url': coverUrl,
        'duration_seconds': durationSeconds,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Трек загружен. После проверки модератором появится в каталоге.')),
      );
    } on DioException catch (e) {
      setState(() {
        _uploading = false;
        _error = apiErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _uploading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(PhosphorIcons.uploadSimple(), color: SeeUColors.accent),
                const SizedBox(width: 8),
                const Text('Загрузить свой трек',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _filePickerTile(
              label: 'Аудиофайл (mp3 / wav / m4a)',
              valueText: _audio?.name ?? 'Выбрать файл',
              icon: PhosphorIcons.musicNotesSimple(),
              onTap: _uploading ? null : _pickAudio,
              c: c,
              done: _audio != null,
            ),
            const SizedBox(height: 8),
            _filePickerTile(
              label: 'Обложка (опционально)',
              valueText: _cover?.name ?? 'Выбрать изображение',
              icon: PhosphorIcons.image(),
              onTap: _uploading ? null : _pickCover,
              c: c,
              done: _cover != null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              enabled: !_uploading,
              decoration: const InputDecoration(
                labelText: 'Название',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _artist,
              enabled: !_uploading,
              decoration: const InputDecoration(
                labelText: 'Артист',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _genre,
              enabled: !_uploading,
              decoration: const InputDecoration(
                labelText: 'Жанр (опционально)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              maxLength: 40,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: SeeUColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _uploading ? null : _submit,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(PhosphorIcons.uploadSimple(), size: 18),
              label: Text(_uploading ? 'Загружаем…' : 'Загрузить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filePickerTile({
    required String label,
    required String valueText,
    required IconData icon,
    required VoidCallback? onTap,
    required SeeUThemeColors c,
    required bool done,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: done ? SeeUColors.accent : c.line,
            width: done ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: done ? SeeUColors.accent : c.ink2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11, color: c.ink3)),
                  Text(valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: done ? c.ink : c.ink2)),
                ],
              ),
            ),
            if (done) Icon(Icons.check, color: SeeUColors.accent, size: 18),
          ],
        ),
      ),
    );
  }
}
