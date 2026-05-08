import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/tokens.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _activeCategory = '';
  String _query = '';
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FileItem> _applySearch(List<FileItem> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((f) =>
            f.filename.toLowerCase().contains(q) ||
            f.description.toLowerCase().contains(q) ||
            (f.user?.username.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(fileCategoriesProvider);
    final filesAsync = ref.watch(filesProvider(_activeCategory.isEmpty ? null : _activeCategory));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(theme)),
          if (_searchOpen) SliverToBoxAdapter(child: _buildSearchField(theme)),
          if (_query.isEmpty) SliverToBoxAdapter(child: _buildUploadZone(theme)),
          SliverToBoxAdapter(
            child: categoriesAsync.when(
              data: (cats) => _buildCategories(cats, theme),
              loading: () => const SizedBox(height: 50),
              error: (_, __) => const SizedBox(),
            ),
          ),
          filesAsync.when(
            data: (files) {
              final filtered = _applySearch(files);
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        _query.isEmpty
                            ? 'Файлов ещё нет'
                            : 'По запросу «$_query» ничего',
                        style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                );
              }
              return _buildFileList(filtered, theme);
            },
            loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverToBoxAdapter(
                child: Center(child: Text('Ошибка: $e'))),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Поиск по файлам…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '▮ SHARED DRIVE',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: SeeUColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Файлы',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 36,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _searchCtrl.clear();
                _query = '';
              }
            }),
            icon: Icon(
              _searchOpen ? Icons.close : Icons.search,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadZone(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: [
            SeeUColors.accent.withValues(alpha: 0.1),
            Colors.amber.withValues(alpha: 0.1),
          ]),
          border: Border.all(
              color: SeeUColors.accent.withValues(alpha: 0.5),
              style: BorderStyle.none),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                    colors: [SeeUColors.accent, Colors.amber]),
                boxShadow: [
                  BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8))
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Загрузить файл',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text('pdf · zip · img · exe · txt',
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5))),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('+ DROP',
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: theme.scaffoldBackgroundColor)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories(List<FileCategory> cats, ThemeData theme) {
    final allCats = [FileCategory(id: '', name: 'Все'), ...cats];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: allCats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = allCats[i];
          final isActive = cat.id == _activeCategory;
          return GestureDetector(
            onTap: () => setState(() => _activeCategory = cat.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color:
                    isActive ? theme.colorScheme.onSurface : Colors.transparent,
                border: isActive ? null : Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                cat.name,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? theme.scaffoldBackgroundColor
                        : theme.colorScheme.onSurface),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileList(List<FileItem> files, ThemeData theme) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildFileCard(files[i], theme),
          ),
          childCount: files.length,
        ),
      ),
    );
  }

  Widget _buildFileCard(FileItem file, ThemeData theme) {
    final color = _colorForType(file.fileExtension);
    return GestureDetector(
      onTap: () => context.push('/files/${file.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.15),
                      color.withValues(alpha: 0.05)
                    ]),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(file.fileExtension.toUpperCase(),
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                      '${file.fileSizeFormatted} · ↓ ${file.downloadsFormatted} · @${file.user?.username ?? ''}',
                      style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5))),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: file.isPreviewable
                    ? null
                    : theme.colorScheme.surfaceContainerHighest,
                gradient: file.isPreviewable
                    ? LinearGradient(
                        colors: [SeeUColors.accent, Colors.amber])
                    : null,
              ),
              child: Icon(
                file.isPreviewable ? Icons.play_arrow : Icons.download,
                color: file.isPreviewable
                    ? Colors.white
                    : theme.colorScheme.onSurface,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForType(String ext) {
    switch (ext) {
      case 'pdf':
        return SeeUColors.accent;
      case 'zip':
      case 'rar':
        return const Color(0xFFC04CFD);
      case 'txt':
        return const Color(0xFF2FA84F);
      default:
        return Colors.amber;
    }
  }
}
