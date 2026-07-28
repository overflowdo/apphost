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
