/// Kontakt alarmowy.
class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.notifyOnCrash = true,
  });

  final String id;
  final String name;
  final String phone;

  /// Czy ten kontakt dostaje wiadomość przy wykrytym upadku.
  final bool notifyOnCrash;

  EmergencyContact copyWith({
    String? name,
    String? phone,
    bool? notifyOnCrash,
  }) => EmergencyContact(
    id: id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    notifyOnCrash: notifyOnCrash ?? this.notifyOnCrash,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'notify_on_crash': notifyOnCrash,
  };

  static EmergencyContact? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final phone = json['phone'] as String?;
    if (id == null || phone == null || phone.trim().isEmpty) return null;
    return EmergencyContact(
      id: id,
      name: json['name'] as String? ?? phone,
      phone: phone,
      notifyOnCrash: json['notify_on_crash'] as bool? ?? true,
    );
  }
}

/// Jak czuły ma być wykrywacz upadku.
enum CrashSensitivity {
  low('Niska', 45, 35),
  medium('Średnia', 32, 25),
  high('Wysoka', 24, 18);

  const CrashSensitivity(this.label, this.impactG10, this.speedDropKmh);

  final String label;

  /// Próg uderzenia w dziesiątych częściach g (żeby enum został stałą).
  final int impactG10;

  double get impactG => impactG10 / 10;

  /// O ile musi spaść prędkość, żeby uznać to za wypadek.
  final int speedDropKmh;

  static CrashSensitivity parse(String? value) =>
      CrashSensitivity.values.firstWhere(
        (item) => item.name == value,
        orElse: () => CrashSensitivity.medium,
      );
}

/// Ustawienia bezpieczeństwa.
class SafetySettings {
  const SafetySettings({
    this.crashDetectionEnabled = false,
    this.sensitivity = CrashSensitivity.medium,
    this.countdownSeconds = 30,
    this.contacts = const [],
    this.shareLiveLink = true,
  });

  /// Wyłączone domyślnie: wykrywanie upadku bez kontaktu alarmowego nie ma
  /// komu nic zgłosić, a fałszywy alarm o trzeciej nad ranem to realny koszt.
  final bool crashDetectionEnabled;

  final CrashSensitivity sensitivity;

  /// Ile sekund zawodnik ma na anulowanie alarmu.
  final int countdownSeconds;

  final List<EmergencyContact> contacts;

  /// Czy do wiadomości dołączyć link do sesji LIVE, gdy jest aktywna.
  final bool shareLiveLink;

  List<EmergencyContact> get crashContacts =>
      contacts.where((contact) => contact.notifyOnCrash).toList();

  /// Czy alarm ma dokąd pójść.
  bool get isUsable => crashDetectionEnabled && crashContacts.isNotEmpty;

  SafetySettings copyWith({
    bool? crashDetectionEnabled,
    CrashSensitivity? sensitivity,
    int? countdownSeconds,
    List<EmergencyContact>? contacts,
    bool? shareLiveLink,
  }) => SafetySettings(
    crashDetectionEnabled: crashDetectionEnabled ?? this.crashDetectionEnabled,
    sensitivity: sensitivity ?? this.sensitivity,
    countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    contacts: contacts ?? this.contacts,
    shareLiveLink: shareLiveLink ?? this.shareLiveLink,
  );

  Map<String, dynamic> toJson() => {
    'enabled': crashDetectionEnabled,
    'sensitivity': sensitivity.name,
    'countdown_seconds': countdownSeconds,
    'share_live_link': shareLiveLink,
    'contacts': contacts.map((contact) => contact.toJson()).toList(),
  };

  factory SafetySettings.fromJson(Map<String, dynamic> json) => SafetySettings(
    crashDetectionEnabled: json['enabled'] as bool? ?? false,
    sensitivity: CrashSensitivity.parse(json['sensitivity'] as String?),
    countdownSeconds: (json['countdown_seconds'] as num?)?.toInt() ?? 30,
    shareLiveLink: json['share_live_link'] as bool? ?? true,
    contacts: (json['contacts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EmergencyContact.fromJson)
        .whereType<EmergencyContact>()
        .toList(),
  );
}
