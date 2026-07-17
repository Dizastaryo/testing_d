import 'package:flutter/material.dart';
import '../../../core/models/file_item.dart';
import 'converted_pdf_reader_screen.dart';
import 'epub_reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'text_reader_screen.dart';

/// Открывает нужный ридер в зависимости от формата файла.
///
/// PDF/EPUB: нативный ридер, оригинальный документ.
/// TXT/MD:   скачивает оригинал с R2, рендерит inline.
/// FB2/DOCX/RTF/ODT/PPTX/ODP: бэкенд конвертирует в PDF через LibreOffice,
///   Flutter открывает результат через PdfReaderScreen.
/// ExtractedTextReaderScreen и SlidePreviewScreen оставлены для обратной
///   совместимости — удаляются в Фазе 3.
/// [jumpTo] — позиция закладки (`{page,total}` для PDF, `{offset,total}` для
/// текста). Когда задана, ридер открывается на этом месте, а не на последнем
/// прочитанном.
void openReader(BuildContext context, FileItem file,
    {Map<String, dynamic>? jumpTo}) {
  final ext = file.fileExtension;
  final isBook = file.category?.slug == 'books';
  final jumpPage = (jumpTo?['page'] as num?)?.toInt();
  final jumpFraction = _fractionFrom(jumpTo);
  // rootNavigator: ридер закрывает весь экран, включая нижнее меню Библиотеки.
  // Библиотечные под-экраны теперь живут внутри Shell, поэтому без root таб-бар
  // «прилипал» бы под текстом книги.
  switch (ext) {
    case 'pdf':
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => PdfReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          fileUrl: file.fileUrl,
          author: file.authorName,
          coverUrl: file.coverUrl,
          isBook: isBook,
          initialPage: jumpPage,
        ),
      ));
    case 'epub':
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => EpubReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          fileUrl: file.fileUrl,
          author: file.authorName,
          coverUrl: file.coverUrl,
        ),
      ));
    case 'txt':
    case 'md':
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => TextReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          format: ext,
          fileUrl: file.fileUrl,
          author: file.authorName,
          coverUrl: file.coverUrl,
          isBook: isBook,
          initialFraction: jumpFraction,
        ),
      ));
    case 'fb2':
    case 'docx':
    case 'rtf':
    case 'odt':
    case 'pptx':
    case 'odp':
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => ConvertedPdfReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          format: ext,
        ),
      ));
  }
}

/// Доля прочитанного из позиции закладки: новый формат `pct` или старый
/// пиксельный `offset`/`total` (offset/total = доля на момент сохранения).
double? _fractionFrom(Map<String, dynamic>? pos) {
  if (pos == null) return null;
  final pct = (pos['pct'] as num?)?.toDouble();
  if (pct != null) return pct.clamp(0.0, 1.0);
  final offset = (pos['offset'] as num?)?.toDouble();
  final total = (pos['total'] as num?)?.toDouble();
  if (offset != null && total != null && total > 0) {
    return (offset / total).clamp(0.0, 1.0);
  }
  return null;
}

bool canRead(FileItem file) => file.isTier1;
