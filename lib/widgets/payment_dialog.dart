import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/finance_models.dart';

class PaymentSubmission {
  final String nim;
  final String paymentTypeId;
  final int amount;

  const PaymentSubmission({
    required this.nim,
    required this.paymentTypeId,
    required this.amount,
  });
}

class PaymentDialog extends StatefulWidget {
  final List<PaymentType> paymentTypes;
  final List<StudentAccount> students;
  final bool Function(StudentAccount student, PaymentType paymentType)?
  paymentTypeFilter;

  const PaymentDialog({
    super.key,
    required this.paymentTypes,
    required this.students,
    this.paymentTypeFilter,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final TextEditingController _nimController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  bool _isSearching = false;
  bool _isSubmitting = false;
  StudentAccount? _studentData;
  PaymentType? _selectedType;

  @override
  void dispose() {
    _nimController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _searchNim() {
    final nim = _nimController.text.trim();
    if (nim.isEmpty) {
      _showError('Masukkan NIM terlebih dahulu.');
      return;
    }

    setState(() {
      _isSearching = true;
      _studentData = null;
      _selectedType = null;
      _amountController.clear();
    });

    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }

      StudentAccount? result;
      for (final student in widget.students) {
        if (student.nim == nim) {
          result = student;
          break;
        }
      }

      setState(() {
        _isSearching = false;
        _studentData = result;
      });

      if (result == null) {
        _showError('NIM tidak ditemukan.');
        return;
      }

      final eligiblePaymentTypes = _eligiblePaymentTypesForStudent(result);
      if (eligiblePaymentTypes.isEmpty) {
        _showError(
          'Semua tagihan sudah lunas atau tidak ada jenis pembayaran yang berlaku.',
        );
      }
    });
  }

  Future<void> _confirmPayment() async {
    final student = _studentData;
    final paymentType = _selectedType;
    if (student == null || paymentType == null) {
      _showError('Pilih mahasiswa dan jenis pembayaran.');
      return;
    }

    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showError('Nominal pembayaran tidak valid.');
      return;
    }

    if (!_isPaymentTypeApplicable(student, paymentType)) {
      _showError(
        'Jenis pembayaran ini tidak berlaku untuk mahasiswa tersebut.',
      );
      return;
    }

    final missingRequirements = _findMissingRequirements(student, paymentType);
    if (missingRequirements.isNotEmpty) {
      _showError(
        'Pembayaran ${paymentType.name} tidak bisa diproses. '
        'Lunasi dulu: ${missingRequirements.join(', ')}.',
      );
      return;
    }

    final dueAmount = _requiredAmountFor(student, paymentType);
    final paidAmount = _effectivePaidAmountFor(
      student,
      paymentType,
      requiredAmount: dueAmount,
    );
    final remainingAmount = dueAmount - paidAmount;

