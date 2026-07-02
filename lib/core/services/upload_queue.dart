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
  /// Upload progress 0.0–1.0. `null` = indeterminate (size unknown).
  final double? progress;

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
    this.progress,
  });

  UploadTask copyWith({bool? isUploading, String? errorMessage, double? progress}) => UploadTask(
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
        progress: progress ?? this.progress,
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
  /// Also cleans up any temp file produced by voice/video-note recording.
  void cancel(String taskId) {
    final idx = state.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = state[idx];
    task.cancelToken.cancel();
    _deleteTempFile(task);
    final chatId = task.chatId;
    state = state.where((t) => t.id != taskId).toList();
    _processNext(chatId);
  }

  /// Retry a failed task without re-selecting the file. Clears the error,
  /// issues a fresh [CancelToken], and re-queues the task for upload.
  /// Only has an effect when [UploadTask.errorMessage] is non-null.
  void retry(String taskId) {
    final idx = state.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final old = state[idx];
    if (old.errorMessage == null) return;
    final retried = UploadTask(
      id: old.id,
      chatId: old.chatId,
      kind: old.kind,
      thumbnail: old.thumbnail,
      waveform: old.waveform,
      durationSec: old.durationSec,
      fileName: old.fileName,
      fileBytes: old.fileBytes,
      bytes: old.bytes,
      filePath: old.filePath,
      mediaType: old.mediaType,
      caption: old.caption,
      replyTo: old.replyTo,
      cancelToken: CancelToken(),
    );
    state = [for (final t in state) if (t.id == taskId) retried else t];
    _processNext(old.chatId);
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
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          final p = (sent / total).clamp(0.0, 1.0);
          // Throttle state updates to ~1% increments to avoid excessive rebuilds.
          final current = state
              .where((t) => t.id == task.id)
              .map((t) => t.progress ?? 0.0)
              .firstOrNull ?? 0.0;
          if (p - current < 0.01 && p < 1.0) return;
          state = [
            for (final t in state)
              if (t.id == task.id) t.copyWith(progress: p) else t
          ];
        },
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

      // Success — delete temp file and remove from queue.
      _deleteTempFile(task);
      state = state.where((t) => t.id != task.id).toList();
      _processNext(task.chatId);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // cancel() already removed the task from state and cleaned up the file.
        return;
      }
      state = [
        for (final t in state)
          if (t.id == task.id)
            t.copyWith(isUploading: false, errorMessage: apiErrorMessage(e))
          else
            t
      ];
      // Unblock the queue: subsequent tasks in this chat must not starve.
      _processNext(task.chatId);
    } catch (e) {
      state = [
        for (final t in state)
          if (t.id == task.id)
            t.copyWith(isUploading: false, errorMessage: friendlyError(e))
          else
            t
      ];
      // Unblock the queue: subsequent tasks in this chat must not starve.
      _processNext(task.chatId);
    }
  }

  /// Deletes the temp file produced by a voice/video-note recording.
  /// No-op for tasks backed by in-memory [bytes] or permanent gallery paths.
  void _deleteTempFile(UploadTask task) {
    if ((task.kind == UploadTaskKind.voice ||
            task.kind == UploadTaskKind.videoNote) &&
        task.filePath != null) {
      try {
        File(task.filePath!).deleteSync();
      } catch (_) {}
    }
  }
}

final uploadQueueProvider =
    StateNotifierProvider<UploadQueueNotifier, List<UploadTask>>(
  (ref) => UploadQueueNotifier(ref),
);
