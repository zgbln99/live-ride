import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/live_privacy.dart';
import '../services/live_service.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';
import '../widgets/share_sheet.dart';
import 'group_ride_sheet.dart';
import 'live_diagnostics_sheet.dart';

/// Skąd otwarto arkusz LIVE.
///
/// Przekazywane jawnie, a nie zgadywane ze stosu nawigacji. Stos mówi tylko,
/// co jest pod spodem — nie mówi, czy zawodnik JEDZIE. Te dwie rzeczy rozeszły
/// się dokładnie tam, gdzie boli: arkusz otwarty z licznika w trakcie
/// nawigacji wyglądał identycznie jak otwarty z zakładki LIVE na postoju,
/// a wyjście z niego znaczyło w obu wypadkach co innego.
enum LiveSheetSource {
  /// Otwarty z ekranu jazdy. Pod spodem trwa przejazd i nawigacja.
  rideComputer,

  /// Otwarty z zakładki LIVE. Nie ma do czego wracać poza listą.
  liveTab,
}

/// Start, join, share or end a LIVE session.
///
/// The same sheet is used from the ride computer and from the LIVE tab so the
/// controls never disagree with each other.
Future<void> showLiveSheet(
  BuildContext context,
  AppServices services, {
  LiveSheetSource source = LiveSheetSource.liveTab,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // Bez tego arkusz kończy się na połowie ekranu, a prywatność, ustawienia
    // linku i diagnostyka dawno się tam nie mieszczą.
    isScrollControlled: true,
    builder: (sheetContext) => _LiveSheet(services: services, source: source),
  );
}

class _LiveSheet extends StatefulWidget {
  const _LiveSheet({required this.services, required this.source});

  final AppServices services;
  final LiveSheetSource source;

  @override
  State<_LiveSheet> createState() => _LiveSheetState();
}

class _LiveSheetState extends State<_LiveSheet> {
  bool _busy = false;

  /// Zamyka WYŁĄCZNIE ten arkusz.
  ///
  /// Nie dotyka ani transmisji, ani licznika, ani nawigacji, ani sensorów —
  /// to jest wyjście z ekranu ustawień, a nie z jazdy.
  void _close() => LrSheetClose.popOnce(context);

