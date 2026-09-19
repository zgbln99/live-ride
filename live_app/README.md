# Live Ride — aplikacja mobilna

Live Ride to własny, samodzielnie hostowany komputer rowerowy i platforma
tras. Ten katalog zawiera klienta w Flutterze: licznik, nawigację, rejestrator
przejazdów i nadajnik LIVE. Dzieli serwer z projektem webowym w `../web`, ale
nie dzieli z nim ani jednego widoku.

Serwer: `https://ride.76-13-3-214.sslip.io`
(zmiana: `--dart-define=LIVE_RIDE_SERVER=…`).

Cała aplikacja i publiczny podgląd LIVE mówią po polsku.

---

## Co potrafi

### Jazda

**Komputer rowerowy** — jeden ekran obsługuje wolną jazdę i nawigację, więc
przyrząd nie zmienia się między nimi. Stron może być dowolnie wiele i
przesuwa się je palcem w bok; każda ma własny układ (1, 2, 3, 4, 6 albo 8
pól) i własny zestaw z ponad czterdziestu pól: prędkość, dystans, czas,
wysokość, nachylenie, VAM, tętno i jego strefy, moc chwilowa i uśredniana
(3 s, 10 s, 30 s), moc normalizowana, IF, TSS, W/kg, balans, praca w kJ,
kadencja, dystans do mety, ETA, pogoda. Przytrzymanie pola zmienia je w
miejscu. Gotowe zestawy stron: podstawowy, treningowy, nawigacyjny, górski,
wyścigowy.

**Tryb cichy** — pięć sekund po ostatnim dotknięciu komputer przestaje być
aplikacją. Drugorzędne przyciski gasną, pasek sterowania zwija się i oddaje
miejsce mapie, a zostaje przyrząd: mapa, trasa, zawodnik, następny zakręt,
dystans do mety, ETA i wszystkie pola danych. Jedno dotknięcie przywraca
sterowanie. Chowanie trwa 420 ms, powrót 150 ms. Ukryte sterowanie przestaje
przyjmować dotknięcia w chwili, gdy zaczyna gasnąć, więc dotknięcie nigdy nie
trafi w półprzezroczysty przycisk ZAKOŃCZ.

**Tryb wyścigu i blokada ekranu** — tryb wyścigu chowa sterowanie i podbija
jasność, żeby dało się odczytać liczby w pełnym słońcu. Dotknięcie go nie
przerywa, ale świadome przytrzymanie zawsze przywraca sterowanie. Blokada
ekranu połyka dotknięcia i odblokowuje się przytrzymaniem — pomaga w deszczu,
gdy krople naciskają przyciski same.

**Automatyczna pauza** — licznik zatrzymuje się na postoju i rusza, gdy
zawodnik ruszy. Próg i opóźnienie są w ustawieniach, bo „stoję" znaczy co
innego na światłach i na podjeździe. Ręczna pauza nigdy nie wznawia się sama.

**ClimbPro** — na wykrytym podjeździe pojawia się panel: ile zostało do
szczytu, ile w pionie, jak stromo jest teraz, z pozycją na profilu. Na
szczycie zostaje wynik z czasem i VAM.

**Segmenty** — wytnij podjazd z trasy, a Live Ride zacznie mierzyć na nim
czas. Wjazd wymaga właściwego kierunku jazdy, zjazd z linii przerywa próbę,
a przejazd do końca podbija rekord. W trakcie widać deltę wobec rekordu.

**Wirtualny rywal** — stała prędkość, czas na trasie albo ghost z
wcześniejszego przejazdu, jadący dokładnie tak jak Ty wtedy. Różnica pokazana
w sekundach, nie w metrach.

**Treningi** — kroki z limitem czasu albo dystansu i celem mocy, tętna,
kadencji lub prędkości. Pasek pokazuje, co teraz, ile zostało i czy jesteś w
celu; o wyjściu z celu aplikacja mówi dopiero po kilku sekundach, bo jedna
próbka to wyjście zza zakrętu.

