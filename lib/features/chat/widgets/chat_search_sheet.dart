import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/chat_provider.dart';

class ChatSearchSheet extends ConsumerStatefulWidget {
  final String chatId;
  final void Function(ChatMessage) onResultTap;
  const ChatSearchSheet({
    super.key,
    required this.chatId,
    required this.onResultTap,
  });

  @override
  ConsumerState<ChatSearchSheet> createState() => _ChatSearchSheetState();
}

class _ChatSearchSheetState extends ConsumerState<ChatSearchSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    if (!mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(
        ApiEndpoints.chatMessages(widget.chatId),
        queryParameters: {'q': q, 'limit': 100},
      );
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data
              .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
              .toList()
          : <ChatMessage>[];
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _results = [];
      });
    }
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay =
        now.year == local.year && now.month == local.month && now.day == local.day;
    if (sameDay) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
            children: [
              SeeUSectionHeader(
                kicker: 'Поиск',
                title: 'В этом чате',
              ),
              const SizedBox(height: 12),
              // Плоское поле — внутри уже стеклянного шита (без стекла на стекле).
              Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                  border: Border.all(color: c.line, width: 0.5),
                ),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _onChanged,
                  style: SeeUTypography.body.copyWith(color: c.ink),
                  cursorColor: SeeUColors.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    icon: PhosphorIcon(PhosphorIcons.magnifyingGlass(),
                        size: 18, color: c.ink3),
                    hintText: 'Слово или фраза…',
                    hintStyle: SeeUTypography.body.copyWith(color: c.ink3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(c)),
            ],
          ),
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    if (_loading) {
      return const Center(
        child:
            CircularProgressIndicator(color: SeeUColors.accent, strokeWidth: 2.5),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Не удалось выполнить поиск',
              style: SeeUTypography.body.copyWith(color: c.ink2)),
        ),
      );
    }
    if (_ctrl.text.trim().isEmpty) {
      return Center(
        child: Text('Введите запрос для поиска',
            style: SeeUTypography.body.copyWith(color: c.ink3)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('Ничего не найдено',
            style: SeeUTypography.body.copyWith(color: c.ink3)),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
      itemBuilder: (_, i) {
        final m = _results[i];
        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          title: Text(m.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SeeUTypography.body.copyWith(fontSize: 13)),
          subtitle: Text(_fmtTime(m.createdAt),
              style:
                  SeeUTypography.caption.copyWith(color: c.ink3, fontSize: 11)),
          trailing: Icon(PhosphorIcons.caretRight(), size: 14, color: c.ink3),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onResultTap(m);
          },
        );
      },
    );
  }
}
