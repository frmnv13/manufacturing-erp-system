import 'dart:typed_data';
import 'dart:convert';

import 'package:excel/excel.dart';

import '../models/bank_mutation_models.dart';
import '../widgets/student_dialog.dart';

class StudentImportResult {
  final List<StudentDraft> rows;
  final int skippedRows;

  const StudentImportResult({required this.rows, required this.skippedRows});
}

class ExcelImportService {
  ExcelImportService._();

  static BankMutationImportParseResult parseBankMutations(
    Uint8List bytes, {
    String fileName = '',
  }) {
    final ext = fileName.trim().toLowerCase();
    if (ext.endsWith('.csv')) {
      return _parseBankMutationsFromCsv(bytes);
    }
    return _parseBankMutationsFromExcel(bytes);
  }

  static StudentImportResult parseStudents(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('File excel tidak memiliki sheet.');
    }

    final sheetName = workbook.tables.keys.first;
    final sheet = workbook.tables[sheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      throw const FormatException('Sheet excel kosong.');
    }

    final headerRow = sheet.rows.first;
    final headers = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final key = _normalizeHeader(_cellText(headerRow[i]));
      if (key.isNotEmpty) {
        headers[key] = i;
      }
    }

    final nimIndex = headers['nim'];
    final nameIndex = headers['nama'];
    final majorIndex = headers['prodi'];
    final classIndex = headers['kelas'];
    final semesterIndex = headers['semester'];
    final scholarshipIndex = _findFirstHeaderIndex(headers, const [
      'beasiswa',
      'beasiswapersen',
      'potongan',
      'potonganbeasiswa',
      'scholarship',
    ]);
    final installmentIndex = _findFirstHeaderIndex(headers, const [
      'cicilan',
      'termin',
      'termincicilan',
      'installment',
      'installmentterms',
    ]);
    if (nimIndex == null ||
        nameIndex == null ||
        majorIndex == null ||
        classIndex == null ||
        semesterIndex == null) {
      throw const FormatException(
        'Header wajib: NIM, Nama, Prodi, Kelas, Semester.',
      );
    }

    final result = <StudentDraft>[];
    final seenNims = <String>{};
    var skippedRows = 0;

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final nim = _cellAt(row, nimIndex);
      final name = _cellAt(row, nameIndex);
      final major = _cellAt(row, majorIndex);
      final className = _cellAt(row, classIndex);
      final semesterRaw = _cellAt(row, semesterIndex);
      final scholarshipRaw = scholarshipIndex == null
          ? ''
          : _cellAt(row, scholarshipIndex);
      final installmentRaw = installmentIndex == null
          ? ''
          : _cellAt(row, installmentIndex);

      if (nim.isEmpty &&
          name.isEmpty &&
          major.isEmpty &&
          className.isEmpty &&
          semesterRaw.isEmpty) {
        continue;
      }

      final semester = int.tryParse(semesterRaw);
      final scholarshipPercent = _parseScholarshipPercent(scholarshipRaw);
      final installmentTerms = _parseInstallmentTerms(installmentRaw);
      if (nim.isEmpty ||
          name.isEmpty ||
          major.isEmpty ||
          className.isEmpty ||
          semester == null ||
          semester <= 0 ||
          seenNims.contains(nim)) {
        skippedRows += 1;
        continue;
      }

      seenNims.add(nim);
      result.add(
        StudentDraft(
          nim: nim,
          name: name,
          major: major,
          className: className,
          semester: semester,
          scholarshipPercent: scholarshipPercent,
          installmentTerms: scholarshipPercent == 100 ? 1 : installmentTerms,
        ),
      );
    }

    return StudentImportResult(rows: result, skippedRows: skippedRows);
  }

  static String _normalizeHeader(String input) {
    return input.trim().toLowerCase().replaceAll(' ', '');
  }

  static String _cellAt(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) {
      return '';
    }
    return _cellText(row[index]);
  }

  static String _cellText(Data? cell) {
    if (cell == null) {
      return '';
    }
    final value = cell.value;
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static BankMutationImportParseResult _parseBankMutationsFromExcel(
    Uint8List bytes,
  ) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('File excel tidak memiliki sheet.');
    }

    final sheetName = workbook.tables.keys.first;
    final sheet = workbook.tables[sheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      throw const FormatException('Sheet excel kosong.');
    }

    final headerRow = sheet.rows.first;
    final headers = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final key = _normalizeHeader(_cellText(headerRow[i]));
      if (key.isNotEmpty) {
        headers[key] = i;
      }
    }

    final dateIndex = _findFirstHeaderIndex(headers, const [
      'tanggal',
      'tgl',
      'date',
      'datetime',
      'waktu',
    ]);
    final descriptionIndex = _findFirstHeaderIndex(headers, const [
      'keterangan',
      'beritatransfer',
      'berita',
      'deskripsi',
      'description',
      'uraian',
    ]);
    final amountIndex = _findFirstHeaderIndex(headers, const [
      'nominal',
      'jumlah',
      'amount',
      'kredit',
      'credit',
    ]);
    final debitIndex = _findFirstHeaderIndex(headers, const ['debit']);
    final creditIndex = _findFirstHeaderIndex(headers, const [
      'kredit',
      'credit',
    ]);
    final referenceIndex = _findFirstHeaderIndex(headers, const [
      'referensi',
      'ref',
      'reff',
      'no',
      'nomorreferensi',
    ]);
    final bankAccountIndex = _findFirstHeaderIndex(headers, const [
      'rekening',
      'norek',
      'nomorrekening',
      'rekeningbank',
      'bankaccount',
      'account',
    ]);

    if (descriptionIndex == null ||
        (amountIndex == null && debitIndex == null && creditIndex == null)) {
      throw const FormatException(
        'Header mutasi wajib minimal memiliki Keterangan dan Nominal/Kredit/Debit.',
      );
    }

    final rows = <BankMutationImportRow>[];
    var skippedRows = 0;

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final description = _cellAt(row, descriptionIndex).trim();
      final dateText = dateIndex == null ? '' : _cellAt(row, dateIndex).trim();
      final referenceNo = referenceIndex == null
          ? ''
          : _cellAt(row, referenceIndex);
      final bankAccount = bankAccountIndex == null
          ? ''
          : _cellAt(row, bankAccountIndex).trim();

      var amount = 0;
      var isCredit = true;
      if (amountIndex != null) {
        amount = _parseCurrency(_cellAt(row, amountIndex));
      } else if (creditIndex != null || debitIndex != null) {
        final creditValue = creditIndex == null
            ? 0
            : _parseCurrency(_cellAt(row, creditIndex));
        final debitValue = debitIndex == null
            ? 0
            : _parseCurrency(_cellAt(row, debitIndex));
        if (creditValue > 0) {
          amount = creditValue;
          isCredit = true;
        } else {
          amount = debitValue;
          isCredit = false;
        }
      }

      if (description.isEmpty && amount <= 0) {
        continue;
      }
      if (description.isEmpty || amount <= 0) {
        skippedRows += 1;
        continue;
      }

      rows.add(
        BankMutationImportRow(
          mutationDate: _parseDate(dateText),
          description: description,
          amount: amount,
          isCredit: isCredit,
          referenceNo: referenceNo,
          bankAccount: bankAccount,
        ),
      );
    }

    return BankMutationImportParseResult(rows: rows, skippedRows: skippedRows);
  }

  static BankMutationImportParseResult _parseBankMutationsFromCsv(
    Uint8List bytes,
  ) {
    final rawText = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(rawText);
    if (lines.isEmpty) {
      throw const FormatException('File CSV kosong.');
    }

    final delimiter = lines.first.contains(';') ? ';' : ',';
    final headerParts = _splitCsvLine(lines.first, delimiter);
    final headers = <String, int>{};
    for (var i = 0; i < headerParts.length; i++) {
      final key = _normalizeHeader(headerParts[i]);
      if (key.isNotEmpty) {
        headers[key] = i;
      }
    }

    final dateIndex = _findFirstHeaderIndex(headers, const [
      'tanggal',
      'tgl',
      'date',
      'datetime',
      'waktu',
    ]);
    final descriptionIndex = _findFirstHeaderIndex(headers, const [
      'keterangan',
      'beritatransfer',
      'berita',
      'deskripsi',
      'description',
      'uraian',
    ]);
    final amountIndex = _findFirstHeaderIndex(headers, const [
      'nominal',
      'jumlah',
      'amount',
      'kredit',
      'credit',
    ]);
    final debitIndex = _findFirstHeaderIndex(headers, const ['debit']);
    final creditIndex = _findFirstHeaderIndex(headers, const [
      'kredit',
      'credit',
    ]);
    final referenceIndex = _findFirstHeaderIndex(headers, const [
      'referensi',
      'ref',
      'reff',
      'no',
      'nomorreferensi',
    ]);
    final bankAccountIndex = _findFirstHeaderIndex(headers, const [
      'rekening',
      'norek',
      'nomorrekening',
      'rekeningbank',
      'bankaccount',
      'account',
    ]);

    if (descriptionIndex == null ||
        (amountIndex == null && debitIndex == null && creditIndex == null)) {
      throw const FormatException(
        'Header CSV mutasi wajib minimal memiliki Keterangan dan Nominal/Kredit/Debit.',
      );
    }

    final rows = <BankMutationImportRow>[];
    var skippedRows = 0;

    for (var i = 1; i < lines.length; i++) {
      final parts = _splitCsvLine(lines[i], delimiter);
      final description = _valueAt(parts, descriptionIndex).trim();
      final dateText = dateIndex == null
          ? ''
          : _valueAt(parts, dateIndex).trim();
      final referenceNo = referenceIndex == null
          ? ''
          : _valueAt(parts, referenceIndex).trim();
      final bankAccount = bankAccountIndex == null
          ? ''
          : _valueAt(parts, bankAccountIndex).trim();

      var amount = 0;
      var isCredit = true;
      if (amountIndex != null) {
        amount = _parseCurrency(_valueAt(parts, amountIndex));
      } else if (creditIndex != null || debitIndex != null) {
        final creditValue = creditIndex == null
            ? 0
            : _parseCurrency(_valueAt(parts, creditIndex));
        final debitValue = debitIndex == null
            ? 0
            : _parseCurrency(_valueAt(parts, debitIndex));
        if (creditValue > 0) {
          amount = creditValue;
          isCredit = true;
        } else {
          amount = debitValue;
          isCredit = false;
        }
      }

      if (description.isEmpty && amount <= 0) {
        continue;
      }
      if (description.isEmpty || amount <= 0) {
        skippedRows += 1;
        continue;
      }

      rows.add(
        BankMutationImportRow(
          mutationDate: _parseDate(dateText),
          description: description,
          amount: amount,
          isCredit: isCredit,
          referenceNo: referenceNo,
          bankAccount: bankAccount,
        ),
      );
    }

    return BankMutationImportParseResult(rows: rows, skippedRows: skippedRows);
  }

  static int? _findFirstHeaderIndex(
    Map<String, int> headers,
    List<String> keys,
  ) {
    for (final key in keys) {
      final index = headers[_normalizeHeader(key)];
      if (index != null) {
        return index;
      }
    }
    return null;
  }

  static List<String> _splitCsvLine(String line, String delimiter) {
    final parts = line.split(delimiter);
    return parts
        .map((item) => item.trim().replaceAll(RegExp(r'^"+|"+$'), '').trim())
        .toList();
  }

  static String _valueAt(List<String> values, int index) {
    if (index < 0 || index >= values.length) {
      return '';
    }
    return values[index];
  }

  static int _parseCurrency(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll('Rp', '')
        .replaceAll('rp', '')
        .replaceAll('.', '')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9-]'), '');
    final value = int.tryParse(cleaned) ?? 0;
    return value < 0 ? 0 : value;
  }

  static int _parseScholarshipPercent(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) {
      return 0;
    }
    if (value.contains('100')) {
      return 100;
    }
    if (value.contains('75')) {
      return 75;
    }
    if (value.contains('50')) {
      return 50;
    }
    if (value.contains('25')) {
      return 25;
    }
    final parsed = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (parsed <= 0) {
      return 0;
    }
    if (parsed >= 100) {
      return 100;
    }
    if (parsed >= 75) {
      return 75;
    }
    if (parsed >= 50) {
      return 50;
    }
    if (parsed >= 25) {
      return 25;
    }
    return 0;
  }

  static int _parseInstallmentTerms(String raw) {
    final parsed = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
    if (parsed <= 1) {
      return 1;
    }
    if (parsed > 12) {
      return 12;
    }
    return parsed;
  }

  static DateTime? _parseDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }

    final direct = DateTime.tryParse(value);
    if (direct != null) {
      return direct;
    }

    final slashMatch = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$',
    ).firstMatch(value);
    if (slashMatch != null) {
      final day = int.tryParse(slashMatch.group(1) ?? '') ?? 1;
      final month = int.tryParse(slashMatch.group(2) ?? '') ?? 1;
      var year = int.tryParse(slashMatch.group(3) ?? '') ?? DateTime.now().year;
      if (year < 100) {
        year += 2000;
      }
      return DateTime(year, month, day);
    }

    return null;
  }
}

class BankMutationImportParseResult {
  final List<BankMutationImportRow> rows;
  final int skippedRows;

  const BankMutationImportParseResult({
    required this.rows,
    required this.skippedRows,
  });
}
