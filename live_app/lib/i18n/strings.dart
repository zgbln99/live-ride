import 'package:flutter/widgets.dart';

/// Wszystkie teksty aplikacji.
///
/// Polski jest językiem bazowym i jest zaimplementowany tutaj wprost. Kolejny
/// język dodaje się przez rozszerzenie tej klasy i nadpisanie getterów —
/// brakujące tłumaczenie spada wtedy na polski zamiast wysypywać ekran.
///
/// Teksty są getterami, a nie mapą, bo literówka w kluczu mapy jest błędem
/// dopiero na urządzeniu, a literówka w getterze nie kompiluje się.
class Strings {
  const Strings();

  String get localeCode => 'pl';

  // ---------------------------------------------------------------- ogólne
  String get appName => 'LIVE RIDE';
  String get ok => 'OK';
  String get cancel => 'Anuluj';
  String get save => 'Zapisz';
  String get delete => 'Usuń';
  String get rename => 'Zmień nazwę';
  String get edit => 'Edytuj';
  String get add => 'Dodaj';
  String get close => 'Zamknij';
  String get back => 'Wróć';
  String get retry => 'Spróbuj ponownie';
  String get done => 'Gotowe';
  String get next => 'Dalej';
  String get share => 'Udostępnij';
  String get copy => 'Kopiuj';
  String get copied => 'Skopiowano';
  String get search => 'Szukaj';
  String get loading => 'Wczytywanie…';
  String get none => 'brak';
  String get all => 'Wszystkie';
  String get more => 'Więcej';
  String get settings => 'Ustawienia';
  String get openSettings => 'Otwórz Ustawienia';
  String get notAvailable => '--';
  String get today => 'Dziś';
  String get yesterday => 'Wczoraj';

  // ------------------------------------------------------------ nawigacja
  String get tabRide => 'JAZDA';
  String get tabRoutes => 'TRASY';
  String get tabMusic => 'MUZYKA';
  String get tabHistory => 'HISTORIA';
  String get tabLive => 'LIVE';
  String get tabProfile => 'PROFIL';

  // ----------------------------------------------------------- logowanie
  String get signIn => 'Zaloguj się';
  String get signInTitle => 'Zaloguj się i jedź';
  String get register => 'Utwórz konto';
  String get registerTitle => 'Załóż konto zawodnika';
  String get username => 'Nazwa użytkownika';
  String get email => 'E-mail';
  String get password => 'Hasło';
  String get haveAccount => 'Mam już konto';
  String get createAccount => 'Załóż nowe konto';
  String get signOut => 'Wyloguj się';
  String get sessionExpired =>
      'Sesja wygasła. Zaloguj się ponownie, żeby wrócić do LIVE i synchronizacji.';
  String get wrongCredentials => 'Błędna nazwa użytkownika lub hasło.';
  String get usernameTaken => 'Ta nazwa użytkownika lub e-mail są już zajęte.';
  String get notSignedIn => 'Nie jesteś zalogowany.';
  String get passwordTooShort => 'Hasło musi mieć co najmniej 8 znaków.';
  String get usernameRequired => 'Podaj nazwę użytkownika.';
  String get emailRequired => 'Podaj adres e-mail.';
  String get emailInvalid => 'To nie wygląda na adres e-mail.';

  // ------------------------------------------------------- pulpit i listy
  String ridingAsTelemetry(String name, int seconds) =>
      'Jedziesz jako $name. Dane lecą na serwer co $seconds s, dopóki trwa '
      'nagrywanie przejazdu.';
  String sensorBattery(int percent) => '$percent % baterii';
  String get connectStrapHint =>
      'Podłącz opaskę WHOOP albo dowolny pasek Bluetooth z tętnem.';

  String get importGpxHint =>
      'Zaimportuj plik GPX, żeby jechać zaplanowaną trasą.';
  String get historyEmptyHint =>
      'Zakończone przejazdy pojawią się tutaj z pełnymi statystykami '
      'i eksportem do GPX.';

  // ---------------------------------------------------------------- jazda
  String get startRide => 'ROZPOCZNIJ JAZDĘ';
  String get backToRide => 'WRÓĆ DO JAZDY';
  String get freeRide => 'Wolna jazda';
  String get freeRideSubtitle => 'Wolna jazda — bez trasy.';
  String get rideInProgress => 'JAZDA W TOKU';
  String get readyToRide => 'GOTOWY DO JAZDY';
  String get rideInProgressSubtitle => 'Komputer rowerowy nadal pracuje.';
  String get rideDescription =>
      'Ślad GPS, prędkość, dystans, przewyższenie, tętno i transmisja LIVE.';
  String get recording => 'NAGRYWANIE';
  String get paused => 'PAUZA';
  String get pause => 'PAUZA';
  String get resume => 'WZNÓW';
  String get finish => 'ZAKOŃCZ';
  String get saving => 'ZAPIS…';
  String get elapsed => 'CZAS';
  String get exitRide => 'Zakończ jazdę';
  String get exitNavigation => 'Zakończ nawigację';
  String get keepRiding => 'Jedź dalej';
  String get finishAndSave => 'Zakończ i zapisz';
  String get discardRide => 'Odrzuć ten przejazd';
  String get rideDiscardedTooShort =>
      'Przejazd odrzucony — był za krótki, żeby go zapisać.';
  String get rideSettings => 'Ustawienia jazdy';
  String get headingUp => 'Mapa zgodnie z kierunkiem jazdy';
  String get headingUpSubtitle => 'Obracaj mapę razem z kierunkiem jazdy';
  String get keepScreenOn => 'Nie wygaszaj ekranu';
  String get showWeather => 'Pokazuj pogodę';
  String get dataFields => 'Pola danych';
  String get presets => 'Zestawy';
  String get page => 'Strona';
  String get recenter => 'Wyśrodkuj';
  String get zoomIn => 'Przybliż';
  String get zoomOut => 'Oddal';
  String get routeOverview => 'Podgląd całej trasy';
  String get tapToShowControls => 'DOTKNIJ, ABY POKAZAĆ STEROWANIE';
  String get noFix => 'BRAK GPS';
  String get liveOffline => 'LIVE OFFLINE';
  String get mapUnavailableOffline => 'Mapa niedostępna offline';
  String get followTheTrack => 'Jedź po śladzie';
  String get stayOnRoute => 'Trzymaj się trasy';
  String get arriveAtDestination => 'Dojazd do celu';
  String get continueStraight => 'Jedź dalej';
  String get offRoute => 'POZA TRASĄ';
  String get followingImportedTrack =>
      'JEDZIESZ PO ZAIMPORTOWANYM ŚLADZIE · brak wskazówek';
  String get remainingShort => 'ZOSTAŁO';
  String get eta => 'NA MECIE';
  String get lostGpsSignal => 'Utracono sygnał GPS.';
  String get locationServicesOff =>
      'Usługi lokalizacji są wyłączone. Włącz je, żeby nagrać przejazd.';
  String get locationNeeded =>
      'Live Ride potrzebuje dostępu do lokalizacji, żeby nagrać przejazd.';
  String get locationBlocked =>
      'Dostęp do lokalizacji jest zablokowany. Włącz go w Ustawieniach, '
      'żeby nagrywać przejazdy i nawigować.';

