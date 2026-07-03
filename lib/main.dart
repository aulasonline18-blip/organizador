import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await initializeDateFormatting('pt_BR');

  final notificationService = NotificationService();
  await notificationService.initialize();

  final preferences = await SharedPreferences.getInstance();
  final repository = CommitmentRepository(
    preferences: preferences,
    secureStorage: const FlutterSecureStorage(),
  );
  final walletRepository = WalletRepository(preferences: preferences);

  runApp(
    OrganizerApp(
      repository: repository,
      walletRepository: walletRepository,
      notificationService: notificationService,
    ),
  );
}

class OrganizerApp extends StatelessWidget {
  const OrganizerApp({
    required this.repository,
    required this.walletRepository,
    required this.notificationService,
    super.key,
  });

  final CommitmentRepository repository;
  final WalletRepository walletRepository;
  final NotificationService notificationService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F6F63),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Organizador',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: CategoryHomePage(
        repository: repository,
        walletRepository: walletRepository,
        notificationService: notificationService,
      ),
    );
  }
}

enum CommitmentStatus { pending, done, paid }

enum CommitmentCategory { compromisso, conta, trabalho, pessoal, saude, estudo }

enum RepeatRule { none, weekly, monthly, yearly }

extension CommitmentStatusLabel on CommitmentStatus {
  String get label => switch (this) {
    CommitmentStatus.pending => 'Pendente',
    CommitmentStatus.done => 'Concluido',
    CommitmentStatus.paid => 'Pago',
  };
}

extension CommitmentCategoryLabel on CommitmentCategory {
  String get label => switch (this) {
    CommitmentCategory.compromisso => 'Compromisso',
    CommitmentCategory.conta => 'Conta',
    CommitmentCategory.trabalho => 'Trabalho',
    CommitmentCategory.pessoal => 'Pessoal',
    CommitmentCategory.saude => 'Saude',
    CommitmentCategory.estudo => 'Estudo',
  };
}

extension RepeatRuleLabel on RepeatRule {
  String get label => switch (this) {
    RepeatRule.none => 'Nao repetir',
    RepeatRule.weekly => 'Toda semana',
    RepeatRule.monthly => 'Todo mes',
    RepeatRule.yearly => 'Todo ano',
  };
}

class Commitment {
  const Commitment({
    required this.id,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.category,
    required this.status,
    required this.reminderOffsets,
    required this.createdAt,
    this.repeatRule = RepeatRule.none,
    this.amount,
    this.hasSensitiveData = false,
  });

  final String id;
  final String title;
  final String description;
  final DateTime dueAt;
  final CommitmentCategory category;
  final CommitmentStatus status;
  final List<int> reminderOffsets;
  final DateTime createdAt;
  final RepeatRule repeatRule;
  final double? amount;
  final bool hasSensitiveData;

  bool get isOverdue =>
      status == CommitmentStatus.pending && dueAt.isBefore(DateTime.now());

  Commitment copyWith({
    String? title,
    String? description,
    DateTime? dueAt,
    CommitmentCategory? category,
    CommitmentStatus? status,
    List<int>? reminderOffsets,
    RepeatRule? repeatRule,
    double? amount,
    bool clearAmount = false,
    bool? hasSensitiveData,
  }) {
    return Commitment(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueAt: dueAt ?? this.dueAt,
      category: category ?? this.category,
      status: status ?? this.status,
      reminderOffsets: reminderOffsets ?? this.reminderOffsets,
      createdAt: createdAt,
      repeatRule: repeatRule ?? this.repeatRule,
      amount: clearAmount ? null : amount ?? this.amount,
      hasSensitiveData: hasSensitiveData ?? this.hasSensitiveData,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'dueAt': dueAt.toIso8601String(),
    'category': category.name,
    'status': status.name,
    'reminderOffsets': reminderOffsets,
    'createdAt': createdAt.toIso8601String(),
    'repeatRule': repeatRule.name,
    'amount': amount,
    'hasSensitiveData': hasSensitiveData,
  };

  static Commitment fromJson(Map<String, Object?> json) {
    return Commitment(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      dueAt: DateTime.parse(json['dueAt'] as String),
      category: CommitmentCategory.values.byName(json['category'] as String),
      status: CommitmentStatus.values.byName(json['status'] as String),
      reminderOffsets: (json['reminderOffsets'] as List<dynamic>)
          .map((value) => value as int)
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      repeatRule: RepeatRule.values.byName(
        json['repeatRule'] as String? ?? RepeatRule.none.name,
      ),
      amount: (json['amount'] as num?)?.toDouble(),
      hasSensitiveData: json['hasSensitiveData'] as bool? ?? false,
    );
  }
}

class SensitiveCommitmentData {
  const SensitiveCommitmentData({
    this.email = '',
    this.login = '',
    this.password = '',
    this.notes = '',
  });

