import 'package:flutter/material.dart';

class SummaryCards extends StatelessWidget {
  final int ledgerBalance;
  final int totalIncome;
  final int totalExpense;
  final int activeStudentCount;
  final int unpaidBillCount;
  final int? realBalance;
  final VoidCallback? onActiveStudentTap;
  final VoidCallback? onUnpaidBillTap;

  const SummaryCards({
    super.key,
    required this.ledgerBalance,
    required this.totalIncome,
    required this.totalExpense,
    required this.activeStudentCount,
    required this.unpaidBillCount,
    this.realBalance,
    this.onActiveStudentTap,
    this.onUnpaidBillTap,
  });

  @override
  Widget build(BuildContext context) {
    final difference = realBalance == null ? 0 : realBalance! - ledgerBalance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 920;
        final wideCardWidth = isCompact ? constraints.maxWidth : 430.0;
        final smallCardWidth = isCompact ? constraints.maxWidth : 240.0;

        return Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            SizedBox(
              width: wideCardWidth,
              child: _buildBalanceCard(
                ledgerBalance: ledgerBalance,
                totalIncome: totalIncome,
                totalExpense: totalExpense,
              ),
            ),
            _buildSmallCard(
              width: smallCardWidth,
              title: 'Mhs. Aktif',
              value: _formatCount(activeStudentCount),
              subtitle: 'Total mahasiswa terdaftar',
              icon: Icons.people_outline,
              onTap: onActiveStudentTap,
            ),
            _buildSmallCard(
              width: smallCardWidth,
              title: 'Tagihan Belum Lunas',
              value: _formatCount(unpaidBillCount),
              subtitle: 'Total kewajiban pembayaran',
              icon: Icons.report_problem_outlined,
              onTap: onUnpaidBillTap,
            ),
            _buildSmallCard(
              width: smallCardWidth,
              title: 'Selisih Rekening',
              value: realBalance == null ? '-' : _formatRupiah(difference.abs()),
              subtitle: realBalance == null
                  ? 'Belum dicocokkan'
                  : difference == 0
                      ? 'Saldo cocok'
                      : difference > 0
                          ? 'Rekening lebih besar'
                          : 'Rekening lebih kecil',
              icon: Icons.account_balance_outlined,
              valueColor: realBalance == null
                  ? Colors.black87
                  : difference == 0
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBalanceCard({
    required int ledgerBalance,
    required int totalIncome,
    required int totalExpense,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Saldo Buku Keuangan',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            _formatRupiah(ledgerBalance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _FlowTile(
                  icon: Icons.arrow_downward,
                  label: 'Pemasukan',
                  amount: _formatRupiah(totalIncome),
                  color: const Color(0xFF86EFAC),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _FlowTile(
                  icon: Icons.arrow_upward,
                  label: 'Pengeluaran',
                  amount: _formatRupiah(totalExpense),
                  color: const Color(0xFFFECACA),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallCard({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final card = Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 32),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return card;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: card,
    );
  }

  String _formatCount(int value) {
    final raw = value.toString();
    return raw.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  }

  String _formatRupiah(int amount) {
    final raw = amount.abs().toString();
    final withSeparator = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return 'Rp$withSeparator';
  }
}

class _FlowTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String amount;
  final Color color;

  const _FlowTile({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label\n$amount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