  // -------------------------------------------------------- pola danych
  String get fieldSpeed => 'PRĘDKOŚĆ';
  String get fieldAvgSpeed => 'ŚR. PRĘDKOŚĆ';
  String get fieldMaxSpeed => 'MAKS. PRĘDKOŚĆ';
  String get fieldDistance => 'DYSTANS';
  String get fieldElapsed => 'CZAS';
  String get fieldMovingTime => 'W RUCHU';
  String get fieldElevation => 'WYSOKOŚĆ';
  String get fieldAscent => 'PODJAZD';
  String get fieldDescent => 'ZJAZD';
  String get fieldGradient => 'NACHYLENIE';
  String get fieldHeartRate => 'TĘTNO';
  String get fieldAvgHeartRate => 'ŚR. TĘTNO';
  String get fieldMaxHeartRate => 'MAKS. TĘTNO';
  String get fieldHeartRateZone => 'STREFA HR';
  String get fieldCadence => 'KADENCJA';
  String get fieldAvgCadence => 'ŚR. KADENCJA';
  String get fieldPower => 'MOC';
  String get fieldPower3s => 'MOC 3 S';
  String get fieldPower10s => 'MOC 10 S';
  String get fieldPower30s => 'MOC 30 S';
  String get fieldAvgPower => 'ŚR. MOC';
  String get fieldNormalizedPower => 'NP';
  String get fieldTss => 'TSS';
  String get fieldIntensityFactor => 'IF';
  String get fieldGps => 'GPS';
  String get fieldTemperature => 'TEMP.';
  String get fieldWind => 'WIATR';
  String get fieldRain => 'DESZCZ';
  String get fieldClock => 'GODZINA';
  String get fieldRemaining => 'DO METY';
  String get fieldEta => 'NA MECIE';
  String get fieldBattery => 'BATERIA';
  String get fieldDistanceToTurn => 'DO ZAKRĘTU';
  String get fieldDistanceToClimb => 'DO PODJAZDU';
  String get fieldClimbRemaining => 'PODJAZD ZOST.';
  String get fieldPaceDelta => 'DO PLANU';

  String fieldsCount(int count) => '$count ${_pola(count)}';
  String get layoutOne => '1 pole';
  String get dataPages => 'Strony danych';
  String get addPage => 'Dodaj stronę';
  String get removePage => 'Usuń stronę';
  String get pageName => 'Nazwa strony';
  String get presetTouring => 'Wycieczka';
  String get presetTraining => 'Trening';
  String get presetRace => 'Wyścig';
  String get presetNavigation => 'Nawigacja';
  String get presetNight => 'Noc';
  String get longPressToChange => 'Przytrzymaj pole, aby je zmienić';

  // -------------------------------------------------------------- pogoda
  String get weather => 'Pogoda';
  String get conditions => 'Warunki';
  String get feelsLike => 'odczuwalna';
  String get windHead => 'czołowy';
  String get windTail => 'z tyłu';
  String get windCross => 'boczny';
  String get rainChance => 'szansa opadów';
  String get noRainData => 'brak danych o opadach';
  String get weatherUnavailable => 'Pogoda niedostępna';
  String get weatherAppearsWithPosition =>
      'Pogoda pojawi się, gdy Live Ride pozna Twoją pozycję.';
  String get weatherAlongRoute => 'Pogoda na trasie';
  String get atStart => 'Na starcie';
  String get atFinish => 'Na mecie';
  String get sunset => 'Zachód słońca';
  String get clear => 'Bezchmurnie';
  String get partlyCloudy => 'Częściowe zachmurzenie';
  String get cloudy => 'Pochmurno';
  String get fog => 'Mgła';
  String get drizzle => 'Mżawka';
  String get rain => 'Deszcz';
  String get heavyRain => 'Ulewa';
  String get snow => 'Śnieg';
  String get thunderstorm => 'Burza';
  String get unknownCondition => '--';

