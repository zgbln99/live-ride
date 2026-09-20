/**
 * Wybór motywu przez widza.
 *
 * Domyślnie strona idzie za systemem i to jest właściwa odpowiedź dla prawie
 * każdego. Przełącznik istnieje dla jednego przypadku, którego system nie
 * obsłuży: ktoś ogląda jazdę wieczorem na telefonie ustawionym na jasny
 * motyw, bo tak mu wygodnie w dzień.
 *
 * Wybór trzymamy w `localStorage`, ale strona musi działać bez niego —
 * w trybie prywatnym i przy zablokowanych danych witryny odczyt potrafi
 * rzucić wyjątkiem, a to nie jest powód, żeby nie pokazać jazdy.
 */

export type ThemeChoice = "system" | "light" | "dark";

const STORAGE_KEY = "lr-theme";

export function readTheme(): ThemeChoice {
    try {
        const stored = localStorage.getItem(STORAGE_KEY);
        if (stored === "light" || stored === "dark" || stored === "system") return stored;
    } catch {
        // Brak dostępu do pamięci znaczy tylko tyle, że idziemy za systemem.
    }
    return "system";
}

export function applyTheme(choice: ThemeChoice): void {
    const root = document.documentElement;
    if (choice === "system") {
        root.removeAttribute("data-lr-theme");
    } else {
        root.setAttribute("data-lr-theme", choice);
    }
    try {
        localStorage.setItem(STORAGE_KEY, choice);
    } catch {
        // Niezapamiętany wybór działa do końca wizyty. Wystarczy.
    }
}

/** Kolejny stan przełącznika: system → ciemny → jasny → system. */
export function nextTheme(choice: ThemeChoice): ThemeChoice {
    return choice === "system" ? "dark" : choice === "dark" ? "light" : "system";
}

export function themeLabel(choice: ThemeChoice): string {
    return choice === "system" ? "AUTO" : choice === "dark" ? "NOC" : "DZIEŃ";
}