**Powiadomienia** — picie, jedzenie, odstępy czasowe i dystansowe, progi
tętna, mocy i kadencji, zjazd z trasy, podjazd przed tobą, słaba bateria
sensora, deszcz, zmrok. Wibracja, pasek na ekranie i opcjonalnie czytanie na
głos po polsku.

**Bezpieczeństwo** — wykrywanie upadku szuka trzech rzeczy naraz: uderzenia,
nagłego spadku prędkości i bezruchu po nim. Alarm przechodzi przez odliczanie
z wielkim przyciskiem „nic mi nie jest", a wiadomość otwiera się w aplikacji
SMS z pozycją i linkiem LIVE. Ręczne SOS idzie tą samą drogą.

### Trasy

**Kreator tras** — rysowanie po mapie z przyciąganiem do dróg, waypointy z
przeciąganiem i zmianą kolejności, cofanie i ponawianie, pętla, „tam i z
powrotem", odwracanie kierunku, profil roweru i charakter trasy (szybko,
widokowo, unikaj ruchu), preferencje nawierzchni, wysokości z serwera.

**Briefing trasy** — po otwarciu trasy Live Ride mówi, co Cię czeka: dystans,
przewyższenie, szacowany czas, największy podjazd z kategorią, strome
fragmenty, wiatr czołowy względem kierunku jazdy, pierwszy deszcz, zachód
słońca, szacowany wydatek energii i sugerowane postoje. Każde zdanie ma
pokrycie w danych — bez wysokości nie ma zdań o podjazdach, bez wagi w
profilu nie ma szacunku kalorii.

**Import GPX** — z Plików, iCloud Drive albo dowolnej chmury, z obsługą
plików w UTF‑16 i z preambułą, którą dokleja część eksporterów.

**Mapy offline** — pobranie pasa 1,5 km wokół trasy w powiększeniach
przydatnych w jeździe, z postępem i możliwością usunięcia.

### Po jeździe

**Historia i statystyki** — tydzień, miesiąc, rok i całość z sumami,
wykresem dystansu i porównaniem z poprzednim okresem. Rekordy: najdłuższy
przejazd, najdłużej w siodle, najwięcej w pionie, najwyższa średnia i
prędkość, najlepsza moc normalizowana. Kalendarz z intensywnością dnia i
mapa cieplna wszystkich śladów.