  // --------------------------------------------------------------- trasy
  String get routes => 'Trasy';
  String get route => 'Trasa';
  String get searchRoutes => 'Szukaj tras';
  String get importGpx => 'IMPORTUJ GPX';
  String get exportGpx => 'Eksportuj GPX';
  String get noRoutesYet => 'Nie masz jeszcze tras';
  String get noRoutesMessage =>
      'Zaplanuj trasę w kreatorze albo zaimportuj plik GPX z Plików, iCloud '
      'Drive lub dowolnej chmury — Live Ride poprowadzi Cię zakręt po zakręcie.';
  String get noMatches => 'Brak wyników';
  String get navigate => 'NAWIGUJ';
  String get ride => 'JEDŹ';
  String get preview => 'Podgląd';
  String get preparing => 'PRZYGOTOWUJĘ…';
  String get imported => 'ZAIMPORTOWANA';
  String get createdInApp => 'Utworzona w Live Ride';
  String get importedGpx => 'Zaimportowany GPX';
  String get added => 'DODANO';
  String get ridden => 'PRZEJECHANA';
  String get points => 'Punkty';
  String get deleteRouteTitle => 'Usunąć tę trasę?';
  String deleteRouteMessage(String name) =>
      'Trasa „$name” zostanie usunięta z tego urządzenia.';
  String get plan => 'PLANUJ';
  String get liveIsOn => 'LIVE jest włączone';
  String get waitingForSignal => 'CZEKAM NA SYGNAŁ';
  String get continueAhead => 'Jedź prosto';
  String get newRoute => 'NOWA TRASA';
  String get editRoute => 'EDYCJA TRASY';
  String get undo => 'Cofnij';
  String get searchPlace => 'Szukaj miejsca';
  String get myPosition => 'Moja pozycja';
  String get fitView => 'Dopasuj widok';
  String get waypointsShort => 'Punkty';
  String get profileShort => 'Profil';
  String get saveUpper => 'ZAPISZ';
  String get noGpsPosition => 'Brak pozycji GPS.';
  String get unnamedRoute => 'Trasa bez nazwy';
  String get waypoints => 'Punkty trasy';
  String get placeQueryHint => 'Miasto, ulica albo nazwa miejsca';
  String get typeAtLeastThree => 'Wpisz co najmniej trzy znaki.';
  String get searchingPlaces => 'Szukam…';
  String get descent2 => 'Zjazd';
  String get bike => 'Rower';
  String get routeCharacter => 'Charakter trasy';
  String get surface => 'Nawierzchnia';
  String get avoidAndPrefer => 'Unikaj i preferuj';
  String get avoidTunnels => 'Unikaj tuneli';
  String get apply => 'ZASTOSUJ';
  String get maxSpeed => 'Maks. prędkość';
  String get avgSpeed => 'Śr. prędkość';
  String get avgHeartRate => 'Śr. tętno';
  String get maxHeartRateShort => 'Maks. tętno';
  String get elevation => 'Wysokość';
  String get openSettingsButton => 'OTWÓRZ USTAWIENIA';
  String get tryAgain => 'SPRÓBUJ PONOWNIE';
  String nothingMatches(String query) =>
      'Nic w Twojej bibliotece nie pasuje do „$query".';
  String get editInBuilder => 'Edytuj w kreatorze';
  String get routeName => 'Nazwa trasy';
  String get routeShapeLoop => 'Pętla';
  String get routeShapeOutAndBack => 'Tam i z powrotem';
  String get routeShapePointToPoint => 'Z punktu do punktu';

  String get rideMorning => 'Poranna jazda';
  String get rideMidday => 'Południowa jazda';
  String get rideAfternoon => 'Popołudniowa jazda';
  String get rideEvening => 'Wieczorna jazda';

  String get alerts => 'Powiadomienia';
  String get haptics => 'Wibracje';
  String get hapticsHint =>
      'Krótka wibracja przy powiadomieniu — czytelna nawet w rękawiczkach.';
  String get everyMinutes => 'Co ile minut';
  String get everyKilometers => 'Co ile km';
  String get threshold => 'Próg';
  String get needsPowerMeter => 'wymaga miernika mocy';
  String get needsCadenceSensor => 'wymaga czujnika kadencji';
  String get needsHeartRateStrap => 'wymaga paska na klatę';
  String get autoPauseTitle => 'Automatyczna pauza';
  String get autoPauseHint =>
      'Licznik zatrzymuje się na postoju i rusza, gdy ruszysz.';

  // -------------------------------------------------------------- offline
  String get offline => 'Offline i synchronizacja';
  String get synchronisation => 'Synchronizacja';
  String get syncExplainer =>
      'Telefon jest źródłem prawdy. Przejazd jest zapisany i kompletny w '
      'chwili zakończenia, a kopia na serwerze może poczekać do następnego '
      'zasięgu.';
  String get everythingSynced => 'Wszystko zsynchronizowane';
  String waitingToSync(int count) => 'Czeka na wysłanie: $count';
  String get lastSync => 'Ostatnia synchronizacja';
  String get syncNow => 'SYNCHRONIZUJ TERAZ';
  String get offlineMaps => 'Mapy offline';
  String get offlineMapsExplainer =>
      'Pobierz mapę wokół trasy, a nawigacja zadziała bez zasięgu. Pobieramy '
      'pas 1,5 km wokół trasy w powiększeniach przydatnych w jeździe.';
  String get offlineMapsUnsupported =>
      'Ta platforma nie obsługuje map offline.';
  String get noOfflineMaps => 'Nie masz pobranych map.';
  String get downloadOfflineMap => 'Pobierz mapę offline';
  String get offlineMapReady => 'Mapa pobrana';

