/// Canonical emoji sets for quick-reaction UI.
///
/// Three places used to define their own copy of the same 5 emojis:
/// post_card, stories_row, chat_screen. Removing the dupes keeps the picker
/// visually consistent across feed/stories/chat (was an audit-flagged
/// inconsistency: a divergent list would have made post-reactions, story
/// reactions and message reactions feel like separate features).
///
/// To change the set, edit *here only*.
library;

/// 5-emoji quick-reaction set. Order = display order in the picker:
/// fire / heart / laugh / mind-blown / clap.
const List<String> kQuickReactionEmojis = <String>[
  '\u{1F525}',         // 🔥
  '\u{2764}\u{FE0F}',  // ❤️
  '\u{1F602}',         // 😂
  '\u{1F92F}',         // 🤯
  '\u{1F44F}',         // 👏
];