  final String email;
  final String login;
  final String password;
  final String notes;

  bool get isEmpty =>
      email.trim().isEmpty &&
      login.trim().isEmpty &&
      password.trim().isEmpty &&
      notes.trim().isEmpty;

  Map<String, String> toJson() => {
    'email': email,
    'login': login,
    'password': password,
    'notes': notes,
  };

  static SensitiveCommitmentData fromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const SensitiveCommitmentData();
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return SensitiveCommitmentData(
      email: json['email'] as String? ?? '',
      login: json['login'] as String? ?? '',
      password: json['password'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}

class CommitmentRepository {
  CommitmentRepository({
    required SharedPreferences preferences,
    required FlutterSecureStorage secureStorage,
    // Named public parameters keep the constructor readable at call sites.
    // ignore: prefer_initializing_formals
  }) : _preferences = preferences,
       // ignore: prefer_initializing_formals
       _secureStorage = secureStorage;

  static const _commitmentsKey = 'commitments_v1';

  final SharedPreferences _preferences;
  final FlutterSecureStorage _secureStorage;

  Future<List<Commitment>> loadCommitments() async {
    final raw = _preferences.getString(_commitmentsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    final commitments = decoded
        .map((item) => Commitment.fromJson(item as Map<String, Object?>))
        .toList();
    commitments.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return commitments;
  }

  Future<void> saveCommitments(List<Commitment> commitments) async {
    final encoded = jsonEncode(
      commitments.map((commitment) => commitment.toJson()).toList(),
    );
    await _preferences.setString(_commitmentsKey, encoded);
  }

  Future<SensitiveCommitmentData> loadSensitiveData(String id) async {
    final raw = await _secureStorage.read(key: _sensitiveKey(id));
    return SensitiveCommitmentData.fromJson(raw);
  }

  Future<void> saveSensitiveData(
    String id,
    SensitiveCommitmentData sensitiveData,
  ) async {
    if (sensitiveData.isEmpty) {
      await _secureStorage.delete(key: _sensitiveKey(id));
      return;
    }
    await _secureStorage.write(
      key: _sensitiveKey(id),
      value: jsonEncode(sensitiveData.toJson()),
    );
  }

  Future<void> deleteSensitiveData(String id) =>
      _secureStorage.delete(key: _sensitiveKey(id));

  String _sensitiveKey(String id) => 'commitment_sensitive_$id';
}

class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.balance,
    required this.createdAt,
  });

  final String id;
  final String name;
  final double balance;
  final DateTime createdAt;

