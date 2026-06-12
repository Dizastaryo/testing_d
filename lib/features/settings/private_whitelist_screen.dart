import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/design/design.dart';

/// Экран управления private-whitelist браслета.
/// Показывает взаимных подписчиков — пользователь выбирает кто видит его
/// в private BLE-режиме (mode=0x01).
///
/// GET  /users/me/private-whitelist        — текущий whitelist
/// GET  /users/me/mutual-followers         — все взаимные подписчики
/// PUT  /users/me/private-whitelist        — сохранить выбор
class PrivateWhitelistScreen extends ConsumerStatefulWidget {
  const PrivateWhitelistScreen({super.key});

  @override
  ConsumerState<PrivateWhitelistScreen> createState() =>
      _PrivateWhitelistScreenState();
}

class _PrivateWhitelistScreenState
    extends ConsumerState<PrivateWhitelistScreen> {
  // Все взаимные подписчики
  List<_UserItem> _mutuals = [];
  // Текущий выбор (user_id → выбран)
  final Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      // Параллельно грузим whitelist и всех взаимных подписчиков
      final results = await Future.wait([
        api.get('/users/me/private-whitelist'),
        api.get('/users/me/mutuals'),
      ]);

      final whitelistIds = (results[0].data['items'] as List)
          .map((e) => e['user_id'] as String)
          .toSet();

      // /users/me/mutuals возвращает UserShort: { id, username, full_name, avatar_url }
      final mutuals = (results[1].data['items'] as List)
          .map((e) => _UserItem(
                id: e['id'] as String,
                username: e['username'] as String,
                fullName: e['full_name'] as String? ?? '',
                avatarUrl: e['avatar_url'] as String? ?? '',
              ))
          .toList();

      if (mounted) {
        setState(() {
          _mutuals = mutuals;
          _selected
            ..clear()
            ..addAll(whitelistIds);
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final api = ref.read(apiClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.put(
        '/users/me/private-whitelist',
        data: {'user_ids': _selected.toList()},
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Список обновлён')),
      );
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: ${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Приватный режим',
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.w400,
            fontSize: 22,
            color: c.ink,
          ),
        ),
        actions: [
          if (!_loading && _error == null)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SeeUColors.accent,
                      ),
                    )
                  : Text(
                      'Сохранить',
                      style: TextStyle(
                        color: SeeUColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: SeeUColors.accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill),
                          size: 48, color: SeeUColors.error),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: c.ink2)),
                      const SizedBox(height: 16),
                      SeeUButton(label: 'Повторить', onTap: () {
                        setState(() { _loading = true; _error = null; });
                        _load();
                      }),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Пояснение
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            PhosphorIcons.lockSimple(PhosphorIconsStyle.fill),
                            size: 18,
                            color: SeeUColors.accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'В приватном режиме тебя видят только выбранные люди. '
                              'Идеально для пар — добавь только партнёра.',
                              style: TextStyle(
                                color: c.ink2,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            'Взаимные подписчики',
                            style: SeeUTypography.subtitle.copyWith(
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_selected.length} / ${_mutuals.length}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: c.ink3,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_mutuals.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'Пока нет взаимных подписчиков.\n'
                            'Когда появятся — можно выбрать кто тебя видит.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.ink3, height: 1.5),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _mutuals.length,
                          itemBuilder: (context, i) {
                            final user = _mutuals[i];
                            final selected = _selected.contains(user.id);
                            return _MutualTile(
                              user: user,
                              selected: selected,
                              onTap: () => setState(() {
                                if (selected) {
                                  _selected.remove(user.id);
                                } else {
                                  _selected.add(user.id);
                                }
                              }),
                            );
                          },
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _UserItem {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;

  const _UserItem({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
  });
}

class _MutualTile extends StatelessWidget {
  final _UserItem user;
  final bool selected;
  final VoidCallback onTap;

  const _MutualTile({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? SeeUColors.accent.withValues(alpha: 0.08)
              : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? SeeUColors.accent : c.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: c.surface2,
              backgroundImage: user.avatarUrl.isNotEmpty
                  ? NetworkImage(user.avatarUrl)
                  : null,
              child: user.avatarUrl.isEmpty
                  ? Text(
                      user.username.isNotEmpty
                          ? user.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  if (user.fullName.isNotEmpty)
                    Text(
                      user.fullName,
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: selected
                  ? Icon(
                      PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                      key: const ValueKey('checked'),
                      color: SeeUColors.accent,
                      size: 24,
                    )
                  : Icon(
                      PhosphorIcons.circle(),
                      key: const ValueKey('unchecked'),
                      color: c.ink4,
                      size: 24,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
