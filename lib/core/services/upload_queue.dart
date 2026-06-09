import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../providers/chat_provider.dart';
import '../utils/format.dart';

enum UploadTaskKind { voice, videoNote, image, video, audio, file }

class UploadTask {
  final String id;
  final String chatId;
  final UploadTaskKind kind;
  // UI display
  final Uint8List? thumbnail;
  final List<double> waveform;
  final int durationSec;
  final String fileName;
  final int fileBytes;
  // Upload payload: exactly one of bytes/filePath must be non-null
  final Uint8List? bytes;
  final String? filePath;
  // Message params
  final String mediaType; // 'image'|'audio'|'video'|'video_note'|'file'
  final String caption;
  final ReplyPreview? replyTo;
  final CancelToken cancelToken;
  // Runtime state
  final bool isUploading;
  final String? errorMessage;

  const UploadTask({
    required this.id,
    required this.chatId,
    required this.kind,
    this.thumbnail,
    this.waveform = const [],
    this.durationSec = 0,
    this.fileName = '',
    this.fileBytes = 0,
    this.bytes,
    this.filePath,
    required this.mediaType,
    this.caption = '',
    this.replyTo,
    required this.cancelToken,
    this.isUploading = false,
    this.errorMessage,
  });

  UploadTask copyWith({bool? isUploading, String? errorMessage}) => UploadTask(
        id: id,
        chatId: chatId,
        kind: kind,
        thumbnail: thumbnail,
        waveform: waveform,
        durationSec: durationSec,
        fileName: fileName,
        fileBytes: fileBytes,
        bytes: bytes,
        filePath: filePath,
        mediaType: mediaType,
        caption: caption,
        replyTo: replyTo,
        cancelToken: cancelToken,
        isUploading: isUploading ?? this.isUploading,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  static String newId() => const Uuid().v4();
}

/// Global upload queue. Survives navigation — lives in root ProviderScope.
/// At most one active upload per chatId (uploads for different chats run in
/// parallel). UI reads this provider and shows pending bubbles.
class UploadQueueNotifier extends StateNotifier<List<UploadTask>> {
  final Ref _ref;
  UploadQueueNotifier(this._ref) : super([]);

  /// Add a new task and start processing for its chat.
  void enqueue(UploadTask task) {
    state = [...state, task];
    _processNext(task.chatId);
  }

  /// Cancel a task by id (safe to call if already gone).
  void cancel(String taskId) {
    final idx = state.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = state[idx];
    task.cancelToken.cancel();
    final chatId = task.chatId;
    state = state.where((t) => t.id != taskId).toList();
    _processNext(chatId);
  }

  void _processNext(String chatId) {
    if (state.any((t) => t.chatId == chatId && t.isUploading)) return;
    final next = state.cast<UploadTask?>().firstWhere(
          (t) => t!.chatId == chatId && !t.isUploading && t.errorMessage == null,
          orElse: () => null,
        );
    if (next == null) return;
    state = [for (final t in state) if (t.id == next.id) t.copyWith(isUploading: true) else t];
    _execute(next);
  }

  Future<void> _execute(UploadTask task) async {
    try {
      final api = _ref.read(apiClientProvider);
      final FormData formData;

      if (task.bytes != null) {
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            task.bytes!,
            filename: task.fileName.isNotEmpty ? task.fileName : 'upload',
          ),
        });
      } else if (task.filePath != null) {
        final filename =
            task.fileName.isNotEmpty ? task.fileName : task.filePath!.split('/').last;
        MediaType? ct;
        if (task.kind == UploadTaskKind.voice) ct = MediaType('audio', 'mp4');
        if (task.kind == UploadTaskKind.videoNote) ct = MediaType('video', 'mp4');
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            task.filePath!,
            filename: filename,
            contentType: ct,
          ),
        });
      } else {
        throw Exception('UploadTask has no data');
      }

      final upload = await api.post(
        ApiEndpoints.mediaUpload,
        data: formData,
        cancelToken: task.cancelToken,
      );
      final url = upload.data['data']['url'] as String;

      await _ref.read(chatMessagesProvider(task.chatId).notifier).sendMessage(
            task.caption,
            attachedMediaUrl: url,
            attachedMediaType: task.mediaType,
            mediaDurationSeconds: task.durationSec,
            waveform: task.waveform,
            replyTo: task.replyTo,
          );

      // Success — remove from queue
      state = state.where((t) => t.id != task.id).toList();
      _processNext(task.chatId);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // cancel() already removed the task from state
        return;
      }
      state = [
        for (final t in state)
          if (t.id == task.id)
            t.copyWith(isUploading: false, errorMessage: apiErrorMessage(e))
          else
            t
      ];
    } catch (e) {
      state = [
        for (final t in state)
          if (t.id == task.id)
            t.copyWith(isUploading: false, errorMessage: friendlyError(e))
          else
            t
      ];
    } finally {
      // Delete temp file for voice and video-note recordings
      if ((task.kind == UploadTaskKind.voice ||
              task.kind == UploadTaskKind.videoNote) &&
          task.filePath != null) {
        try {
          File(task.filePath!).deleteSync();
        } catch (_) {}
      }
    }
  }
}

final uploadQueueProvider =
    StateNotifierProvider<UploadQueueNotifier, List<UploadTask>>(
  (ref) => UploadQueueNotifier(ref),
);