  // ------------------------------------------------------------ integracje
  String get integrations => 'Integracje';
  String get exportAndSync => 'Eksport i synchronizacja';
  String get stravaNeedsCredentials =>
      'Podaj client ID i sekret aplikacji Strava, żeby się połączyć.';
  String get stravaStateMismatch =>
      'Odpowiedź Stravy nie pasuje do zapytania. Spróbuj ponownie.';
  String get stravaAccessDenied => 'Nie zgodziłeś się na dostęp.';
  String get stravaAuthFailed => 'Strava odrzuciła logowanie.';
  String get stravaNoCode => 'Strava nie odesłała kodu autoryzacji.';
  String get stravaSignInAgain => 'Zaloguj się do Stravy ponownie.';
  String get stravaRateLimited =>
      'Strava chwilowo ogranicza zapytania. Spróbuj za kilka minut.';
  String get stravaRejected => 'Strava odrzuciła ten plik.';
  String get stravaTimeout => 'Strava nie odpowiedziała na czas.';
  String get stravaUnreachable => 'Brak połączenia ze Stravą.';
  String get stravaNoUploadId => 'Strava nie podała identyfikatora wysyłki.';
  String get stravaSetupTitle => 'Własna aplikacja Strava';
  String get stravaSetupIntro =>
      'Strava wymaga, żeby każda aplikacja miała własne client ID i sekret. '
      'Live Ride celowo nie ma wspólnych — sekret w aplikacji rozdawanej '
      'wszystkim należałby do wszystkich naraz. Twój zostaje na tym '
      'telefonie.';
  String get stravaStep1 =>
      'Wejdź na strava.com/settings/api i utwórz aplikację.';
  String get stravaStep2 => 'W polu Authorization Callback Domain wpisz:';
  String get stravaStep3 => 'Skopiuj Client ID i Client Secret poniżej.';
  String get clientSecret => 'Client secret';
  String get connectStrava => 'POŁĄCZ ZE STRAVĄ';
  String get uploadToStrava => 'Wyślij do Stravy';
  String get uploadDone => 'Wysłano';
  String get uploadProcessing => 'Strava przetwarza plik…';
  String get uploadFailed => 'Wysyłka nie powiodła się';
  String get noPublicApi => 'Brak publicznego API';
  String noPublicApiMessage(String name) =>
      '$name nie udostępnia API aplikacjom spoza swojego programu '
      'partnerskiego i nie da się o nie poprosić jako osoba prywatna. '
      'Przycisk „Połącz", który nic nie robi, byłby kłamstwem — zamiast '
      'niego Live Ride daje to, co naprawdę działa: eksport pliku, który '
      '$name zaimportuje.';
  String get exportFile => 'Eksportuj plik';
  String get healthTitle => 'Apple Health / Health Connect';
  String get healthIntro =>
      'Zapis jest jednostronny i tylko na żądanie. Live Ride nic z Health nie '
      'czyta i nic nie wysyła sam z siebie.';
  String get healthAutoExport => 'Zapisuj przejazdy automatycznie';
  String get healthGrant => 'Udziel zgody';
  String get healthReady => 'Gotowe do zapisu';
  String get healthDenied => 'Brak zgody na zapis';
  String get healthNotInstalled =>
      'Zainstaluj Health Connect, żeby zapisywać przejazdy.';
  String get healthUnsupported =>
      'Ta platforma nie udostępnia Apple Health ani Health Connect.';
  String get exportedToHealth => 'Zapisano w Health';

  // ---------------------------------------------------------- bezpieczeństwo
  String get safety => 'Bezpieczeństwo';
  String get crashDetection => 'Wykrywanie upadku';
  String get crashDetectionHint =>
      'Mocne uderzenie, nagły spadek prędkości i bezruch po nim. Każde z '
      'osobna zdarza się w normalnej jeździe — dopiero razem znaczą coś '
      'złego.';
  String get crashDetectionNeedsContact =>
      'Dodaj kontakt alarmowy — bez niego alarm nie ma komu nic zgłosić.';
  String get sensitivity => 'Czułość';
  String get countdown => 'Odliczanie';
  String get countdownHint => 'Tyle masz na anulowanie fałszywego alarmu.';
  String get emergencyContacts => 'Kontakty alarmowe';
  String get addContact => 'Dodaj kontakt';
  String get contactName => 'Imię';
  String get contactPhone => 'Numer telefonu';
  String get notifyOnCrash => 'Powiadom przy upadku';
  String get shareLiveLinkLabel => 'Dołącz link LIVE';
  String get shareLiveLinkHint =>
      'Gdy sesja LIVE jest aktywna, wiadomość zawiera link z Twoją pozycją '
      'na żywo.';
  String get sos => 'SOS';
  String get sosCrashTitle => 'Wygląda na upadek';
  String get sosManualTitle => 'Alarm SOS';
  String get sosCancel => 'NIC MI NIE JEST';
  String get sosSendNow => 'WYŚLIJ TERAZ';
  String sosCountdown(int seconds) =>
      'Za $seconds s wyślę wiadomość do kontaktów alarmowych.';
  String get sosCrashMessage =>
      'Live Ride wykrył upadek podczas mojej jazdy. Moja ostatnia znana '
      'pozycja:';
  String get sosManualMessage =>
      'Potrzebuję pomocy. Moja ostatnia znana pozycja:';
  String get sosSendFailed =>
      'Nie udało się otworzyć wiadomości. Zadzwoń bezpośrednio:';
  String get call => 'Zadzwoń';
  String get noEmergencyContacts => 'Brak kontaktów alarmowych';
  String get smsDisclaimer =>
      'Wiadomość otwiera się w aplikacji SMS, żebyś zobaczył jej treść przed '
      'wysłaniem. Automatyczna wysyłka bez Twojego udziału nie jest możliwa '
      'na iOS i Live Ride nie udaje, że jest.';

  // ------------------------------------------------------------- segmenty
  String get segments => 'Segmenty';
  String get segment => 'Segment';
  String get newSegment => 'Nowy segment';
  String get segmentName => 'Nazwa segmentu';
  String get noSegments => 'Nie masz jeszcze segmentów';
  String get noSegmentsMessage =>
      'Wytnij fragment trasy albo przejazdu, a Live Ride zacznie mierzyć na '
      'nim czas i porównywać go z Twoim rekordem.';
  String segmentCreated(String name) => 'Segment „$name" zapisany';
  String get attempts => 'Próby';
  String get noAttempts => 'Jeszcze nie przejechałeś tego segmentu.';
  String get personalBest => 'Rekord';
  String aheadOfRecord(String seconds) => '$seconds s przed rekordem';
  String behindRecord(String seconds) => '$seconds s za rekordem';
  String get aheadShort => 'PRZED';
  String get behindShort => 'ZA';
  String get pacePartner => 'Wirtualny rywal';
  String get pacePartnerHint =>
      'Ścigaj się ze stałą prędkością, z czasem na trasie albo ze swoim '
      'wcześniejszym przejazdem.';
  String get startPacePartner => 'Uruchom rywala';
  String get stopPacePartner => 'Wyłącz rywala';
  String get targetSpeed => 'Prędkość docelowa';
  String get targetTime => 'Czas docelowy';
  String get ghostNeedsRide =>
      'Ghost potrzebuje wcześniejszego przejazdu z zapisanym śladem.';