  @override
  Widget build(BuildContext context) {
    final live = widget.services.live;
    final session = live.session;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Arkusz rośnie z treścią, ale nie ponad ekran: sam nagłówek ma
        // zostać widoczny nawet wtedy, gdy treść jest dłuższa niż telefon.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(session),
            // `Flexible`, nie `Expanded`: przy krótkiej treści arkusz ma
            // zostać niski, a nie rozciągnąć się na cały ekran.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: session == null
                      ? _beforeStart()
                      : _whileLive(session),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nagłówek, który NIE odjeżdża razem z treścią.
  ///
  /// Wyjście z arkusza jest kontrolą bezpieczeństwa: zawodnik dotyka go
  /// w ruchu, jedną ręką, często w rękawiczkach. Przycisk na końcu dwóch
  /// ekranów ustawień nie jest wyjściem — jest zagadką.
  Widget _header(LiveSession? session) {
    final fromRide = widget.source == LiveSheetSource.rideComputer;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LR.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LrWordmark(compact: true),
              const Spacer(),
              LrSheetClose(onClose: _close),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: session == null
                ? Text(
                    S.broadcastingOff,
                    style: LR.fieldLabel.copyWith(color: LR.muted),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: LrStatusChip(
                      label: S.broadcastingActive,
                      color: LR.alert,
                      filled: true,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _close,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              // Z licznika wracamy do nawigacji i tak to się nazywa.
              // Z zakładki LIVE nie ma do czego wracać — zostaje „gotowe".
              child: Text(fromRide ? S.backToNavigation : S.doneAction),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _beforeStart() => [
    Text(S.liveDescription, style: LR.body.copyWith(height: 1.45)),
    const SizedBox(height: 14),
    _visibilityPicker(),
    const SizedBox(height: 10),
    _expiryPicker(),
    const SizedBox(height: 18),
    FilledButton.icon(
      onPressed: _busy ? null : _start,
      icon: const Icon(Icons.sensors, size: 18),
      label: Text(S.startLive),
    ),
    const SizedBox(height: 10),
    OutlinedButton.icon(
      onPressed: _busy ? null : _join,
      icon: const Icon(Icons.group_add_outlined, size: 18),
      label: Text(S.joinWithCode),
    ),
  ];

  List<Widget> _whileLive(LiveSession session) {
    final live = widget.services.live;
    final url = live.viewerUrl ?? '';
    final disabled = live.share.visibility == LiveShareVisibility.disabled;

    return [
      _row(S.rider, widget.services.profile.riderName),
      const SizedBox(height: 12),
      _copyRow(S.joinCode, session.joinToken),
      const SizedBox(height: 12),
      _copyRow(S.spectatorLink, url),
      if (!session.hasRoute) ...[
        const SizedBox(height: 8),
        Text(
          S.liveNoRouteHint,
          style: LR.body.copyWith(fontSize: 11.5, height: 1.4),
        ),
      ],
      const SizedBox(height: 16),
      _privacySection(live),
      const SizedBox(height: 14),
      _locationSection(live),
      const SizedBox(height: 14),
      _visibilityPicker(),
      const SizedBox(height: 10),
      _expiryPicker(),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: disabled
            ? null
            : () => showLrShareSheet(
                context,
                title: S.shareLiveTitle,
                subtitle: S.shareLiveSubtitle,
                url: url,
                message: live.shareMessage(),
              ),
        icon: const Icon(Icons.ios_share, size: 18),
        label: Text(S.shareTheLink),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        icon: const Icon(Icons.groups_outlined, size: 18),
        label: Text(S.groupRide),
        onPressed: () => showGroupRideSheet(context, widget.services),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        icon: const Icon(Icons.autorenew, size: 18),
        label: Text(S.newLinkAction),
        onPressed: _busy ? null : _rotate,
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        icon: const Icon(Icons.monitor_heart_outlined, size: 18),
        label: Text(S.liveDiagnostics),
        onPressed: () => showLiveDiagnosticsSheet(context, widget.services),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: _busy ? null : _stop,
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        label: Text(S.endLive),
        style: OutlinedButton.styleFrom(
          foregroundColor: LR.alert,
          side: const BorderSide(color: LR.alert),
        ),
      ),
    ];
  }

  Widget _visibilityPicker() {
    final live = widget.services.live;
    return LrPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.linkVisibility, style: LR.fieldLabel),
          const SizedBox(height: 8),
          SegmentedButton<LiveShareVisibility>(
            showSelectedIcon: false,
            segments: [
              for (final visibility in LiveShareVisibility.values)
                ButtonSegment(
                  value: visibility,
                  label: Text(
                    visibility.label,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
            selected: {live.share.visibility},
            onSelectionChanged: (selection) =>
                _applyShare(live.share.copyWith(visibility: selection.first)),
          ),
          const SizedBox(height: 8),
          Text(switch (live.share.visibility) {
            LiveShareVisibility.unlisted => S.linkUnlistedHint,
            LiveShareVisibility.public => S.linkPublicHint,
            LiveShareVisibility.disabled => S.linkDisabledHint,
          }, style: LR.body.copyWith(fontSize: 11.5, height: 1.4)),
        ],
      ),
    );
  }

  Widget _expiryPicker() {
    final live = widget.services.live;
    return LrPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.linkExpiry, style: LR.fieldLabel),
          const SizedBox(height: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<LiveShareExpiry>(
              isExpanded: true,
              value: live.share.expiry,
              items: [
                for (final expiry in LiveShareExpiry.values)
                  DropdownMenuItem(
                    value: expiry,
                    child: Text(expiry.label, style: LR.fieldValue(14)),
                  ),
              ],
              onChanged: (expiry) => expiry == null
                  ? null
                  : _applyShare(live.share.copyWith(expiry: expiry)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyShare(LiveShareSettings settings) async {
    final ok = await widget.services.live.updateShare(settings);
    if (!mounted) return;
    setState(() {});
    // Wybór i tak jest zapisany lokalnie; komunikat mówi tylko tyle, że
    // serwer jeszcze o nim nie wie.
    if (!ok) showLrMessage(context, S.linkSettingsQueued);
  }

  Widget _row(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: LR.fieldLabel),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _copyRow(String label, String value) => LrPanel(
    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
    child: Row(
      children: [
        Expanded(child: _row(label, value)),
        IconButton(
          tooltip: S.copy,
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (mounted) showLrMessage(context, S.linkCopied);
          },
        ),
      ],
    ),
  );

  /// Co z jazdy widzą obserwujący.
  ///
  /// Przełączniki były wcześniej wyłącznie w arkuszu jazdy grupowej, więc
  /// zawodnik jadący sam NIE MIAŁ JAK włączyć tętna — a domyślnie jest
  /// wyłączone, bo to dana osobista. Efekt wyglądał jak usterka publicznej
  /// strony: telefon pokazuje 142 bpm, strona nie pokazuje nic, i nic nigdzie
  /// nie mówi, dlaczego.
  Widget _privacySection(LiveSessionController live) {
    final privacy = live.privacy;
    final all =
        privacy.sharePosition &&
        privacy.shareSpeed &&
        privacy.shareHeartRate &&
        privacy.sharePower &&
        privacy.shareBattery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(S.sharedInLive, style: LR.fieldLabel)),
            TextButton(
              onPressed: all
                  ? null
                  : () => live.updatePrivacy(
                      const LivePrivacy(
                        sharePosition: true,
                        shareSpeed: true,
                        shareHeartRate: true,
                        sharePower: true,
                        shareBattery: true,
                      ),
                    ),
              child: Text(S.shareEverything),
            ),
          ],
        ),
        _privacyTile(
          S.sharePosition,
          privacy.sharePosition,
          (value) => live.updatePrivacy(
            privacy.copyWith(sharePosition: value),
          ),
        ),
        _privacyTile(
          S.shareSpeed,
          privacy.shareSpeed,
          (value) => live.updatePrivacy(privacy.copyWith(shareSpeed: value)),
        ),
        _privacyTile(
          S.shareHeartRate,
          privacy.shareHeartRate,
          (value) => live.updatePrivacy(
            privacy.copyWith(shareHeartRate: value),
          ),
          // Bez podłączonego paska przełącznik i tak nie ma czego wysyłać —
          // lepiej powiedzieć to wprost, niż zostawić kogoś z włączonym
          // przełącznikiem i pustym polem na stronie.
          hint: widget.services.heartRate.latestBpm == null
              ? S.noHeartRateSensor
              : null,
        ),
        _privacyTile(
          S.sharePower,
          privacy.sharePower,
          (value) => live.updatePrivacy(privacy.copyWith(sharePower: value)),
          hint: widget.services.sensors.snapshot.powerWatts == null
              ? S.noPowerSensor
              : null,
        ),
        _privacyTile(
          S.shareBattery,
          privacy.shareBattery,
          (value) => live.updatePrivacy(privacy.copyWith(shareBattery: value)),
        ),
        if (!privacy.sharesAnything)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              S.sharesNothing,
              style: LR.body.copyWith(fontSize: 12, color: LR.alert),
            ),
          ),
      ],
    );
  }

  /// Ograniczenia lokalizacji — trzy decyzje, wszystkie egzekwowane przez
  /// serwer.
  ///
  /// Każda z nich zrobiona w przeglądarce byłaby warta tyle, co komentarz
  /// w kodzie: dane i tak poleciałyby po sieci, a „ukrycie" polegałoby na
  /// tym, że widz ich nie kliknie. Tutaj są tylko przełączniki — decyzję
  /// wykonuje publiczne API, które po prostu nie zna odpowiedzi.
  Widget _locationSection(LiveSessionController live) {
    final privacy = live.privacy;
    if (!privacy.sharePosition) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.locationPrivacy, style: LR.fieldLabel),
        const SizedBox(height: 6),
        _choiceRow(
          label: S.locationDelay,
          values: liveLocationDelayChoices,
          selected: privacy.locationDelaySeconds,
          labelFor: (value) => value == 0 ? S.locationDelayNone : '$value s',
          onSelected: (value) => live.updatePrivacy(
            privacy.copyWith(locationDelaySeconds: value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text(
            S.locationDelayHint,
            style: LR.body.copyWith(fontSize: 11.5, height: 1.35),
          ),
        ),
        _choiceRow(
          label: S.hideStart,
          values: liveHideRadiusChoices,
          selected: privacy.hideStartMeters,
          labelFor: (value) => value == 0 ? S.hideNone : '$value m',
          onSelected: (value) =>
              live.updatePrivacy(privacy.copyWith(hideStartMeters: value)),
        ),
        const SizedBox(height: 6),
        _choiceRow(
          label: S.hideFinish,
          values: liveHideRadiusChoices,
          selected: privacy.hideFinishMeters,
          labelFor: (value) => value == 0 ? S.hideNone : '$value m',
          onSelected: (value) =>
              live.updatePrivacy(privacy.copyWith(hideFinishMeters: value)),
        ),
        _privacyTile(
          S.locationCoarse,
          privacy.locationCoarse,
          (value) =>
              live.updatePrivacy(privacy.copyWith(locationCoarse: value)),
          hint: S.locationCoarseHint,
        ),
      ],
    );
  }

  /// Wiersz wyboru z kilku wartości. Cztery pozycje da się trafić
  /// w rękawiczkach; suwak od zera do minuty nie.
  Widget _choiceRow({
    required String label,
    required List<int> values,
    required int selected,
    required String Function(int) labelFor,
    required ValueChanged<int> onSelected,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: LR.body.copyWith(color: LR.ink, fontSize: 14)),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        children: [
          for (final value in values)
            ChoiceChip(
              label: Text(labelFor(value)),
              selected: selected == value,
              onSelected: (_) => onSelected(value),
            ),
        ],
      ),
    ],
  );

  Widget _privacyTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    String? hint,
  }) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    title: Text(title, style: LR.body.copyWith(color: LR.ink, fontSize: 14)),
    subtitle: hint == null
        ? null
        : Text(hint, style: LR.body.copyWith(fontSize: 11.5)),
    value: value,
    onChanged: onChanged,
  );

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      // Trasa wczytana do licznika jedzie razem z sesją: bez niej publiczna
      // strona nie narysuje planu, nie policzy postępu ani ETA.
      final route = widget.services.recorder.route;
      await widget.services.live.create(routeClientId: route?.id);
      if (mounted) setState(() {});
      // Link bez zawodnika na mapie jest linkiem do pustej strony. Pierwsza
      // telemetria idzie natychmiast, jeszcze zanim ktokolwiek ruszy —
      // zawodnik, który udostępnia jazdę stojąc przed domem, ma być widoczny
      // w chwili, w której znajomy otworzy wiadomość.
      await widget.services.recorder.publishLiveNow();
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) showLrMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) showLrMessage(context, S.liveStartFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final ok = await widget.services.live.rotateShareLink();
    if (!mounted) return;
    setState(() => _busy = false);
    showLrMessage(context, ok ? S.newLinkDone : S.newLinkFailed, error: !ok);
  }

  Future<void> _join() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.joinLiveTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: S.liveCode),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(S.joinWithCode),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      await widget.services.live.join(code);
      if (mounted) setState(() {});
      // Tak samo jak przy własnej jeździe: grupa ma zobaczyć dołączającego
      // od razu, a nie dopiero wtedy, gdy ten ruszy.
      await widget.services.recorder.publishLiveNow();
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) showLrMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) showLrMessage(context, S.liveJoinFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    await widget.services.live.stop();
    if (mounted) setState(() => _busy = false);
  }
}
