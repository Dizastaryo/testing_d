import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';
import '../core/design/design.dart';
import '../core/providers/chat_provider.dart';

/// Builds the public deep link to a post. Used for both clipboard и share sheet.
String postShareUrl(String postId) => 'https://seeu.app/post/$postId';

String userShareUrl(String username) => 'https://seeu.app/u/$username';

/// Shows a bottom sheet with «Скопировать ссылку», «Поделиться через…»
/// and any extra options the caller provides.
///
/// `forwardablePostId` enables a «Переслать в SeeU» action that opens an
/// inline chat picker and sends the post as an attachment.
Future<void> showShareSheet({
  required BuildContext context,
  required String url,
  required String title,
  String? subtitle,
  String? forwardablePostId,
  List<Widget> extra = const [],
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      final c = context.seeuColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Icon(PhosphorIcons.shareNetwork(),
                        color: SeeUColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: SeeUTypography.body
                                  .copyWith(fontWeight: FontWeight.w600)),
                          if (subtitle != null && subtitle.isNotEmpty)
                            Text(subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SeeUTypography.caption
                                    .copyWith(color: c.ink2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.line),
              ListTile(
                leading: Icon(PhosphorIcons.linkSimple(), color: c.ink),
                title: const Text('Скопировать ссылку'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await Clipboard.setData(ClipboardData(text: url));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ссылка скопирована')),
                  );
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.share(), color: c.ink),
                title: const Text('Поделиться через…'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final text = subtitle != null && subtitle.isNotEmpty
                      ? '$subtitle\n$url'
                      : url;
                  await Share.share(text, subject: title);
                },
              ),
              if (forwardablePostId != null && forwardablePostId.isNotEmpty)
                ListTile(
                  leading: Icon(PhosphorIcons.paperPlaneTilt(),
                      color: SeeUColors.accent),
                  title: const Text('Переслать в SeeU'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _showChatPicker(context, postId: forwardablePostId);
                  },
                ),
              ...extra,
            ],
          ),
        ),
      );
    },
  );
}

/// Shows a chat list as a bottom sheet with **multi-select**. Юзер выбирает
/// один или несколько чатов (direct + group), затем тапает «Отправить» и пост
/// разлетается во все выбранные через `attached_post_id` (kind="shared_post").
/// Реализован через [_ForwardChatPicker] с собственным state'ом.
Future<void> _showChatPicker(BuildContext context, {required String postId}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ForwardChatPicker(postId: postId),
  );
}

class _ForwardChatPicker extends ConsumerStatefulWidget {
  final String postId;
  const _ForwardChatPicker({required this.postId});

  @override
  ConsumerState<_ForwardChatPicker> createState() => _ForwardChatPickerState();
}

class _ForwardChatPickerState extends ConsumerState<_ForwardChatPicker> {
  final Set<String> _selected = {};
  bool _submitting = false;

  void _toggle(String chatId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.add(chatId)) {
        _selected.remove(chatId);
      }
    });
  }

  /// Russian-plural для «N чат(а/ов)». 1 = чат, 2-4 = чата, 5+ = чатов.
  String _pluralChats(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'чат';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'чата';
    }
    return 'чатов';
  }

  Future<void> _submit() async {
    if (_selected.isEmpty || _submitting) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);

    final api = ref.read(apiClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Параллельный fan-out — каждый POST в свой chat независим. Ошибки
    // изолированы per-chat: одна не должна потопить остальные.
    final results = await Future.wait(_selected.map<Future<bool>>((chatId) async {
      try {
        await api.post(
          ApiEndpoints.chatMessages(chatId),
          data: {
            'text': '',
            'attached_post_id': widget.postId,
          },
        );
        return true;
      } on DioException {
        return false;
      } catch (_) {
        return false;
      }
    }));

    final total = results.length;
    final ok = results.where((r) => r).length;
    final fail = total - ok;

    if (!mounted) return;
    navigator.pop();
    final msg = fail == 0
        ? 'Отправлено в $ok ${_pluralChats(ok)}'
        : 'Отправлено в $ok из $total · ошибки: $fail';
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final chatList = ref.watch(chatListProvider).chats;
    final c = context.seeuColors;
    final count = _selected.length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildBody(chatList, c, count),
            ),
            // Bottom-bar — slide-in / fade-in когда есть выбор. Disabled
            // во время отправки (показывает spinner вместо текста).
            if (count > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildSubmitBar(count, c),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(List<Chat> chatList, SeeUThemeColors c, int count) {
    return [
            // Header — иконка + заголовок + counter «N выбрано»
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Icon(PhosphorIcons.paperPlaneTilt(),
                      color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Переслать в чат',
                        style: SeeUTypography.body
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$count выбрано',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: SeeUColors.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),
            Expanded(
              child: chatList.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text('У вас пока нет чатов',
                            style: TextStyle(color: c.ink2)),
                      ),
                    )
                  : ListView.builder(
                      // bottom padding под bottom-bar чтобы последний tile
                      // не уезжал под кнопку «Отправить»
                      padding: EdgeInsets.only(bottom: count > 0 ? 88 : 8),
                      itemCount: chatList.length,
                      itemBuilder: (_, i) {
                        final chat = chatList[i];
                        final isGroup = chat.isGroup;
                        final isSelected = _selected.contains(chat.id);
                        // Avatar logic: group → cover_url + group-fallback,
                        // direct → otherUser avatar.
                        final avatar = isGroup
                            ? chat.coverUrl
                            : (chat.otherUser?.avatarUrl ?? '');
                        final label = isGroup
                            ? chat.title
                            : '@${chat.otherUser?.username ?? ''}';
                        final subLabel = isGroup
                            ? '${chat.participantsCount} участников'
                            : (chat.lastMessage.isNotEmpty
                                ? chat.lastMessage
                                : '');
                        return ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: isGroup && avatar.isEmpty
                                  ? SeeUGradients.heroOrange
                                  : null,
                              color: avatar.isEmpty && !isGroup
                                  ? c.surface2
                                  : null,
                              image: avatar.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(avatar),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: avatar.isEmpty && isGroup
                                ? const Icon(
                                    PhosphorIconsBold.usersThree,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(label,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (isGroup) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: SeeUColors.accent
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: const Text(
                                    'группа',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: SeeUColors.accent,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: subLabel.isNotEmpty
                              ? Text(subLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: c.ink2))
                              : null,
                          trailing: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? SeeUColors.accent
                                  : Colors.transparent,
                              border: isSelected
                                  ? null
                                  : Border.all(
                                      color:
                                          c.ink3.withValues(alpha: 0.5),
                                      width: 1.5,
                                    ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 16)
                                : null,
                          ),
                          onTap: () => _toggle(chat.id),
                        );
                      },
                    ),
            ),
    ];
  }

  Widget _buildSubmitBar(int count, SeeUThemeColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: GestureDetector(
        onTap: _submitting ? null : _submit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          decoration: BoxDecoration(
            gradient: _submitting ? null : SeeUGradients.heroOrange,
            color: _submitting
                ? SeeUColors.accent.withValues(alpha: 0.6)
                : null,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  'Отправить в $count ${_pluralChats(count)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Wrapper для bottom-bar — рендерится поверх sheet'а, виден только когда
/// что-то выбрано. Использует `Positioned` через Stack во внешнем builder'е…
/// см. _ForwardChatPicker.build — pаdding tile-листа добавляет место под него.
//
// Note: bottom-bar реализован inline в [_ForwardChatPickerState.build] как
// часть Stack — если потребуется выделить отдельным widget'ом, легко вынести.
