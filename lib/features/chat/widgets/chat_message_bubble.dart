import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/design.dart';
import '../../../core/providers/chat_provider.dart';
import 'video_bubble.dart';
import 'voice_bubble.dart';

// ---------------------------------------------------------------------------
// Icebreaker chip
// ---------------------------------------------------------------------------

class ChatIcebreakerChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const ChatIcebreakerChip({super.key, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(
            color: SeeUColors.accent.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: SeeUTypography.caption.copyWith(
            color: SeeUColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date separator
// ---------------------------------------------------------------------------

class ChatDateSeparator extends StatelessWidget {
  final String label;
  const ChatDateSeparator({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line, width: 0.5),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          boxShadow: SeeUShadows.sm,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: c.ink3,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble with reactions and read receipts
// ---------------------------------------------------------------------------

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showTail;
  final String? reaction;
  final Map<String, int> allReactions;
  final VoidCallback onLongPress;
  final VoidCallback? onDoubleTap;
  final void Function(String emoji) onReactionSelected;
  /// B7: avatar URL for the last message in a cluster (other user only).
  final String? senderAvatarUrl;
  /// Group chat: имя отправителя (показывается над баблом для чужих сообщений).
  final String? senderName;
  final bool isGroup;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showTail = true,
    this.reaction,
    this.allReactions = const {},
    required this.onLongPress,
    this.onDoubleTap,
    required this.onReactionSelected,
    this.senderAvatarUrl,
    this.senderName,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final localTime = message.createdAt.toLocal();
    final time =
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';

    // B6: grouping — 8px between different authors, 4px same author
    return Padding(
      padding: EdgeInsets.only(
        top: showTail ? 8 : 4,
        bottom: allReactions.isNotEmpty ? 22 : 0,
        left: isMine ? 48 : 0,
        right: isMine ? 0 : 48,
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Имя отправителя для group-чата (первое сообщение в кластере)
          if (isGroup && !isMine && showTail && senderName != null && senderName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 34, bottom: 2),
              child: Text(
                senderName!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _senderColor(senderName!),
                ),
              ),
            ),
          GestureDetector(
            onLongPress: onLongPress,
            onDoubleTap: onDoubleTap,
            child: Row(
              mainAxisAlignment:
                  isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // B7: small avatar for last message in other user's cluster
                if (!isMine)
                  SizedBox(
                    width: 28,
                    child: showTail
                        ? Padding(
                            padding: const EdgeInsets.only(right: 6, bottom: 2),
                            child: _buildSenderAvatar(c),
                          )
                        : const SizedBox.shrink(),
                  ),
                Flexible(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildBubbleContainer(message, isMine, c, time),
                      if (allReactions.isNotEmpty)
                        Positioned(
                          bottom: -14,
                          right: isMine ? 8 : null,
                          left: isMine ? null : 8,
                          child: Wrap(
                            spacing: 4,
                            children: allReactions.entries
                                .map((e) => GestureDetector(
                                      onTap: () => onReactionSelected(e.key),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: e.key == reaction
                                              ? SeeUColors.accentSoft
                                              : c.surface,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: SeeUShadows.sm,
                                          border: e.key == reaction
                                              ? Border.all(
                                                  color: SeeUColors.accent,
                                                  width: 0.8)
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(e.key,
                                                style: const TextStyle(
                                                    fontSize: 13)),
                                            if (e.value > 1) ...[
                                              const SizedBox(width: 3),
                                              Text('${e.value}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: c.ink2,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                // Time + receipts now inside bubble (B4)
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// F3: detect emoji-only messages (1-3 emoji, no other text).
  /// Uses code-point heuristic: short text, no ASCII letters/digits/whitespace,
  /// all runes above basic Latin. Covers standard emoji + ZWJ sequences.
  static bool _isEmojiOnlyText(String text) {
    if (text.isEmpty || text.length > 36) return false;
    if (RegExp(r'[a-zA-Z0-9\s]').hasMatch(text)) return false;
    // Разрешаем:
    // • emoji-блоки Unicode (>= 0x2600)
    // • ZWJ 0x200D — склеивает семейные/профессиональные emoji (👨‍👩‍👧)
    // • Variation selectors 0xFE00-0xFE0F — emoji vs text representation
    // • Skin-tone modifiers 0x1F3FB-0x1F3FF
    // • Regional indicators 0x1F1E0-0x1F1FF — флаги (🇷🇺)
    return text.runes.every((r) =>
        r >= 0x2600 ||
        r == 0x200D ||
        (r >= 0xFE00 && r <= 0xFE0F) ||
        (r >= 0x1F3FB && r <= 0x1F3FF) ||
        (r >= 0x1F1E0 && r <= 0x1F1FF));
  }

  bool _isEmojiOnly(ChatMessage msg) {
    if (msg.kind == 'deleted' || msg.isDeletedForAll) return false;
    if (msg.kind != 'text' && msg.kind.isNotEmpty) return false;
    if (msg.replyTo != null) return false;
    return _isEmojiOnlyText(msg.text.trim());
  }

  /// Counts visible emoji units (excludes ZWJ, variation selectors, skin tones).
  static int _countEmojiUnits(String text) {
    int count = 0;
    for (final r in text.runes) {
      if (r == 0x200D) continue; // ZWJ
      if (r >= 0xFE00 && r <= 0xFE0F) continue; // variation selectors
      if (r >= 0x1F3FB && r <= 0x1F3FF) continue; // skin tone modifiers
      count++;
    }
    return count;
  }

  // B1/B2/B3/B4/B5: Redesigned bubble container with gradient, inline time
  Widget _buildBubbleContainer(
      ChatMessage msg, bool mine, SeeUThemeColors c, String time) {
    // time передаётся дальше в _buildBubbleContent для голосовых сообщений
    // (у них нет внешнего time-row из-за `if (!isVoice)` условия ниже).
    // F3: emoji-only → big emoji with subtle pill background
    if (_isEmojiOnly(msg)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: mine
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF6B4A), Color(0xFFFF4A30)],
                )
              : null,
          color: mine ? null : c.surface2.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              msg.text.trim(),
              style: TextStyle(
                fontSize: _countEmojiUnits(msg.text.trim()) <= 3 ? 48.0 : 36.0,
                height: 1.1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(time, style: TextStyle(fontSize: 10, color: mine ? Colors.white.withValues(alpha: 0.65) : c.ink3)),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      (msg.isRead || msg.isDelivered)
                          ? PhosphorIconsBold.checks
                          : PhosphorIconsRegular.check,
                      size: 14,
                      color: msg.isRead ? Colors.white : const Color(0xBBFFFFFF),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isVoice = msg.kind == 'voice' || msg.kind == 'audio';
    final isVideoNote = (msg.kind == 'video' || msg.kind == 'video_note') &&
        (msg.attachedMediaType == 'video_note' || msg.kind == 'video_note');
    final isVideo = (msg.kind == 'video' || msg.kind == 'video_note') &&
        msg.attachedMediaUrl.isNotEmpty;
    final isSticker =
        msg.kind == 'image' && msg.attachedMediaType == 'sticker';
    final isMedia = (msg.kind == 'shared_post' && msg.attachedPost != null) ||
        (msg.kind == 'image' && msg.attachedMediaUrl.isNotEmpty);

    final bubblePadding = isSticker
        ? EdgeInsets.zero
        : isMedia
            ? const EdgeInsets.all(4)
            : (isVoice || isVideo)
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(12, 8, 12, 4); // B5: compact

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(mine ? 20 : 8), // B3: 4→8
      bottomRight: Radius.circular(mine ? 8 : 20), // B3: 4→8
    );

    return Container(
      padding: bubblePadding,
      decoration: isVoice || isSticker || isVideo
          ? null
          : BoxDecoration(
              gradient: mine
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF6B4A), Color(0xFFFF4A30)],
                    )
                  : null,
              color: mine ? null : c.surface,
              borderRadius: bubbleRadius,
              border: mine
                  ? null
                  : Border.all(color: c.line, width: 0.5),
              boxShadow: mine ? null : SeeUShadows.sm,
            ),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (msg.forwardedFromSender.isNotEmpty) ...[
            _buildForwardedBanner(msg.forwardedFromSender, mine, c),
            const SizedBox(height: 2),
          ],
          if (msg.replyTo != null) ...[
            _buildReplyQuoted(msg.replyTo!, mine, c),
            const SizedBox(height: 4),
          ],
          _buildBubbleContent(msg, mine, c, time),
          // B4: inline time + receipts inside bubble (для голосовых и видео — внутри их виджетов)
          if (!isVoice && !isVideoNote)
            Padding(
              padding: isSticker
                  ? const EdgeInsets.fromLTRB(4, 2, 4, 0)
                  : isMedia
                      ? const EdgeInsets.fromLTRB(8, 4, 4, 2)
                      : const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (msg.expiresAt != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChatTtlCountdown(
                        expiresAt: msg.expiresAt!,
                        chatId: msg.chatId,
                        messageId: msg.id,
                      ),
                    ),
                  Text(time,
                      style: TextStyle(
                        fontSize: 11,
                        color: (mine && !isSticker)
                            ? const Color(0xDDFFFFFF)
                            : c.ink3,
                      )),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      (msg.isRead || msg.isDelivered)
                          ? PhosphorIconsBold.checks
                          : PhosphorIconsRegular.check,
                      size: 14,
                      color: msg.isRead ? Colors.white : const Color(0xBBFFFFFF),
                    ),
                    if (msg.recipientsCount > 1 &&
                        msg.readCount > 0 &&
                        msg.readCount < msg.recipientsCount)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Text(
                          '${msg.readCount}/${msg.recipientsCount}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xDDFFFFFF),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildForwardedBanner(String sender, bool isMine, SeeUThemeColors c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          PhosphorIconsRegular.arrowBendUpRight,
          size: 11,
          color: isMine ? Colors.white.withValues(alpha: 0.7) : SeeUColors.accent,
        ),
        const SizedBox(width: 4),
        Text(
          'Переслано от @$sender',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isMine ? Colors.white.withValues(alpha: 0.7) : SeeUColors.accent,
          ),
        ),
      ],
    );
  }

  Widget _buildReplyQuoted(
      ReplyPreview reply, bool isMine, SeeUThemeColors c) {
    final stripeColor = isMine ? Colors.white : SeeUColors.accent;
    final titleColor = isMine ? Colors.white : SeeUColors.accent;
    final textColor = isMine ? Colors.white70 : c.ink2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.15)
            : c.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 4, color: stripeColor),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('@${reply.senderUsername}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: titleColor)),
                  const SizedBox(height: 1),
                  Text(reply.shortLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: textColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleContent(
      ChatMessage message, bool isMine, SeeUThemeColors c, String time) {
    // Сообщение удалено для всех
    if (message.kind == 'deleted' || message.isDeletedForAll) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.prohibit,
            size: 14,
            color: isMine ? Colors.white60 : c.ink3,
          ),
          const SizedBox(width: 6),
          Text(
            'Сообщение удалено',
            style: SeeUTypography.body.copyWith(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: isMine ? Colors.white60 : c.ink3,
            ),
          ),
        ],
      );
    }
    if (message.kind == 'shared_post' && message.attachedPost != null) {
      return ChatSharedPostPreview(
        post: message.attachedPost!,
        isMine: isMine,
        trailingText: message.text,
      );
    }
    if (message.kind == 'image' &&
        message.attachedMediaType == 'sticker' &&
        message.attachedMediaUrl.isNotEmpty) {
      final absUrl = AppConfig.absUrl(message.attachedMediaUrl);
      return CachedNetworkImage(
        imageUrl: absUrl,
        width: 140,
        height: 140,
        fit: BoxFit.contain,
        placeholder: (_, __) =>
            const SizedBox(width: 140, height: 140),
        errorWidget: (_, __, ___) =>
            const SizedBox(width: 140, height: 140),
      );
    }
    if (message.kind == 'image' && message.attachedMediaUrl.isNotEmpty) {
      return ChatImageAttachment(
        url: message.attachedMediaUrl,
        isMine: isMine,
        trailingText: message.text,
      );
    }
    if ((message.kind == 'video' || message.kind == 'video_note') &&
        message.attachedMediaUrl.isNotEmpty) {
      final url = message.attachedMediaUrl.startsWith('http')
          ? message.attachedMediaUrl
          : '${AppConfig.apiOrigin}${message.attachedMediaUrl}';
      if (message.attachedMediaType == 'video_note' ||
          message.kind == 'video_note') {
        return VideoNoteBubble(
          videoUrl: url,
          isMine: isMine,
          sentTimeLabel: time,
          isRead: message.isRead,
          isDelivered: message.isDelivered,
        );
      }
      return VideoBubble(
        videoUrl: url,
        isMine: isMine,
        sentTimeLabel: time,
        isRead: message.isRead,
        isDelivered: message.isDelivered,
      );
    }
    if ((message.kind == 'voice' || message.kind == 'audio') &&
        message.attachedMediaUrl.isNotEmpty) {
      final url = message.attachedMediaUrl.startsWith('http')
          ? message.attachedMediaUrl
          : '${AppConfig.apiOrigin}${message.attachedMediaUrl}';
      return VoiceBubble(
        audioUrl: url,
        durationSec: message.mediaDurationSeconds,
        waveformSamples:
            message.waveform.isNotEmpty ? message.waveform : null,
        isMine: isMine,
        chatId: message.chatId,
        messageId: message.id,
        sentTimeLabel: time,
        isRead: message.isRead,
        isDelivered: message.isDelivered,
      );
    }
    return _buildMixedText(
      message.text,
      textColor: isMine ? Colors.white : c.ink,
    );
  }

  /// Renders text with emojis slightly larger (18px) than surrounding text (14px).
  static Widget _buildMixedText(String text, {required Color textColor}) {
    // Fast path: ASCII-only, no emojis
    if (text.runes.every((r) => r < 0x2194)) {
      return Text(
        text,
        style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
      );
    }

    // Matches emoji sequences: base + optional skin tone + ZWJ chains + flags
    final emojiRegex = RegExp(
      r'[\u{1F300}-\u{1FAFF}][\u{1F3FB}-\u{1F3FF}]?(?:\u{200D}[\u{1F300}-\u{1FAFF}][\u{1F3FB}-\u{1F3FF}]?)*'
      r'|[\u{2600}-\u{27BF}]\u{FE0F}?'
      r'|[\u{1F1E0}-\u{1F1FF}][\u{1F1E0}-\u{1F1FF}]'
      r'|[\u{1F000}-\u{1F02F}]|[\u{1F0A0}-\u{1F0FF}]',
      unicode: true,
    );

    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final m in emojiRegex.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, m.start),
          style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
        ));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(fontSize: 18, height: 1.3, color: textColor),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
      ));
    }

    if (spans.length == 1 && spans.first is TextSpan &&
        (spans.first as TextSpan).style?.fontSize == 14) {
      // No emoji found by regex
      return Text(text, style: TextStyle(fontSize: 14, color: textColor, height: 1.4));
    }

    return RichText(
      text: TextSpan(children: spans),
      overflow: TextOverflow.clip,
    );
  }

  static const _nameColors = [
    Color(0xFFE05C5C), Color(0xFF5C8BE0), Color(0xFF5CB87A),
    Color(0xFFE09E5C), Color(0xFF9E5CE0), Color(0xFF5CCCE0),
    Color(0xFFE05CA3), Color(0xFF7A9E5C),
  ];

  Color _senderColor(String name) {
    final idx = (name.codeUnitAt(0) + name.length) % _nameColors.length;
    return _nameColors[idx];
  }

  /// Строит аватарку отправителя: фото профиля или инициалы/иконка.
  Widget _buildSenderAvatar(SeeUThemeColors c) {
    final hasUrl = senderAvatarUrl != null && senderAvatarUrl!.isNotEmpty;
    final name = senderName ?? '';
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join()
        : '';
    final color = name.isNotEmpty ? _senderColor(name) : c.surface2;

    return CircleAvatar(
      radius: 11,
      backgroundColor: hasUrl ? c.surface2 : color,
      backgroundImage: hasUrl ? CachedNetworkImageProvider(senderAvatarUrl!) : null,
      child: hasUrl
          ? null
          : initials.isNotEmpty
              ? Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                )
              : Icon(PhosphorIconsRegular.user, size: 10, color: Colors.white),
    );
  }
}