  String get raceMode => 'Tryb wyścigu';
  String get raceModeHint =>
      'Tylko liczby, bez przycisków, z podbitą jasnością ekranu.';
  String get lockScreen => 'Zablokuj ekran';
  String get holdToUnlock => 'PRZYTRZYMAJ, ABY ODBLOKOWAĆ';
  String get boostBrightness => 'Podbij jasność';
  String get brightnessUnavailable =>
      'System nie pozwolił zmienić jasności ekranu.';

  String get climbInProgress => 'PODJAZD';
  String get climbDone => 'PODJAZD ZALICZONY';
  String get remainingClimb => 'DO SZCZYTU';
  String get remainingAscent => 'W PIONIE';
  String get gradientNow => 'NACHYLENIE';
  String climbAhead(String distance) => 'Za $distance podjazd';

  // ------------------------------------------------------- briefing trasy
  String get briefing => 'Briefing';
  String get briefingTitle => 'Przed startem';
  String get climbs => 'Podjazdy';
  String get noClimbs => 'Brak wyraźnych podjazdów na tej trasie.';
  String get loadingForecast => 'Liczę prognozę na trasie…';
  String get routeUnavailable => 'Nie mogę wczytać trasy';
  String get distance => 'Dystans';
  String get ascent => 'Przewyższenie';
  String get descent => 'Spadek';
  String get difficulty => 'Trudność';
  String get estimatedTime => 'Szacowany czas';
  String get averageGradient => 'Średnie nachylenie';
  String get maxGradient => 'Maks. nachylenie';
  String get climbCategory => 'Kategoria';
  String get startNow => 'Start teraz';
  String get addRiderWeightHint =>
      'Uzupełnij wagę w profilu, żeby zobaczyć szacowany wydatek energii.';

  // ------------------------------------------------------------ historia
  String get records => 'Rekordy';
  String get calendar => 'Kalendarz';
  String get heatmap => 'Mapa cieplna';
  String get heatmapEmpty => 'Za mało przejazdów';
  String get heatmapEmptyMessage =>
      'Mapa cieplna rysuje się z zapisanych śladów. Przejedź kilka tras, '
      'a zobaczysz tu swoje ulubione drogi.';
  String heatmapPointCount(int count) => '$count punktów z Twoich przejazdów';
  String comparedToPrevious(String change) =>
      '$change względem poprzedniego okresu';
  String get average => 'Średnia';
  String get movingTime => 'W ruchu';
  String get history => 'Historia';
  String get rideSummary => 'PODSUMOWANIE PRZEJAZDU';
  String get noRidesYet => 'Brak zapisanych przejazdów';
  String get noRidesMessage =>
      'Naciśnij ROZPOCZNIJ JAZDĘ na karcie Jazda. Po zakończeniu przejazd '
      'trafi tutaj razem ze śladem, statystykami i eksportem GPX.';
  String get allTime => 'Wszystko';
  String get last30Days => 'Ostatnie 30 dni';
  String get lastRide => 'Ostatni przejazd';
  String get rides => 'Przejazdy';
  String get gpsPoints => 'Punkty GPS';
  String get deleteRideTitle => 'Usunąć ten przejazd?';
  String get deleteRideMessage =>
      'Zapisany ślad zostanie usunięty z tego urządzenia.';
  String get renameRide => 'Zmień nazwę przejazdu';
  String get rideName => 'Nazwa przejazdu';
  String get elevationProfile => 'Profil wysokości';
  String get noElevationData => 'Brak danych o wysokości';
  String get morningRide => 'Poranna jazda';
  String get middayRide => 'Południowa jazda';
  String get afternoonRide => 'Popołudniowa jazda';
  String get eveningRide => 'Wieczorna jazda';

  // ---------------------------------------------------------------- LIVE
  String get liveTracking => 'Transmisja LIVE';
  String get notBroadcasting => 'Nie transmitujesz';
  String get broadcasting => 'TRANSMISJA';
  String get live => 'LIVE';
  String get reconnecting => 'ŁĄCZENIE PONOWNE';
  String get startLive => 'ROZPOCZNIJ LIVE';
  String get startOrJoinLive => 'ROZPOCZNIJ LUB DOŁĄCZ DO LIVE';
  String get joinWithCode => 'DOŁĄCZ KODEM';
  String get joinLiveTitle => 'Dołącz do LIVE';
  String get liveCode => 'Kod LIVE';
  String get joinCode => 'KOD DOŁĄCZENIA';
  String get spectatorLink => 'LINK DLA WIDZÓW';
  String get shareTheLink => 'UDOSTĘPNIJ LINK';
  String get endLive => 'ZAKOŃCZ LIVE';
  String get rider => 'Zawodnik';
  String get liveDescription =>
      'Udostępnij jeden link. Każdy, kto go ma, zobaczy Twoją pozycję, '
      'prędkość, dystans i tętno na pełnoekranowej mapie — bez zakładania konta.';
  String get waitingForFirstUpload => 'Czekam na pierwszą wysyłkę telemetrii…';
  String lastUpdate(String time) => 'Ostatnia aktualizacja $time';
  String get followMyRide => 'Śledź moją jazdę w Live Ride';
  String get liveSignInAgain =>
      'Zaloguj się ponownie, żeby rozpocząć transmisję LIVE.';
  String get liveCodeNotFound =>
      'Żadna aktywna transmisja nie używa tego kodu.';
  String get liveCodeInvalid => 'Ten kod LIVE nie wygląda poprawnie.';

