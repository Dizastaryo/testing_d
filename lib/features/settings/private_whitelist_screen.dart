import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    try {
      await api.put(
        '/users/me/private-whitelist',
        data: {'user_ids': _selected.toList()},
      );
      if (!mounted) return;
      showSeeUSnackBar(context, 'Список обновлён', tone: SeeUTone.success);
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Ошибка: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Приватный режим',
            kicker: 'БРАСЛЕТ',
            leading: Tappable.scaled(
              onTap: () => context.pop(),
              scaleFactor: 0.9,
              child: SizedBox(
                width: 40,
                height: 40,
                child:
                    Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
              ),
            ),
            actions: [
              if (!_loading && _error == null)
                Tappable.faded(
                  onTap: _saving ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
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
                            style: SeeUTypography.subtitle.copyWith(
                              color: SeeUColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
            ],
          ),
          Expanded(child: _buildBody(c)),
        ],
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    return _loading
          ? const Center(child: CircularProgressIndicator(color: SeeUColors.accent))
          : _error != null
              ? SeeUErrorState(
                  error: _error,
                  onRetry: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
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
                        borderRadius: BorderRadius.circular(SeeURadii.small),
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
                              borderRadius:
                                  BorderRadius.circular(SeeURadii.medium),
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
                      Expanded(
                        child: SeeUEmptyState(
                          icon: PhosphorIcons.usersThree(),
                          title: 'Пока нет взаимных подписчиков',
                          subtitle:
                              'Когда появятся — можно выбрать кто тебя видит.',
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

    return Tappable.faded(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: c.line, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: c.surface2,
              backgroundImage: user.avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(user.avatarUrl,
                      maxWidth: 120, maxHeight: 120)
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
