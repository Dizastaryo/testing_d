import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';

final _metricsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get('/admin/metrics');
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  return Map<String, int>.from(data as Map);
});

class _DailyPoint {
  final String day; // YYYY-MM-DD
  final int dau;
  final int signups;
  final int posts;
  const _DailyPoint(this.day, this.dau, this.signups, this.posts);
}

final _timeSeriesProvider =
    FutureProvider.autoDispose<List<_DailyPoint>>((ref) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get('/admin/metrics/timeseries',
      queryParameters: {'days': 30});
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  final items = (data as Map)['items'] as List? ?? [];
  return items
      .map((e) => _DailyPoint(
            e['day']?.toString() ?? '',
            (e['dau'] ?? 0) as int,
            (e['signups'] ?? 0) as int,
            (e['posts'] ?? 0) as int,
          ))
      .toList();
});

class AdminMetricsPage extends ConsumerWidget {
  const AdminMetricsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(_metricsProvider);
    final ts = ref.watch(_timeSeriesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_metricsProvider);
        ref.invalidate(_timeSeriesProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Метрики',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                  onPressed: () {
                    ref.invalidate(_metricsProvider);
                    ref.invalidate(_timeSeriesProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            m.when(
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )),
              error: (e, _) => _errorBox(e.toString()),
              data: (data) => _grid(data),
            ),
            const SizedBox(height: 24),
            ts.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _errorBox(e.toString()),
              data: (points) => _ChartsSection(points: points),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(Map<String, int> m) {
    final cards = [
      _Card('Юзеры всего', m['users'] ?? 0),
      _Card('+ за сутки', m['users_today'] ?? 0, accent: true),
      _Card('Постов всего', m['posts'] ?? 0),
      _Card('Постов за сутки', m['posts_today'] ?? 0, accent: true),
      _Card('Активных историй', m['stories_active'] ?? 0),
      _Card('Жалоб ожидают', m['reports_pending'] ?? 0,
          danger: (m['reports_pending'] ?? 0) > 0),
      _Card('Жалоб за сутки', m['reports_today'] ?? 0, accent: true),
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: cards.map((c) => SizedBox(width: 220, child: c)).toList(),
    );
  }

  Widget _errorBox(String msg) => Card(
        color: const Color(0xFFFFEFEC),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Ошибка: $msg',
              style: const TextStyle(color: Color(0xFFB02F1F))),
        ),
      );
}

class _Card extends StatelessWidget {
  final String label;
  final int value;
  final bool accent;
  final bool danger;

  const _Card(this.label, this.value,
      {this.accent = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? const Color(0xFFE74C3C)
        : (accent ? const Color(0xFFFF5A3C) : Colors.black87);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            const SizedBox(height: 6),
            Text('$value',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: color,
                )),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 30-day charts
// ---------------------------------------------------------------------------

class _ChartsSection extends StatelessWidget {
  final List<_DailyPoint> points;
  const _ChartsSection({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('30 дней',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'DAU — уникальные активные юзеры',
          subtitle: 'кто создал пост / коммент / лайк / посмотрел сторис',
          color: const Color(0xFFFF5A3C),
          values: points.map((p) => p.dau).toList(),
          days: points.map((p) => p.day).toList(),
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Регистрации',
          subtitle: 'новые юзеры по дням',
          color: const Color(0xFF1E88E5),
          values: points.map((p) => p.signups).toList(),
          days: points.map((p) => p.day).toList(),
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Новые посты',
          subtitle: 'без учёта рилов и сторис',
          color: const Color(0xFF43A047),
          values: points.map((p) => p.posts).toList(),
          days: points.map((p) => p.day).toList(),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final List<int> values;
  final List<String> days;
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.values,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    final today = values.isNotEmpty ? values.last : 0;
    final avg = values.isNotEmpty
        ? (values.fold<int>(0, (a, b) => a + b) / values.length).round()
        : 0;
    final peak =
        values.isNotEmpty ? values.reduce((a, b) => a > b ? a : b) : 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                _stat('Сегодня', today, color),
                const SizedBox(width: 16),
                _stat('Среднее', avg, Colors.grey.shade700),
                const SizedBox(width: 16),
                _stat('Пик', peak, Colors.grey.shade700),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 160,
              child: CustomPaint(
                painter: _LineChartPainter(values: values, color: color),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_shortDay(days.first),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
                Text(_shortDay(days[days.length ~/ 2]),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
                Text('сегодня',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Text('$value',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      );

  String _shortDay(String yyyymmdd) {
    if (yyyymmdd.length < 10) return yyyymmdd;
    return '${yyyymmdd.substring(8, 10)}.${yyyymmdd.substring(5, 7)}';
  }
}

class _LineChartPainter extends CustomPainter {
  final List<int> values;
  final Color color;
  const _LineChartPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV =
        values.fold<int>(0, (a, b) => a > b ? a : b).clamp(1, 1 << 30);

    // Background grid
    final grid = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Build the line + fill polygon
    final stride = values.length > 1
        ? size.width / (values.length - 1)
        : size.width;
    final path = Path();
    final fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * stride;
      final y = size.height - (values[i] / maxV) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo((values.length - 1) * stride, size.height);
    fill.close();

    // Gradient fill
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Last-point marker
    final lastX = (values.length - 1) * stride;
    final lastY = size.height - (values.last / maxV) * size.height;
    canvas.drawCircle(
      Offset(lastX, lastY),
      4,
      Paint()..color = color,
    );
    canvas.drawCircle(
      Offset(lastX, lastY),
      4,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values || old.color != color;
}
