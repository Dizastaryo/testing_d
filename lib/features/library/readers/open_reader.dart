import 'package:flutter/material.dart';
import '../../../core/models/file_item.dart';
import 'epub_reader_screen.dart';
import 'extracted_text_reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'slide_preview_screen.dart';
import 'text_reader_screen.dart';

/// Открывает нужный ридер в зависимости от формата файла.
/// Tier 1: pdf, epub, txt, md — полноценные встроенные ридеры.
/// Tier 2: fb2, docx, rtf, odt — extracted text ридер.
/// Tier 3: pptx, odp — карусель слайдов.
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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExtractedTextReaderScreen(
          fileId: file.id,
          title: file.displayTitle,
          format: ext,
        ),
      ));
    case 'pptx':
    case 'odp':
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SlidePreviewScreen(
          fileId: file.id,
          title: file.displayTitle,
          format: ext,
          fileUrl: file.fileUrl,
        ),
      ));
  }
}

bool canRead(FileItem file) =>
    file.isTier1 || file.isTier2 || file.isTier3;
