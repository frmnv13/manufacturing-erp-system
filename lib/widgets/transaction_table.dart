import 'package:flutter/material.dart';

import '../models/finance_models.dart';

class TransactionTable extends StatelessWidget {
  final List<FinanceTransaction> transactions;

  const TransactionTable({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.resolveWith(
            (_) => Colors.grey.shade50,
          ),
          horizontalMargin: 20,
          columnSpacing: 28,
          columns: const [
            DataColumn(
              label: Text(
                'Kategori',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Keterangan',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Tanggal',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Metode',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              numeric: true,
              label: Text(
                'Nominal',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Status',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: transactions.map(_buildRow).toList(),
        ),
      ),
    );
  }

  DataRow _buildRow(FinanceTransaction transaction) {
    return DataRow(
      cells: [
        DataCell(
          Text(
            transaction.category,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(Text(transaction.description)),
        DataCell(Text(_formatDate(transaction.date))),
        DataCell(Text(_paymentMethodLabel(transaction.paymentMethod))),
        DataCell(
          Text(
            '${transaction.isIncome ? '+' : '-'}${_formatRupiah(transaction.amount)}',
            style: TextStyle(
              color: transaction.isIncome
                  ? Colors.green.shade700
                  : Colors.red.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(_StatusChip(status: transaction.status)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  String _paymentMethodLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'bank_transfer':
        return 'Transfer Bank';
      case 'reconciliation':
        return 'Rekonsiliasi';
      case 'manual_adjustment':
        return 'Penyesuaian';
      case 'expense':
        return 'Pengeluaran';
      case 'manual':
        return 'Input Manual';
      default:
        return raw.trim().isEmpty ? 'Manual' : raw;
    }
  }

  String _formatRupiah(int amount) {
    final raw = amount.toString();
    final withSeparator = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return 'Rp$withSeparator';
  }
}

class _StatusChip extends StatelessWidget {
  final FinanceTransactionStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _backgroundColor(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          color: _foregroundColor(status),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _label(FinanceTransactionStatus status) {
    switch (status) {
      case FinanceTransactionStatus.completed:
        return 'Selesai';
      case FinanceTransactionStatus.pending:
        return 'Diproses';
      case FinanceTransactionStatus.failed:
        return 'Gagal';
    }
  }

  Color _foregroundColor(FinanceTransactionStatus status) {
    switch (status) {
      case FinanceTransactionStatus.completed:
        return Colors.green.shade700;
      case FinanceTransactionStatus.pending:
        return Colors.orange.shade800;
      case FinanceTransactionStatus.failed:
        return Colors.red.shade700;
    }
  }

  Color _backgroundColor(FinanceTransactionStatus status) {
    switch (status) {
      case FinanceTransactionStatus.completed:
        return Colors.green.shade50;
      case FinanceTransactionStatus.pending:
        return Colors.orange.shade50;
      case FinanceTransactionStatus.failed:
        return Colors.red.shade50;
    }
  }
}
