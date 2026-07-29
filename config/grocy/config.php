<?php
// Grocy-Feature-Flags: nur die gewünschten Module aktiv lassen.
//
// AKTIV (Defaults aus config-dist.php): Bestand (FEATURE_FLAG_STOCK) inkl.
// Standort-Tracking Kühlschrank/Regal/Keller (FEATURE_FLAG_STOCK_LOCATION_TRACKING),
// Verbrauchen/Kaufen, Einkaufsliste (FEATURE_FLAG_SHOPPINGLIST) und der
// Barcode-Scanner (FEATURE_FLAG_DISABLE_BROWSER_BARCODE_CAMERA_SCANNING bleibt false).
//
// AUS -> die unten auf false gesetzten Module verschwinden inkl. Navigation.
//
// Grocy lädt ZUERST diese Datei und danach config-dist.php für alle nicht hier
// gesetzten Werte (siehe app.php) -> hier reichen die Overrides. Gemountet nach
// /config/data/config.php via compose/tools/grocy.yml (read-only).
//
// Produkte gruppieren (z.B. verschiedene Tomatensoßen) geht OHNE Flag:
//   - Produktgruppen (Stammdaten) = Kategorie/Sortierung
//   - Eltern-/Kind-Produkte       = "egal welche Sorte zählt als ein Bestand"
//                                    mit kumuliertem Mindestbestand

Setting('FEATURE_FLAG_RECIPES', false);     // Rezepte + Speiseplan
Setting('FEATURE_FLAG_CHORES', false);      // Hausarbeiten
Setting('FEATURE_FLAG_TASKS', false);       // Aufgaben
Setting('FEATURE_FLAG_BATTERIES', false);   // Batterien
Setting('FEATURE_FLAG_EQUIPMENT', false);   // Geräte
Setting('FEATURE_FLAG_CALENDAR', false);    // Kalender

// --- Single-Sign-on über Authelia (kein zweiter Grocy-Login) ---------------
// Grocy vertraut dem von Authelia via Traefik weitergereichten Remote-User-
// Header (forward-auth -> authResponseHeaders in
// config/traefik/dynamic/middlewares.yml). Der Authelia-Login (dein custom
// Passwort) ist damit die einzige Anmeldung; admin/admin entfällt.
//
// SICHERHEIT: Der Header darf NIE vom Client kommen -> die authelia-chain
// strippt client-gesetzte Remote-User-Header vor forward-auth (middlewares.yml).
//
// Header EXAKT wie Traefik ihn sendet ("Remote-User"); Grocy liest ihn per
// PSR-7 getHeader() (Bindestrich, NICHT der Default "REMOTE_USER").
// Der übermittelte Nutzername (Authelia-Login, i.d.R. "admin") muss einem
// Grocy-Nutzer entsprechen – der Default-Nutzer "admin" existiert bereits.
Setting('AUTH_CLASS', 'Grocy\\Middleware\\ReverseProxyAuthMiddleware');
Setting('REVERSE_PROXY_AUTH_HEADER', 'Remote-User');