  // ------------------------------------------------------------- sensory
  String get sensors => 'Sensory';
  String get heartRate => 'Tętno';
  String get sensorsNearby => 'Sensory w pobliżu';
  String get scan => 'SKANUJ';
  String get scanning => 'SKANUJĘ…';
  String get scanForSensors => 'SZUKAJ SENSORÓW';
  String get lookingForSensors => 'Szukam sensorów…';
  String get noSensorsFound =>
      'Nie znaleziono sensorów. Naciśnij SKANUJ z założonym i wybudzonym pasem.';
  String get connected => 'POŁĄCZONY';
  String get connecting => 'ŁĄCZENIE';
  String get notConnected => 'NIEPOŁĄCZONY';
  String get disconnect => 'ROZŁĄCZ';
  String get reconnect => 'POŁĄCZ PONOWNIE';
  String get forgetSensor => 'Zapomnij sensor';
  String lastUsed(String name) => 'Ostatnio używany: $name';
  String connectedTo(String name) => 'Połączono z $name';
  String get noBeat => 'BRAK TĘTNA';
  String get wornContactDetected => 'Założony · wykryto kontakt ze skórą';
  String get notWorn => 'Nie jest założony · brak kontaktu ze skórą';
  String get bluetoothDevice => 'Urządzenie Bluetooth';
  String get bluetoothOff =>
      'Bluetooth jest wyłączony. Włącz go w Centrum sterowania lub '
      'Ustawieniach i skanuj ponownie.';
  String get bluetoothDenied =>
      'Odmówiono dostępu do Bluetooth. Zezwól na niego w Ustawieniach, '
      'żeby używać pasa tętna.';
  String get bluetoothUnauthorized =>
      'Live Ride nie ma zgody na Bluetooth. Włącz ją w Ustawieniach.';
  String get sensorGone =>
      'Ten sensor nie jest już w zasięgu. Skanuj ponownie.';
  String get noHeartRateService =>
      'To urządzenie nie udostępnia usługi tętna. W WHOOP włącz najpierw '
      'Broadcast Heart Rate.';
  String get usingWhoop => 'Pas WHOOP';
  String get whoopIntro =>
      'WHOOP nie rozgłasza tętna, dopóki nie włączysz transmisji — dlatego '
      'potrafi tu nie być widoczny.';
  String get whoopStep1 => 'Otwórz aplikację WHOOP i zostaw ją otwartą.';
  String get whoopStep2 => 'Przejdź do Menu → Device Settings.';
  String get whoopStep3 => 'Włącz Broadcast Heart Rate.';
  String get whoopStep4 => 'Wróć tutaj — pas pojawi się poniżej jako WHOOP.';
  String get anyStrapWorks =>
      'Każdy pas Bluetooth działa bez konfiguracji: zwilż elektrody i pojawi '
      'się od razu.';
  String get heartRateServiceLabel => 'Usługa tętna';
  String get tapToConnectWhoop =>
      'Dotknij, aby połączyć · wymaga Broadcast Heart Rate';

  String get pairedSensors => 'Sparowane sensory';
  String get foundSensors => 'Znalezione';
  String get searchingSensors => 'Szukam sensorów…';
  String get sensorSources => 'Źródła danych';
  String get speedSource => 'Prędkość';
  String get cadenceSource => 'Kadencja';
  String get wheelCircumference => 'Obwód koła';
  String get wheelCircumferenceHint =>
      '2105 mm to typowe 700×25c. Zły obwód przekłamie dystans z czujnika.';
  String get sensorStale => 'brak sygnału';
  String get autoConnectOn => 'Łącz automatycznie';
  String get autoConnectOff => 'Nie łącz automatycznie';

  String get heartRateStrap => 'Pasek na klatę';
  String get noSensorsConnected => 'Żaden sensor nie jest połączony';
  String get cadence => 'Kadencja';
  String get power => 'Moc';
  String get connect => 'POŁĄCZ';

