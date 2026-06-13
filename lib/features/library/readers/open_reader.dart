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
void openReader(BuildContext context, FileItem file) {
  final ext = file.fileExtension;
  switch (ext) {
    case 'pdf':
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          fileUrl: file.fileUrl,
        ),
      ));
    case 'epub':
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EpubReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          fileUrl: file.fileUrl,
        ),
      ));
    case 'txt':
    case 'md':
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TextReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          format: ext,
          fileUrl: file.fileUrl,
        ),
      ));
    case 'fb2':
    case 'docx':
    case 'rtf':
    case 'odt':
    case 'pptx':
    case 'odp':
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConvertedPdfReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          format: ext,
        ),
      ));
  }
}

bool canRead(FileItem file) => file.isTier1;
