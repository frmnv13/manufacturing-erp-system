import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';

class ExcelExportService {
  ExcelExportService._();

  static Future<void> exportRows({
    required String fileName,
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    if (defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    sheet.appendRow(headers.map((value) => TextCellValue(value)).toList());
    for (final row in rows) {
      sheet.appendRow(row.map((value) => TextCellValue(value)).toList());
    }

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('Gagal membuat file excel.');
    }

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: Uint8List.fromList(bytes),
      ext: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }
}