  Wallet copyWith({String? name, double? balance}) {
    return Wallet(
      id: id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'balance': balance,
    'createdAt': createdAt.toIso8601String(),
  };

  static Wallet fromJson(Map<String, Object?> json) {
    final legacyPositive = (json['positiveAmount'] as num?)?.toDouble();
    final legacyNegative = (json['negativeAmount'] as num?)?.toDouble();
    return Wallet(
      id: json['id'] as String,
      name: json['name'] as String,
      balance:
          (json['balance'] as num?)?.toDouble() ??
          ((legacyPositive ?? 0) - (legacyNegative ?? 0)),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class WalletRepository {
  WalletRepository({required SharedPreferences preferences})
    // Named public parameters keep the constructor readable at call sites.
    // ignore: prefer_initializing_formals
    : _preferences = preferences;

  static const _walletsKey = 'wallets_v1';

  final SharedPreferences _preferences;

  Future<List<Wallet>> loadWallets() async {
    final raw = _preferences.getString(_walletsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    final wallets = decoded
        .map((item) => Wallet.fromJson(item as Map<String, Object?>))
        .toList();
    wallets.sort((a, b) => a.name.compareTo(b.name));
    return wallets;
  }

  Future<void> saveWallets(List<Wallet> wallets) async {
    wallets.sort((a, b) => a.name.compareTo(b.name));
    await _preferences.setString(
      _walletsKey,
      jsonEncode(wallets.map((wallet) => wallet.toJson()).toList()),
    );
  }
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linux = LinuxInitializationSettings(defaultActionName: 'Abrir');
    const windows = WindowsInitializationSettings(
      appName: 'Organizador',
      appUserModelId: 'com.organizador.app',
      guid: '6b4fb24c-7e5d-4ef7-8fd6-9f8b8bf2b3d6',
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        linux: linux,
        windows: windows,
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  Future<void> scheduleCommitment(Commitment commitment) async {
    if (kIsWeb || commitment.status != CommitmentStatus.pending) {
      return;
    }

    await cancelCommitment(commitment.id);

    for (final offset in commitment.reminderOffsets) {
      final scheduledAt = commitment.dueAt.subtract(Duration(minutes: offset));
      if (scheduledAt.isBefore(DateTime.now())) {
        continue;
      }

      final title = offset == 0
          ? commitment.title
          : '${commitment.title} em ${_formatOffset(offset)}';
      final amount = commitment.amount == null
          ? ''
          : ' Valor: ${NumberFormat.simpleCurrency(locale: 'pt_BR').format(commitment.amount)}.';

      await _scheduleNotification(
        id: _notificationId(commitment.id, offset),
        title: title,
        body:
            '${commitment.category.label} marcado para ${DateFormat('dd/MM HH:mm', 'pt_BR').format(commitment.dueAt)}.$amount',
        scheduledAt: scheduledAt,
        payload: commitment.id,
      );
    }
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    required String payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'commitments',
        'Compromissos',
        channelDescription: 'Lembretes de compromissos e obrigacoes',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    final scheduledDate = tz.TZDateTime.from(scheduledAt, tz.local);

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } on PlatformException {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  Future<void> cancelCommitment(String id) async {
    if (kIsWeb) {
      return;
    }
    for (final offset in ReminderOptions.all.keys) {
      await _plugin.cancel(id: _notificationId(id, offset));
    }
  }

  int _notificationId(String id, int offset) =>
      id.codeUnits.fold(offset + 17, (value, unit) => value * 31 + unit) %
      2147483647;

  String _formatOffset(int minutes) {
    if (minutes == 0) {
      return 'agora';
    }
    if (minutes < 60) {
      return '$minutes min';
    }
    if (minutes < 1440) {
      return '${minutes ~/ 60} h';
    }
    return '${minutes ~/ 1440} dia(s)';
  }
}

class SecureAccessService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> unlock() async {
    if (kIsWeb) {
      return true;
    }

    try {
      final supported = await _auth.isDeviceSupported();
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      if (!supported && !canCheckBiometrics) {
        return true;
      }

      return _auth.authenticate(
        localizedReason: 'Confirme sua identidade para ver dados sensiveis.',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return true;
    }
  }
}

class ReminderOptions {
  static const all = <int, String>{
    0: 'Na hora',
    15: '15 min antes',
    60: '1 h antes',
    1440: '1 dia antes',
    10080: '1 semana antes',
  };
}

class CategoryHomePage extends StatelessWidget {
  const CategoryHomePage({
    required this.repository,
    required this.walletRepository,
    required this.notificationService,
    super.key,
  });

  final CommitmentRepository repository;
  final WalletRepository walletRepository;
  final NotificationService notificationService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organizador')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            CategoryTile(
              icon: Icons.event_note,
              title: 'Compromissos',
              subtitle: 'Obrigacoes, contas, lembretes e acessos',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CommitmentsPage(
                      repository: repository,
                      notificationService: notificationService,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            CategoryTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Bolsas',
              subtitle: 'Carteiras com entradas, saidas e saldo',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        WalletsPage(repository: walletRepository),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class CommitmentsPage extends StatefulWidget {
  const CommitmentsPage({
    required this.repository,
    required this.notificationService,
    super.key,
  });

  final CommitmentRepository repository;
  final NotificationService notificationService;

  @override
  State<CommitmentsPage> createState() => _CommitmentsPageState();
}

class _CommitmentsPageState extends State<CommitmentsPage> {
  final _secureAccessService = SecureAccessService();
  final _currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
  List<Commitment> _commitments = [];
  final Set<String> _expandedCommitments = {};
  bool _loading = true;
  CommitmentCategory? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final commitments = await widget.repository.loadCommitments();
    if (!mounted) {
      return;
    }
    setState(() {
      _commitments = commitments;
      _loading = false;
    });
  }

  Future<void> _persist(List<Commitment> commitments) async {
    commitments.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    await widget.repository.saveCommitments(commitments);
    if (mounted) {
      setState(() => _commitments = commitments);
    }
    for (final commitment in commitments) {
      try {
        await widget.notificationService.scheduleCommitment(commitment);
      } on PlatformException {
        // Saving the commitment is more important than scheduling failure.
      }
    }
  }

  Future<void> _openForm([Commitment? commitment]) async {
    final result = await Navigator.of(context).push<CommitmentFormResult>(
      MaterialPageRoute(
        builder: (context) => CommitmentFormPage(
          repository: widget.repository,
          initialCommitment: commitment,
        ),
      ),
    );
    if (result == null) {
      return;
    }

    final updated = [..._commitments];
    final index = updated.indexWhere((item) => item.id == result.commitment.id);
    if (index == -1) {
      updated.add(result.commitment);
    } else {
      updated[index] = result.commitment;
    }

    await widget.repository.saveSensitiveData(
      result.commitment.id,
      result.sensitiveData,
    );
    try {
      await widget.notificationService.cancelCommitment(result.commitment.id);
    } on PlatformException {
      // Notification cleanup should not block saving the commitment.
    }
    await _persist(updated);
  }

  Future<void> _delete(Commitment commitment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir compromisso?'),
        content: Text('Isso remove "${commitment.title}" e seus dados salvos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final updated = _commitments
        .where((item) => item.id != commitment.id)
        .toList();
    await widget.notificationService.cancelCommitment(commitment.id);
    await widget.repository.deleteSensitiveData(commitment.id);
    await _persist(updated);
  }

  Future<void> _setStatus(
    Commitment commitment,
    CommitmentStatus status,
  ) async {
    final updated = _commitments.map((item) {
      return item.id == commitment.id ? item.copyWith(status: status) : item;
    }).toList();
    Commitment? nextOccurrence;
    if (commitment.status == CommitmentStatus.pending &&
        status != CommitmentStatus.pending &&
        commitment.repeatRule != RepeatRule.none) {
      nextOccurrence = _nextOccurrence(commitment);
      updated.add(nextOccurrence);
      if (commitment.hasSensitiveData) {
        final sensitive = await widget.repository.loadSensitiveData(
          commitment.id,
        );
        await widget.repository.saveSensitiveData(nextOccurrence.id, sensitive);
      }
    }
    if (status == CommitmentStatus.pending) {
      await _persist(updated);
    } else {
      try {
        await widget.notificationService.cancelCommitment(commitment.id);
      } on PlatformException {
        // Notification cleanup should not block status changes.
      }
      await _persist(updated);
    }
  }

  Commitment _nextOccurrence(Commitment commitment) {
    return Commitment(
      id: const Uuid().v4(),
      title: commitment.title,
      description: commitment.description,
      dueAt: _nextDueAt(commitment.dueAt, commitment.repeatRule),
      category: commitment.category,
      status: CommitmentStatus.pending,
      reminderOffsets: commitment.reminderOffsets,
      createdAt: DateTime.now(),
      repeatRule: commitment.repeatRule,
      amount: commitment.amount,
      hasSensitiveData: commitment.hasSensitiveData,
    );
  }

  DateTime _nextDueAt(DateTime current, RepeatRule repeatRule) {
    return switch (repeatRule) {
      RepeatRule.none => current,
      RepeatRule.weekly => current.add(const Duration(days: 7)),
      RepeatRule.monthly => _addMonths(current, 1),
      RepeatRule.yearly => _addMonths(current, 12),
    };
  }

  DateTime _addMonths(DateTime date, int months) {
    final targetMonth = date.month + months;
    final year = date.year + ((targetMonth - 1) ~/ 12);
    final month = ((targetMonth - 1) % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      date.day > lastDay ? lastDay : date.day,
      date.hour,
      date.minute,
    );
  }

  Future<void> _showSensitiveData(Commitment commitment) async {
    final unlocked = await _secureAccessService.unlock();
    if (!unlocked || !mounted) {
      return;
    }
    final sensitive = await widget.repository.loadSensitiveData(commitment.id);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SensitiveDataSheet(sensitiveData: sensitive),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _categoryFilter == null
        ? _commitments
        : _commitments
              .where((item) => item.category == _categoryFilter)
              .toList();
    final pendingCount = _commitments
        .where((item) => item.status == CommitmentStatus.pending)
        .length;
    final overdueCount = _commitments.where((item) => item.isOverdue).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compromissos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  _SummaryHeader(
                    total: _commitments.length,
                    pending: pendingCount,
                    overdue: overdueCount,
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<CommitmentCategory?>(
                      segments: [
                        const ButtonSegment(
                          value: null,
                          icon: Icon(Icons.inbox_outlined),
                          label: Text('Todos'),
                        ),
                        ...CommitmentCategory.values.map(
                          (category) => ButtonSegment(
                            value: category,
                            label: Text(category.label),
                          ),
                        ),
                      ],
                      selected: {_categoryFilter},
                      onSelectionChanged: (selection) {
                        setState(() => _categoryFilter = selection.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    const EmptyState()
                  else
                    ...filtered.map(
                      (commitment) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CommitmentCard(
                          commitment: commitment,
                          expanded: _expandedCommitments.contains(
                            commitment.id,
                          ),
                          amountLabel: commitment.amount == null
                              ? null
                              : _currency.format(commitment.amount),
                          onToggleExpanded: () {
                            setState(() {
                              if (_expandedCommitments.contains(
                                commitment.id,
                              )) {
                                _expandedCommitments.remove(commitment.id);
                              } else {
                                _expandedCommitments.add(commitment.id);
                              }
                            });
                          },
                          onEdit: () => _openForm(commitment),
                          onDelete: () => _delete(commitment),
                          onShowSensitive: commitment.hasSensitiveData
                              ? () => _showSensitiveData(commitment)
                              : null,
                          onStatusChanged: (status) =>
                              _setStatus(commitment, status),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.total,
    required this.pending,
    required this.overdue,
  });

  final int total;
  final int pending;
  final int overdue;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryMetric(label: 'Total', value: total),
            ),
            Expanded(
              child: _SummaryMetric(label: 'Pendentes', value: pending),
            ),
            Expanded(
              child: _SummaryMetric(
                label: 'Vencidos',
                value: overdue,
                highlight: overdue > 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final int value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum compromisso cadastrado',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class CommitmentCard extends StatelessWidget {
  const CommitmentCard({
    required this.commitment,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChanged,
    this.amountLabel,
    this.onShowSensitive,
    super.key,
  });

  final Commitment commitment;
  final bool expanded;
  final String? amountLabel;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onShowSensitive;
  final ValueChanged<CommitmentStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat(
      'EEE, dd/MM/yyyy HH:mm',
      'pt_BR',
    ).format(commitment.dueAt).replaceFirst('.', '');
    final statusColor = commitment.isOverdue
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onToggleExpanded,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            expanded ? 14 : 10,
            6,
            expanded ? 14 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.chevron_right,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      commitment.title,
                      maxLines: expanded ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!expanded)
                    Icon(
                      commitment.isOverdue
                          ? Icons.error_outline
                          : Icons.schedule,
                      size: 18,
                      color: statusColor,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd/MM', 'pt_BR').format(commitment.dueAt),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: statusColor),
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                _ExpandedCommitmentDetails(
                  commitment: commitment,
                  dateLabel: dateLabel,
                  statusColor: statusColor,
                  amountLabel: amountLabel,
                  onEdit: onEdit,
                  onDelete: onDelete,
                  onShowSensitive: onShowSensitive,
                  onStatusChanged: onStatusChanged,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedCommitmentDetails extends StatelessWidget {
  const _ExpandedCommitmentDetails({
    required this.commitment,
    required this.dateLabel,
    required this.statusColor,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChanged,
    this.amountLabel,
    this.onShowSensitive,
  });

  final Commitment commitment;
  final String dateLabel;
  final Color statusColor;
  final String? amountLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onShowSensitive;
  final ValueChanged<CommitmentStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, right: 8),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(
                              Icons.schedule,
                              size: 18,
                              color: statusColor,
                            ),
                            label: Text(dateLabel),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(commitment.category.label),
                          ),
                          if (commitment.repeatRule != RepeatRule.none)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.repeat),
                              label: Text(commitment.repeatRule.label),
                            ),
                          if (amountLabel != null)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.payments_outlined),
                              label: Text(amountLabel!),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Acoes',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                      case 'delete':
                        onDelete();
                      case 'pending':
                        onStatusChanged(CommitmentStatus.pending);
                      case 'done':
                        onStatusChanged(CommitmentStatus.done);
                      case 'paid':
                        onStatusChanged(CommitmentStatus.paid);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'pending', child: Text('Pendente')),
                    PopupMenuItem(value: 'done', child: Text('Concluido')),
                    PopupMenuItem(value: 'paid', child: Text('Pago')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('Excluir')),
                  ],
                ),
              ],
            ),
            if (commitment.description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(commitment.description),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  commitment.status == CommitmentStatus.pending
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle,
                  size: 18,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    commitment.isOverdue ? 'Vencido' : commitment.status.label,
                    style: TextStyle(color: statusColor),
                  ),
                ),
                if (onShowSensitive != null)
                  IconButton.filledTonal(
                    tooltip: 'Ver dados protegidos',
                    onPressed: onShowSensitive,
                    icon: const Icon(Icons.lock_open),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CommitmentFormResult {
  const CommitmentFormResult({
    required this.commitment,
    required this.sensitiveData,
  });

  final Commitment commitment;
  final SensitiveCommitmentData sensitiveData;
}

class CommitmentFormPage extends StatefulWidget {
  const CommitmentFormPage({
    required this.repository,
    this.initialCommitment,
    super.key,
  });

  final CommitmentRepository repository;
  final Commitment? initialCommitment;

  @override
  State<CommitmentFormPage> createState() => _CommitmentFormPageState();
}

class _CommitmentFormPageState extends State<CommitmentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _emailController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _sensitiveNotesController = TextEditingController();

  late DateTime _dueAt;
  late CommitmentCategory _category;
  late CommitmentStatus _status;
  late RepeatRule _repeatRule;
  late Set<int> _reminderOffsets;
  bool _loadingSensitive = true;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCommitment;
    _titleController.text = initial?.title ?? '';
    _descriptionController.text = initial?.description ?? '';
    _amountController.text = initial?.amount?.toStringAsFixed(2) ?? '';
    _dueAt = initial?.dueAt ?? DateTime.now().add(const Duration(hours: 1));
    _category = initial?.category ?? CommitmentCategory.compromisso;
    _status = initial?.status ?? CommitmentStatus.pending;
    _repeatRule = initial?.repeatRule ?? RepeatRule.none;
    _reminderOffsets = {
      ...(initial?.reminderOffsets ?? [60, 15, 0]),
    };
    _loadSensitive();
  }

  Future<void> _loadSensitive() async {
    final id = widget.initialCommitment?.id;
    if (id != null) {
      final sensitive = await widget.repository.loadSensitiveData(id);
      _emailController.text = sensitive.email;
      _loginController.text = sensitive.login;
      _passwordController.text = sensitive.password;
      _sensitiveNotesController.text = sensitive.notes;
    }
    if (mounted) {
      setState(() => _loadingSensitive = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    _emailController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    _sensitiveNotesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
    );
    if (time == null) {
      return;
    }
    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final sensitive = SensitiveCommitmentData(
      email: _emailController.text.trim(),
      login: _loginController.text.trim(),
      password: _passwordController.text,
      notes: _sensitiveNotesController.text.trim(),
    );
    final amountText = _amountController.text.trim().replaceAll(',', '.');
    final initial = widget.initialCommitment;
    final commitment = Commitment(
      id: initial?.id ?? const Uuid().v4(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      dueAt: _dueAt,
      category: _category,
      status: _status,
      reminderOffsets: _reminderOffsets.toList()..sort(),
      createdAt: initial?.createdAt ?? DateTime.now(),
      repeatRule: _repeatRule,
      amount: amountText.isEmpty ? null : double.tryParse(amountText),
      hasSensitiveData: !sensitive.isEmpty,
    );

    Navigator.pop(
      context,
      CommitmentFormResult(commitment: commitment, sensitiveData: sensitive),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialCommitment == null
              ? 'Novo compromisso'
              : 'Editar compromisso',
        ),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _loadingSensitive ? null : _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: _loadingSensitive
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titulo',
                      prefixIcon: Icon(Icons.event_note),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe um titulo'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descricao',
                      prefixIcon: Icon(Icons.notes),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(_dueAt),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CommitmentCategory>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: CommitmentCategory.values
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _category = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CommitmentStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.task_alt),
                    ),
                    items: CommitmentStatus.values
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _status = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<RepeatRule>(
                    initialValue: _repeatRule,
                    decoration: const InputDecoration(
                      labelText: 'Repetir',
                      prefixIcon: Icon(Icons.repeat),
                    ),
                    items: RepeatRule.values
                        .map(
                          (repeatRule) => DropdownMenuItem(
                            value: repeatRule,
                            child: Text(repeatRule.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _repeatRule = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final text = value?.trim().replaceAll(',', '.') ?? '';
                      if (text.isEmpty) {
                        return null;
                      }
                      return double.tryParse(text) == null
                          ? 'Informe um valor valido'
                          : null;
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Lembretes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ReminderOptions.all.entries.map((entry) {
                      return FilterChip(
                        label: Text(entry.value),
                        selected: _reminderOffsets.contains(entry.key),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _reminderOffsets.add(entry.key);
                            } else {
                              _reminderOffsets.remove(entry.key);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Dados protegidos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _loginController,
                    decoration: const InputDecoration(
                      labelText: 'Login',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.password),
                      suffixIcon: IconButton(
                        tooltip: _hidePassword
                            ? 'Mostrar senha'
                            : 'Ocultar senha',
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    obscureText: _hidePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sensitiveNotesController,
                    decoration: const InputDecoration(
                      labelText: 'Observacoes sensiveis',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Salvar compromisso'),
                  ),
                ],
              ),
            ),
    );
  }
}

class WalletsPage extends StatefulWidget {
  const WalletsPage({required this.repository, super.key});

  final WalletRepository repository;

  @override
  State<WalletsPage> createState() => _WalletsPageState();
}

class _WalletsPageState extends State<WalletsPage> {
  final _currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
  List<Wallet> _wallets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wallets = await widget.repository.loadWallets();
    if (!mounted) {
      return;
    }
    setState(() {
      _wallets = wallets;
      _loading = false;
    });
  }

  Future<void> _persist(List<Wallet> wallets) async {
    await widget.repository.saveWallets(wallets);
    if (mounted) {
      setState(() => _wallets = wallets);
    }
  }

  Future<void> _createWallet() async {
    final result = await Navigator.of(context).push<Wallet>(
      MaterialPageRoute(builder: (context) => const CreateWalletPage()),
    );
    if (result == null) {
      return;
    }

    final updated = [..._wallets];
    final index = updated.indexWhere((item) => item.id == result.id);
    if (index == -1) {
      updated.add(result);
    } else {
      updated[index] = result;
    }
    await _persist(updated);
  }

  Future<void> _openWallet(Wallet wallet) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            WalletDetailPage(wallet: wallet, onWalletChanged: _upsertWallet),
      ),
    );
  }

  Future<void> _upsertWallet(Wallet wallet) async {
    final updated = [..._wallets];
    final index = updated.indexWhere((item) => item.id == wallet.id);
    if (index == -1) {
      updated.add(wallet);
    } else {
      updated[index] = wallet;
    }
    await _persist(updated);
  }

  Future<void> _delete(Wallet wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir carteira?'),
        content: Text('Isso remove "${wallet.name}" da categoria Bolsas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _persist(_wallets.where((item) => item.id != wallet.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final totalBalance = _wallets.fold<double>(
      0,
      (sum, wallet) => sum + wallet.balance,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bolsas'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  WalletSummaryHeader(
                    balance: _currency.format(totalBalance),
                    negativeBalance: totalBalance < 0,
                  ),
                  const SizedBox(height: 16),
                  if (_wallets.isEmpty)
                    const WalletEmptyState()
                  else
                    ..._wallets.map(
                      (wallet) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: WalletTile(
                          wallet: wallet,
                          balanceLabel: _currency.format(wallet.balance),
                          onOpen: () => _openWallet(wallet),
                          onDelete: () => _delete(wallet),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createWallet,
        icon: const Icon(Icons.add),
        label: const Text('Carteira'),
      ),
    );
  }
}

class WalletSummaryHeader extends StatelessWidget {
  const WalletSummaryHeader({
    required this.balance,
    required this.negativeBalance,
    super.key,
  });

  final String balance;
  final bool negativeBalance;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resultado geral',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(
              balance,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: negativeBalance
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletEmptyState extends StatelessWidget {
  const WalletEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma carteira cadastrada',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class WalletTile extends StatelessWidget {
  const WalletTile({
    required this.wallet,
    required this.balanceLabel,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });

  final Wallet wallet;
  final String balanceLabel;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final balanceColor = wallet.balance < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: balanceColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wallet.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text('Abrir carteira'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 104),
                child: Text(
                  balanceLabel,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: balanceColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Acoes',
                onSelected: (value) {
                  switch (value) {
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'delete', child: Text('Excluir')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CreateWalletPage extends StatefulWidget {
  const CreateWalletPage({super.key});

  @override
  State<CreateWalletPage> createState() => _CreateWalletPageState();
}

class _CreateWalletPageState extends State<CreateWalletPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _create() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.pop(
      context,
      Wallet(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        balance: 0,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova carteira'),
        actions: [
          IconButton(
            tooltip: 'Criar',
            onPressed: _create,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome da carteira',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _create(),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe um nome'
                    : null,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Criar carteira'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WalletDetailPage extends StatefulWidget {
  const WalletDetailPage({
    required this.wallet,
    required this.onWalletChanged,
    super.key,
  });

  final Wallet wallet;
  final Future<void> Function(Wallet wallet) onWalletChanged;

  @override
  State<WalletDetailPage> createState() => _WalletDetailPageState();
}

class _WalletDetailPageState extends State<WalletDetailPage> {
  final _formKey = GlobalKey<FormState>();
  final _addController = TextEditingController();
  final _withdrawController = TextEditingController();
  final _currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
  late Wallet _wallet;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _wallet = widget.wallet;
  }

  @override
  void dispose() {
    _addController.dispose();
    _withdrawController.dispose();
    super.dispose();
  }

  Future<void> _addAmount() async {
    if (!_formKey.currentState!.validate() || _saving) {
      return;
    }
    final amount = _parseAmount(_addController.text);
    if (amount <= 0) {
      return;
    }
    await _saveBalance(_wallet.balance + amount);
    _addController.clear();
  }

  Future<void> _withdrawAmount() async {
    if (!_formKey.currentState!.validate() || _saving) {
      return;
    }
    final amount = _parseAmount(_withdrawController.text);
    if (amount <= 0) {
      return;
    }
    await _saveBalance(_wallet.balance - amount);
    _withdrawController.clear();
  }

  Future<void> _resetWallet() async {
    if (_saving) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resetar carteira?'),
        content: const Text('Isso limpa o saldo desta carteira.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resetar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _saveBalance(0);
    }
  }

  Future<void> _saveBalance(double balance) async {
    setState(() => _saving = true);
    final updated = _wallet.copyWith(balance: balance);
    await widget.onWalletChanged(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _wallet = updated;
      _saving = false;
    });
  }

  double _parseAmount(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  String? _validateAmount(String? value) {
    final text = value?.trim().replaceAll(',', '.') ?? '';
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text) == null ? 'Informe um valor valido' : null;
  }

  @override
  Widget build(BuildContext context) {
    final balanceColor = _wallet.balance < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(_wallet.name)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saldo da carteira',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        _currency.format(_wallet.balance),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: balanceColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Adicionar',
                  prefixIcon: Icon(Icons.add_circle_outline),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _saving ? null : _addAmount,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar ao saldo'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _withdrawController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Retirar',
                  prefixIcon: Icon(Icons.remove_circle_outline),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _saving ? null : _withdrawAmount,
                  icon: const Icon(Icons.remove),
                  label: const Text('Retirar do saldo'),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _saving ? null : _resetWallet,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Resetar carteira'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SensitiveDataSheet extends StatefulWidget {
  const SensitiveDataSheet({required this.sensitiveData, super.key});

  final SensitiveCommitmentData sensitiveData;

  @override
  State<SensitiveDataSheet> createState() => _SensitiveDataSheetState();
}

class _SensitiveDataSheetState extends State<SensitiveDataSheet> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.sensitiveData;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      shrinkWrap: true,
      children: [
        Text('Dados protegidos', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (data.isEmpty)
          const Text('Nenhum dado protegido salvo.')
        else ...[
          _SensitiveRow(label: 'E-mail', value: data.email),
          _SensitiveRow(label: 'Login', value: data.login),
          if (data.password.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Senha'),
              subtitle: Text(_showPassword ? data.password : '••••••••'),
              trailing: IconButton(
                tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          _SensitiveRow(label: 'Observacoes', value: data.notes),
        ],
      ],
    );
  }
}

class _SensitiveRow extends StatelessWidget {
  const _SensitiveRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
