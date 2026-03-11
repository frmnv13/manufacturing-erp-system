import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';

class StudentDraft {
  final String nim;
  final String name;
  final String major;
  final String className;
  final int semester;
  final int scholarshipPercent;
  final int installmentTerms;

  const StudentDraft({
    required this.nim,
    required this.name,
    required this.major,
    required this.className,
    required this.semester,
    this.scholarshipPercent = 0,
    this.installmentTerms = 1,
  });
}

class StudentDialog extends StatefulWidget {
  final StudentAccount? initialStudent;
  final List<String> existingNims;

  const StudentDialog({
    super.key,
    this.initialStudent,
    required this.existingNims,
  });

  @override
  State<StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<StudentDialog> {
  late final TextEditingController _nimController;
  late final TextEditingController _nameController;
  late final TextEditingController _majorController;
  late final TextEditingController _classController;
  late final TextEditingController _semesterController;
  int _scholarshipPercent = 0;
  int _installmentTerms = 1;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStudent;
    _nimController = TextEditingController(text: initial?.nim ?? '');
    _nameController = TextEditingController(text: initial?.name ?? '');
    _majorController = TextEditingController(text: initial?.major ?? '');
    _classController = TextEditingController(text: initial?.className ?? '');
    _semesterController = TextEditingController(
      text: initial?.semester.toString() ?? '',
    );
    _scholarshipPercent = initial?.scholarshipPercent ?? 0;
    _installmentTerms = initial?.installmentTerms ?? 1;
  }

  @override
  void dispose() {
    _nimController.dispose();
    _nameController.dispose();
    _majorController.dispose();
    _classController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  void _submit() {
    final nim = _nimController.text.trim();
    final name = _nameController.text.trim();
    final major = _majorController.text.trim();
    final className = _classController.text.trim();
    final semester = int.tryParse(_semesterController.text.trim());

    if (nim.isEmpty || name.isEmpty || major.isEmpty || className.isEmpty) {
      _showError('Semua field wajib diisi.');
      return;
    }
    if (semester == null || semester <= 0) {
      _showError('Semester tidak valid.');
      return;
    }

    final initialNim = widget.initialStudent?.nim;
    final duplicateNim = widget.existingNims.any(
      (item) => item == nim && item != initialNim,
    );
    if (duplicateNim) {
      _showError('NIM sudah terdaftar.');
      return;
    }

    Navigator.of(context).pop(
      StudentDraft(
        nim: nim,
        name: name,
        major: major,
        className: className,
        semester: semester,
        scholarshipPercent: _scholarshipPercent,
        installmentTerms: _installmentTerms,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialStudent != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Mahasiswa' : 'Tambah Mahasiswa'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nimController,
                decoration: const InputDecoration(
                  labelText: 'NIM',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Mahasiswa',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _majorController,
                decoration: const InputDecoration(
                  labelText: 'Program Studi',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _classController,
                decoration: const InputDecoration(
                  labelText: 'Kelas',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _semesterController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Semester',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _scholarshipPercent,
                decoration: const InputDecoration(
                  labelText: 'Skema Potongan Beasiswa',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem<int>(value: 0, child: Text('Tidak ada (0%)')),
                  DropdownMenuItem<int>(value: 25, child: Text('Beasiswa 25%')),
                  DropdownMenuItem<int>(value: 50, child: Text('Beasiswa 50%')),
                  DropdownMenuItem<int>(value: 75, child: Text('Beasiswa 75%')),
                  DropdownMenuItem<int>(value: 100, child: Text('Beasiswa 100%')),
                ],
                onChanged: (value) {
                  setState(() {
                    _scholarshipPercent = value ?? 0;
                    if (_scholarshipPercent == 100) {
                      _installmentTerms = 1;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _installmentTerms,
                decoration: const InputDecoration(
                  labelText: 'Skema Cicilan',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem<int>(value: 1, child: Text('Lunas langsung (1x)')),
                  DropdownMenuItem<int>(value: 2, child: Text('Cicilan 2x')),
                  DropdownMenuItem<int>(value: 3, child: Text('Cicilan 3x')),
                  DropdownMenuItem<int>(value: 4, child: Text('Cicilan 4x')),
                ],
                onChanged: _scholarshipPercent == 100
                    ? null
                    : (value) {
                        setState(() {
                          _installmentTerms = value ?? 1;
                        });
                      },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _scholarshipPercent == 100
                      ? 'Beasiswa 100%: tagihan otomatis Rp0.'
                      : _installmentTerms > 1
                          ? 'Cicilan aktif: mahasiswa dianggap on-track jika sudah bayar minimal termin awal.'
                          : 'Pembayaran penuh sekali lunas.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Simpan'),
        ),
      ],
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }
}
