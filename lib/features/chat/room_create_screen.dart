import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/room_provider.dart';

class RoomCreateScreen extends ConsumerStatefulWidget {
  const RoomCreateScreen({super.key});

  @override
  ConsumerState<RoomCreateScreen> createState() => _RoomCreateScreenState();
}

class _RoomCreateScreenState extends ConsumerState<RoomCreateScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _type = 'voice'; // 'voice' | 'text'
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название комнаты')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(ApiEndpoints.rooms, data: {
        'type': _type,
        'name': name,
        'description': _descController.text.trim(),
        'is_public': true,
      });
      final data = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data'] as Map<String, dynamic>
          : resp.data as Map<String, dynamic>;
      final room = Room.fromJson(data);
      ref.read(roomListProvider.notifier).addRoom(room);
      if (!mounted) return;
      context.go('/room/${room.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(PhosphorIcons.x(), size: 22, color: c.ink),
                  ),
                  Expanded(
                    child: Text(
                      'Новая комната',
                      style: SeeUTypography.title.copyWith(color: c.ink),
                    ),
                  ),
                  GestureDetector(
                    onTap: _creating ? null : _create,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: _nameController.text.isNotEmpty
                            ? SeeUColors.accent
                            : c.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _creating
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Создать',
                              style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600,
                                color: _nameController.text.isNotEmpty ? Colors.white : c.ink3,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Type selector
                  Text(
                    'ТИП КОМНАТЫ',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 0.8, color: c.ink3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _TypeCard(
                          title: 'Голосовая',
                          subtitle: 'Голосовой канал\n+ текстовый чат',
                          icon: PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                          selected: _type == 'voice',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _type = 'voice');
                          },
                          c: c,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TypeCard(
                          title: 'Текстовая',
                          subtitle: 'Только\nтекстовый чат',
                          icon: PhosphorIcons.chatText(PhosphorIconsStyle.fill),
                          selected: _type == 'text',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _type = 'text');
                          },
                          c: c,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // Name
                  Text(
                    'НАЗВАНИЕ',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 0.8, color: c.ink3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.line),
                    ),
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      maxLength: 120,
                      style: TextStyle(fontSize: 16, color: c.ink),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: _type == 'voice'
                            ? 'Например: «Вечерний джем»'
                            : 'Например: «Флаттер-разработка»',
                        hintStyle: TextStyle(fontSize: 16, color: c.ink3),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Description
                  Text(
                    'ОПИСАНИЕ (НЕОБЯЗАТЕЛЬНО)',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 0.8, color: c.ink3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.line),
                    ),
                    child: TextField(
                      controller: _descController,
                      maxLines: 3,
                      maxLength: 500,
                      style: TextStyle(fontSize: 15, color: c.ink),
                      decoration: InputDecoration(
                        hintText: 'Расскажите о чём комната...',
                        hintStyle: TextStyle(fontSize: 15, color: c.ink3),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _TypeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? SeeUColors.accent.withValues(alpha: 0.08) : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SeeUColors.accent : c.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? SeeUColors.accent.withValues(alpha: 0.15)
                    : c.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon, size: 18,
                color: selected ? SeeUColors.accent : c.ink3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: selected ? SeeUColors.accent : c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: c.ink3, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
