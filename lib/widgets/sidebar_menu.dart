import 'package:flutter/material.dart';

class FinanceMenuIndex {
  const FinanceMenuIndex._();

  static const int dashboard = 0;
  static const int tagihan = 1;
  static const int mutasiBank = 2;
  static const int rekonsiliasi = 3;
  static const int verifikasiManual = 4;
  static const int pelunasanPenyesuaian = 5;
  static const int laporan = 6;
  static const int pengaturan = 7;
}

class FinanceMenuItem {
  final int index;
  final IconData icon;
  final String label;

  const FinanceMenuItem({
    required this.index,
    required this.icon,
    required this.label,
  });
}

const List<FinanceMenuItem> financeAdminMenuItems = <FinanceMenuItem>[
  FinanceMenuItem(
    index: FinanceMenuIndex.dashboard,
    icon: Icons.dashboard_outlined,
    label: 'Dashboard',
  ),
  FinanceMenuItem(
    index: FinanceMenuIndex.tagihan,
    icon: Icons.receipt_long_outlined,
    label: 'Tagihan',
  ),
  FinanceMenuItem(
    index: FinanceMenuIndex.mutasiBank,
    icon: Icons.account_balance_outlined,
    label: 'Mutasi Bank',
  ),
  FinanceMenuItem(
    index: FinanceMenuIndex.rekonsiliasi,
    icon: Icons.compare_arrows_outlined,
    label: 'Rekonsiliasi',
  ),
  FinanceMenuItem(
    index: FinanceMenuIndex.verifikasiManual,
    icon: Icons.fact_check_outlined,
    label: 'Verifikasi Manual',
  ),
  FinanceMenuItem(
    index: FinanceMenuIndex.pelunasanPenyesuaian,
    icon: Icons.rule_folder_outlined,
    label: 'Pelunasan/Penyesuaian',
  ),
  FinanceMenuItem(
    index: FinanceMenuIndex.laporan,
    icon: Icons.insert_drive_file_outlined,
    label: 'Laporan',
  ),
  FinanceMenuItem(
    index: FinanceMenuIndex.pengaturan,
    icon: Icons.settings_outlined,
    label: 'Pengaturan',
  ),
];

String financeAdminMenuTitleForIndex(int index) {
  for (final item in financeAdminMenuItems) {
    if (item.index == index) {
      return item.label;
    }
  }
  return financeAdminMenuItems.first.label;
}

class SidebarMenu extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final List<FinanceMenuItem> menuItems;

  const SidebarMenu({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.menuItems = financeAdminMenuItems,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KeuanganUSH',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Sistem Administrasi Kampus',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: menuItems.length,
                itemBuilder: (context, idx) {
                  final item = menuItems[idx];
                  return _buildMenuItem(item);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(FinanceMenuItem item) {
    final isActive = item.index == selectedIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isActive ? const Color(0xFF2563EB) : Colors.grey.shade600,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isActive ? const Color(0xFF2563EB) : Colors.black87,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: isActive,
        selectedTileColor: const Color(0xFFEFF6FF),
        onTap: () => onItemSelected(item.index),
      ),
    );
  }
}