**Eksport i integracje** — GPX i TCX do udostępnienia, wysyłka do Stravy
przez jej API (z czekaniem na przetworzenie pliku, zanim powiemy „wysłano"),
zapis do Apple Health / Health Connect. Komoot i Garmin nie mają publicznego
API dla aplikacji spoza swoich programów partnerskich — zamiast martwego
przycisku „Połącz" jest wyjaśnienie i eksport pliku, który oba zaimportują.

### LIVE i grupa

**Śledzenie na żywo** — jedna sesja, jeden link, zero kont po stronie
oglądających. Zawodnik decyduje, co widzą: pozycję, prędkość, tętno i moc
przełącza się osobno, a pola nieudostępnione w ogóle nie opuszczają telefonu.

**Jazda grupowa** — dołączenie kodem, wszyscy na jednej mapie, punkt zbiórki
i szybkie wiadomości do jednego dotknięcia.

**Live Activity** — na ekranie blokady i w Dynamic Island: prędkość, dystans,
czas, tętno, a przy nawigacji następny zakręt. Napędzana przez rejestrator, a
nie przez widok, więc żyje tak długo jak przejazd.

### Sprzęt

**Sensory BLE** — tętno (w tym WHOOP), kadencja, prędkość z koła, moc i
trenażery FTMS, z baterią, siłą sygnału i automatycznym łączeniem. Bez
sensora pola pokazują „--", nigdy zera.

**Garaż** — rowery z licznikiem przebiegu, który rośnie razem z przejazdami,
i komponenty z limitem kilometrów albo dni: łańcuch, kaseta, klocki, opony,
uszczelniacz.

**Spotify** — sterowanie tym, co już gra, bez wychodzenia z ekranu jazdy.

---

## Pierwsze uruchomienie na Macu

```bash
cd live_app
chmod +x bootstrap.sh
./bootstrap.sh
```

Bootstrap generuje świeże powłoki iOS i Androida, przywraca źródła Live Ride i
konfiguruje: nazwę, bundle id (`pl.marekpiatak.liveride`), uprawnienia
lokalizacji (także w tle), Bluetooth, ruch (wykrywanie upadku), HealthKit,
usługę pierwszoplanową i wake lock na Androidzie, schemat `liveride://` dla
Spotify i Stravy, zapytania o aplikacje SMS i telefonu (SOS) oraz rozszerzenie
widgetu Live Activity.

Potem w Xcode: **Runner → Signing & Capabilities → Automatically manage
signing → Twój zespół**, to samo dla celu **LiveRideWidgets**, i:

```bash
flutter pub get
flutter analyze
flutter test
flutter run --release
```

### Live Activity i „Cycle inside Runner"

Rozszerzenie widgetu dodaje skrypt `ios_native/scripts/add_live_activity_target.rb`,
który uruchamia bootstrap. Skrypt ustawia też kolejność faz budowania: faza
kopiująca `.appex` musi wykonać się **przed** flutterowym „Thin Binary", który
czyta gotowy pakiet. Bez tego Xcode 15+ odmawia budowania z błędem
„Cycle inside Runner". Gdyby `pod install` albo aktualizacja Xcode kiedykolwiek
przestawiły fazy z powrotem:

```bash
ruby ios_native/scripts/add_live_activity_target.rb ios --order-only
```

Tryb `--order-only` nie rusza targetu — tylko przywraca kolejność.

Bootstrap bez widgetu: `./bootstrap.sh --no-live-activity`.

---

## Konfiguracja przy budowaniu

| Define | Domyślnie | Do czego |
| --- | --- | --- |
| `LIVE_RIDE_SERVER` | `https://ride.76-13-3-214.sslip.io` | adres serwera Live Ride |
| `LIVE_RIDE_WEATHER_URL` | `https://api.open-meteo.com/v1/forecast` | pogoda |
| `LIVE_RIDE_WEATHER_KEY` | *(puste)* | tylko dla dostawców wymagających klucza |
| `LIVE_RIDE_SPOTIFY_CLIENT_ID` | *(puste)* | opcjonalnie; da się też wkleić w aplikacji |

**Żaden sekret nie jest wkompilowany.** Domyślny dostawca pogody nie wymaga
klucza. Poświadczenia Spotify i Stravy podaje sam zawodnik i leżą wyłącznie na
jego urządzeniu.

---

## Integracje wymagające własnych poświadczeń

### Spotify

1. [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) → utwórz aplikację.
2. Redirect URI **dokładnie**: `liveride://spotify-callback`
3. Zaznacz **Web API** i zapisz.
4. Wklej client ID w zakładce Muzyka.

Sterowanie odtwarzaniem wymaga Spotify **Premium** — to reguła Spotify dla
każdej aplikacji zewnętrznej, nie ograniczenie Live Ride.

### Strava

1. [strava.com/settings/api](https://www.strava.com/settings/api) → utwórz aplikację.
2. Authorization Callback Domain: `liveride`
3. Skopiuj **Client ID** i **Client Secret** do ekranu Eksport i synchronizacja.

Strava nie wspiera PKCE, więc wymiana kodu na token potrzebuje sekretu
aplikacji. W aplikacji rozdawanej wszystkim byłby to błąd; tutaj sekret należy
do Ciebie i nie opuszcza telefonu.

### Apple Health / Health Connect

Zapis jest jednostronny, tylko na żądanie i domyślnie wyłączony. Na Androidzie
potrzebny jest zainstalowany Health Connect.

---

## Co sprawdzić na prawdziwym iPhonie

| # | Gdzie | Co powinno się zdarzyć |
| --- | --- | --- |
| 1 | Start | Ekran logowania po polsku. Konto albo logowanie; nazwa użytkownika staje się nazwą zawodnika. |
| 2 | Każda zakładka | Jeden system wizualny: białe panele, włosowe linie, czarny druk, jeden cyjanowy akcent. |
| 3 | LIVE → karta tętna | Ekran WHOOP. Z włączonym Broadcast Heart Rate opaska pojawia się z odznaką WHOOP; po połączeniu widać BPM, wykres, baterię i sygnał. |
| 4 | Profil → Sensory | Skan wykrywa czujniki kadencji, prędkości, mocy i trenażery; wartości na żywo u góry. |
| 5 | Muzyka | Karta konfiguracji Spotify, logowanie w arkuszu przeglądarki systemowej, potem sterowanie odtwarzaniem. |
| 6 | ROZPOCZNIJ JAZDĘ | Komputer rowerowy. Po pięciu sekundach bez dotknięcia sterowanie znika; jedno dotknięcie je przywraca. Przesuwanie w bok zmienia stronę pól. |
| 7 | Zablokuj telefon w trakcie jazdy | Live Activity: prędkość, dystans, czas, tętno — a przy nawigacji następny zakręt. Przytrzymanie Dynamic Island rozwija widok. |
| 8 | Ustawienia jazdy → Tryb wyścigu | Sterowanie znika, jasność rośnie; przytrzymanie ekranu je przywraca. |
| 9 | Ustawienia jazdy → SOS | Pełnoekranowe odliczanie z przyciskiem „nic mi nie jest"; wysyłka otwiera aplikację SMS z gotową treścią. |

Jeśli karta na ekranie blokady się nie pojawia: Ustawienia → Live Ride →
Aktywności na żywo. Zakładka Profil mówi, czy iOS ma je włączone.

---

## Testy

```bash
flutter test          # 501 testów aplikacji
cd ../db && go test ./routes/...
cd ../web && npx svelte-check
```

Testy obejmują między innymi: dekodery BLE (HR, CSC, moc, FTMS) na prawdziwych
ramkach bajtów, wykrywanie podjazdów i fałszywego przewyższenia z szumu
wysokościomierza, briefing trasy, wiatr względem kierunku jazdy, wykrywanie
upadku na sekwencjach (dziura, światła, upuszczony telefon, prawdziwy upadek),
segmenty, wirtualnego rywala, treningi, zapytania statystyczne w SQLite,
kontrakt Dart↔Swift dla Live Activity oraz kolejność faz budowania w Xcode.

---

## Znane ograniczenia

- Źródła Swift zostały napisane i objęte testami kontraktowymi, ale **nie
  skompilowane** w środowisku, w którym powstały — nie ma w nim SDK iOS.
  Kompilują się na Macu, a rozjazd między stroną Dart i Swift wyłapuje
  `test/live_activity_contract_test.dart`. Pierwszy prawdziwy build jest Twój.
- Live Activity wymaga iOS 16.2+. Poniżej zakładka Profil mówi to wprost, a
  jazda działa bez zmian.
- Sterowanie Spotify wymaga Premium i jednego aktywnego urządzenia Spotify —
  obie rzeczy to reguły Spotify.
- Komoot i Garmin Connect nie udostępniają publicznego API aplikacjom spoza
  swoich programów partnerskich. Live Ride nie udaje, że się z nimi łączy;
  daje eksport pliku, który oba zaimportują.
- Automatyczna wysyłka SMS bez udziału użytkownika nie jest możliwa na iOS.
  Alarm otwiera aplikację SMS z gotową treścią — ekran mówi to wprost.
- Nagrywanie w tle zależy od zgody na lokalizację „zawsze". Bez niej system
  wstrzymuje aktualizacje przy zablokowanym ekranie.
- Mapy offline działają na iOS i Androidzie; na innych platformach ekran mówi,
  że ich nie ma, zamiast pokazywać przycisk bez działania.
- Instrukcje zakręt po zakręcie wymagają endpointu Valhalli na serwerze. Bez
  niego zaimportowany ślad jest nawigowany bez zapowiedzi zakrętów.
- Aplikacja jest mobilna; `flutter build web` wymaga wcześniejszego
  `flutter create . --platforms=web` i służy tylko do sprawdzenia kompilacji.