// ---------------------------------------------------------------------------
// Small avatar for app bar
// ---------------------------------------------------------------------------

class ChatSmallAvatar extends StatelessWidget {
  final String? avatarUrl;
  final bool isOnline;
  final double size;
  final bool isGroup;

  const ChatSmallAvatar({
    super.key,
    this.avatarUrl,
    this.isOnline = false,
    this.size = 36,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    final placeholder = Container(
      decoration: isGroup
          ? const BoxDecoration(
              shape: BoxShape.circle, gradient: SeeUGradients.heroOrange)
          : BoxDecoration(shape: BoxShape.circle, color: c.surface2),
      child: Icon(
        isGroup ? PhosphorIconsBold.usersThree : PhosphorIconsRegular.user,
        size: size * 0.45,
        color: isGroup ? Colors.white : c.ink3,
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface2),
            clipBehavior: Clip.antiAlias,
            child: hasUrl
                ? CachedNetworkImage(
                    imageUrl: avatarUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => placeholder,
                    errorWidget: (_, __, ___) => placeholder,
                  )
                : placeholder,
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  color: SeeUColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared post preview rendered inside a chat bubble
// ---------------------------------------------------------------------------

class ChatSharedPostPreview extends StatelessWidget {
  final AttachedPostShort post;
  final bool isMine;
  final String trailingText;
  const ChatSharedPostPreview({
    super.key,
    required this.post,
    required this.isMine,
    required this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final preview =
        post.thumbnailUrl.isNotEmpty ? post.thumbnailUrl : post.mediaUrl;
    final fg = isMine ? Colors.white : c.ink;
    final fgSoft = isMine ? Colors.white.withValues(alpha: 0.85) : c.ink2;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => context.push('/post/${post.id}'),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.15)
                    : c.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: preview.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: preview,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: c.line),
                            errorWidget: (_, __, ___) =>
                                Container(color: c.line),
                          )
                        : Container(color: c.line),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          post.authorUsername.isNotEmpty
                              ? '@${post.authorUsername}'
                              : 'SeeU',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeeUTypography.body.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: fg),
                        ),
                        if (post.caption.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(post.caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SeeUTypography.body.copyWith(
                                  fontSize: 11, color: fgSoft, height: 1.3)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (trailingText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(trailingText,
                  style: SeeUTypography.body.copyWith(
                      fontSize: 14, color: fg, height: 1.4)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image attachment rendered inside a chat bubble
// ---------------------------------------------------------------------------

class ChatImageAttachment extends StatelessWidget {
  final String url;
  final bool isMine;
  final String trailingText;
  const ChatImageAttachment({
    super.key,
    required this.url,
    required this.isMine,
    required this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final fg = isMine ? Colors.white : c.ink;
    final absUrl = url.startsWith('http')
        ? url
        : (url.startsWith('/') ? '${AppConfig.apiOrigin}$url' : url);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxHeight: 320, minHeight: 120, minWidth: 180),
              child: CachedNetworkImage(
                imageUrl: absUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: c.line, height: 200, width: 180),
                errorWidget: (_, __, ___) => Container(
                  color: c.line,
                  height: 120,
                  width: 180,
                  child: Icon(PhosphorIconsRegular.imageBroken,
                      color: c.ink3, size: 32),
                ),
              ),
            ),
          ),
          if (trailingText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(trailingText,
                  style: SeeUTypography.body.copyWith(
                      fontSize: 14, color: fg, height: 1.4)),
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// CHAT-11: TTL countdown bubble
// ===========================================================================

class ChatTtlCountdown extends ConsumerStatefulWidget {
  final DateTime expiresAt;
  final String chatId;
  final String messageId;

  const ChatTtlCountdown({
    super.key,
    required this.expiresAt,
    required this.chatId,
    required this.messageId,
  });

  @override
  ConsumerState<ChatTtlCountdown> createState() => _ChatTtlCountdownState();
}

class _ChatTtlCountdownState extends ConsumerState<ChatTtlCountdown> {
  Timer? _ticker;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  /// Рекурсивный таймер: интервал адаптируется к оставшемуся времени.
  /// < 60с → тикает каждую секунду; < 1ч → каждые 15с; иначе → каждые 30с.
  /// Это решает проблему фиксированного интервала который не переключался
  /// при пересечении границы в 1 минуту.
  void _scheduleTick() {
    _ticker?.cancel();
    if (_removed || !mounted) return;
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      if (!_removed) {
        _removed = true;
        ref
            .read(chatMessagesProvider(widget.chatId).notifier)
            .removeMessageLocally(widget.messageId);
      }
      return;
    }
    final interval = remaining.inSeconds < 60
        ? const Duration(seconds: 1)
        : remaining.inMinutes < 60
            ? const Duration(seconds: 15)
            : const Duration(seconds: 30);
    _ticker = Timer(interval, () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    if (d.isNegative) return '0с';
    if (d.inDays >= 1) return '${d.inDays}д';
    if (d.inHours >= 1) {
      final mins = d.inMinutes.remainder(60);
      return mins == 0 ? '${d.inHours}ч' : '${d.inHours}ч $minsм';
    }
    if (d.inMinutes >= 1) return '${d.inMinutes}м';
    return '${d.inSeconds}с';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return const SizedBox.shrink();
    final c = context.seeuColors;
    final urgent = remaining.inMinutes < 5;
    final warning = remaining.inHours < 1;
    final color = urgent
        ? SeeUColors.error
        : warning
            ? SeeUColors.accent
            : c.ink3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(PhosphorIconsFill.timer, size: 11, color: color),
        const SizedBox(width: 2),
        Text(
          _format(remaining),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 3),
      ],
    );
  }
}
