import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/emergency.dart';
import '../services/app_services.dart';
import '../services/local_store.dart';
import '../widgets/lr_common.dart';

/// Ustawienia bezpieczeństwa: wykrywanie upadku i kontakty alarmowe.
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final safety = AppServices.of(context).safety;

    return AnimatedBuilder(
      animation: safety,
      builder: (context, _) {
        final settings = safety.settings;
        return Scaffold(
          appBar: AppBar(title: Text(S.safety)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.health_and_safety_outlined),
                title: Text(S.crashDetection),
                subtitle: Text(
                  settings.crashDetectionEnabled &&
                          settings.crashContacts.isEmpty
                      ? S.crashDetectionNeedsContact
                      : S.crashDetectionHint,
                  style:
                      settings.crashDetectionEnabled &&
                          settings.crashContacts.isEmpty
                      ? LR.body.copyWith(fontSize: 12.5, color: LR.alert)
                      : null,
                ),
                value: settings.crashDetectionEnabled,
                onChanged: (value) => safety.update(
                  settings.copyWith(crashDetectionEnabled: value),
                ),
              ),
              if (settings.crashDetectionEnabled) ...[
                ListTile(
                  title: Text(S.sensitivity),
                  trailing: DropdownButton<CrashSensitivity>(
                    value: settings.sensitivity,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final value in CrashSensitivity.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) => value == null
                        ? null
                        : safety.update(settings.copyWith(sensitivity: value)),
                  ),
                ),
                ListTile(
                  title: Text(S.countdown),
                  subtitle: Text(S.countdownHint),
                  trailing: Text(
                    '${settings.countdownSeconds} s',
                    style: LR.fieldValue(16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Slider(
                    value: settings.countdownSeconds.toDouble(),
                    min: 10,
                    max: 90,
                    divisions: 16,
                    label: '${settings.countdownSeconds} s',
                    onChanged: (value) => safety.update(
                      settings.copyWith(countdownSeconds: value.round()),
                    ),
                  ),
                ),
                SwitchListTile(
                  title: Text(S.shareLiveLinkLabel),
                  subtitle: Text(S.shareLiveLinkHint),
                  value: settings.shareLiveLink,
                  onChanged: (value) =>
                      safety.update(settings.copyWith(shareLiveLink: value)),
                ),
              ],
              const Divider(height: 1),
              LrSectionHeader(
                title: S.emergencyContacts,
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(S.addContact),
                  onPressed: () => _addContact(context),
                ),
              ),
              if (settings.contacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(S.noEmergencyContacts, style: LR.body),
                )
              else
                for (final contact in settings.contacts)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(contact.name),
                    subtitle: Text(contact.phone),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: contact.notifyOnCrash,
                          onChanged: (value) => safety.update(
                            settings.copyWith(
                              contacts: [
                                for (final item in settings.contacts)
                                  item.id == contact.id
                                      ? item.copyWith(notifyOnCrash: value)
                                      : item,
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => safety.update(
                            settings.copyWith(
                              contacts: settings.contacts
                                  .where((item) => item.id != contact.id)
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  S.smsDisclaimer,
                  style: LR.body.copyWith(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addContact(BuildContext context) async {
    final safety = AppServices.of(context).safety;
    final name = TextEditingController();
    final phone = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.addContact),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: S.contactName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: S.contactPhone),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.save),
          ),
        ],
      ),
    );

    final contactName = name.text.trim();
    final contactPhone = phone.text.trim();
    name.dispose();
    phone.dispose();
    if (saved != true || contactPhone.isEmpty) return;

    final settings = safety.settings;
    await safety.update(
      settings.copyWith(
        contacts: [
          ...settings.contacts,
          EmergencyContact(
            id: newLocalId('contact'),
            name: contactName.isEmpty ? contactPhone : contactName,
            phone: contactPhone,
          ),
        ],
      ),
    );
  }
}
