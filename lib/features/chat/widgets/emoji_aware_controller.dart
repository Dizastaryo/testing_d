import 'package:flutter/material.dart';

/// TextEditingController that renders emojis proportionally larger than
/// surrounding text. Emoji size = base * (18/14) ≈ +28%.
class EmojiAwareController extends TextEditingController {
  static final _emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}][\u{1F3FB}-\u{1F3FF}]?(?:\u{200D}[\u{1F300}-\u{1FAFF}][\u{1F3FB}-\u{1F3FF}]?)*'
    r'|[\u{2600}-\u{27BF}]\u{FE0F}?'
    r'|[\u{1F1E0}-\u{1F1FF}][\u{1F1E0}-\u{1F1FF}]'
    r'|[\u{1F000}-\u{1F02F}]|[\u{1F0A0}-\u{1F0FF}]',
    unicode: true,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = text;
    // Fast path: no emoji candidates
    if (t.runes.every((r) => r < 0x2194)) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }

    final baseSize = style?.fontSize ?? 14.0;
    final emojiSize = baseSize * (18 / 14);

    final spans = <TextSpan>[];
    int cursor = 0;
    for (final m in _emojiRegex.allMatches(t)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: t.substring(cursor, m.start), style: style));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: style?.copyWith(fontSize: emojiSize) ??
            TextStyle(fontSize: emojiSize),
      ));
      cursor = m.end;
    }
    if (cursor < t.length) {
      spans.add(TextSpan(text: t.substring(cursor), style: style));
    }

    if (spans.isEmpty) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }

    // Handle composing region underline (IME on Android/iOS)
    if (!value.isComposingRangeValid || !withComposing) {
      return TextSpan(style: style, children: spans);
    }

    final composingStyle =
        style?.merge(const TextStyle(decoration: TextDecoration.underline)) ??
            const TextStyle(decoration: TextDecoration.underline);
    return TextSpan(
      style: style,
      children: [
        TextSpan(
            text: t.substring(0, value.composing.start), style: style),
        TextSpan(
            text: t.substring(
                value.composing.start, value.composing.end),
            style: composingStyle),
        TextSpan(text: t.substring(value.composing.end), style: style),
      ],
    );
  }
}
