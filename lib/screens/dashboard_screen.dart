import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state_store.dart';
import '../data/remote_admin_api.dart';
import '../data/remote_bank_mutation_api.dart';
import '../models/admin_models.dart';
import '../models/bank_mutation_models.dart';
import '../models/dashboard_state_model.dart';
import '../models/finance_models.dart';
import '../utils/excel_export_service.dart';
import '../utils/excel_import_service.dart';
import '../widgets/expense_dialog.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/payment_type_dialog.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/student_dialog.dart';
import '../widgets/summary_cards.dart';
import '../widgets/transaction_table.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onLogoutRequested;
  final String? signedInUsername;
  final String? signedInRole;
  final String? signedInToken;

  const DashboardScreen({
    super.key,
    this.onLogoutRequested,
    this.signedInUsername,
    this.signedInRole,
    this.signedInToken,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _desktopBreakpoint = 1024.0;
  final RemoteAdminApi _adminApi = RemoteAdminApi.fromEnvironment();
  final RemoteBankMutationApi _bankMutationApi =
      RemoteBankMutationApi.fromEnvironment();

  int _selectedIndex = 0;
  int _ledgerBalance = 0;
  int? _realBalance;
  bool _autoReconcileEnabled = true;
  bool _strictPrerequisiteValidation = true;
  bool _allowManualSettlementOverride = false;
  bool _notifyDifferenceOnDashboard = true;
  String _operatorName = 'Administrator';
  bool _isInitializing = true;
  bool _persistenceReady = false;
  bool _isAdminDataLoading = false;
  bool _adminDataLoaded = false;
  bool _isBankMutationLoading = false;
  bool _bankMutationLoadInitialized = false;
  bool _isBankMutationBatchProcessing = false;
  String _selectedBankMutationStatus = '';
  double _bankMutationMinConfidence = 0;
  Timer? _saveDebounce;

  List<PaymentType> _paymentTypes = const [];
  List<StudentAccount> _students = const [];
  List<FinanceTransaction> _transactions = const [];
  List<AdminUserAccount> _adminUsers = const [];
  List<AdminAuditLog> _adminAuditLogs = const [];
  List<BankMutationItem> _bankMutations = const [];
  List<BankAutoMatchRule> _bankAutoMatchRules = const [];
  Map<String, int> _bankMutationCounts = const {
    'unmatched': 0,
    'candidate': 0,
    'matched': 0,
    'approved': 0,
    'rejected': 0,
  };

  bool get _isAccessControlled => widget.signedInRole != null;
  String get _effectiveRole =>
      (widget.signedInRole ?? 'owner').trim().toLowerCase();
  String get _effectiveToken => (widget.signedInToken ?? '').trim();
  bool get _canCallAdminApi =>
      _adminApi.isConfigured && _effectiveToken.isNotEmpty;
  bool get _canUseBankMutationApi =>
      _bankMutationApi.isConfigured && _effectiveToken.isNotEmpty;
  bool get _canImportOrApproveMutation =>
      _canUseBankMutationApi &&
      (_effectiveRole == 'owner' ||
          _effectiveRole == 'admin' ||
          _effectiveRole == 'operator');
  bool get _canManageMasterData =>
      !_isAccessControlled ||
      _effectiveRole == 'owner' ||
      _effectiveRole == 'admin';

  int get _totalIncome => _transactions
      .where((item) => item.isIncome)
      .fold(0, (prev, item) => prev + item.amount);

  int get _totalExpense => _transactions
      .where((item) => !item.isIncome)
      .fold(0, (prev, item) => prev + item.amount);

  int get _unpaidBillCount =>
      _buildOutstandingBills().where((item) => item.isOverdue).length;

  int? get _balanceDifference =>
      _realBalance == null ? null : _realBalance! - _ledgerBalance;
  int get _pendingTransactionCount => _transactions
      .where((item) => item.status == FinanceTransactionStatus.pending)
      .length;
  int get _failedTransactionCount => _transactions
      .where((item) => item.status == FinanceTransactionStatus.failed)
      .length;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPersistedState());
  }

  @override
  void setState(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    super.setState(fn);
    if (_persistenceReady) {
      _saveDebounce?.cancel();
      _saveDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_persistState()),
      );
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPersistedState() async {
    final fallback = _toStateModel();
    var saved = fallback;
    var persistenceReady = false;

    try {
      saved = await AppStateStore.instance.loadDashboardState(
        fallback: fallback,
      );
      persistenceReady = true;
    } catch (_) {
      saved = fallback;
    }

    if (!mounted) {
      return;
    }

    final maxMenuIndex = financeAdminMenuItems.length - 1;
    final selectedIndex = saved.selectedIndex;
    super.setState(() {
      _selectedIndex = selectedIndex < 0 || selectedIndex > maxMenuIndex
          ? 0
          : selectedIndex;
      _ledgerBalance = saved.ledgerBalance;
      _realBalance = saved.realBalance;
      _autoReconcileEnabled = saved.autoReconcileEnabled;
      _strictPrerequisiteValidation = saved.strictPrerequisiteValidation;
      _allowManualSettlementOverride = saved.allowManualSettlementOverride;
      _notifyDifferenceOnDashboard = saved.notifyDifferenceOnDashboard;
      _operatorName = saved.operatorName;
      _paymentTypes = List<PaymentType>.from(saved.paymentTypes);
      _students = List<StudentAccount>.from(saved.students);
      _transactions = List<FinanceTransaction>.from(saved.transactions);
      _bankAutoMatchRules = List<BankAutoMatchRule>.from(
        saved.bankAutoMatchRules,
      );
      _isInitializing = false;
      _persistenceReady = persistenceReady;
    });

    if (_selectedIndex == FinanceMenuIndex.pengaturan) {
      unawaited(_loadAdminPanelData());
    }
    if (_selectedIndex == FinanceMenuIndex.mutasiBank) {
      unawaited(_loadBankMutations());
    }
    if (persistenceReady) {
      unawaited(_persistState());
    }
  }

  DashboardStateModel _toStateModel() {
    return DashboardStateModel(
      selectedIndex: _selectedIndex,
      ledgerBalance: _ledgerBalance,
      realBalance: _realBalance,
      autoReconcileEnabled: _autoReconcileEnabled,
      strictPrerequisiteValidation: _strictPrerequisiteValidation,
      allowManualSettlementOverride: _allowManualSettlementOverride,
      notifyDifferenceOnDashboard: _notifyDifferenceOnDashboard,
      operatorName: _operatorName,
      paymentTypes: List<PaymentType>.from(_paymentTypes),
      students: List<StudentAccount>.from(_students),
      transactions: List<FinanceTransaction>.from(_transactions),
      bankAutoMatchRules: List<BankAutoMatchRule>.from(_bankAutoMatchRules),
    );
  }

  Future<void> _persistState() async {
    try {
      await AppStateStore.instance.saveDashboardState(_toStateModel());
    } catch (_) {
      // Keep app usable if persistence is unavailable.
    }
  }

  Future<void> _loadAdminPanelData({bool force = false}) async {
    if (!_canManageMasterData || !_canCallAdminApi) {
      return;
    }
    if (_isAdminDataLoading) {
      return;
    }
    if (!force && _adminDataLoaded) {
      return;
    }

    setState(() {
      _isAdminDataLoading = true;
    });

    try {
      final responses = await Future.wait([
        _adminApi.fetchUsers(token: _effectiveToken),
        _adminApi.fetchAuditLogs(token: _effectiveToken, limit: 100),
      ]);

      final users =
          List<AdminUserAccount>.from(responses[0] as List<AdminUserAccount>)
            ..sort(
              (a, b) =>
                  a.username.toLowerCase().compareTo(b.username.toLowerCase()),
            );
      final auditLogs = List<AdminAuditLog>.from(
        responses[1] as List<AdminAuditLog>,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _adminUsers = users;
        _adminAuditLogs = auditLogs;
        _adminDataLoaded = true;
      });
    } catch (error) {
      if (mounted) {
        _showErrorMessage(
          _readableError(error, fallback: 'Gagal memuat data admin.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAdminDataLoading = false;
        });
      }
    }
  }

  Future<void> _loadBankMutations({bool force = false}) async {
    if (!_canUseBankMutationApi) {
      return;
    }
    if (_isBankMutationLoading) {
      return;
    }
    if (!force && _bankMutationLoadInitialized) {
      return;
    }

    setState(() {
      _isBankMutationLoading = true;
    });

    try {
      final result = await _bankMutationApi.fetchMutations(
        token: _effectiveToken,
        status: _selectedBankMutationStatus,
        limit: 300,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _bankMutations = result.items;
        _bankMutationCounts = result.counts;
        _bankMutationLoadInitialized = true;
      });
    } catch (error) {
      if (mounted) {
        _showErrorMessage(
          _readableError(error, fallback: 'Gagal memuat mutasi bank.'),
        );
        setState(() {
          // Mark initialized to prevent auto-retry loop that causes blinking UI.
          _bankMutationLoadInitialized = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBankMutationLoading = false;
        });
      }
    }
  }

  Future<void> _importBankMutationFile() async {
    if (!_canImportOrApproveMutation) {
      _showErrorMessage('Role Anda tidak memiliki akses import mutasi bank.');
      return;
    }

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (!mounted || picked == null || picked.files.isEmpty) {
        return;
      }

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showErrorMessage('Gagal membaca file mutasi.');
        return;
      }

      final parsed = ExcelImportService.parseBankMutations(
        bytes,
        fileName: file.name,
      );
      if (parsed.rows.isEmpty) {
        _showErrorMessage('Tidak ada data valid untuk diimport.');
        return;
      }
      final transformed = _applyBankAutoMatchRules(parsed.rows);

      final summary = await _bankMutationApi.importRows(
        token: _effectiveToken,
        rows: transformed.rows,
        sourceFile: file.name,
      );

      await _loadBankMutations(force: true);
      _showInfoMessage(
        'Import selesai. Masuk: ${summary.imported}, duplikat: ${summary.duplicates}, '
        'skip: ${parsed.skippedRows + summary.skipped}, hijau: ${summary.matched}, '
        'kuning: ${summary.candidate + summary.unmatched}, '
        'rule match: ${transformed.matchedRows}, '
        'diubah: ${transformed.appliedRows}, '
        'tag NIM: ${transformed.nimTaggedRows}, '
        'tag Prodi: ${transformed.majorTaggedRows}.',
      );
    } on FormatException catch (error) {
      _showErrorMessage(error.message);
    } catch (error) {
      _showErrorMessage(
        _readableError(error, fallback: 'Gagal import mutasi bank.'),
      );
    }
  }

  _BankMutationRuleApplyResult _applyBankAutoMatchRules(
    List<BankMutationImportRow> rows,
  ) {
    final activeRules = _bankAutoMatchRules
        .where((item) => item.isEnabled)
        .toList();
    if (activeRules.isEmpty || rows.isEmpty) {
      return _BankMutationRuleApplyResult(
        rows: List<BankMutationImportRow>.from(rows),
        matchedRows: 0,
        appliedRows: 0,
        nimTaggedRows: 0,
        majorTaggedRows: 0,
      );
    }

    final preparedRules = <_PreparedBankAutoMatchRule>[];
    for (final rule in activeRules) {
      final rawPattern = rule.descriptionRegex.trim();
      if (rawPattern.isEmpty) {
        preparedRules.add(
          _PreparedBankAutoMatchRule(rule: rule, descriptionRegex: null),
        );
        continue;
      }
      try {
        preparedRules.add(
          _PreparedBankAutoMatchRule(
            rule: rule,
            descriptionRegex: RegExp(rawPattern, caseSensitive: false),
          ),
        );
      } catch (_) {
        // Abaikan rule dengan regex tidak valid agar import tetap berjalan.
      }
    }

    if (preparedRules.isEmpty) {
      return _BankMutationRuleApplyResult(
        rows: List<BankMutationImportRow>.from(rows),
        matchedRows: 0,
        appliedRows: 0,
        nimTaggedRows: 0,
        majorTaggedRows: 0,
      );
    }

    final resultRows = <BankMutationImportRow>[];
    var matchedRows = 0;
    var appliedRows = 0;
    var nimTaggedRows = 0;
    var majorTaggedRows = 0;

    for (final original in rows) {
      var current = original;
      var matched = false;
      var applied = false;
      var nimTagged = false;
      var majorTagged = false;

      for (final prepared in preparedRules) {
        if (!_ruleMatchesBankAccount(prepared.rule, current.bankAccount)) {
          continue;
        }

        final regex = prepared.descriptionRegex;
        String extractedNim = '';
        if (regex != null) {
          final match = regex.firstMatch(current.description);
          if (match == null) {
            continue;
          }
          if (prepared.rule.nimCaptureGroup <= match.groupCount) {
            extractedNim = match.group(prepared.rule.nimCaptureGroup) ?? '';
          }
        }

        matched = true;

        var nextDescription = current.description.trim();
        var nextBankAccount = current.bankAccount.trim();

        final prepend = prepared.rule.prependText.trim();
        if (prepend.isNotEmpty &&
            !nextDescription.toLowerCase().contains(prepend.toLowerCase())) {
          nextDescription = '$prepend $nextDescription'.trim();
          applied = true;
        }

        final nimDigits = extractedNim.replaceAll(RegExp(r'[^0-9]'), '');
        if (nimDigits.length >= 5 &&
            !RegExp(
              '\\b${RegExp.escape(nimDigits)}\\b',
            ).hasMatch(nextDescription)) {
          nextDescription = '$nextDescription NIM $nimDigits'.trim();
          applied = true;
          nimTagged = true;
        }

        final major = prepared.rule.majorLabel.trim();
        if (major.isNotEmpty) {
          final majorTag = 'PRODI $major';
          if (!nextDescription.toUpperCase().contains(majorTag.toUpperCase())) {
            nextDescription = '$nextDescription $majorTag'.trim();
            applied = true;
            majorTagged = true;
          }
        }

        final overrideAccount = prepared.rule.bankAccountOverride.trim();
        if (nextBankAccount.isEmpty && overrideAccount.isNotEmpty) {
          nextBankAccount = overrideAccount;
          applied = true;
        }

        current = BankMutationImportRow(
          mutationDate: current.mutationDate,
          description: nextDescription,
          amount: current.amount,
          isCredit: current.isCredit,
          referenceNo: current.referenceNo,
          bankAccount: nextBankAccount,
        );
        break;
      }

      if (matched) {
        matchedRows += 1;
      }
      if (applied) {
        appliedRows += 1;
      }
      if (nimTagged) {
        nimTaggedRows += 1;
      }
      if (majorTagged) {
        majorTaggedRows += 1;
      }

      resultRows.add(current);
    }

    return _BankMutationRuleApplyResult(
      rows: resultRows,
      matchedRows: matchedRows,
      appliedRows: appliedRows,
      nimTaggedRows: nimTaggedRows,
      majorTaggedRows: majorTaggedRows,
    );
  }

  bool _ruleMatchesBankAccount(BankAutoMatchRule rule, String bankAccount) {
    final pattern = rule.bankAccountPattern.trim();
    if (pattern.isEmpty) {
      return true;
    }
    return bankAccount.toLowerCase().contains(pattern.toLowerCase());
  }

  String _buildBankRuleId() {
    final base = 'rule-${DateTime.now().millisecondsSinceEpoch}';
    var id = base;
    var counter = 2;
    while (_bankAutoMatchRules.any((item) => item.id == id)) {
      id = '$base-$counter';
      counter += 1;
    }
    return id;
  }

  Future<void> _openBankAutoMatchRulesDialog() async {
    if (!_canManageMasterData) {
      _showErrorMessage('Aksi ini hanya untuk role owner/admin.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final sortedRules =
                List<BankAutoMatchRule>.from(_bankAutoMatchRules)..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

            return AlertDialog(
              title: const Text('Rule Auto-Match per Bank/Prodi'),
              content: SizedBox(
                width: 1180,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aturan ini diterapkan saat import mutasi untuk '
                        'menambahkan konteks NIM/PRODI sesuai pola bank.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final draft = await _openBankRuleEditorDialog();
                              if (!mounted || draft == null) {
                                return;
                              }
                              setState(() {
                                _bankAutoMatchRules = [
                                  ..._bankAutoMatchRules,
                                  BankAutoMatchRule(
                                    id: _buildBankRuleId(),
                                    name: draft.name,
                                    bankAccountPattern:
                                        draft.bankAccountPattern,
                                    majorLabel: draft.majorLabel,
                                    descriptionRegex: draft.descriptionRegex,
                                    nimCaptureGroup: draft.nimCaptureGroup,
                                    bankAccountOverride:
                                        draft.bankAccountOverride,
                                    prependText: draft.prependText,
                                    isEnabled: draft.isEnabled,
                                  ),
                                ];
                              });
                              setModalState(() {});
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah Rule'),
                          ),
                          Text(
                            'Total: ${sortedRules.length} '
                            '(aktif: ${sortedRules.where((item) => item.isEnabled).length})',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (sortedRules.isEmpty)
                        Text(
                          'Belum ada rule auto-match.',
                          style: TextStyle(color: Colors.grey.shade700),
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Aktif')),
                              DataColumn(label: Text('Nama Rule')),
                              DataColumn(label: Text('Filter Rekening')),
                              DataColumn(label: Text('Regex Deskripsi')),
                              DataColumn(label: Text('Group NIM')),
                              DataColumn(label: Text('Tag Prodi')),
                              DataColumn(label: Text('Override Rekening')),
                              DataColumn(label: Text('Prefix')),
                              DataColumn(label: Text('Aksi')),
                            ],
                            rows: sortedRules.map((rule) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Switch(
                                      value: rule.isEnabled,
                                      onChanged: (value) {
                                        setState(() {
                                          _bankAutoMatchRules =
                                              _bankAutoMatchRules
                                                  .map(
                                                    (item) => item.id == rule.id
                                                        ? item.copyWith(
                                                            isEnabled: value,
                                                          )
                                                        : item,
                                                  )
                                                  .toList();
                                        });
                                        setModalState(() {});
                                      },
                                    ),
                                  ),
                                  DataCell(Text(rule.name)),
                                  DataCell(
                                    Text(
                                      rule.bankAccountPattern.trim().isEmpty
                                          ? '-'
                                          : rule.bankAccountPattern,
                                    ),
                                  ),
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 220,
                                      ),
                                      child: Text(
                                        rule.descriptionRegex.trim().isEmpty
                                            ? '-'
                                            : rule.descriptionRegex,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(rule.nimCaptureGroup.toString()),
                                  ),
                                  DataCell(
                                    Text(
                                      rule.majorLabel.trim().isEmpty
                                          ? '-'
                                          : rule.majorLabel,
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      rule.bankAccountOverride.trim().isEmpty
                                          ? '-'
                                          : rule.bankAccountOverride,
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      rule.prependText.trim().isEmpty
                                          ? '-'
                                          : rule.prependText,
                                    ),
                                  ),
                                  DataCell(
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        OutlinedButton(
                                          onPressed: () async {
                                            final draft =
                                                await _openBankRuleEditorDialog(
                                                  initial:
                                                      _BankAutoMatchRuleDraft.fromRule(
                                                        rule,
                                                      ),
                                                );
                                            if (!mounted || draft == null) {
                                              return;
                                            }
                                            setState(() {
                                              _bankAutoMatchRules = _bankAutoMatchRules
                                                  .map(
                                                    (item) => item.id == rule.id
                                                        ? item.copyWith(
                                                            name: draft.name,
                                                            bankAccountPattern:
                                                                draft
                                                                    .bankAccountPattern,
                                                            majorLabel: draft
                                                                .majorLabel,
                                                            descriptionRegex: draft
                                                                .descriptionRegex,
                                                            nimCaptureGroup: draft
                                                                .nimCaptureGroup,
                                                            bankAccountOverride:
                                                                draft
                                                                    .bankAccountOverride,
                                                            prependText: draft
                                                                .prependText,
                                                            isEnabled:
                                                                draft.isEnabled,
                                                          )
                                                        : item,
                                                  )
                                                  .toList();
                                            });
                                            setModalState(() {});
                                          },
                                          child: const Text('Edit'),
                                        ),
                                        OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              _bankAutoMatchRules =
                                                  _bankAutoMatchRules
                                                      .where(
                                                        (item) =>
                                                            item.id != rule.id,
                                                      )
                                                      .toList();
                                            });
                                            setModalState(() {});
                                          },
                                          child: const Text('Hapus'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_BankAutoMatchRuleDraft?> _openBankRuleEditorDialog({
    _BankAutoMatchRuleDraft? initial,
  }) async {
    final nameController = TextEditingController(text: initial?.name ?? '');
    final bankPatternController = TextEditingController(
      text: initial?.bankAccountPattern ?? '',
    );
    final majorController = TextEditingController(
      text: initial?.majorLabel ?? '',
    );
    final regexController = TextEditingController(
      text: initial?.descriptionRegex ?? '',
    );
    final groupController = TextEditingController(
      text: (initial?.nimCaptureGroup ?? 1).toString(),
    );
    final overrideController = TextEditingController(
      text: initial?.bankAccountOverride ?? '',
    );
    final prependController = TextEditingController(
      text: initial?.prependText ?? '',
    );
    var isEnabled = initial?.isEnabled ?? true;
    String errorText = '';

    final result = await showDialog<_BankAutoMatchRuleDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                initial == null
                    ? 'Tambah Rule Auto-Match'
                    : 'Edit Rule Auto-Match',
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama Rule',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: bankPatternController,
                        decoration: const InputDecoration(
                          labelText: 'Filter Rekening (contains, opsional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: regexController,
                        decoration: const InputDecoration(
                          labelText: 'Regex Deskripsi (opsional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: groupController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Capture Group NIM',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: majorController,
                        decoration: const InputDecoration(
                          labelText: 'Tag Prodi (opsional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: overrideController,
                        decoration: const InputDecoration(
                          labelText: 'Override Rekening jika kosong (opsional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: prependController,
                        decoration: const InputDecoration(
                          labelText: 'Prefix Deskripsi (opsional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: isEnabled,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Rule aktif'),
                        onChanged: (value) {
                          setModalState(() {
                            isEnabled = value;
                          });
                        },
                      ),
                      if (errorText.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText,
                            style: TextStyle(color: Colors.red.shade700),
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
                  onPressed: () {
                    final name = nameController.text.trim();
                    final bankPattern = bankPatternController.text.trim();
                    final major = majorController.text.trim();
                    final regex = regexController.text.trim();
                    final group =
                        int.tryParse(groupController.text.trim()) ?? 1;
                    final overrideAccount = overrideController.text.trim();
                    final prepend = prependController.text.trim();

                    if (name.isEmpty) {
                      setModalState(() {
                        errorText = 'Nama rule wajib diisi.';
                      });
                      return;
                    }
                    if (group <= 0) {
                      setModalState(() {
                        errorText = 'Capture group NIM harus >= 1.';
                      });
                      return;
                    }
                    if (regex.isNotEmpty) {
                      try {
                        RegExp(regex);
                      } catch (_) {
                        setModalState(() {
                          errorText = 'Regex deskripsi tidak valid.';
                        });
                        return;
                      }
                    }

                    Navigator.of(context).pop(
                      _BankAutoMatchRuleDraft(
                        name: name,
                        bankAccountPattern: bankPattern,
                        majorLabel: major,
                        descriptionRegex: regex,
                        nimCaptureGroup: group,
                        bankAccountOverride: overrideAccount,
                        prependText: prepend,
                        isEnabled: isEnabled,
                      ),
                    );
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    bankPatternController.dispose();
    majorController.dispose();
    regexController.dispose();
    groupController.dispose();
    overrideController.dispose();
    prependController.dispose();

    return result;
  }

  Future<void> _approveBankMutation(BankMutationItem item) async {
    if (!_canImportOrApproveMutation) {
      _showErrorMessage('Role Anda tidak memiliki akses approve mutasi.');
      return;
    }
    if (item.matchedInvoice == null) {
      _showErrorMessage('Mutasi ini belum memiliki tagihan target.');
      return;
    }

    try {
      await _bankMutationApi.approveMutation(
        token: _effectiveToken,
        mutationId: item.id,
        invoiceId: item.matchedInvoice!.id,
      );
      final syncResult = _syncApprovedBankMutationToLocalState(item);
      await _loadBankMutations(force: true);
      if (syncResult.synced) {
        _showInfoMessage(
          'Mutasi #${item.id} di-approve dan sinkron lokal '
          '${_formatRupiah(syncResult.appliedAmount)} berhasil.',
        );
      } else {
        _showInfoMessage(
          'Mutasi #${item.id} berhasil di-approve. Sinkron lokal dilewati: '
          '${syncResult.reason}.',
        );
      }
    } catch (error) {
      _showErrorMessage(
        _readableError(error, fallback: 'Gagal approve mutasi.'),
      );
    }
  }

  Future<void> _rejectBankMutation(BankMutationItem item) async {
    if (!_canImportOrApproveMutation) {
      _showErrorMessage('Role Anda tidak memiliki akses reject mutasi.');
      return;
    }
    try {
      await _bankMutationApi.rejectMutation(
        token: _effectiveToken,
        mutationId: item.id,
      );
      await _loadBankMutations(force: true);
      _showInfoMessage('Mutasi #${item.id} ditandai reject.');
    } catch (error) {
      _showErrorMessage(
        _readableError(error, fallback: 'Gagal reject mutasi.'),
      );
    }
  }

  bool _canApproveBankMutationItem(
    BankMutationItem item, {
    double minConfidence = 0,
  }) {
    return _canImportOrApproveMutation &&
        item.matchedInvoice != null &&
        (item.matchStatus == 'matched' || item.matchStatus == 'candidate') &&
        item.confidence >= minConfidence;
  }

  bool _canRejectBankMutationItem(BankMutationItem item) {
    return _canImportOrApproveMutation &&
        item.matchStatus != 'approved' &&
        item.matchStatus != 'rejected';
  }

  List<BankMutationItem> _bankMutationDisplayItems() {
    final minConfidence = _bankMutationMinConfidence;
    final filtered = _bankMutations.where(
      (item) => item.confidence >= minConfidence,
    );
    return filtered.toList();
  }

  Future<bool> _confirmBankMutationBatchAction({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Lanjut'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _approveBankMutationBatch() async {
    if (!_canImportOrApproveMutation) {
      _showErrorMessage('Role Anda tidak memiliki akses approve mutasi.');
      return;
    }
    if (_isBankMutationBatchProcessing) {
      return;
    }

    final candidates = _bankMutationDisplayItems().where((item) {
      return _canApproveBankMutationItem(
        item,
        minConfidence: _bankMutationMinConfidence,
      );
    }).toList();

    if (candidates.isEmpty) {
      _showInfoMessage('Tidak ada mutasi yang memenuhi syarat approve massal.');
      return;
    }

    final confirmed = await _confirmBankMutationBatchAction(
      title: 'Approve Massal Mutasi',
      message:
          'Akan approve ${candidates.length} mutasi (skor >= '
          '${_bankMutationMinConfidence.toStringAsFixed(0)}%). Lanjutkan?',
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isBankMutationBatchProcessing = true;
    });

    var success = 0;
    var failed = 0;
    var synced = 0;
    var skippedSync = 0;
    try {
      for (final item in candidates) {
        try {
          await _bankMutationApi.approveMutation(
            token: _effectiveToken,
            mutationId: item.id,
            invoiceId: item.matchedInvoice!.id,
          );
          success += 1;
          final syncResult = _syncApprovedBankMutationToLocalState(item);
          if (syncResult.synced) {
            synced += 1;
          } else {
            skippedSync += 1;
          }
        } catch (_) {
          failed += 1;
        }
      }

      await _loadBankMutations(force: true);
      if (mounted) {
        _showInfoMessage(
          'Approve massal selesai. Berhasil: $success, gagal: $failed, '
          'sinkron lokal: $synced, dilewati: $skippedSync.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBankMutationBatchProcessing = false;
        });
      }
    }
  }

  _BankMutationLocalSyncResult _syncApprovedBankMutationToLocalState(
    BankMutationItem item,
  ) {
    if (_hasLocalPostingForBankMutation(item.id)) {
      return const _BankMutationLocalSyncResult.skipped(
        'mutasi sudah pernah diposting ke lokal',
      );
    }

    if (!item.isCredit) {
      return const _BankMutationLocalSyncResult.skipped(
        'mutasi debit tidak diposting sebagai pemasukan',
      );
    }

    final invoice = item.matchedInvoice;
    if (invoice == null) {
      return const _BankMutationLocalSyncResult.skipped(
        'tagihan hasil match tidak ditemukan',
      );
    }

    final resolvedNim = _resolveBankMutationNim(item);
    if (resolvedNim.isEmpty) {
      return const _BankMutationLocalSyncResult.skipped(
        'NIM tidak ditemukan pada hasil match',
      );
    }

    final studentIndex = _students.indexWhere(
      (student) => student.nim == resolvedNim,
    );
    if (studentIndex < 0) {
      return _BankMutationLocalSyncResult.skipped(
        'mahasiswa NIM $resolvedNim tidak ada di data lokal',
      );
    }

    final paymentType = _findPaymentTypeByInvoiceName(invoice.paymentTypeName);
    if (paymentType == null) {
      return _BankMutationLocalSyncResult.skipped(
        'jenis tagihan "${invoice.paymentTypeName}" tidak ditemukan di data lokal',
      );
    }

    final student = _students[studentIndex];
    final remainingAmount = _remainingAmountFor(student, paymentType);
    if (remainingAmount <= 0) {
      return const _BankMutationLocalSyncResult.skipped('tagihan sudah lunas');
    }

    final incomingAmount = item.amount > 0 ? item.amount : 0;
    if (incomingAmount <= 0) {
      return const _BankMutationLocalSyncResult.skipped(
        'nominal mutasi tidak valid',
      );
    }
    final appliedAmount = incomingAmount > remainingAmount
        ? remainingAmount
        : incomingAmount;

    final transactionStatus = _autoReconcileEnabled
        ? FinanceTransactionStatus.completed
        : FinanceTransactionStatus.pending;

    setState(() {
      _students = List<StudentAccount>.from(_students)
        ..[studentIndex] = _recordStudentPayment(
          student,
          paymentType.id,
          appliedAmount,
        );
      _ledgerBalance += appliedAmount;
      _transactions = [
        FinanceTransaction(
          category: paymentType.name,
          description:
              'Auto-match mutasi bank #${item.id} - ${student.nim} - ${student.name}',
          date: DateTime.now(),
          amount: appliedAmount,
          isIncome: true,
          status: transactionStatus,
          studentNim: student.nim,
          paymentTypeId: paymentType.id,
          paymentMethod: 'bank_transfer',
        ),
        ..._transactions,
      ];
    });

    return _BankMutationLocalSyncResult.synced(appliedAmount);
  }

  String _resolveBankMutationNim(BankMutationItem item) {
    final primary = (item.matchedStudent?.nim ?? item.parsedNim).trim();
    final normalizedPrimary = _normalizeMaybeNim(primary);
    if (normalizedPrimary.isNotEmpty) {
      return normalizedPrimary;
    }

    final descriptionMatch = RegExp(
      r'\b\d{5,15}\b',
    ).firstMatch(item.description);
    if (descriptionMatch != null) {
      return descriptionMatch.group(0) ?? '';
    }
    return '';
  }

  String _normalizeMaybeNim(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return '';
    }
    if (RegExp(r'^\d{5,15}$').hasMatch(text)) {
      return text;
    }
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 5) {
      return digits;
    }
    return '';
  }

  bool _hasLocalPostingForBankMutation(int mutationId) {
    final marker = '#$mutationId';
    return _transactions.any((item) {
      final description = item.description.toLowerCase();
      return description.contains('mutasi bank') &&
          description.contains(marker);
    });
  }

  List<BankMutationItem> _manualMatchableBankMutations() {
    final items = _bankMutationDisplayItems().where((item) {
      if (!item.isCredit) {
        return false;
      }
      if (item.matchStatus == 'approved' || item.matchStatus == 'rejected') {
        return false;
      }
      return true;
    }).toList();
    items.sort((a, b) {
      final dateA = a.mutationDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = b.mutationDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });
    return items;
  }

  List<PaymentType> _availablePaymentTypesForStudent(StudentAccount student) {
    final result = _paymentTypes.where((paymentType) {
      if (!_isPaymentTypeApplicable(student, paymentType)) {
        return false;
      }
      return _remainingAmountFor(student, paymentType) > 0;
    }).toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<void> _openManualBankMutationMatchDialog({
    BankMutationItem? initialMutation,
  }) async {
    if (_students.isEmpty || _paymentTypes.isEmpty) {
      _showErrorMessage('Data mahasiswa/jenis pembayaran belum tersedia.');
      return;
    }

    final mutations = _manualMatchableBankMutations();
    if (mutations.isEmpty) {
      _showInfoMessage('Tidak ada mutasi transfer yang perlu diproses manual.');
      return;
    }

    var selectedMutation = initialMutation;
    if (selectedMutation == null ||
        !mutations.any((item) => item.id == selectedMutation!.id)) {
      selectedMutation = mutations.first;
    }

    String? selectedNim;
    String? selectedPaymentTypeId;
    final amountController = TextEditingController();
    var shouldApproveBackend = _canImportOrApproveMutation;
    var isSubmitting = false;
    String errorText = '';

    void applyDefaultsForMutation(BankMutationItem mutation) {
      selectedNim = null;
      selectedPaymentTypeId = null;
      final resolvedNim = _resolveBankMutationNim(mutation);
      if (_students.any((item) => item.nim == resolvedNim)) {
        selectedNim = resolvedNim;
      }
      amountController.text = mutation.amount.toString();
      final matchedName = mutation.matchedInvoice?.paymentTypeName ?? '';
      final matchedType = _findPaymentTypeByInvoiceName(matchedName);
      if (matchedType != null) {
        selectedPaymentTypeId = matchedType.id;
      }
    }

    applyDefaultsForMutation(selectedMutation);

    final result = await showDialog<_ManualBankMutationMatchSubmission>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final selectedStudent = selectedNim == null
                ? null
                : _students.firstWhere(
                    (item) => item.nim == selectedNim,
                    orElse: () => _students.first,
                  );
            final availableTypes = selectedStudent == null
                ? const <PaymentType>[]
                : _availablePaymentTypesForStudent(selectedStudent);
            if (selectedPaymentTypeId != null &&
                !availableTypes.any(
                  (item) => item.id == selectedPaymentTypeId,
                )) {
              selectedPaymentTypeId = null;
            }
            final selectedPaymentType = selectedPaymentTypeId == null
                ? null
                : availableTypes.firstWhere(
                    (item) => item.id == selectedPaymentTypeId,
                    orElse: () => availableTypes.first,
                  );

            final selectedRemaining =
                selectedStudent == null || selectedPaymentType == null
                ? null
                : _remainingAmountFor(selectedStudent, selectedPaymentType);

            return AlertDialog(
              title: const Text('Proses Transfer Non-VA'),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selectedMutation!.id,
                        decoration: const InputDecoration(
                          labelText: 'Pilih Mutasi Transfer',
                          border: OutlineInputBorder(),
                        ),
                        items: mutations
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: item.id,
                                child: Text(
                                  '#${item.id} | ${_formatDateTime(item.mutationDate)} | ${_formatRupiah(item.amount)}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                if (value == null) {
                                  return;
                                }
                                final found = mutations.firstWhere(
                                  (item) => item.id == value,
                                );
                                setModalState(() {
                                  selectedMutation = found;
                                  errorText = '';
                                  applyDefaultsForMutation(found);
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          selectedMutation!.description,
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedNim,
                        decoration: const InputDecoration(
                          labelText: 'Pilih Mahasiswa (NIM)',
                          border: OutlineInputBorder(),
                        ),
                        items: _students
                            .map(
                              (student) => DropdownMenuItem<String>(
                                value: student.nim,
                                child: Text('${student.nim} - ${student.name}'),
                              ),
                            )
                            .toList(),
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                setModalState(() {
                                  selectedNim = value;
                                  selectedPaymentTypeId = null;
                                  errorText = '';
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPaymentTypeId,
                        decoration: const InputDecoration(
                          labelText: 'Jenis Tagihan',
                          border: OutlineInputBorder(),
                        ),
                        items: availableTypes
                            .map(
                              (paymentType) => DropdownMenuItem<String>(
                                value: paymentType.id,
                                child: Text(
                                  '${paymentType.name} (sisa ${_formatRupiah(_remainingAmountFor(selectedStudent!, paymentType))})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                setModalState(() {
                                  selectedPaymentTypeId = value;
                                  errorText = '';
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Nominal Diposting',
                          border: const OutlineInputBorder(),
                          prefixText: 'Rp',
                          helperText: selectedRemaining == null
                              ? null
                              : 'Sisa tagihan: ${_formatRupiah(selectedRemaining)}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: shouldApproveBackend,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Approve juga ke backend'),
                        subtitle: const Text(
                          'Jika aktif, status mutasi backend ikut berubah menjadi approved.',
                        ),
                        onChanged: _canImportOrApproveMutation && !isSubmitting
                            ? (value) {
                                setModalState(() {
                                  shouldApproveBackend = value;
                                });
                              }
                            : null,
                      ),
                      if (!_canImportOrApproveMutation)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Backend approve tidak tersedia untuk role/sesi ini.',
                            style: TextStyle(color: Colors.orange.shade800),
                          ),
                        ),
                      if (errorText.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          final amount =
                              int.tryParse(amountController.text.trim()) ?? 0;
                          if (selectedMutation == null) {
                            setModalState(() {
                              errorText = 'Mutasi belum dipilih.';
                            });
                            return;
                          }
                          if (selectedNim == null || selectedNim!.isEmpty) {
                            setModalState(() {
                              errorText = 'Mahasiswa wajib dipilih.';
                            });
                            return;
                          }
                          if (selectedPaymentTypeId == null ||
                              selectedPaymentTypeId!.isEmpty) {
                            setModalState(() {
                              errorText = 'Jenis tagihan wajib dipilih.';
                            });
                            return;
                          }
                          if (amount <= 0) {
                            setModalState(() {
                              errorText = 'Nominal posting tidak valid.';
                            });
                            return;
                          }
                          setModalState(() {
                            isSubmitting = true;
                          });
                          Navigator.of(context).pop(
                            _ManualBankMutationMatchSubmission(
                              mutation: selectedMutation!,
                              studentNim: selectedNim!,
                              paymentTypeId: selectedPaymentTypeId!,
                              amount: amount,
                              approveBackend: shouldApproveBackend,
                            ),
                          );
                        },
                  child: const Text('Proses'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();

    if (!mounted || result == null) {
      return;
    }

    await _processManualBankMutationMatch(result);
  }

  Future<void> _processManualBankMutationMatch(
    _ManualBankMutationMatchSubmission submission,
  ) async {
    final mutation = submission.mutation;
    if (_hasLocalPostingForBankMutation(mutation.id)) {
      _showInfoMessage(
        'Mutasi #${mutation.id} sudah pernah diposting ke lokal.',
      );
      return;
    }

    final studentIndex = _students.indexWhere(
      (student) => student.nim == submission.studentNim,
    );
    if (studentIndex < 0) {
      _showErrorMessage('Mahasiswa tidak ditemukan di data lokal.');
      return;
    }

    final paymentType = _findPaymentTypeById(submission.paymentTypeId);
    if (paymentType == null) {
      _showErrorMessage('Jenis tagihan tidak ditemukan.');
      return;
    }

    final student = _students[studentIndex];
    final remainingAmount = _remainingAmountFor(student, paymentType);
    if (remainingAmount <= 0) {
      _showErrorMessage('Tagihan mahasiswa ini sudah lunas.');
      return;
    }

    final amount = submission.amount > remainingAmount
        ? remainingAmount
        : submission.amount;
    if (amount <= 0) {
      _showErrorMessage('Nominal posting tidak valid.');
      return;
    }

    if (submission.approveBackend) {
      if (!_canImportOrApproveMutation) {
        _showErrorMessage('Sesi ini tidak memiliki akses approve backend.');
        return;
      }
      try {
        await _bankMutationApi.approveMutation(
          token: _effectiveToken,
          mutationId: mutation.id,
          invoiceId: mutation.matchedInvoice?.id,
        );
      } catch (error) {
        _showErrorMessage(
          _readableError(error, fallback: 'Gagal approve mutasi di backend.'),
        );
        return;
      }
    }

    final transactionStatus = _autoReconcileEnabled
        ? FinanceTransactionStatus.completed
        : FinanceTransactionStatus.pending;

    setState(() {
      _students = List<StudentAccount>.from(_students)
        ..[studentIndex] = _recordStudentPayment(
          student,
          paymentType.id,
          amount,
        );
      _ledgerBalance += amount;
      _transactions = [
        FinanceTransaction(
          category: paymentType.name,
          description:
              'Manual match mutasi bank #${mutation.id} - ${student.nim} - ${student.name}',
          date: DateTime.now(),
          amount: amount,
          isIncome: true,
          status: transactionStatus,
          studentNim: student.nim,
          paymentTypeId: paymentType.id,
          paymentMethod: 'bank_transfer',
        ),
        ..._transactions,
      ];
    });

    if (submission.approveBackend) {
      await _loadBankMutations(force: true);
      _showInfoMessage(
        'Transfer #${mutation.id} berhasil diposting dan di-approve backend.',
      );
      return;
    }

    _showInfoMessage(
      'Transfer #${mutation.id} berhasil diposting ke lokal '
      '(status backend belum diubah).',
    );
  }

  Future<void> _rejectUnmatchedBankMutationBatch() async {
    if (!_canImportOrApproveMutation) {
      _showErrorMessage('Role Anda tidak memiliki akses reject mutasi.');
      return;
    }
    if (_isBankMutationBatchProcessing) {
      return;
    }

    final candidates = _bankMutationDisplayItems().where((item) {
      return item.matchStatus == 'unmatched' &&
          _canRejectBankMutationItem(item);
    }).toList();

    if (candidates.isEmpty) {
      _showInfoMessage('Tidak ada mutasi unmatched untuk reject massal.');
      return;
    }

    final confirmed = await _confirmBankMutationBatchAction(
      title: 'Reject Massal Unmatched',
      message:
          'Akan reject ${candidates.length} mutasi unmatched '
          '(skor >= ${_bankMutationMinConfidence.toStringAsFixed(0)}% sesuai tampilan). '
          'Lanjutkan?',
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isBankMutationBatchProcessing = true;
    });

    var success = 0;
    var failed = 0;
    try {
      for (final item in candidates) {
        try {
          await _bankMutationApi.rejectMutation(
            token: _effectiveToken,
            mutationId: item.id,
          );
          success += 1;
        } catch (_) {
          failed += 1;
        }
      }

      await _loadBankMutations(force: true);
      if (mounted) {
        _showInfoMessage(
          'Reject massal selesai. Berhasil: $success, gagal: $failed.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBankMutationBatchProcessing = false;
        });
      }
    }
  }

  Future<void> _exportBankMutationReviewExcel() async {
    try {
      final items = _bankMutationDisplayItems();
      if (items.isEmpty) {
        _showInfoMessage('Tidak ada data mutasi untuk diexport.');
        return;
      }

      final rows = items.map((item) {
        final nimText = item.matchedStudent?.nim ?? item.parsedNim;
        final invoiceText = item.matchedInvoice == null
            ? '-'
            : '${item.matchedInvoice!.paymentTypeName} '
                  '(${_formatRupiah(item.matchedInvoice!.amountDue)})';
        return <String>[
          _formatDateTime(item.mutationDate),
          item.referenceNo,
          item.description,
          nimText.isEmpty ? '-' : nimText,
          invoiceText,
          _formatRupiah(item.amount),
          _bankMutationStatusLabel(item.matchStatus),
          '${item.confidence.toStringAsFixed(0)}%',
          item.matchReason.isEmpty ? '-' : item.matchReason,
        ];
      }).toList();

      await ExcelExportService.exportRows(
        fileName: 'review_mutasi_bank_${_fileTimestamp()}',
        sheetName: 'MutasiBank',
        headers: const [
          'Tanggal',
          'Referensi',
          'Keterangan',
          'NIM',
          'Tagihan',
          'Nominal',
          'Status Match',
          'Skor',
          'Alasan Match',
        ],
        rows: rows,
      );
      _showInfoMessage('Data review mutasi berhasil diunduh.');
    } catch (_) {
      _showErrorMessage('Gagal mengunduh data review mutasi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 260,
              child: SidebarMenu(
                selectedIndex: _selectedIndex,
                onItemSelected: _onItemSelected,
              ),
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(financeAdminMenuTitleForIndex(_selectedIndex)),
        centerTitle: false,
      ),
      drawer: Drawer(
        child: SidebarMenu(
          selectedIndex: _selectedIndex,
          onItemSelected: (index) {
            _onItemSelected(index);
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case FinanceMenuIndex.dashboard:
        return _buildDashboardContent();
      case FinanceMenuIndex.tagihan:
        return _buildPaymentTypeContent();
      case FinanceMenuIndex.mutasiBank:
        return _buildTransactionContent();
      case FinanceMenuIndex.rekonsiliasi:
        return _buildReconciliationContent();
      case FinanceMenuIndex.verifikasiManual:
        return _buildManualVerificationContent();
      case FinanceMenuIndex.pelunasanPenyesuaian:
        return _buildSettlementAdjustmentContent();
      case FinanceMenuIndex.laporan:
        return _buildReportContent();
      case FinanceMenuIndex.pengaturan:
        return _buildSettingsContent();
      default:
        return _buildDashboardContent();
    }
  }

  Widget _buildDashboardContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final horizontalPadding = compact ? 16.0 : 32.0;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: compact ? 20 : 32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                _buildHeaderInfo(),
                const SizedBox(height: 16),
                _buildActions(compact: true),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_buildHeaderInfo(), _buildActions(compact: false)],
                ),
              ],
              const SizedBox(height: 28),
              SummaryCards(
                ledgerBalance: _ledgerBalance,
                totalIncome: _totalIncome,
                totalExpense: _totalExpense,
                activeStudentCount: _students.length,
                unpaidBillCount: _unpaidBillCount,
                realBalance: _realBalance,
                onActiveStudentTap: _openActiveStudentsDialog,
                onUnpaidBillTap: _openUnpaidBillsDialog,
              ),
              const SizedBox(height: 32),
              _buildReconciliationBanner(),
              const SizedBox(height: 28),
              const Text(
                'Transaksi Terakhir',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TransactionTable(transactions: _transactions.take(8).toList()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionContent() {
    if (_canUseBankMutationApi &&
        !_bankMutationLoadInitialized &&
        !_isBankMutationLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadBankMutations());
      });
    }
    final displayedMutations = _bankMutationDisplayItems();
    final readyApproveCount = displayedMutations
        .where(
          (item) => _canApproveBankMutationItem(
            item,
            minConfidence: _bankMutationMinConfidence,
          ),
        )
        .length;
    final readyRejectCount = displayedMutations
        .where(
          (item) =>
              item.matchStatus == 'unmatched' &&
              _canRejectBankMutationItem(item),
        )
        .length;
    final isBankMutationBusy =
        _isBankMutationLoading || _isBankMutationBatchProcessing;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Semua Transaksi',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Pemasukan dan pengeluaran akan otomatis mengubah saldo buku.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          TransactionTable(transactions: _transactions),
          const SizedBox(height: 28),
          const Text(
            'Auto-Match Mutasi Bank',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Import mutasi bank lalu sistem menandai Hijau (siap approve) atau Kuning (cek manual).',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          if (!_canUseBankMutationApi)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'Fitur mutasi bank aktif jika login ke backend (API_BASE_URL + token sesi).',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _downloadBankMutationTemplate,
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Template Mutasi'),
                ),
                OutlinedButton.icon(
                  onPressed: _openBankAutoMatchRulesDialog,
                  icon: const Icon(Icons.rule_outlined),
                  label: const Text('Aturan Auto-Match'),
                ),
                ElevatedButton.icon(
                  onPressed: isBankMutationBusy || !_canImportOrApproveMutation
                      ? null
                      : _importBankMutationFile,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import Mutasi Excel/CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: isBankMutationBusy
                      ? null
                      : () => _openManualBankMutationMatchDialog(),
                  icon: const Icon(Icons.sync_alt_outlined),
                  label: const Text('Proses Transfer Non-VA'),
                ),
                OutlinedButton.icon(
                  onPressed: isBankMutationBusy
                      ? null
                      : () => unawaited(_loadBankMutations(force: true)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBankMutationStatus,
                    decoration: const InputDecoration(
                      labelText: 'Filter Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem<String>(
                        value: '',
                        child: Text('Semua Status'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'matched',
                        child: Text('Hijau (Matched)'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'candidate',
                        child: Text('Kuning (Candidate)'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'unmatched',
                        child: Text('Kuning (Unmatched)'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'approved',
                        child: Text('Approved'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'rejected',
                        child: Text('Rejected'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBankMutationStatus = value ?? '';
                      });
                      unawaited(_loadBankMutations(force: true));
                    },
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<double>(
                    initialValue: _bankMutationMinConfidence,
                    decoration: const InputDecoration(
                      labelText: 'Min Skor',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem<double>(
                        value: 0,
                        child: Text('Semua Skor'),
                      ),
                      DropdownMenuItem<double>(
                        value: 50,
                        child: Text('>= 50%'),
                      ),
                      DropdownMenuItem<double>(
                        value: 70,
                        child: Text('>= 70%'),
                      ),
                      DropdownMenuItem<double>(
                        value: 80,
                        child: Text('>= 80%'),
                      ),
                      DropdownMenuItem<double>(
                        value: 90,
                        child: Text('>= 90%'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _bankMutationMinConfidence = value ?? 0;
                      });
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isBankMutationBusy
                      ? null
                      : _exportBankMutationReviewExcel,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export Review'),
                ),
                ElevatedButton.icon(
                  onPressed: isBankMutationBusy || readyApproveCount == 0
                      ? null
                      : _approveBankMutationBatch,
                  icon: const Icon(Icons.done_all_outlined),
                  label: Text('Approve Massal ($readyApproveCount)'),
                ),
                OutlinedButton.icon(
                  onPressed: isBankMutationBusy || readyRejectCount == 0
                      ? null
                      : _rejectUnmatchedBankMutationBatch,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: Text('Reject Unmatched ($readyRejectCount)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Data tampil: ${displayedMutations.length} dari ${_bankMutations.length} '
              '(min skor ${_bankMutationMinConfidence.toStringAsFixed(0)}%).',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              'Rule Auto-Match aktif: '
              '${_bankAutoMatchRules.where((item) => item.isEnabled).length} '
              'dari ${_bankAutoMatchRules.length}.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildReportMetric(
                  'Hijau',
                  (_bankMutationCounts['matched'] ?? 0).toString(),
                ),
                _buildReportMetric(
                  'Kuning',
                  ((_bankMutationCounts['candidate'] ?? 0) +
                          (_bankMutationCounts['unmatched'] ?? 0))
                      .toString(),
                ),
                _buildReportMetric(
                  'Approved',
                  (_bankMutationCounts['approved'] ?? 0).toString(),
                ),
                _buildReportMetric(
                  'Rejected',
                  (_bankMutationCounts['rejected'] ?? 0).toString(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildBankMutationTable(),
          ],
        ],
      ),
    );
  }

  Widget _buildBankMutationTable() {
    final rows = _bankMutationDisplayItems();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: _isBankMutationLoading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          : rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _bankMutations.isEmpty
                    ? 'Belum ada data mutasi bank.'
                    : 'Tidak ada data yang sesuai filter skor/status.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Tanggal')),
                  DataColumn(label: Text('Keterangan')),
                  DataColumn(label: Text('NIM')),
                  DataColumn(label: Text('Tagihan')),
                  DataColumn(label: Text('Nominal')),
                  DataColumn(label: Text('Status Match')),
                  DataColumn(label: Text('Skor')),
                  DataColumn(label: Text('Aksi')),
                ],
                rows: rows.map(_buildBankMutationRow).toList(),
              ),
            ),
    );
  }

  DataRow _buildBankMutationRow(BankMutationItem item) {
    final statusText = _bankMutationStatusLabel(item.matchStatus);
    final statusColor = _bankMutationStatusColor(item.matchStatus);
    final reason = item.matchReason.trim();
    final nimText = item.matchedStudent?.nim ?? item.parsedNim;
    final invoiceText = item.matchedInvoice == null
        ? '-'
        : '${item.matchedInvoice!.paymentTypeName} (${_formatRupiah(item.matchedInvoice!.amountDue)})';
    final canApprove = _canApproveBankMutationItem(item);
    final canReject = _canRejectBankMutationItem(item);
    final isBusy = _isBankMutationLoading || _isBankMutationBatchProcessing;
    final canManualProcess =
        item.isCredit &&
        item.matchStatus != 'approved' &&
        item.matchStatus != 'rejected' &&
        !_hasLocalPostingForBankMutation(item.id);

    return DataRow(
      cells: [
        DataCell(Text(_formatDateTime(item.mutationDate))),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              reason.isEmpty
                  ? item.description
                  : '${item.description}\n$reason',
            ),
          ),
        ),
        DataCell(Text(nimText.isEmpty ? '-' : nimText)),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(invoiceText),
          ),
        ),
        DataCell(Text(_formatRupiah(item.amount))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              statusText,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        DataCell(Text('${item.confidence.toStringAsFixed(0)}%')),
        DataCell(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: canApprove && !isBusy
                    ? () => _approveBankMutation(item)
                    : null,
                child: const Text('Approve'),
              ),
              OutlinedButton(
                onPressed: canManualProcess && !isBusy
                    ? () => _openManualBankMutationMatchDialog(
                        initialMutation: item,
                      )
                    : null,
                child: const Text('Proses'),
              ),
              OutlinedButton(
                onPressed: canReject && !isBusy
                    ? () => _rejectBankMutation(item)
                    : null,
                child: const Text('Reject'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _bankMutationStatusLabel(String status) {
    switch (status) {
      case 'matched':
        return 'Hijau';
      case 'candidate':
        return 'Kuning';
      case 'unmatched':
        return 'Kuning';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  Color _bankMutationStatusColor(String status) {
    switch (status) {
      case 'matched':
        return Colors.green.shade700;
      case 'candidate':
        return Colors.orange.shade800;
      case 'unmatched':
        return Colors.amber.shade800;
      case 'approved':
        return Colors.blue.shade700;
      case 'rejected':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Widget _buildReconciliationContent() {
    final difference = _balanceDifference;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Text(
                'Rekonsiliasi Saldo',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              OutlinedButton.icon(
                onPressed: _openReconcileDialog,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Input Saldo Rekening'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pencocokan saldo berjalan internal di aplikasi ini tanpa integrasi sistem eksternal.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildReportMetric('Saldo Buku', _formatRupiah(_ledgerBalance)),
              _buildReportMetric(
                'Saldo Rekening',
                _realBalance == null ? '-' : _formatRupiah(_realBalance!),
              ),
              _buildReportMetric(
                'Antrean Verifikasi',
                '$_pendingTransactionCount pending / $_failedTransactionCount gagal',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              difference == null
                  ? 'Saldo rekening belum diinput.'
                  : difference == 0
                  ? 'Saldo buku dan rekening sudah cocok.'
                  : 'Selisih ${_formatRupiah(difference.abs())} '
                        '(${difference > 0 ? 'rekening lebih besar' : 'rekening lebih kecil'}).',
              style: TextStyle(
                color: difference == null
                    ? Colors.grey.shade700
                    : difference == 0
                    ? Colors.green.shade700
                    : Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (difference != null && difference != 0)
            ElevatedButton.icon(
              onPressed: _applyReconciliationAdjustment,
              icon: const Icon(Icons.rule_folder_outlined),
              label: const Text('Buat Penyesuaian Selisih'),
            ),
        ],
      ),
    );
  }

  Widget _buildManualVerificationContent() {
    final queue = _transactions
        .asMap()
        .entries
        .where(
          (entry) => entry.value.status != FinanceTransactionStatus.completed,
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Verifikasi Manual',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tinjau transaksi yang pending/gagal lalu tetapkan status final.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          if (queue.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'Tidak ada antrean verifikasi.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          ...queue.map(_buildVerificationTile),
        ],
      ),
    );
  }

  Widget _buildSettlementAdjustmentContent() {
    final bills = _buildOutstandingBills();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Text(
                'Pelunasan / Penyesuaian',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _openAdjustmentDialog,
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Tambah Penyesuaian'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Kelola pelunasan tagihan dan koreksi saldo langsung dari sistem ini.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          if (bills.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'Seluruh tagihan mahasiswa sudah lunas.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          ...bills.map(_buildOutstandingBillTile),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    if (_canManageMasterData &&
        _isAccessControlled &&
        _canCallAdminApi &&
        !_adminDataLoaded &&
        !_isAdminDataLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadAdminPanelData());
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pengaturan Operasional',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Seluruh konfigurasi berlaku untuk aplikasi lokal ini dan tidak terhubung sistem lain.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  value: _autoReconcileEnabled,
                  onChanged: (value) {
                    setState(() {
                      _autoReconcileEnabled = value;
                    });
                  },
                  title: const Text('Rekonsiliasi otomatis'),
                  subtitle: const Text(
                    'Transaksi baru langsung selesai jika proses cocok.',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _strictPrerequisiteValidation,
                  onChanged: (value) {
                    setState(() {
                      _strictPrerequisiteValidation = value;
                    });
                  },
                  title: const Text('Validasi prasyarat ketat'),
                  subtitle: const Text(
                    'Cegah pembayaran jika prasyarat belum terpenuhi.',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _allowManualSettlementOverride,
                  onChanged: (value) {
                    setState(() {
                      _allowManualSettlementOverride = value;
                    });
                  },
                  title: const Text('Izinkan override pelunasan manual'),
                  subtitle: const Text(
                    'Admin bisa melunasi walau prasyarat belum lunas.',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _notifyDifferenceOnDashboard,
                  onChanged: (value) {
                    setState(() {
                      _notifyDifferenceOnDashboard = value;
                    });
                  },
                  title: const Text(
                    'Tampilkan notifikasi selisih di dashboard',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Nama Operator'),
                  subtitle: Text(_operatorName),
                  trailing: OutlinedButton(
                    onPressed: _openOperatorDialog,
                    child: const Text('Ubah'),
                  ),
                ),
                if (widget.signedInUsername?.trim().isNotEmpty == true) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Akun Login'),
                    subtitle: Text(widget.signedInUsername!),
                  ),
                ],
                if (widget.signedInRole?.trim().isNotEmpty == true) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Role Akses'),
                    subtitle: Text(widget.signedInRole!),
                  ),
                ],
                if (_canCallAdminApi) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Keamanan Akun'),
                    subtitle: const Text('Ubah password login Anda'),
                    trailing: OutlinedButton(
                      onPressed: _openChangePasswordDialog,
                      child: const Text('Ganti Password'),
                    ),
                  ),
                ],
                if (widget.onLogoutRequested != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Sesi Login'),
                    subtitle: const Text('Akhiri sesi pengguna saat ini'),
                    trailing: OutlinedButton(
                      onPressed: widget.onLogoutRequested,
                      child: const Text('Logout'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_canManageMasterData && _isAccessControlled) ...[
            const SizedBox(height: 16),
            const Text(
              'Manajemen User',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Kelola akun admin/operator untuk kantor ini.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            _buildAdminUsersCard(),
            const SizedBox(height: 16),
            const Text(
              'Audit Log',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Riwayat aktivitas penting (login, perubahan data, update state).',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            _buildAdminAuditLogsCard(),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _canManageMasterData
                  ? _resetAllData
                  : () => _showErrorMessage(
                      'Aksi ini hanya untuk role owner/admin.',
                    ),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Reset Semua Data'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentTypeContent() {
    final sortedStudents = List<StudentAccount>.from(_students)
      ..sort((a, b) => _compareNim(a.nim, b.nim));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Jenis Pembayaran',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _canManageMasterData
                    ? _openPaymentTypeDialog
                    : () => _showErrorMessage(
                        'Aksi ini hanya untuk role owner/admin.',
                      ),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Jenis'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._paymentTypes.map(_buildPaymentTypeTile),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Data Mahasiswa',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _canManageMasterData
                    ? _openAddStudentDialog
                    : () => _showErrorMessage(
                        'Aksi ini hanya untuk role owner/admin.',
                      ),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Tambah Mahasiswa'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _downloadStudentTemplate,
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Download Template Excel'),
              ),
              OutlinedButton.icon(
                onPressed: _canManageMasterData
                    ? _importStudentsFromExcel
                    : () => _showErrorMessage(
                        'Aksi ini hanya untuk role owner/admin.',
                      ),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import Mahasiswa Excel'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (sortedStudents.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'Belum ada data mahasiswa.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('NIM')),
                    DataColumn(label: Text('Nama')),
                    DataColumn(label: Text('Prodi')),
                    DataColumn(label: Text('Kelas')),
                    DataColumn(label: Text('Semester')),
                    DataColumn(label: Text('Beasiswa')),
                    DataColumn(label: Text('Cicilan')),
                    DataColumn(label: Text('Aksi')),
                  ],
                  rows: sortedStudents
                      .map(
                        (student) => DataRow(
                          cells: [
                            DataCell(Text(student.nim)),
                            DataCell(Text(student.name)),
                            DataCell(Text(student.major)),
                            DataCell(Text(student.className)),
                            DataCell(Text(student.semester.toString())),
                            DataCell(Text('${student.scholarshipPercent}%')),
                            DataCell(Text('${student.installmentTerms}x')),
                            DataCell(
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () =>
                                        _openStudentLedgerDialog(student),
                                    child: const Text('Buku Besar'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _canManageMasterData
                                        ? () => _openEditStudentDialog(student)
                                        : null,
                                    child: const Text('Edit'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _canManageMasterData
                                        ? () => _removeStudent(student)
                                        : null,
                                    child: const Text('Hapus'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    final difference = _balanceDifference;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Laporan Keuangan',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildReportMetric('Saldo Buku', _formatRupiah(_ledgerBalance)),
              _buildReportMetric(
                'Saldo Rekening',
                _realBalance == null ? '-' : _formatRupiah(_realBalance!),
              ),
              _buildReportMetric(
                'Total Pemasukan',
                _formatRupiah(_totalIncome),
              ),
              _buildReportMetric(
                'Total Pengeluaran',
                _formatRupiah(_totalExpense),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              difference == null
                  ? 'Belum ada data saldo rekening real. Klik "Cocokkan Rekening".'
                  : difference == 0
                  ? 'Saldo buku dan saldo rekening cocok.'
                  : 'Ada selisih ${_formatRupiah(difference.abs())} '
                        '(${difference > 0 ? 'rekening lebih besar' : 'rekening lebih kecil'}).',
              style: TextStyle(
                color: difference == null
                    ? Colors.grey.shade700
                    : difference == 0
                    ? Colors.green.shade700
                    : Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _exportClearanceStatusExcel,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Export Status Clearance'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TransactionTable(transactions: _transactions),
        ],
      ),
    );
  }

  Widget _buildPaymentTypeTile(PaymentType paymentType) {
    final requirementLabels = paymentType.prerequisiteTypeIds
        .map(_paymentTypeNameById)
        .toList();
    final scopeLabels = <String>[];
    if (paymentType.targetSemester != null) {
      scopeLabels.add('Semester ${paymentType.targetSemester}');
    }
    if (paymentType.targetMajor != null &&
        paymentType.targetMajor!.isNotEmpty) {
      scopeLabels.add('Prodi ${paymentType.targetMajor}');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                paymentType.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _formatRupiah(paymentType.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            requirementLabels.isEmpty
                ? 'Tanpa prasyarat'
                : 'Prasyarat: ${requirementLabels.join(', ')}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          if (scopeLabels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Berlaku untuk: ${scopeLabels.join(' | ')}',
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ADMINISTRATOR',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'Hi, $_operatorName',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildActions({required bool compact}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: compact ? WrapAlignment.start : WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: _openPaymentTypeDialog,
            icon: const Icon(Icons.add_card_outlined),
            label: const Text('Jenis Pembayaran'),
          ),
          ElevatedButton.icon(
            onPressed: _openPaymentDialog,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Input Pembayaran'),
          ),
          ElevatedButton.icon(
            onPressed: _openExpenseDialog,
            icon: const Icon(Icons.outbox_outlined),
            label: const Text('Saldo Output'),
          ),
          OutlinedButton.icon(
            onPressed: _openReconcileDialog,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Cocokkan Rekening'),
          ),
        ],
      ),
    );
  }

  Widget _buildReconciliationBanner() {
    if (!_notifyDifferenceOnDashboard) {
      return const SizedBox.shrink();
    }

    final difference = _balanceDifference;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        difference == null
            ? 'Belum ada saldo rekening real. Gunakan tombol "Cocokkan Rekening".'
            : difference == 0
            ? 'Saldo buku sudah sama dengan saldo rekening.'
            : 'Selisih saldo ${_formatRupiah(difference.abs())}, perlu dicocokkan.',
        style: TextStyle(
          color: difference == null
              ? Colors.grey.shade700
              : difference == 0
              ? Colors.green.shade700
              : Colors.orange.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildReportMetric(String label, String value) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationTile(MapEntry<int, FinanceTransaction> entry) {
    final transaction = entry.value;
    final statusLabel = _statusText(transaction.status);
    final statusColor = _statusColor(transaction.status);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  transaction.description,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${transaction.category} • '
            '${transaction.isIncome ? '+' : '-'}${_formatRupiah(transaction.amount)}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed:
                    transaction.status == FinanceTransactionStatus.completed
                    ? null
                    : () => _updateTransactionStatus(
                        entry.key,
                        FinanceTransactionStatus.completed,
                      ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Setujui'),
              ),
              OutlinedButton.icon(
                onPressed:
                    transaction.status == FinanceTransactionStatus.pending
                    ? null
                    : () => _updateTransactionStatus(
                        entry.key,
                        FinanceTransactionStatus.pending,
                      ),
                icon: const Icon(Icons.hourglass_bottom_outlined),
                label: const Text('Pendingkan'),
              ),
              OutlinedButton.icon(
                onPressed: transaction.status == FinanceTransactionStatus.failed
                    ? null
                    : () => _updateTransactionStatus(
                        entry.key,
                        FinanceTransactionStatus.failed,
                      ),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Tandai Gagal'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutstandingBillTile(_OutstandingBill bill) {
    final canSettle =
        _allowManualSettlementOverride || bill.missingPrerequisites.isEmpty;
    final statusLabel = bill.isBlocked
        ? 'Blocked Prasyarat'
        : bill.isOnTrackInstallment
        ? 'Cicilan On-track'
        : 'Terlambat';
    final statusColor = bill.isBlocked
        ? Colors.orange.shade800
        : bill.isOnTrackInstallment
        ? Colors.green.shade700
        : Colors.red.shade700;
    final statusBackground = bill.isBlocked
        ? Colors.orange.shade50
        : bill.isOnTrackInstallment
        ? Colors.green.shade50
        : Colors.red.shade50;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${bill.studentName} (${bill.nim})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatRupiah(bill.remainingAmount),
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBackground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tagihan: ${bill.paymentTypeName}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            'Netto ${_formatRupiah(bill.dueAmount)} | '
            'Terbayar ${_formatRupiah(bill.paidAmount)} | '
            'Sisa ${_formatRupiah(bill.remainingAmount)}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          if (bill.isOnTrackInstallment) ...[
            const SizedBox(height: 6),
            Text(
              'Status cicilan sesuai jalur, belum masuk daftar menunggak merah.',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (bill.missingPrerequisites.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Prasyarat belum lunas: ${bill.missingPrerequisites.join(', ')}',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: canSettle && bill.remainingAmount > 0
                ? () => _settleOutstandingBill(bill)
                : null,
            icon: const Icon(Icons.done_all_outlined),
            label: Text(
              canSettle
                  ? 'Lunaskan Sisa ${_formatRupiah(bill.remainingAmount)}'
                  : 'Aktifkan Override untuk Melunasi',
            ),
          ),
        ],
      ),
    );
  }

  List<_OutstandingBill> _buildOutstandingBills() {
    final result = <_OutstandingBill>[];
    for (
      var studentIndex = 0;
      studentIndex < _students.length;
      studentIndex++
    ) {
      final student = _students[studentIndex];
      for (final paymentType in _paymentTypes) {
        if (!_isPaymentTypeApplicable(student, paymentType)) {
          continue;
        }

        final dueAmount = _requiredAmountFor(student, paymentType);
        final paidAmount = _effectivePaidAmountFor(
          student,
          paymentType,
          requiredAmount: dueAmount,
        );
        final remainingAmount = _remainingAmountFor(
          student,
          paymentType,
          requiredAmount: dueAmount,
          paidAmount: paidAmount,
        );
        if (remainingAmount <= 0) {
          continue;
        }

        final missingPrerequisites = _findMissingRequirements(
          student,
          paymentType,
        );
        final isBlocked = missingPrerequisites.isNotEmpty;
        final isOnTrackInstallment =
            !isBlocked &&
            _isInstallmentOnTrack(
              student,
              paymentType,
              requiredAmount: dueAmount,
              paidAmount: paidAmount,
              remainingAmount: remainingAmount,
            );

        result.add(
          _OutstandingBill(
            studentIndex: studentIndex,
            nim: student.nim,
            studentName: student.name,
            major: student.major,
            className: student.className,
            semester: student.semester,
            paymentTypeId: paymentType.id,
            paymentTypeName: paymentType.name,
            dueAmount: dueAmount,
            paidAmount: paidAmount,
            remainingAmount: remainingAmount,
            missingPrerequisites: missingPrerequisites,
            isBlocked: isBlocked,
            isOnTrackInstallment: isOnTrackInstallment,
            isOverdue: !isBlocked && !isOnTrackInstallment,
          ),
        );
      }
    }
    return result;
  }

  void _updateTransactionStatus(
    int index,
    FinanceTransactionStatus nextStatus,
  ) {
    if (index < 0 || index >= _transactions.length) {
      return;
    }

    setState(() {
      final current = _transactions[index];
      _transactions = List<FinanceTransaction>.from(_transactions)
        ..[index] = FinanceTransaction(
          category: current.category,
          description: current.description,
          date: current.date,
          amount: current.amount,
          isIncome: current.isIncome,
          status: nextStatus,
          studentNim: current.studentNim,
          paymentTypeId: current.paymentTypeId,
          paymentMethod: current.paymentMethod,
        );
    });

    _showInfoMessage(
      'Status transaksi diperbarui menjadi ${_statusText(nextStatus)}.',
    );
  }

  void _applyReconciliationAdjustment() {
    final difference = _balanceDifference;
    if (difference == null || difference == 0) {
      return;
    }

    setState(() {
      _ledgerBalance += difference;
      _transactions = [
        FinanceTransaction(
          category: 'Penyesuaian Rekonsiliasi',
          description: 'Koreksi saldo akibat selisih rekonsiliasi',
          date: DateTime.now(),
          amount: difference.abs(),
          isIncome: difference > 0,
          status: FinanceTransactionStatus.completed,
          paymentMethod: 'reconciliation',
        ),
        ..._transactions,
      ];
    });

    _showInfoMessage('Penyesuaian rekonsiliasi berhasil dicatat.');
  }

  void _settleOutstandingBill(_OutstandingBill bill) {
    if (bill.studentIndex < 0 || bill.studentIndex >= _students.length) {
      return;
    }

    if (bill.missingPrerequisites.isNotEmpty &&
        !_allowManualSettlementOverride) {
      _showErrorMessage(
        'Pelunasan ditolak. Prasyarat belum terpenuhi: '
        '${bill.missingPrerequisites.join(', ')}.',
      );
      return;
    }

    final student = _students[bill.studentIndex];
    final paymentType = _findPaymentTypeById(bill.paymentTypeId);
    if (paymentType == null) {
      _showErrorMessage('Jenis tagihan tidak ditemukan.');
      return;
    }

    final remainingAmount = _remainingAmountFor(student, paymentType);
    if (remainingAmount <= 0) {
      _showInfoMessage('Tagihan ini sudah lunas.');
      return;
    }

    final transactionStatus = _autoReconcileEnabled
        ? FinanceTransactionStatus.completed
        : FinanceTransactionStatus.pending;

    setState(() {
      _students = List<StudentAccount>.from(_students)
        ..[bill.studentIndex] = _recordStudentPayment(
          student,
          paymentType.id,
          remainingAmount,
        );
      _ledgerBalance += remainingAmount;
      _transactions = [
        FinanceTransaction(
          category: paymentType.name,
          description: 'Pelunasan manual - ${student.nim} - ${student.name}',
          date: DateTime.now(),
          amount: remainingAmount,
          isIncome: true,
          status: transactionStatus,
          studentNim: student.nim,
          paymentTypeId: paymentType.id,
          paymentMethod: 'manual',
        ),
        ..._transactions,
      ];
    });

    _showInfoMessage(
      'Tagihan ${paymentType.name} berhasil dilunasi (${_formatRupiah(remainingAmount)}).',
    );
  }

  Future<void> _openAdjustmentDialog() async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var isIncome = false;

    final result = await showDialog<_AdjustmentSubmission>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Tambah Penyesuaian'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<bool>(
                    initialValue: isIncome,
                    decoration: const InputDecoration(
                      labelText: 'Jenis penyesuaian',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: true,
                        child: Text('Penambahan saldo'),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Pengurangan saldo'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setModalState(() {
                        isIncome = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Nominal',
                      border: OutlineInputBorder(),
                      prefixText: 'Rp',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final amount = int.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0) {
                      return;
                    }
                    Navigator.of(context).pop(
                      _AdjustmentSubmission(
                        amount: amount,
                        isIncome: isIncome,
                        note: noteController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
    noteController.dispose();

    if (!mounted || result == null) {
      return;
    }

    if (!result.isIncome && result.amount > _ledgerBalance) {
      _showErrorMessage('Saldo tidak cukup untuk penyesuaian pengurangan.');
      return;
    }

    final transactionStatus = _autoReconcileEnabled
        ? FinanceTransactionStatus.completed
        : FinanceTransactionStatus.pending;

    setState(() {
      _ledgerBalance += result.isIncome ? result.amount : -result.amount;
      _transactions = [
        FinanceTransaction(
          category: 'Penyesuaian Manual',
          description: result.note.isEmpty ? '-' : result.note,
          date: DateTime.now(),
          amount: result.amount,
          isIncome: result.isIncome,
          status: transactionStatus,
          paymentMethod: 'manual_adjustment',
        ),
        ..._transactions,
      ];
    });

    _showInfoMessage('Penyesuaian manual berhasil dicatat.');
  }

  Future<void> _openOperatorDialog() async {
    final controller = TextEditingController(text: _operatorName);

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ubah Nama Operator'),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama operator',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    setState(() {
      _operatorName = result;
    });
  }

  String _statusText(FinanceTransactionStatus status) {
    switch (status) {
      case FinanceTransactionStatus.completed:
        return 'Selesai';
      case FinanceTransactionStatus.pending:
        return 'Diproses';
      case FinanceTransactionStatus.failed:
        return 'Gagal';
    }
  }

  Color _statusColor(FinanceTransactionStatus status) {
    switch (status) {
      case FinanceTransactionStatus.completed:
        return Colors.green.shade700;
      case FinanceTransactionStatus.pending:
        return Colors.orange.shade800;
      case FinanceTransactionStatus.failed:
        return Colors.red.shade700;
    }
  }

  Future<void> _openPaymentDialog() async {
    final result = await showDialog<PaymentSubmission>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PaymentDialog(
        paymentTypes: _paymentTypes,
        students: _students,
        paymentTypeFilter: _isPaymentTypeApplicable,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final paymentType = _findPaymentTypeById(result.paymentTypeId);
    final studentIndex = _students.indexWhere((item) => item.nim == result.nim);
    if (paymentType == null || studentIndex < 0) {
      _showErrorMessage('Data pembayaran tidak valid.');
      return;
    }

    final student = _students[studentIndex];
    if (!_isPaymentTypeApplicable(student, paymentType)) {
      _showErrorMessage(
        'Jenis pembayaran ${paymentType.name} tidak berlaku untuk mahasiswa ini.',
      );
      return;
    }

    if (_strictPrerequisiteValidation) {
      final missingRequirements = _findMissingRequirements(
        student,
        paymentType,
      );
      if (missingRequirements.isNotEmpty) {
        _showErrorMessage(
          'Tidak bisa input ${paymentType.name}. '
          'Wajib lunas: ${missingRequirements.join(', ')}.',
        );
        return;
      }
    }

    final dueAmount = _requiredAmountFor(student, paymentType);
    final paidAmount = _effectivePaidAmountFor(
      student,
      paymentType,
      requiredAmount: dueAmount,
    );
    final remainingAmount = _remainingAmountFor(
      student,
      paymentType,
      requiredAmount: dueAmount,
      paidAmount: paidAmount,
    );
    if (remainingAmount <= 0) {
      _showErrorMessage('Jenis pembayaran ini sudah lunas.');
      return;
    }

    if (result.amount > remainingAmount) {
      _showErrorMessage(
        'Nominal melebihi sisa tagihan. Maksimal ${_formatRupiah(remainingAmount)}.',
      );
      return;
    }

    final transactionStatus = _autoReconcileEnabled
        ? FinanceTransactionStatus.completed
        : FinanceTransactionStatus.pending;

    setState(() {
      _students = List<StudentAccount>.from(_students)
        ..[studentIndex] = _recordStudentPayment(
          student,
          paymentType.id,
          result.amount,
        );
      _ledgerBalance += result.amount;
      _transactions = [
        FinanceTransaction(
          category: paymentType.name,
          description:
              'Pembayaran ${paymentType.name} - ${student.nim} - ${student.name}',
          date: DateTime.now(),
          amount: result.amount,
          isIncome: true,
          status: transactionStatus,
          studentNim: student.nim,
          paymentTypeId: paymentType.id,
          paymentMethod: 'manual',
        ),
        ..._transactions,
      ];
    });

    _showInfoMessage('Pembayaran ${paymentType.name} berhasil dicatat.');
  }

  Future<void> _openPaymentTypeDialog() async {
    if (!_canManageMasterData) {
      _showErrorMessage('Aksi ini hanya untuk role owner/admin.');
      return;
    }

    final availableMajors =
        _students
            .map((item) => item.major.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final result = await showDialog<PaymentTypeDraft>(
      context: context,
      builder: (_) => PaymentTypeDialog(
        existingPaymentTypes: _paymentTypes,
        availableMajors: availableMajors,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final existingName = _paymentTypes.any(
      (item) => item.name.toLowerCase() == result.name.toLowerCase(),
    );
    if (existingName) {
      _showErrorMessage('Jenis pembayaran dengan nama sama sudah ada.');
      return;
    }

    final newId = _buildPaymentTypeId(result.name);
    setState(() {
      _paymentTypes = [
        ..._paymentTypes,
        PaymentType(
          id: newId,
          name: result.name,
          amount: result.amount,
          prerequisiteTypeIds: result.prerequisiteTypeIds,
          targetSemester: result.targetSemester,
          targetMajor: result.targetMajor,
        ),
      ];
    });

    _showInfoMessage('Jenis pembayaran "${result.name}" berhasil ditambahkan.');
  }

  Future<void> _openAddStudentDialog() async {
    if (!_canManageMasterData) {
      _showErrorMessage('Aksi ini hanya untuk role owner/admin.');
      return;
    }

    final result = await showDialog<StudentDraft>(
      context: context,
      builder: (_) => StudentDialog(
        existingNims: _students.map((item) => item.nim).toList(),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    _upsertStudentFromDraft(result);
    _showInfoMessage('Data mahasiswa berhasil ditambahkan.');
  }

  Future<void> _openEditStudentDialog(StudentAccount student) async {
    if (!_canManageMasterData) {
      _showErrorMessage('Aksi ini hanya untuk role owner/admin.');
      return;
    }

    final result = await showDialog<StudentDraft>(
      context: context,
      builder: (_) => StudentDialog(
        initialStudent: student,
        existingNims: _students.map((item) => item.nim).toList(),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    _upsertStudentFromDraft(result, previousNim: student.nim);
    _showInfoMessage('Data mahasiswa berhasil diperbarui.');
  }

  void _upsertStudentFromDraft(StudentDraft draft, {String? previousNim}) {
    final duplicateNim = _students.any(
      (item) => item.nim == draft.nim && item.nim != previousNim,
    );
    if (duplicateNim) {
      _showErrorMessage('NIM ${draft.nim} sudah digunakan.');
      return;
    }

    final editingIndex = previousNim == null
        ? -1
        : _students.indexWhere((item) => item.nim == previousNim);
    final existingPaidTypeIds = editingIndex >= 0
        ? _students[editingIndex].paidTypeIds
        : const <String>{};
    final existingPaidTypeAmounts = editingIndex >= 0
        ? _students[editingIndex].paidTypeAmounts
        : const <String, int>{};

    final updatedStudent = StudentAccount(
      nim: draft.nim,
      name: draft.name,
      major: draft.major,
      className: draft.className,
      semester: draft.semester,
      scholarshipPercent: draft.scholarshipPercent,
      installmentTerms: draft.installmentTerms,
      paidTypeIds: existingPaidTypeIds,
      paidTypeAmounts: existingPaidTypeAmounts,
    );

    setState(() {
      final nextStudents = List<StudentAccount>.from(_students);
      if (editingIndex >= 0) {
        nextStudents[editingIndex] = updatedStudent;
      } else {
        nextStudents.add(updatedStudent);
      }
      _students = nextStudents;
    });
  }

  Future<void> _removeStudent(StudentAccount student) async {
    if (!_canManageMasterData) {
      _showErrorMessage('Aksi ini hanya untuk role owner/admin.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Mahasiswa'),
          content: Text(
            'Hapus data ${student.name} (${student.nim})? Riwayat pembayaran pada data mahasiswa ini akan hilang.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _students = _students.where((item) => item.nim != student.nim).toList();
    });
    _showInfoMessage('Data mahasiswa berhasil dihapus.');
  }

  Future<void> _downloadStudentTemplate() async {
    try {
      await ExcelExportService.exportRows(
        fileName: 'template_import_mahasiswa',
        sheetName: 'TemplateMahasiswa',
        headers: const [
          'NIM',
          'Nama',
          'Prodi',
          'Kelas',
          'Semester',
          'Beasiswa',
          'Cicilan',
        ],
        rows: const [
          [
            '2301001',
            'Nama Mahasiswa',
            'Teknik Informatika',
            '3A',
            '3',
            '0',
            '1',
          ],
        ],
      );
      _showInfoMessage('Template Excel mahasiswa berhasil diunduh.');
    } catch (_) {
      _showErrorMessage('Gagal mengunduh template Excel mahasiswa.');
    }
  }

  Future<void> _importStudentsFromExcel() async {
    if (!_canManageMasterData) {
      _showErrorMessage('Aksi ini hanya untuk role owner/admin.');
      return;
    }

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls'],
        withData: true,
      );

      if (!mounted || picked == null || picked.files.isEmpty) {
        return;
      }

      final bytes = picked.files.first.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showErrorMessage(
          'Gagal membaca file. Pilih file lagi atau gunakan file berukuran lebih kecil.',
        );
        return;
      }

      final parsed = ExcelImportService.parseStudents(bytes);
      if (parsed.rows.isEmpty) {
        _showErrorMessage('Tidak ada data valid untuk diimport.');
        return;
      }

      var inserted = 0;
      var updated = 0;

      setState(() {
        final nextStudents = List<StudentAccount>.from(_students);
        for (final draft in parsed.rows) {
          final index = nextStudents.indexWhere(
            (item) => item.nim == draft.nim,
          );
          if (index >= 0) {
            final existing = nextStudents[index];
            nextStudents[index] = StudentAccount(
              nim: draft.nim,
              name: draft.name,
              major: draft.major,
              className: draft.className,
              semester: draft.semester,
              scholarshipPercent: draft.scholarshipPercent,
              installmentTerms: draft.installmentTerms,
              paidTypeIds: existing.paidTypeIds,
              paidTypeAmounts: existing.paidTypeAmounts,
            );
            updated += 1;
          } else {
            nextStudents.add(
              StudentAccount(
                nim: draft.nim,
                name: draft.name,
                major: draft.major,
                className: draft.className,
                semester: draft.semester,
                scholarshipPercent: draft.scholarshipPercent,
                installmentTerms: draft.installmentTerms,
              ),
            );
            inserted += 1;
          }
        }
        _students = nextStudents;
      });

      _showInfoMessage(
        'Import selesai. Baru: $inserted, update: $updated, skip: ${parsed.skippedRows}.',
      );
    } on FormatException catch (error) {
      _showErrorMessage(error.message);
    } catch (_) {
      _showErrorMessage('Gagal import data mahasiswa dari excel.');
    }
  }

  Future<void> _openExpenseDialog() async {
    final result = await showDialog<ExpenseSubmission>(
      context: context,
      builder: (_) => const ExpenseDialog(),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.amount > _ledgerBalance) {
      _showErrorMessage('Saldo tidak cukup untuk pengeluaran ini.');
      return;
    }

    setState(() {
      _ledgerBalance -= result.amount;
      final transactionStatus = _autoReconcileEnabled
          ? FinanceTransactionStatus.completed
          : FinanceTransactionStatus.pending;
      _transactions = [
        FinanceTransaction(
          category: result.category,
          description: result.note,
          date: DateTime.now(),
          amount: result.amount,
          isIncome: false,
          status: transactionStatus,
          paymentMethod: 'expense',
        ),
        ..._transactions,
      ];
    });

    _showInfoMessage('Pengeluaran ${result.category} berhasil dicatat.');
  }

  Future<void> _openReconcileDialog() async {
    final controller = TextEditingController(
      text: _realBalance?.toString() ?? '',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Cocokkan Saldo Rekening',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Saldo rekening real',
              border: OutlineInputBorder(),
              prefixText: 'Rp',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value < 0) {
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _realBalance = result;
      if (_autoReconcileEnabled && _realBalance == _ledgerBalance) {
        _transactions = _transactions.map((item) {
          if (item.status != FinanceTransactionStatus.pending) {
            return item;
          }
          return FinanceTransaction(
            category: item.category,
            description: item.description,
            date: item.date,
            amount: item.amount,
            isIncome: item.isIncome,
            status: FinanceTransactionStatus.completed,
            studentNim: item.studentNim,
            paymentTypeId: item.paymentTypeId,
            paymentMethod: item.paymentMethod,
          );
        }).toList();
      }
    });

    _showInfoMessage('Saldo rekening real berhasil diperbarui.');
  }

  Future<void> _openActiveStudentsDialog() async {
    final sortedStudents = List<StudentAccount>.from(_students)
      ..sort((a, b) => _compareNim(a.nim, b.nim));
    final availableMajors =
        sortedStudents
            .map((item) => item.major.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final availableSemesters =
        sortedStudents.map((item) => item.semester).toSet().toList()..sort();

    var selectedMajor = '';
    int? selectedSemester;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredStudents = sortedStudents.where((student) {
              if (selectedMajor.isNotEmpty && student.major != selectedMajor) {
                return false;
              }
              if (selectedSemester != null &&
                  student.semester != selectedSemester) {
                return false;
              }
              return true;
            }).toList();

            return AlertDialog(
              title: const Text('Data Mahasiswa Aktif'),
              content: SizedBox(
                width: 980,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 240,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedMajor,
                              decoration: const InputDecoration(
                                labelText: 'Filter Prodi',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: '',
                                  child: Text('Semua Prodi'),
                                ),
                                ...availableMajors.map(
                                  (major) => DropdownMenuItem<String>(
                                    value: major,
                                    child: Text(major),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  selectedMajor = value ?? '';
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<int?>(
                              initialValue: selectedSemester,
                              decoration: const InputDecoration(
                                labelText: 'Filter Semester',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Semua Semester'),
                                ),
                                ...availableSemesters.map(
                                  (semester) => DropdownMenuItem<int?>(
                                    value: semester,
                                    child: Text('Semester $semester'),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  selectedSemester = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Total data: ${filteredStudents.length}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('NIM')),
                            DataColumn(label: Text('Nama')),
                            DataColumn(label: Text('Prodi')),
                            DataColumn(label: Text('Kelas')),
                            DataColumn(label: Text('Semester')),
                            DataColumn(label: Text('Beasiswa')),
                            DataColumn(label: Text('Cicilan')),
                            DataColumn(label: Text('Lunas')),
                            DataColumn(label: Text('Aksi')),
                          ],
                          rows: filteredStudents
                              .map(
                                (student) => DataRow(
                                  cells: [
                                    DataCell(Text(student.nim)),
                                    DataCell(Text(student.name)),
                                    DataCell(Text(student.major)),
                                    DataCell(Text(student.className)),
                                    DataCell(Text(student.semester.toString())),
                                    DataCell(
                                      Text('${student.scholarshipPercent}%'),
                                    ),
                                    DataCell(
                                      Text('${student.installmentTerms}x'),
                                    ),
                                    DataCell(
                                      Text(
                                        _settledPaymentTypeNames(
                                              student,
                                            ).isEmpty
                                            ? '-'
                                            : _settledPaymentTypeNames(
                                                student,
                                              ).join(', '),
                                      ),
                                    ),
                                    DataCell(
                                      OutlinedButton(
                                        onPressed: () =>
                                            _openStudentLedgerDialog(student),
                                        child: const Text('Buku Besar'),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
                ElevatedButton.icon(
                  onPressed: filteredStudents.isEmpty
                      ? null
                      : () => _exportActiveStudentsExcel(filteredStudents),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download Excel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openUnpaidBillsDialog() async {
    final sortedBills = _buildOutstandingBills()
      ..sort((a, b) {
        final nimCompare = _compareNim(a.nim, b.nim);
        if (nimCompare != 0) {
          return nimCompare;
        }
        return a.paymentTypeName.toLowerCase().compareTo(
          b.paymentTypeName.toLowerCase(),
        );
      });

    final availableMajors =
        sortedBills
            .map((item) => item.major.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final availableSemesters =
        sortedBills.map((item) => item.semester).toSet().toList()..sort();
    final availablePaymentTypes =
        sortedBills
            .map((item) => item.paymentTypeName.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    var selectedMajor = '';
    int? selectedSemester;
    var selectedPaymentType = '';
    var selectedStatus = 'overdue';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredBills = sortedBills.where((bill) {
              if (selectedMajor.isNotEmpty && bill.major != selectedMajor) {
                return false;
              }
              if (selectedSemester != null &&
                  bill.semester != selectedSemester) {
                return false;
              }
              if (selectedPaymentType.isNotEmpty &&
                  bill.paymentTypeName != selectedPaymentType) {
                return false;
              }
              if (selectedStatus.isNotEmpty &&
                  _outstandingBillStatusKey(bill) != selectedStatus) {
                return false;
              }
              return true;
            }).toList();
            final overdueCount = filteredBills
                .where((bill) => bill.isOverdue)
                .length;
            final onTrackCount = filteredBills
                .where((bill) => bill.isOnTrackInstallment)
                .length;
            final blockedCount = filteredBills
                .where((bill) => bill.isBlocked)
                .length;

            return AlertDialog(
              title: const Text('Daftar Tagihan Belum Lunas'),
              content: SizedBox(
                width: 1280,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 240,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedMajor,
                              decoration: const InputDecoration(
                                labelText: 'Filter Prodi',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: '',
                                  child: Text('Semua Prodi'),
                                ),
                                ...availableMajors.map(
                                  (major) => DropdownMenuItem<String>(
                                    value: major,
                                    child: Text(major),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  selectedMajor = value ?? '';
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<int?>(
                              initialValue: selectedSemester,
                              decoration: const InputDecoration(
                                labelText: 'Filter Semester',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Semua Semester'),
                                ),
                                ...availableSemesters.map(
                                  (semester) => DropdownMenuItem<int?>(
                                    value: semester,
                                    child: Text('Semester $semester'),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  selectedSemester = value;
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedPaymentType,
                              decoration: const InputDecoration(
                                labelText: 'Filter Jenis Tagihan',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: '',
                                  child: Text('Semua Jenis'),
                                ),
                                ...availablePaymentTypes.map(
                                  (paymentType) => DropdownMenuItem<String>(
                                    value: paymentType,
                                    child: Text(paymentType),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  selectedPaymentType = value ?? '';
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 240,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedStatus,
                              decoration: const InputDecoration(
                                labelText: 'Filter Status',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem<String>(
                                  value: '',
                                  child: Text('Semua Status'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'overdue',
                                  child: Text('Terlambat'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'on_track',
                                  child: Text('Cicilan On-track'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'blocked',
                                  child: Text('Blocked Prasyarat'),
                                ),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  selectedStatus = value ?? '';
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Total data: ${filteredBills.length} | '
                        'Terlambat: $overdueCount | '
                        'On-track: $onTrackCount | '
                        'Blocked: $blockedCount',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('NIM')),
                            DataColumn(label: Text('Nama')),
                            DataColumn(label: Text('Prodi')),
                            DataColumn(label: Text('Kelas')),
                            DataColumn(label: Text('Semester')),
                            DataColumn(label: Text('Tagihan')),
                            DataColumn(label: Text('Netto')),
                            DataColumn(label: Text('Terbayar')),
                            DataColumn(label: Text('Sisa')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Prasyarat Belum Lunas')),
                          ],
                          rows: filteredBills
                              .map(
                                (bill) => DataRow(
                                  cells: [
                                    DataCell(Text(bill.nim)),
                                    DataCell(Text(bill.studentName)),
                                    DataCell(Text(bill.major)),
                                    DataCell(Text(bill.className)),
                                    DataCell(Text(bill.semester.toString())),
                                    DataCell(Text(bill.paymentTypeName)),
                                    DataCell(
                                      Text(_formatRupiah(bill.dueAmount)),
                                    ),
                                    DataCell(
                                      Text(_formatRupiah(bill.paidAmount)),
                                    ),
                                    DataCell(
                                      Text(_formatRupiah(bill.remainingAmount)),
                                    ),
                                    DataCell(
                                      Text(
                                        _outstandingBillStatusLabel(bill),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _outstandingBillStatusColor(
                                            bill,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        bill.missingPrerequisites.isEmpty
                                            ? '-'
                                            : bill.missingPrerequisites.join(
                                                ', ',
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
                ElevatedButton.icon(
                  onPressed: filteredBills.isEmpty
                      ? null
                      : () => _exportUnpaidBillsExcel(filteredBills),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download Excel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<_StudentLedgerEntry> _buildStudentLedgerEntries(StudentAccount student) {
    final entries = <_StudentLedgerEntry>[];
    for (final paymentType in _paymentTypes) {
      if (!_isPaymentTypeApplicable(student, paymentType)) {
        continue;
      }

      final grossAmount = paymentType.amount < 0 ? 0 : paymentType.amount;
      final dueAmount = _requiredAmountFor(student, paymentType);
      final paidAmount = _effectivePaidAmountFor(
        student,
        paymentType,
        requiredAmount: dueAmount,
      );
      final remainingAmount = _remainingAmountFor(
        student,
        paymentType,
        requiredAmount: dueAmount,
        paidAmount: paidAmount,
      );
      final missingPrerequisites = _findMissingRequirements(
        student,
        paymentType,
      );
      final isSettled = remainingAmount <= 0;
      final isOnTrackInstallment =
          !isSettled &&
          missingPrerequisites.isEmpty &&
          _isInstallmentOnTrack(
            student,
            paymentType,
            requiredAmount: dueAmount,
            paidAmount: paidAmount,
            remainingAmount: remainingAmount,
          );

      entries.add(
        _StudentLedgerEntry(
          paymentTypeId: paymentType.id,
          paymentTypeName: paymentType.name,
          targetSemester: paymentType.targetSemester,
          targetMajor: paymentType.targetMajor,
          grossAmount: grossAmount,
          netAmount: dueAmount,
          paidAmount: paidAmount,
          remainingAmount: remainingAmount,
          isSettled: isSettled,
          isOnTrackInstallment: isOnTrackInstallment,
          missingPrerequisites: missingPrerequisites,
        ),
      );
    }

    entries.sort((a, b) {
      final semA = a.targetSemester ?? 999;
      final semB = b.targetSemester ?? 999;
      final semCompare = semA.compareTo(semB);
      if (semCompare != 0) {
        return semCompare;
      }
      return a.paymentTypeName.toLowerCase().compareTo(
        b.paymentTypeName.toLowerCase(),
      );
    });

    return entries;
  }

  List<FinanceTransaction> _transactionsByStudent(StudentAccount student) {
    final result = _transactions.where((item) {
      final nim = item.studentNim?.trim() ?? '';
      if (nim.isNotEmpty) {
        return nim == student.nim;
      }
      return item.description.contains(student.nim);
    }).toList();
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  String _studentLedgerStatusLabel(_StudentLedgerEntry entry) {
    if (entry.missingPrerequisites.isNotEmpty) {
      return 'Blocked Prasyarat';
    }
    if (entry.isSettled) {
      return 'Lunas';
    }
    if (entry.isOnTrackInstallment) {
      return 'Cicilan On-track';
    }
    return 'Belum Lunas';
  }

  Color _studentLedgerStatusColor(_StudentLedgerEntry entry) {
    if (entry.missingPrerequisites.isNotEmpty) {
      return Colors.orange.shade800;
    }
    if (entry.isSettled) {
      return Colors.green.shade700;
    }
    if (entry.isOnTrackInstallment) {
      return Colors.blue.shade700;
    }
    return Colors.red.shade700;
  }

  Future<void> _openStudentLedgerDialog(StudentAccount student) async {
    final entries = _buildStudentLedgerEntries(student);
    final studentTransactions = _transactionsByStudent(student);
    final totalGross = entries.fold<int>(
      0,
      (previous, entry) => previous + entry.grossAmount,
    );
    final totalNet = entries.fold<int>(
      0,
      (previous, entry) => previous + entry.netAmount,
    );
    final totalPaid = entries.fold<int>(
      0,
      (previous, entry) => previous + entry.paidAmount,
    );
    final totalRemaining = entries.fold<int>(
      0,
      (previous, entry) => previous + entry.remainingAmount,
    );
    final clearanceEligible = entries.every(
      (entry) =>
          entry.isSettled ||
          (entry.isOnTrackInstallment && entry.missingPrerequisites.isEmpty),
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Buku Besar ${student.name} (${student.nim})'),
          content: SizedBox(
            width: 1220,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildReportMetric(
                        'Tagihan Bruto',
                        _formatRupiah(totalGross),
                      ),
                      _buildReportMetric(
                        'Tagihan Netto',
                        _formatRupiah(totalNet),
                      ),
                      _buildReportMetric('Terbayar', _formatRupiah(totalPaid)),
                      _buildReportMetric('Sisa', _formatRupiah(totalRemaining)),
                      _buildReportMetric(
                        'Clearance',
                        clearanceEligible ? 'Boleh' : 'Belum',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ringkasan Tagihan per Jenis Pembayaran',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Jenis Tagihan')),
                        DataColumn(label: Text('Scope')),
                        DataColumn(label: Text('Bruto')),
                        DataColumn(label: Text('Netto')),
                        DataColumn(label: Text('Terbayar')),
                        DataColumn(label: Text('Sisa')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Prasyarat Belum Lunas')),
                      ],
                      rows: entries
                          .map(
                            (entry) => DataRow(
                              cells: [
                                DataCell(Text(entry.paymentTypeName)),
                                DataCell(
                                  Text(
                                    [
                                          if (entry.targetSemester != null)
                                            'Smt ${entry.targetSemester}',
                                          if (entry.targetMajor != null &&
                                              entry.targetMajor!.isNotEmpty)
                                            entry.targetMajor!,
                                        ].isEmpty
                                        ? 'Semua'
                                        : [
                                            if (entry.targetSemester != null)
                                              'Smt ${entry.targetSemester}',
                                            if (entry.targetMajor != null &&
                                                entry.targetMajor!.isNotEmpty)
                                              entry.targetMajor!,
                                          ].join(' | '),
                                  ),
                                ),
                                DataCell(
                                  Text(_formatRupiah(entry.grossAmount)),
                                ),
                                DataCell(Text(_formatRupiah(entry.netAmount))),
                                DataCell(Text(_formatRupiah(entry.paidAmount))),
                                DataCell(
                                  Text(_formatRupiah(entry.remainingAmount)),
                                ),
                                DataCell(
                                  Text(
                                    _studentLedgerStatusLabel(entry),
                                    style: TextStyle(
                                      color: _studentLedgerStatusColor(entry),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    entry.missingPrerequisites.isEmpty
                                        ? '-'
                                        : entry.missingPrerequisites.join(', '),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Histori Transaksi Mahasiswa',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  if (studentTransactions.isEmpty)
                    Text(
                      'Belum ada histori transaksi yang terkait NIM ini.',
                      style: TextStyle(color: Colors.grey.shade700),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Tanggal')),
                          DataColumn(label: Text('Kategori')),
                          DataColumn(label: Text('Deskripsi')),
                          DataColumn(label: Text('Nominal')),
                          DataColumn(label: Text('Status')),
                        ],
                        rows: studentTransactions
                            .map(
                              (transaction) => DataRow(
                                cells: [
                                  DataCell(
                                    Text(_formatDateTime(transaction.date)),
                                  ),
                                  DataCell(Text(transaction.category)),
                                  DataCell(Text(transaction.description)),
                                  DataCell(
                                    Text(
                                      '${transaction.isIncome ? '+' : '-'}${_formatRupiah(transaction.amount)}',
                                      style: TextStyle(
                                        color: transaction.isIncome
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _statusText(transaction.status),
                                      style: TextStyle(
                                        color: _statusColor(transaction.status),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
            ElevatedButton.icon(
              onPressed: () => _exportStudentLedgerExcel(
                student: student,
                entries: entries,
                transactions: studentTransactions,
                clearanceEligible: clearanceEligible,
              ),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download Excel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportStudentLedgerExcel({
    required StudentAccount student,
    required List<_StudentLedgerEntry> entries,
    required List<FinanceTransaction> transactions,
    required bool clearanceEligible,
  }) async {
    try {
      final totalNet = entries.fold<int>(
        0,
        (previous, entry) => previous + entry.netAmount,
      );
      final totalPaid = entries.fold<int>(
        0,
        (previous, entry) => previous + entry.paidAmount,
      );
      final totalRemaining = entries.fold<int>(
        0,
        (previous, entry) => previous + entry.remainingAmount,
      );

      final rows = <List<String>>[
        ['Profil', '${student.nim} - ${student.name}', '', '', ''],
        ['Program', '${student.major} / ${student.className}', '', '', ''],
        ['Semester', student.semester.toString(), '', '', ''],
        ['Beasiswa', '${student.scholarshipPercent}%', '', '', ''],
        ['Skema Cicilan', '${student.installmentTerms}x', '', '', ''],
        ['Clearance', clearanceEligible ? 'Boleh' : 'Belum', '', '', ''],
        ['Total Netto', '', _formatRupiah(totalNet), '', ''],
        ['Total Terbayar', '', _formatRupiah(totalPaid), '', ''],
        ['Total Sisa', '', _formatRupiah(totalRemaining), '', ''],
        ['', '', '', '', ''],
        ['Bagian', 'Jenis/Kategori', 'Nominal', 'Status', 'Keterangan'],
      ];

      rows.addAll(
        entries.map(
          (entry) => [
            'Tagihan',
            entry.paymentTypeName,
            _formatRupiah(entry.netAmount),
            _studentLedgerStatusLabel(entry),
            'Terbayar ${_formatRupiah(entry.paidAmount)} | '
                'Sisa ${_formatRupiah(entry.remainingAmount)}',
          ],
        ),
      );

      rows.add(['', '', '', '', '']);
      rows.add([
        'Bagian',
        'Tanggal/Kategori',
        'Nominal',
        'Status',
        'Deskripsi',
      ]);
      rows.addAll(
        transactions.map(
          (item) => [
            'Transaksi',
            '${_formatDateTime(item.date)} | ${item.category}',
            '${item.isIncome ? '+' : '-'}${_formatRupiah(item.amount)}',
            _statusText(item.status),
            item.description,
          ],
        ),
      );

      await ExcelExportService.exportRows(
        fileName: 'buku_besar_${student.nim}_${_fileTimestamp()}',
        sheetName: 'BukuBesar',
        headers: const ['Kolom1', 'Kolom2', 'Kolom3', 'Kolom4', 'Kolom5'],
        rows: rows,
      );
      _showInfoMessage('Buku besar mahasiswa berhasil diunduh.');
    } catch (_) {
      _showErrorMessage('Gagal mengunduh buku besar mahasiswa.');
    }
  }

  Future<void> _exportClearanceStatusExcel() async {
    try {
      final rows = _students.map((student) {
        final entries = _buildStudentLedgerEntries(student);
        final totalNet = entries.fold<int>(
          0,
          (previous, entry) => previous + entry.netAmount,
        );
        final totalPaid = entries.fold<int>(
          0,
          (previous, entry) => previous + entry.paidAmount,
        );
        final totalRemaining = entries.fold<int>(
          0,
          (previous, entry) => previous + entry.remainingAmount,
        );
        final clearanceEligible = entries.every(
          (entry) =>
              entry.isSettled ||
              (entry.isOnTrackInstallment &&
                  entry.missingPrerequisites.isEmpty),
        );

        return [
          student.nim,
          student.name,
          student.major,
          student.className,
          student.semester.toString(),
          _formatRupiah(totalNet),
          _formatRupiah(totalPaid),
          _formatRupiah(totalRemaining),
          clearanceEligible ? 'Boleh Ujian' : 'Blokir',
        ];
      }).toList()..sort((a, b) => _compareNim(a[0], b[0]));

      await ExcelExportService.exportRows(
        fileName: 'status_clearance_${_fileTimestamp()}',
        sheetName: 'Clearance',
        headers: const [
          'NIM',
          'Nama',
          'Prodi',
          'Kelas',
          'Semester',
          'Tagihan Netto',
          'Terbayar',
          'Sisa',
          'Status Clearance',
        ],
        rows: rows,
      );
      _showInfoMessage('Status clearance berhasil diunduh.');
    } catch (_) {
      _showErrorMessage('Gagal mengunduh status clearance.');
    }
  }

  Future<void> _exportActiveStudentsExcel(List<StudentAccount> students) async {
    try {
      final rows = students
          .map(
            (student) => [
              student.nim,
              student.name,
              student.major,
              student.className,
              student.semester.toString(),
              student.scholarshipPercent.toString(),
              student.installmentTerms.toString(),
              _settledPaymentTypeNames(student).isEmpty
                  ? '-'
                  : _settledPaymentTypeNames(student).join(', '),
            ],
          )
          .toList();

      await ExcelExportService.exportRows(
        fileName: 'mahasiswa_aktif_${_fileTimestamp()}',
        sheetName: 'Mahasiswa',
        headers: const [
          'NIM',
          'Nama',
          'Prodi',
          'Kelas',
          'Semester',
          'Beasiswa',
          'Cicilan',
          'Lunas',
        ],
        rows: rows,
      );
      _showInfoMessage('File Excel mahasiswa berhasil diunduh.');
    } catch (_) {
      _showErrorMessage('Gagal mengunduh file Excel mahasiswa.');
    }
  }

  Future<void> _exportUnpaidBillsExcel(List<_OutstandingBill> bills) async {
    try {
      final rows = bills
          .map(
            (bill) => [
              bill.nim,
              bill.studentName,
              bill.major,
              bill.className,
              bill.semester.toString(),
              bill.paymentTypeName,
              bill.dueAmount.toString(),
              bill.paidAmount.toString(),
              bill.remainingAmount.toString(),
              _outstandingBillStatusLabel(bill),
              bill.missingPrerequisites.isEmpty
                  ? '-'
                  : bill.missingPrerequisites.join(', '),
            ],
          )
          .toList();

      await ExcelExportService.exportRows(
        fileName: 'tagihan_belum_lunas_${_fileTimestamp()}',
        sheetName: 'Tagihan',
        headers: const [
          'NIM',
          'Nama',
          'Prodi',
          'Kelas',
          'Semester',
          'Tagihan',
          'Netto',
          'Terbayar',
          'Sisa',
          'Status',
          'Prasyarat Belum Lunas',
        ],
        rows: rows,
      );
      _showInfoMessage('File Excel tagihan berhasil diunduh.');
    } catch (_) {
      _showErrorMessage('Gagal mengunduh file Excel tagihan.');
    }
  }

  Future<void> _downloadBankMutationTemplate() async {
    try {
      await ExcelExportService.exportRows(
        fileName: 'template_mutasi_bank',
        sheetName: 'MutasiBank',
        headers: const ['Tanggal', 'Keterangan', 'Nominal', 'Referensi'],
        rows: const [
          [
            '2026-02-24 08:00:00',
            'TRF 2301001 SPP SEMESTER 3',
            '1500000',
            'MB-001',
          ],
        ],
      );
      _showInfoMessage('Template mutasi bank berhasil diunduh.');
    } catch (_) {
      _showErrorMessage('Gagal mengunduh template mutasi bank.');
    }
  }

  Widget _buildAdminUsersCard() {
    if (!_canCallAdminApi) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(
          'Panel user memerlukan API backend aktif dan sesi login valid.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Akun pengguna (${_adminUsers.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isAdminDataLoading
                        ? null
                        : () => unawaited(_loadAdminPanelData(force: true)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _openCreateUserDialog,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Tambah User'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isAdminDataLoading && !_adminDataLoaded)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_adminUsers.isEmpty)
            Text(
              'Belum ada user selain akun default.',
              style: TextStyle(color: Colors.grey.shade700),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Username')),
                  DataColumn(label: Text('Nama')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Aksi')),
                ],
                rows: _adminUsers.map((user) {
                  final canEditOwner =
                      _effectiveRole == 'owner' || user.role != 'owner';
                  return DataRow(
                    cells: [
                      DataCell(Text(user.username)),
                      DataCell(Text(user.fullName)),
                      DataCell(Text(user.role)),
                      DataCell(
                        Text(
                          user.isActive ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            color: user.isActive
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DataCell(
                        OutlinedButton(
                          onPressed: canEditOwner
                              ? () => _openEditUserDialog(user)
                              : null,
                          child: const Text('Edit'),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAdminAuditLogsCard() {
    if (!_canCallAdminApi) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(
          'Panel audit memerlukan API backend aktif dan sesi login valid.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Aktivitas terbaru (${_adminAuditLogs.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              OutlinedButton.icon(
                onPressed: _isAdminDataLoading
                    ? null
                    : () => unawaited(_loadAdminPanelData(force: true)),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isAdminDataLoading && !_adminDataLoaded)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_adminAuditLogs.isEmpty)
            Text(
              'Belum ada aktivitas tercatat.',
              style: TextStyle(color: Colors.grey.shade700),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                itemCount: _adminAuditLogs.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _adminAuditLogs[index];
                  final actor = item.actorUsername.trim().isEmpty
                      ? 'system'
                      : item.actorUsername;
                  final target = item.entityId == null
                      ? item.entityType
                      : '${item.entityType}:${item.entityId}';
                  final payloadPreview = _payloadPreviewText(item.payload);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item.action} · $target'),
                    subtitle: Text(
                      '$actor • ${_formatDateTime(item.createdAt)}'
                      '${payloadPreview.isEmpty ? '' : '\n$payloadPreview'}',
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openChangePasswordDialog() async {
    if (!_canCallAdminApi) {
      _showErrorMessage('API belum siap untuk ganti password.');
      return;
    }

    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    var isSubmitting = false;
    var errorText = '';
    var changed = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Ganti Password'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password Lama',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password Baru (min. 8 karakter)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Konfirmasi Password Baru',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (errorText.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          errorText,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final currentPassword = currentController.text.trim();
                          final newPassword = newController.text;
                          final confirmPassword = confirmController.text;

                          if (currentPassword.isEmpty ||
                              newPassword.length < 8) {
                            setModalState(() {
                              errorText =
                                  'Password lama wajib diisi dan password baru minimal 8 karakter.';
                            });
                            return;
                          }
                          if (newPassword != confirmPassword) {
                            setModalState(() {
                              errorText =
                                  'Konfirmasi password baru tidak sama.';
                            });
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            errorText = '';
                          });

                          try {
                            await _adminApi.changePassword(
                              token: _effectiveToken,
                              currentPassword: currentPassword,
                              newPassword: newPassword,
                            );
                            changed = true;
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          } catch (error) {
                            setModalState(() {
                              isSubmitting = false;
                              errorText = _readableError(
                                error,
                                fallback: 'Gagal mengubah password.',
                              );
                            });
                          }
                        },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    currentController.dispose();
    newController.dispose();
    confirmController.dispose();

    if (changed) {
      _showInfoMessage('Password berhasil diubah.');
    }
  }

  Future<void> _openCreateUserDialog() async {
    if (!_canManageMasterData) {
      _showErrorMessage('Aksi ini hanya untuk role owner/admin.');
      return;
    }
    if (!_canCallAdminApi) {
      _showErrorMessage('API backend belum siap.');
      return;
    }

    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final roleOptions = _availableRoleOptions(
      includeOwner: _effectiveRole == 'owner',
    );
    var selectedRole = roleOptions.first;
    var isActive = true;
    var isSubmitting = false;
    var errorText = '';
    var created = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Tambah User'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama Lengkap',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password (min. 8 karakter)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Konfirmasi Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                        items: roleOptions
                            .map(
                              (role) => DropdownMenuItem<String>(
                                value: role,
                                child: Text(_roleLabel(role)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setModalState(() {
                            selectedRole = value ?? roleOptions.first;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: isActive,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Akun aktif'),
                        onChanged: (value) {
                          setModalState(() {
                            isActive = value;
                          });
                        },
                      ),
                      if (errorText.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final username = usernameController.text.trim();
                          final fullName = fullNameController.text.trim();
                          final password = passwordController.text;
                          final confirm = confirmController.text;

                          if (username.isEmpty || fullName.isEmpty) {
                            setModalState(() {
                              errorText =
                                  'Username dan nama lengkap wajib diisi.';
                            });
                            return;
                          }
                          if (password.length < 8) {
                            setModalState(() {
                              errorText = 'Password minimal 8 karakter.';
                            });
                            return;
                          }
                          if (password != confirm) {
                            setModalState(() {
                              errorText = 'Konfirmasi password tidak sama.';
                            });
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            errorText = '';
                          });

                          try {
                            await _adminApi.createUser(
                              token: _effectiveToken,
                              username: username,
                              fullName: fullName,
                              password: password,
                              role: selectedRole,
                              isActive: isActive,
                            );
                            created = true;
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          } catch (error) {
                            setModalState(() {
                              isSubmitting = false;
                              errorText = _readableError(
                                error,
                                fallback: 'Gagal membuat user.',
                              );
                            });
                          }
                        },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    fullNameController.dispose();
    passwordController.dispose();
    confirmController.dispose();

    if (created) {
      await _loadAdminPanelData(force: true);
      _showInfoMessage('User baru berhasil dibuat.');
    }
  }

  Future<void> _openEditUserDialog(AdminUserAccount user) async {
    if (!_canManageMasterData) {
      _showErrorMessage('Aksi ini hanya untuk role owner/admin.');
      return;
    }
    if (!_canCallAdminApi) {
      _showErrorMessage('API backend belum siap.');
      return;
    }
    if (_effectiveRole != 'owner' && user.role == 'owner') {
      _showErrorMessage('Hanya owner yang dapat mengubah akun owner.');
      return;
    }

    final fullNameController = TextEditingController(text: user.fullName);
    final roleOptions = _availableRoleOptions(
      includeOwner: _effectiveRole == 'owner',
    );
    var selectedRole = roleOptions.contains(user.role)
        ? user.role
        : roleOptions.first;
    var isActive = user.isActive;
    var isSubmitting = false;
    var errorText = '';
    var saved = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text('Edit User ${user.username}'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama Lengkap',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                        items: roleOptions
                            .map(
                              (role) => DropdownMenuItem<String>(
                                value: role,
                                child: Text(_roleLabel(role)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setModalState(() {
                            selectedRole = value ?? roleOptions.first;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: isActive,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Akun aktif'),
                        onChanged: (value) {
                          setModalState(() {
                            isActive = value;
                          });
                        },
                      ),
                      if (errorText.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final fullName = fullNameController.text.trim();
                          if (fullName.isEmpty) {
                            setModalState(() {
                              errorText = 'Nama lengkap tidak boleh kosong.';
                            });
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            errorText = '';
                          });

                          try {
                            await _adminApi.updateUser(
                              token: _effectiveToken,
                              userId: user.id,
                              fullName: fullName,
                              role: selectedRole,
                              isActive: isActive,
                            );
                            saved = true;
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          } catch (error) {
                            setModalState(() {
                              isSubmitting = false;
                              errorText = _readableError(
                                error,
                                fallback: 'Gagal memperbarui user.',
                              );
                            });
                          }
                        },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    fullNameController.dispose();

    if (saved) {
      await _loadAdminPanelData(force: true);
      _showInfoMessage('Data user berhasil diperbarui.');
    }
  }

  Future<void> _resetAllData() async {
    setState(() {
      _selectedIndex = 0;
      _ledgerBalance = 0;
      _realBalance = null;
      _paymentTypes = const [];
      _students = const [];
      _transactions = const [];
      _bankAutoMatchRules = const [];
      _selectedBankMutationStatus = '';
      _bankMutationMinConfidence = 0;
      _isBankMutationBatchProcessing = false;
      _bankMutationLoadInitialized = false;
      _bankMutations = const [];
      _bankMutationCounts = const {
        'unmatched': 0,
        'candidate': 0,
        'matched': 0,
        'approved': 0,
        'rejected': 0,
      };
    });
    if (!mounted) {
      return;
    }
    _showInfoMessage('Semua data berhasil direset.');
  }

  bool _isPaymentTypeApplicable(
    StudentAccount student,
    PaymentType paymentType,
  ) {
    final targetMajor = paymentType.targetMajor?.trim() ?? '';
    if (targetMajor.isNotEmpty && targetMajor != student.major.trim()) {
      return false;
    }

    final targetSemester = paymentType.targetSemester;
    if (targetSemester != null && student.semester != targetSemester) {
      return false;
    }
    return true;
  }

  int _compareNim(String left, String right) {
    final leftNumber = int.tryParse(left);
    final rightNumber = int.tryParse(right);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  String _fileTimestamp() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$y$m$d'
        '_$hh$mm$ss';
  }

  String _outstandingBillStatusKey(_OutstandingBill bill) {
    if (bill.isBlocked) {
      return 'blocked';
    }
    if (bill.isOnTrackInstallment) {
      return 'on_track';
    }
    return 'overdue';
  }

  String _outstandingBillStatusLabel(_OutstandingBill bill) {
    final status = _outstandingBillStatusKey(bill);
    switch (status) {
      case 'blocked':
        return 'Blocked Prasyarat';
      case 'on_track':
        return 'Cicilan On-track';
      default:
        return 'Terlambat';
    }
  }

  Color _outstandingBillStatusColor(_OutstandingBill bill) {
    final status = _outstandingBillStatusKey(bill);
    switch (status) {
      case 'blocked':
        return Colors.orange.shade800;
      case 'on_track':
        return Colors.green.shade700;
      default:
        return Colors.red.shade700;
    }
  }

  List<String> _availableRoleOptions({required bool includeOwner}) {
    const allRoles = ['owner', 'admin', 'operator', 'viewer'];
    if (includeOwner) {
      return List<String>.from(allRoles);
    }
    return allRoles.where((role) => role != 'owner').toList();
  }

  String _roleLabel(String role) {
    final value = role.trim();
    if (value.isEmpty) {
      return '-';
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _payloadPreviewText(Map<String, Object?>? payload) {
    if (payload == null || payload.isEmpty) {
      return '';
    }
    final entries = payload.entries.toList();
    final parts = <String>[];
    for (var i = 0; i < entries.length && i < 2; i += 1) {
      final entry = entries[i];
      parts.add('${entry.key}=${entry.value}');
    }
    final suffix = entries.length > 2 ? ', ...' : '';
    return 'payload: ${parts.join(', ')}$suffix';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  String _readableError(Object error, {required String fallback}) {
    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return fallback;
    }
    return raw.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
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

  int _remainingAmountFor(
    StudentAccount student,
    PaymentType paymentType, {
    int? requiredAmount,
    int? paidAmount,
  }) {
    final required = requiredAmount ?? _requiredAmountFor(student, paymentType);
    final paid =
        paidAmount ??
        _effectivePaidAmountFor(student, paymentType, requiredAmount: required);
    final remaining = required - paid;
    return remaining > 0 ? remaining : 0;
  }

  bool _isPaymentTypeSettled(StudentAccount student, PaymentType paymentType) {
    return _remainingAmountFor(student, paymentType) == 0;
  }

  bool _isInstallmentOnTrack(
    StudentAccount student,
    PaymentType paymentType, {
    int? requiredAmount,
    int? paidAmount,
    int? remainingAmount,
  }) {
    final required = requiredAmount ?? _requiredAmountFor(student, paymentType);
    if (required <= 0) {
      return true;
    }

    final paid =
        paidAmount ??
        _effectivePaidAmountFor(student, paymentType, requiredAmount: required);
    final remaining =
        remainingAmount ??
        _remainingAmountFor(
          student,
          paymentType,
          requiredAmount: required,
          paidAmount: paid,
        );
    if (remaining <= 0) {
      return false;
    }

    final terms = student.installmentTerms <= 0 ? 1 : student.installmentTerms;
    if (terms <= 1) {
      return false;
    }

    final minimumPerTerm = (required / terms).ceil();
    return paid >= minimumPerTerm;
  }

  StudentAccount _recordStudentPayment(
    StudentAccount student,
    String paymentTypeId,
    int amount,
  ) {
    final paymentType = _findPaymentTypeById(paymentTypeId);
    if (paymentType == null) {
      return student;
    }
    final safeAmount = amount <= 0 ? 0 : amount;
    final required = _requiredAmountFor(student, paymentType);
    final currentPaid = _effectivePaidAmountFor(
      student,
      paymentType,
      requiredAmount: required,
    );
    final remaining = required - currentPaid;
    if (remaining <= 0 || safeAmount <= 0) {
      return student;
    }

    final applied = safeAmount > remaining ? remaining : safeAmount;
    final nextPaid = currentPaid + applied;

    final nextPaidTypeAmounts = Map<String, int>.from(student.paidTypeAmounts)
      ..[paymentTypeId] = nextPaid;
    final nextPaidTypeIds = Set<String>.from(student.paidTypeIds);
    if (nextPaid >= required) {
      nextPaidTypeIds.add(paymentTypeId);
    } else {
      nextPaidTypeIds.remove(paymentTypeId);
    }

    return student.copyWith(
      paidTypeIds: nextPaidTypeIds,
      paidTypeAmounts: nextPaidTypeAmounts,
    );
  }

  List<String> _settledPaymentTypeNames(StudentAccount student) {
    final names = <String>[];
    for (final paymentType in _paymentTypes) {
      if (_isPaymentTypeSettled(student, paymentType)) {
        names.add(paymentType.name);
      }
    }
    return names;
  }

  List<String> _findMissingRequirements(
    StudentAccount student,
    PaymentType paymentType,
  ) {
    final missing = <String>[];
    for (final prerequisiteId in paymentType.prerequisiteTypeIds) {
      final prerequisite = _findPaymentTypeById(prerequisiteId);
      if (prerequisite == null) {
        continue;
      }
      if (!_isPaymentTypeSettled(student, prerequisite)) {
        missing.add(prerequisite.name);
      }
    }
    return missing;
  }

  PaymentType? _findPaymentTypeById(String id) {
    for (final item in _paymentTypes) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  PaymentType? _findPaymentTypeByInvoiceName(String name) {
    final normalizedTarget = _normalizeLooseText(name);
    if (normalizedTarget.isEmpty) {
      return null;
    }

    for (final item in _paymentTypes) {
      if (_normalizeLooseText(item.name) == normalizedTarget) {
        return item;
      }
    }

    for (final item in _paymentTypes) {
      final normalizedName = _normalizeLooseText(item.name);
      if (normalizedName.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedName)) {
        return item;
      }
    }
    return null;
  }

  String _normalizeLooseText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _paymentTypeNameById(String id) {
    final result = _findPaymentTypeById(id);
    return result?.name ?? id;
  }

  String _buildPaymentTypeId(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final normalized = base.isEmpty ? 'pembayaran' : base;

    var id = normalized;
    var counter = 2;
    while (_paymentTypes.any((item) => item.id == id)) {
      id = '$normalized-$counter';
      counter += 1;
    }
    return id;
  }

  String _formatRupiah(int amount) {
    final raw = amount.toString();
    final withSeparator = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return 'Rp$withSeparator';
  }

  void _showInfoMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _onItemSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == FinanceMenuIndex.pengaturan) {
      unawaited(_loadAdminPanelData());
    }
    if (index == FinanceMenuIndex.mutasiBank) {
      unawaited(_loadBankMutations());
    }
  }
}

class _OutstandingBill {
  final int studentIndex;
  final String nim;
  final String studentName;
  final String major;
  final String className;
  final int semester;
  final String paymentTypeId;
  final String paymentTypeName;
  final int dueAmount;
  final int paidAmount;
  final int remainingAmount;
  final List<String> missingPrerequisites;
  final bool isBlocked;
  final bool isOnTrackInstallment;
  final bool isOverdue;

  const _OutstandingBill({
    required this.studentIndex,
    required this.nim,
    required this.studentName,
    required this.major,
    required this.className,
    required this.semester,
    required this.paymentTypeId,
    required this.paymentTypeName,
    required this.dueAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.missingPrerequisites,
    required this.isBlocked,
    required this.isOnTrackInstallment,
    required this.isOverdue,
  });
}

class _StudentLedgerEntry {
  final String paymentTypeId;
  final String paymentTypeName;
  final int? targetSemester;
  final String? targetMajor;
  final int grossAmount;
  final int netAmount;
  final int paidAmount;
  final int remainingAmount;
  final bool isSettled;
  final bool isOnTrackInstallment;
  final List<String> missingPrerequisites;

  const _StudentLedgerEntry({
    required this.paymentTypeId,
    required this.paymentTypeName,
    required this.targetSemester,
    required this.targetMajor,
    required this.grossAmount,
    required this.netAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.isSettled,
    required this.isOnTrackInstallment,
    required this.missingPrerequisites,
  });
}

class _PreparedBankAutoMatchRule {
  final BankAutoMatchRule rule;
  final RegExp? descriptionRegex;

  const _PreparedBankAutoMatchRule({
    required this.rule,
    required this.descriptionRegex,
  });
}

class _BankMutationLocalSyncResult {
  final bool synced;
  final int appliedAmount;
  final String reason;

  const _BankMutationLocalSyncResult._({
    required this.synced,
    required this.appliedAmount,
    required this.reason,
  });

  const _BankMutationLocalSyncResult.synced(int appliedAmount)
    : this._(synced: true, appliedAmount: appliedAmount, reason: '');

  const _BankMutationLocalSyncResult.skipped(String reason)
    : this._(synced: false, appliedAmount: 0, reason: reason);
}

class _ManualBankMutationMatchSubmission {
  final BankMutationItem mutation;
  final String studentNim;
  final String paymentTypeId;
  final int amount;
  final bool approveBackend;

  const _ManualBankMutationMatchSubmission({
    required this.mutation,
    required this.studentNim,
    required this.paymentTypeId,
    required this.amount,
    required this.approveBackend,
  });
}

class _BankMutationRuleApplyResult {
  final List<BankMutationImportRow> rows;
  final int matchedRows;
  final int appliedRows;
  final int nimTaggedRows;
  final int majorTaggedRows;

  const _BankMutationRuleApplyResult({
    required this.rows,
    required this.matchedRows,
    required this.appliedRows,
    required this.nimTaggedRows,
    required this.majorTaggedRows,
  });
}

class _BankAutoMatchRuleDraft {
  final String name;
  final String bankAccountPattern;
  final String majorLabel;
  final String descriptionRegex;
  final int nimCaptureGroup;
  final String bankAccountOverride;
  final String prependText;
  final bool isEnabled;

  const _BankAutoMatchRuleDraft({
    required this.name,
    required this.bankAccountPattern,
    required this.majorLabel,
    required this.descriptionRegex,
    required this.nimCaptureGroup,
    required this.bankAccountOverride,
    required this.prependText,
    required this.isEnabled,
  });

  factory _BankAutoMatchRuleDraft.fromRule(BankAutoMatchRule rule) {
    return _BankAutoMatchRuleDraft(
      name: rule.name,
      bankAccountPattern: rule.bankAccountPattern,
      majorLabel: rule.majorLabel,
      descriptionRegex: rule.descriptionRegex,
      nimCaptureGroup: rule.nimCaptureGroup,
      bankAccountOverride: rule.bankAccountOverride,
      prependText: rule.prependText,
      isEnabled: rule.isEnabled,
    );
  }
}

class _AdjustmentSubmission {
  final int amount;
  final bool isIncome;
  final String note;

  const _AdjustmentSubmission({
    required this.amount,
    required this.isIncome,
    required this.note,
  });
}