  // -------------------------------------------------------------- muzyka
  String get music => 'Muzyka';
  String get connectSpotify => 'Połącz Spotify';
  String get connectSpotifyButton => 'POŁĄCZ SPOTIFY';
  String get spotifyIntro =>
      'Live Ride steruje tym, co już gra w Spotify — na tym telefonie, '
      'na głośniku albo w samochodzie — więc możesz zmienić utwór bez '
      'wychodzenia z ekranu jazdy.';
  String get oneTimeSetup => 'Jednorazowa konfiguracja';
  String get spotifyClientIdIntro =>
      'Spotify wymaga, żeby każda aplikacja miała własny client ID. Live Ride '
      'celowo nie ma wbudowanego: żadnego współdzielonego klucza, żadnego '
      'limitu, na który nie masz wpływu, żadnego sekretu w aplikacji.';
  String get spotifyStep1 =>
      'Otwórz developer.spotify.com/dashboard i utwórz aplikację.';
  String get spotifyStep2 => 'Dodaj dokładnie ten redirect URI:';
  String get spotifyStep3 => 'Zaznacz Web API i zapisz.';
  String get spotifyStep4 => 'Skopiuj client ID i wklej poniżej.';
  String get spotifyClientIdHint => '32 znaki';
  String get spotifySignInIntro =>
      'Zaloguj się raz. Live Ride prosi tylko o to, co potrzebne, żeby '
      'pokazać utwór i obsłużyć przyciski.';
  String get spotifyClientId => 'Client ID Spotify';
  String get saveAndConnect => 'ZAPISZ I POŁĄCZ';
  String get useDifferentClientId => 'Użyj innego client ID';
  String get nothingPlaying => 'Nic nie gra';
  String get nothingPlayingHint =>
      'Uruchom utwór w Spotify raz — Live Ride przejmie sterowanie.';
  String get playOn => 'Odtwarzaj na';
  String get startSomething => 'Zacznij od czegoś';
  String get refresh => 'ODŚWIEŻ';
  String get load => 'WCZYTAJ';
  String get shuffleOn => 'LOSOWO WŁ.';
  String get shuffleOff => 'LOSOWO WYŁ.';
  String get noSpotifyDevices =>
      'Żadne urządzenie Spotify nie jest aktywne. Otwórz Spotify na telefonie, '
      'głośniku lub komputerze, a pojawi się tutaj.';
  String get playingHere => 'Gra tutaj';
  String get yourPlaylistsAppearHere =>
      'Tutaj pojawią się Twoje playlisty i ostatnio odtwarzane.';
  String get spotifyAccount => 'Konto Spotify';
  String get spotifyNotSignedIn => 'Niezalogowany';
  String get spotifyNeedsClientId => 'Wymaga client ID';
  String get whatLiveRideAsksFor => 'O co prosi Live Ride';
  String get permissionReadPlayback => 'Odczyt tego, co gra';
  String get permissionReadPlaybackWhy => 'żeby pokazać utwór na ekranie';
  String get permissionControlPlayback => 'Sterowanie odtwarzaniem';
  String get permissionControlPlaybackWhy => 'odtwarzanie, pauza, następny';
  String get permissionReadLibrary => 'Odczyt playlist i historii';
  String get permissionReadLibraryWhy => 'żeby było od czego zacząć';
  String get spotifyBrowserNote =>
      'Logowanie odbywa się w systemowym oknie przeglądarki, więc Live Ride '
      'nigdy nie widzi Twojego hasła.';
  String get spotifySignInCancelled =>
      'Logowanie do Spotify zostało anulowane.';
  String get spotifyPremiumRequired =>
      'Sterowanie odtwarzaniem z innej aplikacji wymaga Spotify Premium.';
  String get spotifyNotPremium =>
      'To konto Spotify nie jest Premium. Spotify pozwala innym aplikacjom '
      'sterować odtwarzaniem tylko na Premium, więc przyciski zgłoszą błąd.';
  String get spotifyNoActiveDevice =>
      'Spotify nie ma aktywnego urządzenia. Uruchom utwór w Spotify raz, '
      'a potem wróć — Live Ride przejmie sterowanie.';
  String get spotifySignedOut => 'Spotify Cię wylogowało. Połącz ponownie.';
  String get spotifyRateLimited =>
      'Spotify ogranicza liczbę zapytań; spróbuj za chwilę.';
  String get spotifyTimeout => 'Spotify nie odpowiedział na czas.';
  String get spotifyUnreachable => 'Brak połączenia ze Spotify.';
  String get spotifyRequestFailed => 'Zapytanie do Spotify nie powiodło się.';
  String get spotifyNeedsClientIdFirst =>
      'Najpierw dodaj swój client ID Spotify. Utwórz darmową aplikację na '
      'developer.spotify.com, dodaj redirect URI i wklej tu client ID.';
  String get spotifyAccessDenied => 'Odmówiono dostępu do Spotify.';
  String get spotifyStateMismatch =>
      'Odpowiedź Spotify nie pasowała do tego zapytania i została odrzucona.';
  String get spotifyNoCode => 'Spotify nie zwróciło kodu autoryzacji.';
  String get spotifyNoToken => 'Spotify nie zwróciło nowego tokenu.';
  String get spotifySignInAgain => 'Zaloguj się ponownie do Spotify.';
  String get connectSpotifyOnMusicTab =>
      'Najpierw połącz Spotify na karcie Muzyka.';
  String get previousTrack => 'Poprzedni utwór';
  String get nextTrack => 'Następny utwór';
  String get play => 'Odtwórz';

  String get identity => 'Kim jesteś';
  String get displayName => 'Nazwa widoczna dla innych';
  String get displayNameHint =>
      'To widzą obserwujący na mapie LIVE i to zapisuje się przy przejeździe.';
  String get location => 'Miejscowość';
  String get bio => 'O sobie';
  String get physiology => 'Dane do obliczeń';
  String get physiologyHint =>
      'Każde pole możesz zostawić puste. Puste znaczy „nie wiem", a nie zero '
      '— Live Ride po prostu nie pokaże tego, czego bez tej liczby nie da '
      'się policzyć.';
  String get weightKg => 'Waga (kg)';
  String get heightCm => 'Wzrost (cm)';
  String get birthYear => 'Rocznik';
  String get ftp => 'FTP (W)';
  String get maxHeartRateLabel => 'HR max';
  String get restingHeartRateLabel => 'HR spoczynkowe';
  String get zonesReady =>
      'Strefy są policzone — znajdziesz je w sekcji Trening.';
  String get zonesMissing =>
      'Podaj FTP albo HR max, żeby zobaczyć strefy treningowe.';
  String get trainingZones => 'Strefy treningowe';
  String get heartRateZonesTitle => 'Strefy tętna';
  String get powerZonesTitle => 'Strefy mocy';
  String get zonesFromKarvonen =>
      'Liczone metodą rezerwy tętna (Karvonena), bo podałeś tętno '
      'spoczynkowe.';
  String get zonesFromMaxHr => 'Liczone jako procent HR max.';
  String get zonesFromFtp => 'Liczone z FTP według podziału Coggana.';
  String get wattsPerKg => 'W/kg przy progu';

  // -------------------------------------------------------------- garaż
  String get garage => 'Garaż';
  String get addBike => 'Dodaj rower';
  String get bikeName => 'Nazwa roweru';
  String get bikeKind => 'Typ';
  String get bikeWeight => 'Waga (kg)';
  String get defaultBike => 'Rower domyślny';
  String get defaultShort => 'DOMYŚLNY';
  String get setOdometer => 'Ustaw przebieg';
  String get addComponent => 'Dodaj komponent';
  String get component => 'Komponent';
  String get serviceLimit => 'Przebieg serwisowy (km)';
  String get serviceLimitHint =>
      'Po tylu kilometrach Live Ride przypomni o wymianie. Zostaw puste, '
      'jeśli nie chcesz przypomnienia.';
  String get noServiceLimit => 'bez limitu serwisowego';
  String get replacedComponent => 'Wymieniony — zeruj przebieg';
  String get garageEmpty => 'Garaż jest pusty';
  String get garageEmptyMessage =>
      'Dodaj rower, a Live Ride będzie liczyć jego przebieg i przypominać '
      'o wymianie łańcucha, klocków czy opon.';
  String get serviceDue => 'Serwis';

