/// Модель AI-сгенерированной маски (одна запись из `ai_masks` таблицы).
/// PNG лежит на бэке в `/uploads/ai/masks/&lt;uuid&gt;.png` — frontend качает через
/// CachedNetworkImage по absolute URL `AppConfig.apiOrigin + fileUrl`.
class AIMask {
  final String id;
  final String prompt;
  final String fileUrl; // server-relative, начинается с '/uploads/...'
  final DateTime createdAt;

  const AIMask({
    required this.id,
    required this.prompt,
    required this.fileUrl,
    required this.createdAt,
  });

  factory AIMask.fromJson(Map<String, dynamic> j) {
    return AIMask(
      id: j['id']?.toString() ?? '',
      prompt: j['prompt']?.toString() ?? '',
      fileUrl: j['file_url']?.toString() ?? '',
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
