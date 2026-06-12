import 'package:flutter/material.dart';
import '../../../core/models/file_item.dart';
import 'epub_reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'text_reader_screen.dart';

/// Открывает нужный ридер в зависимости от формата файла.
/// Tier 1: pdf, epub, txt, md — полноценные встроенные ридеры.
/// Tier 2/3 (fb2, docx, rtf, odt, pptx, odp) — текстовый ридер через extracted_text.
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
        ),
      ));
    default:
      // Tier 2/3: показываем extracted_text в текстовом ридере
      if (file.isTier2 || file.isTier3) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TextReaderScreen(
            fileId: file.id,
            title: file.displayTitle,
            format: ext,
          ),
        ));
      }
  }
}

bool canRead(FileItem file) =>
    file.isTier1 || file.isTier2 || file.isTier3;
