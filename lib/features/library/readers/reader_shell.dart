import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/library_provider.dart';

/// Общая обёртка для всех Tier-1/2/3 ридеров.
/// Показывает AppBar с названием, кнопку закладок, прогресс-бар.
/// При dispose сохраняет прогресс через PUT /files/:id/progress.
class ReaderShell extends ConsumerStatefulWidget {
  final String fileId;
  final String title;
  final String docFormat;
  /// Текущая позиция (JSON), устанавливается ридером-потомком.
  final ValueNotifier<Map<String, dynamic>> positionNotifier;
  final Widget child;

  const ReaderShell({
    super.key,
    required this.fileId,
    required this.title,
    required this.docFormat,
    required this.positionNotifier,
    required this.child,
  });

  @override
  ConsumerState<ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends ConsumerState<ReaderShell> {
  @override
  void dispose() {
    _saveProgress();
    super.dispose();
  }

  Future<void> _saveProgress() async {
    final pos = widget.positionNotifier.value;
    if (pos.isEmpty) return;
    try {
      final dio = ref.read(libraryApiClientProvider);
      await dio.put(
        ApiEndpoints.fileProgress(widget.fileId),
        data: {'position': pos},
      );
    } catch (_) {
      // Graceful — не мешаем закрытию
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            Text(
              widget.docFormat.toUpperCase(),
              style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  color: SeeUColors.accent),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(PhosphorIconsRegular.bookmarkSimple, color: c.ink2),
            onPressed: () => _addBookmark(context),
          ),
        ],
      ),
      body: widget.child,
    );
  }

  Future<void> _addBookmark(BuildContext context) async {
    final pos = widget.positionNotifier.value;
    try {
      final dio = ref.read(libraryApiClientProvider);
      await dio.post(
        ApiEndpoints.fileBookmarks(widget.fileId),
        data: {
          'position': pos,
          'note': '',
        },
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Закладка добавлена')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось добавить закладку')),
      );
    }
  }
}

/// Загружает текущий прогресс файла. Возвращает null если нет.
Future<Map<String, dynamic>?> loadProgress(Dio dio, String fileId) async {
  try {
    final resp = await dio.get(ApiEndpoints.fileProgress(fileId));
    if (resp.statusCode == 204) return null;
    final data = resp.data?['data'];
    if (data == null) return null;
    final pos = data['position'];
    if (pos is Map) return Map<String, dynamic>.from(pos);
    if (pos is String) {
      return Map<String, dynamic>.from(jsonDecode(pos) as Map);
    }
    return null;
  } catch (_) {
    return null;
  }
}