    if (remainingAmount <= 0) {
      _showError('Jenis pembayaran ini sudah lunas.');
      return;
    }
    if (amount > remainingAmount) {
      _showError(
        'Nominal melebihi sisa tagihan. Maksimal ${_formatRupiah(remainingAmount)}.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      PaymentSubmission(
        nim: student.nim,
        paymentTypeId: paymentType.id,
        amount: amount,
      ),
    );
  }

  bool _isPaymentTypeApplicable(
    StudentAccount student,
    PaymentType paymentType,
  ) {
    final filter = widget.paymentTypeFilter;
    if (filter == null) {
      return true;
    }
    return filter(student, paymentType);
  }

  int _requiredAmountFor(StudentAccount student, PaymentType paymentType) {
    final baseAmount = paymentType.amount < 0 ? 0 : paymentType.amount;
    final discountPercent = student.scholarshipPercent.clamp(0, 100);
    if (discountPercent >= 100) {
      return 0;
    }
    final discountAmount = (baseAmount * discountPercent / 100).round();
    final result = baseAmount - discountAmount;
    return result < 0 ? 0 : result;
  }

  int _effectivePaidAmountFor(
    StudentAccount student,
    PaymentType paymentType, {
    int? requiredAmount,
  }) {
    final required = requiredAmount ?? _requiredAmountFor(student, paymentType);
    final fromMap = student.paidTypeAmounts[paymentType.id] ?? 0;
    if (fromMap > 0) {
      return fromMap >= required ? required : fromMap;
    }
    if (student.paidTypeIds.contains(paymentType.id)) {
      return required;
    }
    return 0;
  }

  int _remainingAmountFor(StudentAccount student, PaymentType paymentType) {
    final required = _requiredAmountFor(student, paymentType);
    final paid = _effectivePaidAmountFor(
      student,
      paymentType,
      requiredAmount: required,
    );
    final remaining = required - paid;
    return remaining > 0 ? remaining : 0;
  }

  bool _isPaymentTypeSettled(StudentAccount student, PaymentType paymentType) {
    return _remainingAmountFor(student, paymentType) == 0;
  }

  List<PaymentType> _eligiblePaymentTypesForStudent(StudentAccount student) {
    return widget.paymentTypes.where((type) {
      if (!_isPaymentTypeApplicable(student, type)) {
        return false;
      }
      return !_isPaymentTypeSettled(student, type);
    }).toList();
  }

  List<String> _settledPaymentTypeNames(StudentAccount student) {
    final names = <String>[];
    for (final type in widget.paymentTypes) {
      if (_isPaymentTypeSettled(student, type)) {
        names.add(type.name);
      }
    }
    return names;
  }

  List<String> _findMissingRequirements(
    StudentAccount student,
    PaymentType paymentType,
  ) {
    final result = <String>[];
    for (final prerequisiteId in paymentType.prerequisiteTypeIds) {
      PaymentType? prerequisite;
      for (final type in widget.paymentTypes) {
        if (type.id == prerequisiteId) {
          prerequisite = type;
          break;
        }
      }
      if (prerequisite == null) {
        continue;
      }
      if (!_isPaymentTypeSettled(student, prerequisite)) {
        result.add(prerequisite.name);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final student = _studentData;
    final eligiblePaymentTypes = student == null
        ? widget.paymentTypes
        : _eligiblePaymentTypesForStudent(student);
    final selectedType = eligiblePaymentTypes.contains(_selectedType)
        ? _selectedType
        : null;
    final missingRequirements = student == null || selectedType == null
        ? const <String>[]
        : _findMissingRequirements(student, selectedType);

    int? dueAmount;
    int? paidAmount;
    int? remainingAmount;
    if (student != null && selectedType != null) {
      dueAmount = _requiredAmountFor(student, selectedType);
      paidAmount = _effectivePaidAmountFor(
        student,
        selectedType,
        requiredAmount: dueAmount,
      );
      remainingAmount = dueAmount - paidAmount;
      if (remainingAmount < 0) {
        remainingAmount = 0;
      }
    }

    final alreadyPaid = remainingAmount != null && remainingAmount == 0;

    return AlertDialog(
      title: const Text(
        'Input Pembayaran Mahasiswa',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nimController,
                      decoration: const InputDecoration(
                        labelText: 'Masukkan NIM',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchNim(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSearching ? null : _searchNim,
                    icon: _isSearching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: const Text('Cari'),
                  ),
                ],
              ),
              if (student != null) ...[
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Informasi Pelajar',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow('NIM', student.nim),
                _buildInfoRow('Nama', student.name),
                _buildInfoRow(
                  'Program',
                  '${student.major} (${student.className})',
                ),
                _buildInfoRow('Semester', student.semester.toString()),
                _buildInfoRow('Beasiswa', '${student.scholarshipPercent}%'),
                _buildInfoRow('Skema Cicilan', '${student.installmentTerms}x'),
                _buildInfoRow(
                  'Lunas',
                  _settledPaymentTypeNames(student).isEmpty
                      ? '-'
                      : _settledPaymentTypeNames(student).join(', '),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<PaymentType>(
                  key: ValueKey(
                    '${student.nim}_${selectedType?.id ?? 'none'}_${eligiblePaymentTypes.length}',
                  ),
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Jenis Pembayaran',
                    border: OutlineInputBorder(),
                  ),
                  items: eligiblePaymentTypes
                      .map(
                        (item) => DropdownMenuItem<PaymentType>(
                          value: item,
                          child: Text(
                            '${item.name} (Sisa ${_formatRupiah(_remainingAmountFor(student, item))})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedType = value;
                      if (value == null) {
                        _amountController.clear();
                        return;
                      }
                      final remaining = _remainingAmountFor(student, value);
                      _amountController.text = remaining <= 0
                          ? ''
                          : remaining.toString();
                    });
                  },
                ),
                if (eligiblePaymentTypes.isEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Semua tagihan untuk mahasiswa ini sudah lunas atau tidak berlaku.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
                if (selectedType != null &&
                    dueAmount != null &&
                    paidAmount != null &&
                    remainingAmount != null) ...[
                  const SizedBox(height: 10),
                  _buildInfoRow('Tagihan Netto', _formatRupiah(dueAmount)),
                  _buildInfoRow('Terbayar', _formatRupiah(paidAmount)),
                  _buildInfoRow('Sisa', _formatRupiah(remainingAmount)),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Nominal Pembayaran',
                    border: OutlineInputBorder(),
                    prefixText: 'Rp',
                  ),
                ),
                if (alreadyPaid) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Jenis pembayaran ini sudah lunas untuk mahasiswa tersebut.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
                if (missingRequirements.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Belum bisa dibayar. Wajib lunas dulu: ${missingRequirements.join(', ')}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _confirmPayment,
          child: _isSubmitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan Pembayaran'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const Text(' : '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
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
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }
}
