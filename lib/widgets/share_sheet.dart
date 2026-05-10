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

/// Shows a chat list as a bottom sheet. Tapping a chat sends the given post
/// as an attached message (kind = "shared_post").
Future<void> _showChatPicker(BuildContext context, {required String postId}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => Consumer(
      builder: (consumerCtx, ref, _) {
        // Показываем все чаты — direct и group. Для группы используется
        // title и cover_url (или fallback heroOrange-плейсхолдер).
        final chatList = ref.watch(chatListProvider).chats;
        final c = consumerCtx.seeuColors;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(consumerCtx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.paperPlaneTilt(),
                          color: SeeUColors.accent),
                      const SizedBox(width: 8),
                      Text('Переслать в чат',
                          style: SeeUTypography.body
                              .copyWith(fontWeight: FontWeight.w600)),
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
                          itemCount: chatList.length,
                          itemBuilder: (_, i) {
                            final chat = chatList[i];
                            final isGroup = chat.isGroup;
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
                              title: Text(label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: subLabel.isNotEmpty
                                  ? Text(subLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12, color: c.ink2))
                                  : null,
                              trailing: isGroup
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: SeeUColors.accent
                                            .withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(
                                            99),
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
                                    )
                                  : null,
                              onTap: () async {
                                Navigator.pop(sheetCtx);
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                try {
                                  final api = ref.read(apiClientProvider);
                                  await api.post(
                                    ApiEndpoints.chatMessages(chat.id),
                                    data: {
                                      'text': '',
                                      'attached_post_id': postId,
                                    },
                                  );
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(isGroup
                                          ? 'Отправлено в «${chat.title}»'
                                          : 'Отправлено @${chat.otherUser?.username ?? ''}'),
                                    ),
                                  );
                                } on DioException catch (e) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Не отправилось: ${apiErrorMessage(e)}'),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
