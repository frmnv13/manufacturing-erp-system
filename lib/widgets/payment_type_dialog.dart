import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';

class PaymentTypeDraft {
  final String name;
  final int amount;
  final List<String> prerequisiteTypeIds;
  final int? targetSemester;
  final String? targetMajor;

  const PaymentTypeDraft({
    required this.name,
    required this.amount,
    required this.prerequisiteTypeIds,
    required this.targetSemester,
    required this.targetMajor,
  });
}

class PaymentTypeDialog extends StatefulWidget {
  final List<PaymentType> existingPaymentTypes;
  final List<String> availableMajors;

  const PaymentTypeDialog({
    super.key,
    required this.existingPaymentTypes,
    required this.availableMajors,
  });

  @override
  State<PaymentTypeDialog> createState() => _PaymentTypeDialogState();
}

class _PaymentTypeDialogState extends State<PaymentTypeDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _semesterController = TextEditingController();
  final Set<String> _selectedPrerequisites = {};
  String _selectedMajorFilter = '';

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final amount = int.tryParse(_amountController.text.trim());
    final semesterText = _semesterController.text.trim();
    final targetSemester =
        semesterText.isEmpty ? null : int.tryParse(semesterText);

    if (name.isEmpty) {
      _showError('Nama pembayaran wajib diisi.');
      return;
    }
    if (amount == null || amount <= 0) {
      _showError('Nominal pembayaran tidak valid.');
      return;
    }
    if (semesterText.isNotEmpty &&
        (targetSemester == null || targetSemester <= 0)) {
      _showError('Semester target tidak valid.');
      return;
    }

    Navigator.of(context).pop(
      PaymentTypeDraft(
        name: name,
        amount: amount,
        prerequisiteTypeIds: _selectedPrerequisites.toList(),
        targetSemester: targetSemester,
        targetMajor: _selectedMajorFilter.isEmpty ? null : _selectedMajorFilter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Tambah Jenis Pembayaran',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama pembayaran',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Nominal',
                  border: OutlineInputBorder(),
                  prefixText: 'Rp',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _semesterController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Target Semester (opsional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedMajorFilter,
                decoration: const InputDecoration(
                  labelText: 'Target Prodi (opsional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Semua Prodi'),
                  ),
                  ...widget.availableMajors.map(
                    (major) => DropdownMenuItem<String>(
                      value: major,
                      child: Text(major),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedMajorFilter = value ?? '';
                  });
                },
              ),
              const SizedBox(height: 18),
              const Text(
                'Prasyarat pembayaran (opsional)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (widget.existingPaymentTypes.isEmpty)
                const Text('Belum ada jenis pembayaran lain.')
              else
                ...widget.existingPaymentTypes.map(
                  (item) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selectedPrerequisites.contains(item.id),
                    title: Text(item.name),
                    subtitle: Text(_formatRupiah(item.amount)),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedPrerequisites.add(item.id);
                        } else {
                          _selectedPrerequisites.remove(item.id);
                        }
                      });
                    },
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

  String _formatRupiah(int amount) {
    final raw = amount.toString();
    final withSeparator = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return 'Rp$withSeparator';
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