  // -------------------------------------------------------------- profil
  String get profile => 'Profil';
  String get name => 'Imię lub nazwa';
  String get signedInToLiveRide => 'Zalogowany w Live Ride';
  String get displayNameExplainer =>
      'Nazwa wyświetlana to to, co widzą widzowie na mapie LIVE i co zapisuje '
      'się przy każdym przejeździe.';
  String ridingAs(String name) => 'Jedziesz jako $name';
  String get rideComputer => 'Komputer rowerowy';
  String get metricUnits => 'Jednostki metryczne';
  String get metricUnitsOn => 'km · m · km/h';
  String get metricUnitsOff => 'mi · ft · mph';
  String get devicesAndServices => 'Urządzenia i usługi';
  String get whoopAndHeartRate => 'WHOOP i tętno';
  String get noSensorConnected => 'Brak połączonego sensora';
  String get lockScreenLiveActivity => 'Live Activity na ekranie blokady';
  String get checking => 'Sprawdzam…';
  String get liveActivityReady =>
      'Gotowe — uruchamia się automatycznie razem z jazdą';
  String get liveActivityDisabled =>
      'Włącz Live Activities dla Live Ride w Ustawieniach iOS';
  String get iosOnly => 'Tylko iOS';
  String get connection => 'Połączenie';
  String get liveRideServer => 'Serwer Live Ride';
  String get weatherProvider => 'Dostawca pogody';
  String get weatherProviderSubtitle => 'Open-Meteo · bez konta';
  String get finishRideBeforeSignOut => 'Zakończ przejazd przed wylogowaniem.';

  // ----------------------------------------------------------------- GPX
  String get gpxNotAFile => 'To nie jest plik GPX.';
  String get gpxEmpty => 'Wybrany plik GPX jest pusty (0 bajtów).';
  String get gpxPickerFailed => 'Nie udało się otworzyć wyboru plików.';
  String get gpxUnreadable =>
      'Nie udało się odczytać pliku GPX z pamięci urządzenia.';
  String get gpxNoBytes =>
      'iOS nie udostępnił zawartości tego pliku. Jeśli leży w iCloud Drive, '
      'otwórz Pliki, pobierz go (ikona chmury ma zniknąć) i zaimportuj ponownie.';
  String get gpxNoText => 'Plik GPX nie zawiera czytelnego tekstu.';
  String get gpxInvalidXml =>
      'Plik GPX nie jest poprawnym XML-em i nie udało się go odczytać.';
  String gpxTooFewPoints(int valid, int skipped) =>
      'Ten plik GPX nie zawiera używalnej trasy: znaleziono tylko $valid '
      '${_punkty(valid)}${skipped > 0 ? ', a $skipped było nieczytelnych' : ''}.';
  String gpxMissing(String name) =>
      'Brakuje pliku GPX trasy „$name”. Zaimportuj ją ponownie.';
  String gpxImported(String name, String distance, int points) =>
      'Zaimportowano: $name · $distance km · $points ${_punkty(points)}';
  String gpxImportFailed(String error) => 'Import GPX nie powiódł się: $error';
  String exportFailed(String error) => 'Eksport nie powiódł się: $error';

  // ----------------------------------------------------------- serwer API
  String get serverTimeout =>
      'Serwer Live Ride nie odpowiedział na czas. Sprawdź połączenie.';
  String serverUnreachable(String origin) => 'Brak połączenia z $origin.';
  String serverError(int? status) => 'Błąd serwera $status.';
  String get serverRejected => 'Serwer odrzucił zapytanie.';
  String get serverNotFound => 'Nie znaleziono na serwerze.';
  String get requestCancelled => 'Zapytanie anulowane.';
  String get badCertificate =>
      'Nie udało się zweryfikować certyfikatu serwera.';
  String get mapStyleFailed => 'Nie udało się wczytać stylu mapy.';

  // -------------------------------------------------------- liczebniki
  String _punkty(int count) {
    if (count == 1) return 'punkt';
    final rest = count % 10;
    final teen = count % 100;
    if (rest >= 2 && rest <= 4 && (teen < 12 || teen > 14)) return 'punkty';
    return 'punktów';
  }

  String _pola(int count) {
    if (count == 1) return 'pole';
    final rest = count % 10;
    final teen = count % 100;
    if (rest >= 2 && rest <= 4 && (teen < 12 || teen > 14)) return 'pola';
    return 'pól';
  }

  /// Liczebnik dla słowa „przejazd”.
  String przejazdy(int count) {
    if (count == 1) return 'przejazd';
    final rest = count % 10;
    final teen = count % 100;
    if (rest >= 2 && rest <= 4 && (teen < 12 || teen > 14)) return 'przejazdy';
    return 'przejazdów';
  }

  /// Liczebnik dla słowa „minuta”.
  String minuty(int count) {
    if (count == 1) return 'minuta';
    final rest = count % 10;
    final teen = count % 100;
    if (rest >= 2 && rest <= 4 && (teen < 12 || teen > 14)) return 'minuty';
    return 'minut';
  }
}

/// Aktualnie wybrane teksty.
///
/// Serwisy i modele nie mają dostępu do [BuildContext], a i tak muszą
/// zwracać komunikaty dla użytkownika, więc język jest też dostępny globalnie.
Strings get S => _current;
Strings _current = const Strings();

/// Podmienia język aplikacji. Dziś używane tylko przez testy i przyszły
/// przełącznik języka.
void setStrings(Strings strings) => _current = strings;

/// Udostępnia teksty przez drzewo widgetów.
class StringsScope extends InheritedWidget {
  const StringsScope({super.key, required this.strings, required super.child});

  final Strings strings;

  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StringsScope>()?.strings ?? S;

  @override
  bool updateShouldNotify(StringsScope oldWidget) =>
      oldWidget.strings != strings;
}
