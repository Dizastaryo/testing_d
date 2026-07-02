import 'package:flutter/material.dart';

class AudioSubcategoryModel {
  final String id;
  final String titleRu;
  final String titleEn;
  final int trackCount;

  const AudioSubcategoryModel({
    required this.id,
    required this.titleRu,
    required this.titleEn,
    this.trackCount = 0,
  });

  factory AudioSubcategoryModel.fromJson(Map<String, dynamic> j) =>
      AudioSubcategoryModel(
        id: j['id'] ?? '',
        titleRu: j['title_ru'] ?? '',
        titleEn: j['title_en'] ?? '',
        trackCount: (j['track_count'] as num?)?.toInt() ?? 0,
      );

  AudioSubcategoryModel withCount(int count) => AudioSubcategoryModel(
        id: id, titleRu: titleRu, titleEn: titleEn, trackCount: count);
}

class AudioCategoryModel {
  final String id;
  final String titleRu;
  final String titleEn;
  final String description;
  final String icon;
  final int trackCount;
  final List<AudioSubcategoryModel> subcategories;

  const AudioCategoryModel({
    required this.id,
    required this.titleRu,
    required this.titleEn,
    required this.description,
    required this.icon,
    this.trackCount = 0,
    this.subcategories = const [],
  });

  factory AudioCategoryModel.fromJson(Map<String, dynamic> j) =>
      AudioCategoryModel(
        id: j['id'] ?? '',
        titleRu: j['title_ru'] ?? '',
        titleEn: j['title_en'] ?? '',
        description: j['description'] ?? '',
        icon: j['icon'] ?? '',
        trackCount: (j['track_count'] as num?)?.toInt() ?? 0,
        subcategories: (j['subcategories'] as List? ?? [])
            .map((e) =>
                AudioSubcategoryModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String get title => titleRu;

  IconData get iconData => _iconMap[icon] ?? Icons.music_note_rounded;

  Color get color => _colorMap[id] ?? const Color(0xFF6B6560);
}

const _iconMap = <String, IconData>{
  'music_note': Icons.music_note_rounded,
  'smiley': Icons.sentiment_very_satisfied_rounded,
  'book_open': Icons.menu_book_rounded,
  'microphone': Icons.mic_rounded,
  'graduation_cap': Icons.school_rounded,
  'spiral': Icons.self_improvement_rounded,
  'newspaper': Icons.newspaper_rounded,
  'piano_keys': Icons.piano_rounded,
  'dots_three': Icons.more_horiz_rounded,
};

const _colorMap = <String, Color>{
  'music': Color(0xFFFF5A3C),
  'memes': Color(0xFFFF8C42),
  'audiobooks': Color(0xFF4A90D9),
  'podcasts': Color(0xFF7B5EA7),
  'education': Color(0xFF2FA84F),
  'meditation': Color(0xFF58B4AE),
  'news': Color(0xFF3A7BD5),
  'instrumental': Color(0xFFE67E22),
  'other': Color(0xFF8A847C),
};

/// Canonical category list — single source of truth.
/// Backend keeps an identical list in domain/audio.go (KnownCategories).
const kAudioCategories = <AudioCategoryModel>[
  AudioCategoryModel(
    id: 'music',
    titleRu: 'Музыка',
    titleEn: 'Music',
    description: 'Треки всех жанров',
    icon: 'music_note',
    subcategories: [
      AudioSubcategoryModel(id: 'pop', titleRu: 'Поп', titleEn: 'Pop'),
      AudioSubcategoryModel(id: 'hip_hop', titleRu: 'Hip-Hop', titleEn: 'Hip-Hop'),
      AudioSubcategoryModel(id: 'rap', titleRu: 'Рэп', titleEn: 'Rap'),
      AudioSubcategoryModel(id: 'rnb', titleRu: 'R&B', titleEn: 'R&B'),
      AudioSubcategoryModel(id: 'rock', titleRu: 'Рок', titleEn: 'Rock'),
      AudioSubcategoryModel(id: 'electronic', titleRu: 'Электронная', titleEn: 'Electronic'),
      AudioSubcategoryModel(id: 'dance', titleRu: 'Dance', titleEn: 'Dance'),
      AudioSubcategoryModel(id: 'house', titleRu: 'House', titleEn: 'House'),
      AudioSubcategoryModel(id: 'techno', titleRu: 'Techno', titleEn: 'Techno'),
      AudioSubcategoryModel(id: 'jazz', titleRu: 'Jazz', titleEn: 'Jazz'),
      AudioSubcategoryModel(id: 'classical', titleRu: 'Classical', titleEn: 'Classical'),
      AudioSubcategoryModel(id: 'folk', titleRu: 'Folk', titleEn: 'Folk'),
      AudioSubcategoryModel(id: 'kpop', titleRu: 'K-pop', titleEn: 'K-pop'),
      AudioSubcategoryModel(id: 'indie', titleRu: 'Indie', titleEn: 'Indie'),
      AudioSubcategoryModel(id: 'soundtrack', titleRu: 'Soundtrack', titleEn: 'Soundtrack'),
      AudioSubcategoryModel(id: 'local_music', titleRu: 'Local Music', titleEn: 'Local Music'),
    ],
  ),
  AudioCategoryModel(
    id: 'memes',
    titleRu: 'Мемы',
    titleEn: 'Memes',
    description: 'Вирусные звуки и реакции',
    icon: 'smiley',
    subcategories: [
      AudioSubcategoryModel(id: 'funny', titleRu: 'Funny', titleEn: 'Funny'),
      AudioSubcategoryModel(id: 'reaction', titleRu: 'Reaction', titleEn: 'Reaction'),
      AudioSubcategoryModel(id: 'voice_meme', titleRu: 'Voice meme', titleEn: 'Voice meme'),
      AudioSubcategoryModel(id: 'sound_effect', titleRu: 'Sound effect', titleEn: 'Sound effect'),
      AudioSubcategoryModel(id: 'viral', titleRu: 'Viral', titleEn: 'Viral'),
      AudioSubcategoryModel(id: 'short_clip', titleRu: 'Short clip', titleEn: 'Short clip'),
    ],
  ),
  AudioCategoryModel(
    id: 'audiobooks',
    titleRu: 'Аудиокниги',
    titleEn: 'Audiobooks',
    description: 'Книги для прослушивания',
    icon: 'book_open',
    subcategories: [
      AudioSubcategoryModel(id: 'fiction', titleRu: 'Fiction', titleEn: 'Fiction'),
      AudioSubcategoryModel(id: 'non_fiction', titleRu: 'Non-fiction', titleEn: 'Non-fiction'),
      AudioSubcategoryModel(id: 'business', titleRu: 'Business', titleEn: 'Business'),
      AudioSubcategoryModel(id: 'self_development', titleRu: 'Self-development', titleEn: 'Self-development'),
      AudioSubcategoryModel(id: 'kids', titleRu: 'Kids', titleEn: 'Kids'),
      AudioSubcategoryModel(id: 'fantasy', titleRu: 'Fantasy', titleEn: 'Fantasy'),
      AudioSubcategoryModel(id: 'detective', titleRu: 'Detective', titleEn: 'Detective'),
      AudioSubcategoryModel(id: 'history', titleRu: 'History', titleEn: 'History'),
      AudioSubcategoryModel(id: 'science', titleRu: 'Science', titleEn: 'Science'),
    ],
  ),
  AudioCategoryModel(
    id: 'podcasts',
    titleRu: 'Подкасты',
    titleEn: 'Podcasts',
    description: 'Разговоры и истории',
    icon: 'microphone',
    subcategories: [
      AudioSubcategoryModel(id: 'interview', titleRu: 'Interview', titleEn: 'Interview'),
      AudioSubcategoryModel(id: 'talk_show', titleRu: 'Talk show', titleEn: 'Talk show'),
      AudioSubcategoryModel(id: 'story', titleRu: 'Story', titleEn: 'Story'),
      AudioSubcategoryModel(id: 'technology', titleRu: 'Technology', titleEn: 'Technology'),
      AudioSubcategoryModel(id: 'business', titleRu: 'Business', titleEn: 'Business'),
      AudioSubcategoryModel(id: 'sport', titleRu: 'Sport', titleEn: 'Sport'),
      AudioSubcategoryModel(id: 'society', titleRu: 'Society', titleEn: 'Society'),
      AudioSubcategoryModel(id: 'comedy', titleRu: 'Comedy', titleEn: 'Comedy'),
    ],
  ),
  AudioCategoryModel(
    id: 'education',
    titleRu: 'Образование',
    titleEn: 'Education',
    description: 'Знания в аудиоформате',
    icon: 'graduation_cap',
    subcategories: [
      AudioSubcategoryModel(id: 'language', titleRu: 'Language', titleEn: 'Language'),
      AudioSubcategoryModel(id: 'programming', titleRu: 'Programming', titleEn: 'Programming'),
      AudioSubcategoryModel(id: 'school', titleRu: 'School', titleEn: 'School'),
      AudioSubcategoryModel(id: 'university', titleRu: 'University', titleEn: 'University'),
      AudioSubcategoryModel(id: 'science', titleRu: 'Science', titleEn: 'Science'),
      AudioSubcategoryModel(id: 'finance', titleRu: 'Finance', titleEn: 'Finance'),
      AudioSubcategoryModel(id: 'health', titleRu: 'Health', titleEn: 'Health'),
    ],
  ),
  AudioCategoryModel(
    id: 'meditation',
    titleRu: 'Медитация',
    titleEn: 'Meditation',
    description: 'Спокойствие и фокус',
    icon: 'spiral',
    subcategories: [
      AudioSubcategoryModel(id: 'sleep', titleRu: 'Sleep', titleEn: 'Sleep'),
      AudioSubcategoryModel(id: 'focus', titleRu: 'Focus', titleEn: 'Focus'),
      AudioSubcategoryModel(id: 'breathing', titleRu: 'Breathing', titleEn: 'Breathing'),
      AudioSubcategoryModel(id: 'ambient', titleRu: 'Ambient', titleEn: 'Ambient'),
      AudioSubcategoryModel(id: 'nature', titleRu: 'Nature', titleEn: 'Nature'),
    ],
  ),
  AudioCategoryModel(
    id: 'news',
    titleRu: 'Новости',
    titleEn: 'News',
    description: 'Актуальные события',
    icon: 'newspaper',
  ),
  AudioCategoryModel(
    id: 'instrumental',
    titleRu: 'Инструментал',
    titleEn: 'Instrumental',
    description: 'Биты и фоновая музыка',
    icon: 'piano_keys',
    subcategories: [
      AudioSubcategoryModel(id: 'beat', titleRu: 'Beat', titleEn: 'Beat'),
      AudioSubcategoryModel(id: 'lo_fi', titleRu: 'Lo-fi', titleEn: 'Lo-fi'),
      AudioSubcategoryModel(id: 'cinematic', titleRu: 'Cinematic', titleEn: 'Cinematic'),
      AudioSubcategoryModel(id: 'game_music', titleRu: 'Game music', titleEn: 'Game music'),
      AudioSubcategoryModel(id: 'background', titleRu: 'Background', titleEn: 'Background'),
    ],
  ),
  AudioCategoryModel(
    id: 'other',
    titleRu: 'Другое',
    titleEn: 'Other',
    description: 'Всё остальное',
    icon: 'dots_three',
  ),
];

AudioCategoryModel? findCategory(String id) {
  try {
    return kAudioCategories.firstWhere((c) => c.id == id);
  } catch (_) {
    return null;
  }
}
