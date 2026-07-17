import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/user_provider.dart';
import 'widgets/profile_content_tabs.dart';

/// Сохранённые публикации — отдельный экран. Открывается из «Настроек»
/// (раньше был в шапке профиля / меню «Создать»). [username] null → текущий
/// пользователь.
class SavedPostsScreen extends ConsumerStatefulWidget {
  final String? username;
  const SavedPostsScreen({super.key, this.username});

  @override
  ConsumerState<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<SavedPostsScreen> {
  late final String _username;

  @override
  void initState() {
    super.initState();
    _username =
        widget.username ?? ref.read(authProvider).user?.username ?? '';
    if (_username.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(userProfileProvider(_username).notifier).loadSavedPosts();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(), color: c.ink, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Сохранённое', style: SeeUTypography.subtitle),
      ),
      body: SafeArea(
        child: _username.isEmpty
            ? const SeeUEmptyState(
                icon: PhosphorIconsRegular.bookmarkSimple,
                title: 'Пока ничего не сохранено',
                subtitle:
                    'Сохраняйте публикации закладкой — они появятся здесь',
              )
            : Consumer(builder: (context, ref, _) {
                final state = ref.watch(userProfileProvider(_username));
                if (state.savedPostsLoading && state.savedPosts.isEmpty) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: SeeUColors.accent));
                }
                if (state.savedPostsError && state.savedPosts.isEmpty) {
                  return SeeUErrorState(
                    error: 'Не удалось загрузить сохранённое',
                    onRetry: () => ref
                        .read(userProfileProvider(_username).notifier)
                        .loadSavedPosts(),
                  );
                }
                if (state.savedPosts.isEmpty) {
                  return const SeeUEmptyState(
                    icon: PhosphorIconsRegular.bookmarkSimple,
                    title: 'Пока ничего не сохранено',
                    subtitle:
                        'Сохраняйте публикации закладкой — они появятся здесь',
                  );
                }
                return ProfilePostsGrid(posts: state.savedPosts);
              }),
      ),
    );
  }
}
