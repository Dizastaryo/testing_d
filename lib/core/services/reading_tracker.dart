import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../providers/library_provider.dart';

/// Tracks real time spent on each page of a document.
/// A page is "read" when the user spends >= [thresholdSeconds] on it.
///
/// Usage:
///   final tracker = ReadingTracker(actions: actions, fileId: 'abc');
///   await tracker.init();        // loads existing progress from server
///   tracker.startPage(0);        // user is viewing page 0
///   tracker.startPage(1);        // user flipped to page 1
///   tracker.dispose();           // saves & cleans up
class ReadingTracker with WidgetsBindingObserver {
  final LibraryActions actions;
  final String fileId;
  final int thresholdSeconds;

  ReadingTracker({
    required this.actions,
    required this.fileId,
    this.thresholdSeconds = 40,
  });

  /// page_number → cumulative seconds spent
  final Map<int, int> _pageSeconds = {};

  /// Pages that have been counted as "read" (seconds >= threshold)
  final Set<int> _readPages = {};

  /// Currently active page (-1 = none)
  int _currentPage = -1;

  /// Whether app is in foreground (timer only ticks when true)
  bool _appActive = true;

  Timer? _ticker;
  Timer? _syncTimer;
  Timer? _pageJustReadTimer;

  /// Dirty flag — true when local data changed since last sync
  bool _dirty = false;

  /// Explicit lifecycle guard (replaces the old hasListeners/try-catch hack).
  bool _disposed = false;

  // ── Public ValueNotifiers for UI ──────────────────────────────────────────

  /// Progress of current page toward threshold (0.0 – 1.0)
  final currentPageProgress = ValueNotifier<double>(0.0);

  /// Whether current page is already marked as read
  final currentPageRead = ValueNotifier<bool>(false);

  /// Total number of read pages across the file
  final totalReadPages = ValueNotifier<int>(0);

  /// Fires briefly when a page just became "read" (for animation)
  final pageJustRead = ValueNotifier<bool>(false);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Load existing progress from server and start timers.
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    await _loadFromServer();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _syncTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _syncToServer());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _syncTimer?.cancel();
    _pageJustReadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Final flush — runs even though _disposed is true (it never touches the
    // notifiers below once disposed).
    await _syncToServer();
    currentPageProgress.dispose();
    currentPageRead.dispose();
    totalReadPages.dispose();
    pageJustRead.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      // Sync when going to background
      _syncToServer();
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Call when user navigates to a page. Pauses timer on previous page.
  void startPage(int page) {
    if (page == _currentPage) return;
    _currentPage = page;
    _updateNotifiers();
  }

  /// Returns seconds spent on a specific page.
  int secondsForPage(int page) => _pageSeconds[page] ?? 0;

  /// Whether a specific page is read.
  bool isPageRead(int page) => _readPages.contains(page);

  // ── Internal ──────────────────────────────────────────────────────────────

  void _tick() {
    if (_disposed || !_appActive || _currentPage < 0) return;

    final prev = _pageSeconds[_currentPage] ?? 0;
    final next = prev + 1;
    _pageSeconds[_currentPage] = next;
    _dirty = true;

    // Check if page just became "read"
    if (next >= thresholdSeconds && !_readPages.contains(_currentPage)) {
      _readPages.add(_currentPage);
      totalReadPages.value = _readPages.length;
      // Brief notification for UI animation
      pageJustRead.value = true;
      _pageJustReadTimer?.cancel();
      _pageJustReadTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!_disposed) pageJustRead.value = false;
      });
    }

    _updateNotifiers();
  }

  void _updateNotifiers() {
    if (_disposed || _currentPage < 0) return;
    final secs = _pageSeconds[_currentPage] ?? 0;
    final isRead = _readPages.contains(_currentPage);
    currentPageProgress.value =
        isRead ? 1.0 : (secs / thresholdSeconds).clamp(0.0, 1.0);
    currentPageRead.value = isRead;
  }

  /// Folds server page-seconds into local state, keeping the max per page.
  void _mergeFromServer(Map<int, int> serverPages, int threshold) {
    serverPages.forEach((page, secs) {
      final local = _pageSeconds[page] ?? 0;
      _pageSeconds[page] = math.max(local, secs);
    });
    for (final entry in _pageSeconds.entries) {
      if (entry.value >= threshold) _readPages.add(entry.key);
    }
    if (!_disposed) {
      totalReadPages.value = _readPages.length;
      _updateNotifiers();
    }
  }

  Future<void> _loadFromServer() async {
    try {
      final remote = await actions.loadPagesProgress(fileId, thresholdSeconds);
      _mergeFromServer(remote.pages, remote.threshold);
    } catch (_) {
      // Offline — start fresh, will merge on sync
    }
  }

  Future<void> _syncToServer() async {
    if (!_dirty || _pageSeconds.isEmpty) return;
    _dirty = false;
    try {
      // Merge with the server first (max per page) so we never clobber
      // progress recorded by another session/device with a stale snapshot.
      try {
        final remote =
            await actions.loadPagesProgress(fileId, thresholdSeconds);
        _mergeFromServer(remote.pages, remote.threshold);
      } catch (_) {}

      final pagesJson = <String, int>{};
      for (final e in _pageSeconds.entries) {
        pagesJson[e.key.toString()] = e.value;
      }
      await actions.savePagesProgress(fileId, pagesJson);
    } catch (_) {
      _dirty = true; // retry next cycle
    }
  }
}
