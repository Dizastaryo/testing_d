import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/text_layer.dart';

// ─── Sentinel для nullable copyWith ──────────────────────────────
const _absent = Object();

// ─── State ───────────────────────────────────────────────────────

@immutable
class StickerEditorState {
  final List<TextLayer> layers;
  final String? activeLayerId;

  const StickerEditorState({
    this.layers = const [],
    this.activeLayerId,
  });

  TextLayer? get activeLayer =>
      activeLayerId == null
          ? null
          : layers.where((l) => l.id == activeLayerId).firstOrNull;

  StickerEditorState copyWith({
    List<TextLayer>? layers,
    Object? activeLayerId = _absent,
  }) {
    return StickerEditorState(
      layers: layers ?? this.layers,
      activeLayerId: identical(activeLayerId, _absent)
          ? this.activeLayerId
          : activeLayerId as String?,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────

class StickerEditorNotifier extends StateNotifier<StickerEditorState> {
  StickerEditorNotifier() : super(const StickerEditorState()) {
    // Инициализируем историю начальным пустым состоянием.
    _history.add(const StickerEditorState());
    _cursor = 0;
  }

  static const int _maxHistory = 50;

  final List<StickerEditorState> _history = [];
  int _cursor = -1;

  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _history.length - 1;

  // ── History ────────────────────────────────────────────────────

  void _commit(StickerEditorState next) {
    // Удаляем "будущее" если откатывались назад.
    if (_cursor < _history.length - 1) {
      _history.removeRange(_cursor + 1, _history.length);
    }
    _history.add(next);
    // Ограничиваем глубину истории.
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
    _cursor = _history.length - 1;
    state = next;
  }

  void undo() {
    if (!canUndo) return;
    _cursor--;
    state = _history[_cursor];
  }

  void redo() {
    if (!canRedo) return;
    _cursor++;
    state = _history[_cursor];
  }

  // ── Layers ────────────────────────────────────────────────────

  void addLayer() {
    final layer = TextLayer(
      id: _newId(),
      text: 'Текст',
    );
    _commit(state.copyWith(
      layers: [...state.layers, layer],
      activeLayerId: layer.id,
    ));
  }

  void setActive(String? id) {
    // Смена активного слоя не попадает в историю.
    state = state.copyWith(activeLayerId: id);
  }

  void updateLayer(String id, TextLayer updated) {
    _commit(state.copyWith(
      layers: state.layers.map((l) => l.id == id ? updated : l).toList(),
    ));
  }

  /// Обновляет трансформации слоя во время жеста без записи в историю.
  ///
  /// - [positionDelta] — смещение в нормализованных координатах (0–1)
  /// - [scaleFactor]  — множитель к текущему scale (1.0 = без изменений)
  /// - [rotationDelta] — изменение угла в радианах
  ///
  /// Вызывай [commitGesture] по окончании жеста.
  void updateLayerTransform(
    String id, {
    Offset positionDelta = Offset.zero,
    double scaleFactor = 1.0,
    double rotationDelta = 0.0,
  }) {
    state = state.copyWith(
      layers: state.layers.map((l) {
        if (l.id != id) return l;
        return l.copyWith(
          position: Offset(
            (l.position.dx + positionDelta.dx).clamp(0.0, 1.0),
            (l.position.dy + positionDelta.dy).clamp(0.0, 1.0),
          ),
          scale: (l.scale * scaleFactor).clamp(0.2, 8.0),
          rotation: l.rotation + rotationDelta,
        );
      }).toList(),
    );
  }

  /// Обновляет слой БЕЗ записи в историю — для живых слайдеров и жестов.
  /// После окончания взаимодействия вызывай [commitGesture].
  void updateLayerLive(String id, TextLayer updated) {
    state = state.copyWith(
      layers: state.layers.map((l) => l.id == id ? updated : l).toList(),
    );
  }

  /// Обновляет текст активного слоя без записи в историю.
  /// Вызывай [commitGesture] когда пользователь закончил ввод.
  void setActiveLayerText(String text) {
    final active = state.activeLayer;
    if (active == null || active.text == text) return;
    state = state.copyWith(
      layers: state.layers
          .map((l) => l.id == active.id ? l.copyWith(text: text) : l)
          .toList(),
    );
  }

  /// Фиксирует результат жеста в истории.
  void commitGesture() => _commit(state);

  void deleteLayer(String id) {
    final layers = state.layers.where((l) => l.id != id).toList();
    final activeId = state.activeLayerId == id
        ? (layers.isNotEmpty ? layers.last.id : null)
        : state.activeLayerId;
    _commit(state.copyWith(
      layers: layers,
      activeLayerId: activeId,
    ));
  }

  void duplicateLayer(String id) {
    final original = state.layers.firstWhere((l) => l.id == id);
    final copy = original.copyWithNewId(
      _newId(),
      position: Offset(
        (original.position.dx + 0.04).clamp(0.0, 1.0),
        (original.position.dy + 0.04).clamp(0.0, 1.0),
      ),
    );
    final idx = state.layers.indexWhere((l) => l.id == id);
    final layers = [...state.layers]..insert(idx + 1, copy);
    _commit(state.copyWith(layers: layers, activeLayerId: copy.id));
  }

  /// Перемещает слой выше (ближе к зрителю).
  void moveLayerUp(String id) {
    final layers = [...state.layers];
    final idx = layers.indexWhere((l) => l.id == id);
    if (idx < layers.length - 1) {
      final tmp = layers[idx];
      layers[idx] = layers[idx + 1];
      layers[idx + 1] = tmp;
      _commit(state.copyWith(layers: layers));
    }
  }

  /// Перемещает слой ниже (дальше от зрителя).
  void moveLayerDown(String id) {
    final layers = [...state.layers];
    final idx = layers.indexWhere((l) => l.id == id);
    if (idx > 0) {
      final tmp = layers[idx];
      layers[idx] = layers[idx - 1];
      layers[idx - 1] = tmp;
      _commit(state.copyWith(layers: layers));
    }
  }

  void reset() {
    _history
      ..clear()
      ..add(const StickerEditorState());
    _cursor = 0;
    state = const StickerEditorState();
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}

// ─── Provider ────────────────────────────────────────────────────

final stickerEditorProvider = StateNotifierProvider.autoDispose<
    StickerEditorNotifier, StickerEditorState>(
  (ref) => StickerEditorNotifier(),
);
