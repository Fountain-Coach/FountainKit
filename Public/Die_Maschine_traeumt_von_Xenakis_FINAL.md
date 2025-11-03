# „Die Maschine träumt von Xenakis“

Ein PB‑VRT / FountainAI Projekt   
Uraufführung: Opernhaus der Form, 2026  
Version 1.4.2 (S‑Tag: Partiturstil + Git‑Quadrupel‑Legende + Erklärung)

---

## Überblick

> Partitur ist Software

Diese Oper ist eine Versuchsanordnung.  

Musik, Projektion und Systemlogik werden nicht verbunden, sondern gemeinsam komponiert.  Ziel ist eine wiederholbare Aufführung, deren Struktur nachvollziehbar bleibt.  

Das System verwendet PB‑VRT (Prompt‑Bound Visual Regression Testing).   Es macht Veränderungen sichtbar, prüfbar und hält jeden Zustand als Teil einer lernenden Form fest.  

Die Spezifikation folgt dem [PB‑VRT‑Essay im FountainKit‑Repository](https://github.com/Fountain-Coach/FountainKit/blob/main/Public/pb-vrt-spec-and-openapi/PB-VRT-Essay.md).  
Dort wird das Prinzip des Quiet Frame als Grundlage einer präzisen, visuellen Kontrollkette beschrieben.

---

## Architektur

| Schicht | Technologie | Aufgabe |
|----------|-------------|----------|
| Prompt Layer |  LLM‑Semantik | Dramaturgische Steuerung |
| FountainAI Agent Layer | Midi2  | Steuerung von Musik, Licht, Bewegung |
| MetalViewKit | GPU‑Projektionen | Bühnen‑ und Lichtarchitektur |
| PB‑VRT Framework | Visual Regression Testing | Baseline, Drift, Quiet Frame |
| Archiv Layer | FountainStore | Speicherung, Baselines, Varianten |

---

## Leitmotiv

> „Die Maschine träumt, indem sie Form rekombiniert.“

Fünf Akte bilden den Bogen.  

Jeder Akt beschreibt eine Verschiebung von Klang, Raum und Dichte.  
PB‑VRT vergleicht die Zustände und macht Abweichungen nachvollziehbar.  So entsteht eine Oper, die sich selbst beobachtet.

---

## Agenten

| Agent | Aufgabe |
|--------|----------|
| ComposerAgent | Kompositorische Struktur und Regelgenerierung |
| ConductorAgent | Zeit und Synchronität |
| GeometryAgent | Steuerung der MetalViewKit‑Topologien |
| SpectralAgent | Analyse von Frequenzen und Klangdichte |
| ArchivistAgent | Baselines, Drift‑Berichte, Revisionsspeicherung |

---

## Szenenübersicht

**Akt I – Genesis des Rauschens**  
Rauschen wird Struktur.  
Dichte wächst aus Zufall.  

**Akt II – Topologie des Schalls**  
Der Raum wird Klang.  
Bewegung ersetzt Richtung.  

**Akt III – Formalismus träumt**  
Automata erzeugen Melodie.  
Zeit wird Material.  

**Akt IV – Die Stimme der Architektur**  
Licht spricht.  
Die Bühne antwortet.  

**Akt V – Das Schweigen**  
Entropie fällt auf Null.  
Der Quiet Frame bleibt.  

---

## YAML‑Partitur

```yaml
partitur:
  titel: "Die Maschine träumt von Xenakis"
  version: "1.4.2"
  global:
    sync: "midi2_pbvrt_clock"
    meter: "frei"
    dynamik_basis: "p–ff"
  instrumentation:
    streicher: ["vl1", "vl2", "vla", "vc", "kb"]
    holz: ["fl", "ob", "cl", "fg"]
    blech: ["tpt", "tbn", "hn"]
    schlagwerk: ["perc1", "perc2"]
    elektronik: ["elektronik_a", "elektronik_b"]
    stimme: ["chor_aa", "chor_bb"]
  agents:
    - id: "ComposerAgent"
      rolle: "symbolische_transformation"
    - id: "ConductorAgent"
      rolle: "tempo_und_einsatz"
    - id: "GeometryAgent"
      rolle: "metalviewkit_topologie"
    - id: "SpectralAgent"
      rolle: "spektrale_analyse"
    - id: "ArchivistAgent"
      rolle: "pbvrt_snapshot_und_diff"
```

---

## Appendix A – Quiet‑Frame‑Versionierung

Jede Aufführung ist ein Frame.  
PB‑VRT ersetzt klassische Build‑Nummern durch Zustände: Baseline, Drift, Quiet Frame.  
Die Version ist nicht Zahl, sondern Rhythmus.

| Kategorie | Kürzel | Beschreibung |
|------------|--------|---------------|
| Baseline Frame | B‑Tag | Ausgangspunkt |
| Drift Frame | D‑Tag | Veränderung gegenüber Baseline |
| Quiet Frame | Q‑Tag | Stabiler Zustand |
| Archive ID | A‑Tag | Gespeicherte Version |
| Style Tag | S‑Tag | Stilistische Richtlinie dieser Version |

**Repository‑Mapping:**  
- Commit → Drift Frame  
- Tag → Baseline Frame  
- Release → Quiet Frame  
- Snapshot → Archive Frame  
- Style → S‑Tag  

Der S‑Tag dieser Version steht für einen **partiturähnlichen, nüchternen Stil**.  
Die Sprache vermeidet technische Rhetorik, bleibt klar, ruhig und musikalisch strukturiert.  

---

## Begriffslegende zum Git‑Quadrupel

| Begriff | Bedeutung | Funktion im Arbeitsfluss |
|----------|------------|--------------------------|
| **Commit** | Ein Zustands­eintrag im Verlauf der Arbeit. Jeder Commit speichert den exakten Stand des Projekts zu einem Zeitpunkt – alle Dateien, Änderungen und Metadaten. | Dient der feingliedrigen Nachvollziehbarkeit von Entwicklungs­schritten. Jeder Commit ist ein einzelner Takt im zeitlichen Verlauf der Arbeit. |
| **Tag** | Eine Markierung auf einem bestimmten Commit. Sie benennt diesen Zustand und macht ihn auffindbar. | Wird genutzt, um Baselines oder bestimmte Entwicklungsphasen eindeutig zu kennzeichnen. |
| **Release** | Eine gefasste Version des Projekts, die als stabil gilt. Ein Release vereint mehrere Commits und Tags zu einem überprüften Ganzen. | Im PB‑VRT‑Kontext entspricht ein Release dem Quiet Frame – einem reproduzierbaren, ruhigen Zustand der Form. |
| **Snapshot** | Eine Momentaufnahme des gesamten Repositoriums. Sie enthält alle Inhalte und Metadaten in einem eingefrorenen Zustand. | Dient der Archivierung. Ein Snapshot bewahrt eine Version dauerhaft und unabhängig von späteren Änderungen auf. |

**Symbolische Zuordnung im PB‑VRT‑System:**  
- Commit → Drift Frame  
- Tag → Baseline Frame  
- Release → Quiet Frame  
- Snapshot → Archive Frame  

---

## Zusatz: Erklärung des Quadrupels

Ein **Quadrupel** (vom lateinischen *quadruplex* = vierfach) bezeichnet eine **Viererstruktur** – ein System aus vier Elementen, die gemeinsam eine Einheit bilden.  
In der Informatik und Mathematik ist es eine geordnete Vierergruppe `(a, b, c, d)` – jedes Element besitzt seine definierte Rolle.

Im PB‑VRT‑System beschreibt das **Git‑Quadrupel** den vollständigen Lebenszyklus eines Projekts:  

| Element | Funktion | Bedeutung |
|----------|-----------|-----------|
| **Commit** | Einzelner Arbeitsschritt | Bewegung oder Drift |
| **Tag** | Markierter Zustand | Baseline oder Bezugspunkt |
| **Release** | Stabile Version | Quiet Frame |
| **Snapshot** | Eingefrorene Gesamtkopie | Archiv oder Ruhepunkt |

Diese vier Zustände bilden ein geschlossenes System – eine zyklische Form.  
> Im musikalischen Sinn: Das Git‑Quadrupel ist der **Taktzyklus des Repositoriums** – Bewegung, Bezug, Ruhe, Erinnerung.

---

## Lizenz

Creative Commons Attribution‑ShareAlike 4.0 International (CC BY‑SA 4.0)  
© 2025 FountainAI / Benedikt Eickhoff
