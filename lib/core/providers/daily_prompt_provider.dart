import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';

/// Backend-driven daily-prompt — replaces the hardcoded «что вас удивило
/// сегодня?» string that lived in `_DailyPromptCard` for months.
///
/// The card stays visually identical; only the question text rotates.
/// Server picks the prompt by `time.Now().UTC().YearDay() % len(prompts)` —
/// deterministic, same for everyone same day.
///
/// Fallback: if the network call fails (offline, server down), `.value`
/// resolves to the hardcoded original. The feed card never goes blank.
class DailyPrompt {
  final String text;
  final String date; // YYYY-MM-DD

  const DailyPrompt({required this.text, required this.date});

  /// Last-resort default — keeps UX intact when the daily-prompt endpoint
  /// is unreachable.
  static const DailyPrompt fallback = DailyPrompt(
    text: 'что вас удивило\nсегодня?',
    date: '',
  );
}

final dailyPromptProvider = FutureProvider<DailyPrompt>((ref) async {
  try {
    final api = ref.read(apiClientProvider);
    final r = await api.get(ApiEndpoints.dailyPrompt);
    final body = r.data is Map && (r.data as Map).containsKey('data')
        ? r.data['data']
        : r.data;
    if (body is! Map) return DailyPrompt.fallback;
    final text = body['prompt']?.toString();
    final date = body['date']?.toString();
    if (text == null || text.isEmpty) return DailyPrompt.fallback;
    return DailyPrompt(text: text, date: date ?? '');
  } catch (_) {
    return DailyPrompt.fallback;
  }
});
