import 'user.dart';
import 'story.dart';

class Highlight {
  final String id;
  final User author;
  final String title;
  final String coverUrl;
  final List<Story> stories;
  final DateTime createdAt;

  const Highlight({
    required this.id,
    required this.author,
    required this.title,
    required this.coverUrl,
    this.stories = const [],
    required this.createdAt,
  });

  factory Highlight.fromJson(Map<String, dynamic> json) {
    final storiesList = (json['stories'] as List?)
            ?.map((s) => Story.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [];

    return Highlight(
      id: json['id']?.toString() ?? '',
      author: User.fromJson(json['author'] as Map<String, dynamic>? ?? {}),
      title: json['title']?.toString() ?? '',
      coverUrl: json['cover_url']?.toString() ?? '',
      stories: storiesList,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author.toJson(),
    'title': title,
    'cover_url': coverUrl,
    'stories': stories.map((s) => s.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
  };

}
