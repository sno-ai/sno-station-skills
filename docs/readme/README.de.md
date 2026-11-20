# Sno: Kluge Agenten. Routine wie alte Hasen. Jeden Tag ein Stück besser.

**Read in other languages:** [English](../../README.md) · [中文](README.zh-CN.md) · **Deutsch** · [Español](README.es.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [繁體中文](README.zh-TW.md)

![Sno Station – Agenten, antreten! Zwei Köpfe sind besser als einer, und morgens schlauer als am Abend.](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/hero-banner.png)

**Deine KI-Agenten sind wie hochbegabte Neue ohne Kollegen: viel drauf, aber niemand, der ihnen zeigt, wie der Laden läuft. Diese Skills geben ihnen die Routine eines Teams, das schon so manches Release rausgebracht hat.** Einer baut, ein anderer prüft. Wird einem das Kontingent knapp, schreibt er eine Übergabe, und der Nächste macht am exakten Commit weiter. „Fertig“ gibt es nur mit Beleg aus einem echten Lauf. Und nachts gehen sie den Tag noch einmal durch und schlagen dir neue Regeln vor. Ob die gelten, entscheidest du.

Läuft mit **Claude Code, Codex, Cursor und Hermes Agent**, und auch mit OpenClaw. Wo der Agent einen Skill ausführen kann, wird er komplett installiert; wo nicht, in einer abgespeckten Form.

Jeder Skill ist schlichter Text: lesen, kopieren, umbauen, alles erlaubt. Es sind genau die Skills, die [Sno Station](https://github.com/sno-ai/sno-station) in deine vorhandenen Agenten installiert, und die wir selbst jeden Tag benutzen, um Sno Station zu bauen.

[![GitHub-Sterne](https://img.shields.io/github/stars/sno-ai/sno-station-skills?label=stars&color=eab308&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/stargazers)
[![Neuestes Release](https://img.shields.io/github/v/release/sno-ai/sno-station-skills?label=release&color=2dd4bf&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/releases/latest)
[![Lizenz Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-97ca00.svg?labelColor=3b3b3b)](../../LICENSE)
![vor jedem Release selbst getestet](https://img.shields.io/badge/every%20release-self--tested-3b82f6.svg?labelColor=3b3b3b)
![Agenten: Claude Code, Codex, Cursor, Hermes, OpenClaw](https://img.shields.io/badge/agents-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20Cursor%20%C2%B7%20Hermes%20%C2%B7%20OpenClaw-f0a04b.svg?labelColor=3b3b3b)

Für alle Skills sag deinem Agenten einfach:

```text
install sno.ai from GitHub
```

Dein Agent installiert Sno Station und richtet jeden Skill samt der Programme, die sie aufrufen, für alle unterstützten Agenten auf deinem Rechner ein. Dann probier gleich einen aus:

```text
peer-review this
```

Ein anderer Agent liest deine Änderung in einer frischen Sitzung, die vom bisherigen Gespräch nichts mitbekommen hat, und sagt dir, was im echten Einsatz kaputtgehen würde. [Nur einen Skill oder lieber ein Plugin?](#installation)

**Neu hier?** Diese Skills sind nur die eine Hälfte. Die andere ist [Sno Station](https://github.com/sno-ai/sno-station), die Workstation, auf der sie laufen: Agenten, die [sich gegenseitig Nachrichten schicken](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md), [Arbeit, die zu einer festen Uhrzeit startet](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md), und ein Gedächtnis, das sie alle teilen.

[Was sich für dich ändert](#was-sich-für-dich-ändert) · [Warum diese Skills](#warum-diese-skills) · [Der Frust und was dagegen hilft](#der-frust-und-was-dagegen-hilft) · [Geschichten von unserem eigenen Rechner](#ich-lag-im-bett-die-agenten-machten-schichtwechsel) · [Installation](#installation) · [Die Skills](#die-skills) · [Vertrauen ist gut, Kontrolle ist besser](#vertrauen-ist-gut-kontrolle-ist-besser) · [Die Skills und Sno Station](#die-skills-und-sno-station) · [Für Skill-Autoren](#für-skill-autoren) · [Lizenz](#lizenz)

## Was sich für dich ändert

Du arbeitest weiter wie bisher, mit dem Agenten deiner Wahl. Und dann:

1. **Änderung fertig, jetzt soll jemand drüberschauen.** Sag „peer-review this“. Ein Reviewer
   vom jeweils anderen Anbieter liest sie kalt, ohne Vorgeschichte, und sagt dir, was im echten
   Einsatz brechen würde. Der Autor behebt die Ursache, Runde für Runde, bis das Review sauber
   zurückkommt.
2. **Langer Lauf, und du gehst ins Bett.** Sag „arm rotate-agent“. Fällt das Kontingent des
   arbeitenden Agenten über Nacht auf den Schwellenwert, geht die Aufgabe an einen frischen
   Agenten vom anderen Anbieter. Das Briefing wird geprüft, bevor auch nur eine Datei angefasst
   wird.
3. **Es soll zu einer bestimmten Uhrzeit passieren.** Dann sag die Uhrzeit einfach dazu: „prüf
   morgen um 9 den Build“ oder „schreib jeden Morgen um 7 den Bericht“. Pünktlich startet ein
   Agent und erledigt es, ob das Gespräch noch offen ist oder längst zu. `sno heartbeat --due` zeigt,
   was geplant ist. Dieser Teil von Sno Station heißt Finish; die Details stehen im
   [Leitfaden](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md).
4. **Du kommst zurück.** Sag „away brief“. Eine Seite, höchstens 60 Zeilen: was erledigt ist, was
   hängt und warum, was auf deine Antwort wartet und was das Ganze an Kontingent gekostet hat.
5. **Ein Job für jemand anderen.** Sag „write a charter“. Du bekommst eine Datei, die
   festhält, was geliefert werden soll, was tabu ist, was du schon entschieden hast und wie jede
   Erfolgsprüfung belegt wird. Jeder Agent kann sie dann mit `deliver` abarbeiten, und jede
   Prüfung wird durch einen aufgezeichneten echten Lauf belegt.
6. **Jede Nacht schaut das Team zurück.** Die nächtliche Runde liest die Sitzungen des Tages aus
   all deinen Agenten, findet die Fehler, die sich wiederholen, und schlägt Lektionen und
   Skill-Änderungen vor. Morgens nimmst du die an, die dir gefallen, mit
   `sno rem-reflect accept <id>`. Ohne dieses Accept ändert sich nichts.

## Warum diese Skills

Ein einzelner KI-Agent ist der hochbegabte Neue ohne Kollegen. Seine Arbeit prüft er selbst, also
rutscht ihm genau das durch, was er nicht sieht. Um 3 Uhr nachts ist das Kontingent alle, und er
bleibt mitten in deinem Build einfach stehen. Die Tests sind grün, er meldet „fertig“, und
passiert ist: nichts. Um drei Schichten Maschinerie hast du ihn nie gebeten, gebaut hat er sie
trotzdem. Und morgen? Derselbe Fehler wie heute. Hat ihm ja keiner gesagt.

**Sno Station Skills repariert das Team, nicht das Modell.** [Sno Station](https://github.com/sno-ai/sno-station)
installiert diese Skills in die Agenten, die du schon hast, und bringt ihnen bei, was jedes gute
Engineering-Team draufhat. Ein zweites Paar Augen von einem anderen Anbieter. Eine saubere
Übergabe, wenn jemand gehen muss. Eine Leitung, die Arbeit mit einer schriftlichen Definition of
Done verteilt. Eine Seite Zusammenfassung, wenn du zurückkommst. Und jede Nacht eine Retro, aus
der die Fehler dieser Woche als Regeln für die nächste herauskommen.

**Zwei Agenten, zwei Rollen.** Der eine erledigt deine Aufgabe, der andere hält das Ergebnis gegen
deine Anforderungen. Wer welche Rolle spielt, ist offen: Claude Code, Codex, Cursor und Hermes
Agent können beides. Sind beide installiert, läuft das Review beim jeweils anderen, in einer
frischen Sitzung, die vom Gespräch des Autors nichts weiß. Befunde und Korrekturen machen die
zwei unter sich aus.

**Arbeit, die fertig wird, während du schläfst.** Vor dem Schlafengehen scharf schalten, das war's.
Geht das Abo des arbeitenden Agenten zur Neige, schreibt er ein Übergabe-Briefing, solange er
noch kann, weckt einen Agenten vom anderen Anbieter und drückt ihm die Aufgabe samt exaktem
Commit zum Weitermachen in die Hand. Deinem Build ist es egal, welcher Anbieter ihn zu Ende
gebracht hat.

**„Fertig“ heißt belegt.** Jede Aufgabe kann eine schriftliche Liste von Erfolgsprüfungen
mitführen, und jede davon wird durch einen echten Lauf mit bestanden oder nicht bestanden
beantwortet. Nur weil ein Agent „fertig“ sagt, ist noch gar nichts fertig.

**Getestet, bevor es rausgeht.** Jeder Skill in einem Release hat seine eigenen Selbsttests auf
einer sauberen Kopie bestanden, wurde nach persönlichen Pfaden und Überbleibseln durchsucht und
trägt einen Stempel, der genau das bestätigt. Ein Skill, der durchfällt, wird nicht veröffentlicht.

![So funktioniert's: zwei Agenten, ein gemeinsamer Arbeitsbereich, drei Dinge, die du bekommst](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/squad-how-it-works.png)

**Lass gleich einen Stern da. Spätestens wenn dir nachts um 2 der nächste Agent hängen bleibt, bist du froh, dass du das hier wiederfindest.**

## Der Frust und was dagegen hilft

*Stand: 2026-10-23.* Jede Zeile in der linken Spalte ist eine echte Beschwerde aus r/ClaudeCode, r/codex oder r/ClaudeAI aus der Woche vom 20. Oktober 2026. Rechts steht, was auf unseren eigenen Rechnern läuft, kostenlos und Open Source, damit das aufhört.

| Was diese Woche gesagt wurde | Was hilft | Wo |
|---|---|---|
| „Mein 5-Stunden-Limit war nach 30 Minuten weg.“ | Schick nicht mehr das größte Modell für alles los. Opus plant und prüft; Codex schreibt den Code, aufgerufen als Agent aus derselben Sitzung. Ist ein Abo leer, übernimmt das andere die Aufgabe aus demselben Gedächtnis. | `codex-coder`, `sno reach call` |
| „10 Stunden Nachtarbeit verloren, wegen ‚this model is at capacity‘.“ | Bei 2 % seines Kontingents schreibt der arbeitende Agent ein Übergabe-Briefing und weckt den Agenten des anderen Anbieters, der am exakten Commit weitermacht. Du hast derweil geschlafen. | `rotate-agent` |
| „1.100 Dateien, 30.000 Zeilen. Für deren PRs hab ich gar nicht das Token-Budget.“ | Wer pusht, prüft zuerst: Der Autor lässt ein Review vom anderen Anbieter laufen, in einer frischen Sitzung, die das Gespräch nie gesehen hat, und behebt, was zurückkommt, bevor irgendwer sonst draufschaut. | `peer-review` |
| „Ein Reviewer-Subagent hat zwei Wochen lang jeden Commit geprüft. 86 Läufe, genau einen hat er aufgehalten.“ | Ein Harness, der sich selbst prüft, findet nichts Echtes. Der Reviewer ist immer ein anderes Modell in einem anderen Harness, ohne den Chat des Autors. | `peer-review` |
| „Codex wird mit einem Review nie fertig.“ | Harte Obergrenzen, direkt im Skill: 3 Runden für Code, 5 für einen Plan, 1 für Tests, dann ist Schluss und er wartet auf einen Menschen. Ein Lauf, der 15 Minuten lang nichts geschrieben hat, wird als hängend beendet. | `peer-review`, `codex-coder`, `heartbeat` |
| „Codex behandelt jedes Byte wie einen Schwerverbrecher.“ | Spekulative Schutzmechanismen, Blocker und Hashes sind das Erste, was das Review streicht. Nichts kommt rein, ohne dass ein beobachteter Fehler danach verlangt. | `less-is-more` |
| „Wenn Claude sagt, dass es etwas nicht ändert: Wird dieser Grund irgendwo gespeichert, wo Codex ihn beim nächsten Mal liest?“ | Jeder Befund wird genau einmal abgelegt, mit einem Status, den nur ein Mensch setzt. Taucht ein Befund erneut auf, wird seine Zeile aktualisiert, statt dass er als neu zurückkommt, und frühere Entscheidungen gehen ans nächste Review mit. | `peer-review`-Befundregister |
| „Es hat ‚fertig‘ gesagt. Passiert ist nichts.“ | Eine Aufgabe trägt eine schriftliche Liste von Erfolgsprüfungen, jede durch einen echten Lauf mit bestanden oder nicht bestanden beantwortet. Ein „fertig“ vom Agenten zählt null. | `pl`-Arbeitsaufträge |
| „Morgen macht er denselben Fehler wie heute.“ | Jede Nacht liest ein separates Modell die Sitzungen des Tages, macht aus deinen Korrekturen einzeilige Lektionen, und du gibst frei, was bleibt. Der Engpass sind wir. | Self Learning (`R`-Skills) |
| „Die Hälfte meiner Subagenten waren aufgeblasene Einzeiler mit frischem Kontextfenster.“ | Abläufe gehören in Skills, nicht in Subagenten. Zwei Agenten bleiben, einmal für Planung und Ausführung und einmal fürs Review, weil sich genau diese zwei Aufteilungen auszahlen. | das ganze Set |

Jeder Skill aus der rechten Spalte liegt in diesem Repository, kostenlos zum Kopieren in deine eigenen Agenten. Das gemeinsame Gedächtnis, die Kontingent-Überwachung, die die Übergabe auslöst, und der nächtliche Lauf, der die Lektionen schreibt, wohnen in [Sno Station](https://github.com/sno-ai/sno-station). Installier das, und jeder Skill hier ist mit dabei: das volle Erlebnis auf einen Schlag.

## Ich lag im Bett. Die Agenten machten Schichtwechsel.

*Aus dem eigenen Repository von Sno Station, Nacht vom 2026-09-18.*

![Die Kontingent-Überwachung liest alle fünf Minuten bis zur Schwelle herunter, bei 2 % löst die Übergabe aus](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rotation-quota-watch-2026-09-18.png)

Einer unserer Agenten steckte tief in einem langen Build, da war sein Wochenkontingent fast weg.
Stehen bleiben und warten? Nicht sein Stil. Er schrieb eine Übergabenotiz: was fertig war, was
halb fertig, und an welchem Commit es weitergeht. Dann weckte er einen anderen Agenten.

Eine Sache ging schief, und genau die ist das Spannende. Der Neue legte mit dem Editieren los,
bevor er die Übergabe überhaupt bestätigt hatte. Der erste Agent merkte das, pfiff ihn zurück,
schrieb die Notiz neu und übergab noch einmal, diesmal sauber. Eine Viertelstunde später war der
zweite bei der Arbeit, und zwar bei der ersten unerledigten Aufgabe, nicht wieder ganz von vorn.
Wir haben von alldem nichts mitbekommen. Wir haben geschlafen.

Die Nacht lief auf vier Skills, die hier mitkommen: `subscription-quota-check` las das
Kontingent, ohne etwas davon zu verbrauchen, `heartbeat` nahm alle fünf Minuten einen Messwert,
`rotate-agent` entschied, wann und an wen, und `handoff` hat die Arbeit übergeben. Jeder
Kontingent-Messwert, beide Fassungen der Notiz und die Commits liegen öffentlich im
[Evidence-Ordner von Sno Station](https://github.com/sno-ai/sno-station/tree/main/docs/evidence/rotation-2026-09-18).

## Vier Augen sehen mehr als zwei.

Lass den einen Agenten die Arbeit des anderen per `peer-review` prüfen, egal in welche Richtung.
Der Reviewer sitzt immer in einer frischen Sitzung, die das Gespräch nie gesehen hat, und sobald
du zwei Agenten hast, ist es der andere. Nicht jedes Review findet etwas. Aber es findet immer
wieder genau das, was der Autor nicht sehen konnte. Wer sich selbst prüft, schaut eben mit
denselben Gewohnheiten drauf, mit denen er den Code geschrieben hat.

Ein Fall, den wir veröffentlicht haben: Drei Durchgänge eines Agenten haben einen bekannten Bug
hoher Schwere übersehen oder beiseitegelegt, ein einziges Nachlesen durch den anderen schickte
ihn zurück. Die Aufzeichnung steht unter
[cross-vendor-security-audit](#cross-vendor-security-audit--ein-security-audit-das-noch-mal-liest-was-es-aussortiert-hat).

`catch-report` macht daraus Zahlen: wie viele Probleme der zweite Agent gefunden hat, und daneben,
wie viele die Agenten in ihrer eigenen Arbeit gefunden haben. Getrennt gehalten, nie
zusammengezählt.

## Gestern Abend hab ich meinen Agenten angeschnauzt. Er hat mitgeschrieben.

Tagsüber korrigierst du einen Agenten. Nachts liest der Skill `rem-reflect` die Sitzungen des
Tages, sucht die Fehler heraus, die immer wiederkommen, und schlägt Änderungen an den Skills der
Agenten selbst vor. Morgens gibst du die frei, die du willst, mit `sno rem-reflect accept <id>`. Ohne
dieses Accept ändert sich nichts.

![Self Learning berichtet, was es gelernt und geändert hat, 2026-09-18](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-self-repair-2026-09-18.png)

Ein echter Bericht, direkt von unserem Rechner. Zwei Dinge, über die sich der Besitzer an dem
Abend geärgert hatte, waren am nächsten Morgen Regeln in den aktiven Skills, nachdem er sie
angenommen hatte. Eingetippt hat sie niemand.

Am Tag darauf hat es seine eigenen Hausaufgaben kontrolliert.

![Am nächsten Morgen: Self Learning misst, ob die eigenen Änderungen von gestern geholfen haben, 2026-09-19](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-skill-impact-2026-09-19.png)

Es hat sich die drei Skills angesehen, die es am Vortag geändert hatte. Die zwei, die seitdem
wieder benutzt wurden, zeigten keine Fehler; der dritte war noch gar nicht wieder im Einsatz.

## Installation

### Alle Skills mit Sno Station

Kopier diesen Prompt in den Chat deines Agenten:

```text
Install sno.ai from GitHub.
```

Damit wird Sno Station installiert und jeder Skill samt der Programme, die er aufruft, für alle
unterstützten Agenten auf deinem Rechner eingerichtet.

Oder füg diesen Befehl ins Terminal ein:

```bash
curl -fsSL https://sno.ai/install | sh
```

**Sno Station schon installiert?** Führ `sno setup` aus, um die Skills in deine Agenten zu
installieren. Kommt später ein weiterer Agent dazu, einfach noch mal ausführen.

### Einen einzelnen Skill installieren

Nimm den Kopier-Button an einem der Prompts unten und füg den Text in den Chat deines Agenten ein.
Dein Agent findet und installiert den Skill; selbst herunterladen oder Dateien kopieren musst du nichts.

**`peer-review`** prüft Code, Pläne und Dokumente mit einem Reviewer von einem anderen Modellanbieter.
Dafür braucht es Programme von Sno Station und einen angemeldeten Reviewer. Der Prompt prüft diese Abhängigkeiten zuerst.

```text
Install only the peer-review skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
Check its dependencies and tell me what is missing before installing anything else.
```

**`less-is-more`** hilft deinem Agenten, weniger Code zu schreiben und unnötige Komplexität loszuwerden.
Läuft auch ohne Sno Station.

```text
Install only the less-is-more skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
```

**`tag-team`** setzt zwei Agenten auf eine Aufgabe: Einer baut, der andere prüft, und die Befunde
klären sie unter sich. Dafür braucht es das Reach-Programm von Sno Station. Der Prompt prüft das zuerst.

```text
Install only the tag-team skill from https://github.com/sno-ai/sno-station-skills
for this project. Check that `sno reach pair --help` works and tell me what is missing
before installing anything else.
```

Unterstützte Agenten für Sno Station: Claude Code, Codex, Cursor, Hermes Agent und OpenClaw. Jeder Skill
deklariert, was er vom Agenten braucht. Anhand dieser Deklaration installiert das Setup ihn vollständig,
installiert ihn in abgespeckter Form oder lässt ihn weg, wenn der Agent ihn nicht ausführen kann.

Updates kommen von selbst: `sno` aktualisiert sich, sobald es ein neueres Release findet. Die
vollständige Befehlsliste steht in der [Befehlsreferenz von Sno Station](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md).

### Als Plugin installieren

Claude Code:

```bash
claude plugin marketplace add sno-ai/sno-station-skills
claude plugin install sno-station@sno-ai
```

Codex:

```bash
codex plugin marketplace add sno-ai/sno-station-skills
codex plugin add sno-station@sno-ai
```

`sno-station` enthält jeden Skill; die meisten rufen Programme von Sno Station auf, also installier Sno Station gleich mit.
Willst du nur die 12 Skills, die ohne Sno Station laufen, nimm stattdessen `sno-station-standalone@sno-ai`.

## Die Skills

39 Skills, ausgeliefert als 30 Einheiten, sortiert nach sechs Dingen, die ein Team können muss.
Eine Einheit ist ein einzelner Skill oder eine kleine Familie, die zusammen installiert wird. Den
vollständigen Index mit Links findest du in [skills/README.md](../../skills/README.md).

| | Kategorie | Was deine Agenten damit können |
|---|---|---|
| **J** | [Review & Abnahme](#j--review--abnahme) | Sich gegenseitig auf die Finger schauen und nichts als fertig durchwinken, bevor es belegt ist. |
| **M** | [Aufbau & Rollout](#m--aufbau--rollout) | Auf jedem Rechner in einem Schritt startklar sein und dir in klaren Zeilen sagen, wenn etwas kaputt ist. |
| **S** | [Kommunikation & Übergabe](#s--kommunikation--übergabe) | Sich Nachrichten schicken und mit vollem Kontext übernehmen, wenn einer aufhören muss. |
| **H** | [Berichte & Überblick](#h--berichte--überblick) | Dir zeigen, was erledigt ist, was abgefangen wurde und was es gekostet hat. |
| **T** | [Delegation & Arbeitsaufträge](#t--delegation--arbeitsaufträge) | Arbeit mit einer schriftlichen Definition of Done verteilen und andere Agenten führen. |
| **R** | [Rückblick & Verbesserung](#r--rückblick--verbesserung) | Aus den eigenen Fehlern lernen, wobei du jede Änderung freigibst. |

### J · Review & Abnahme

*Kollegen prüfen sich gegenseitig, und nichts gilt als fertig, bevor es die Abnahme besteht.*

#### [peer-review](../../skills/J-peer-review-and-audit/peer-review/) — ein Reviewer vom anderen Anbieter, und nachbessern, bis alles sauber ist

- **Wirklich unabhängig.** Das Review läuft in einer frischen Sitzung ohne das Gespräch des
  Autors und nimmt bevorzugt die CLI des anderen Anbieters. Ist nur eine CLI installiert, läuft
  es trotzdem, in einer frischen Sitzung, und sagt gleich in der ersten Zeile, dass es ein Review
  vom selben Anbieter war.
- **Jagt, was dich wirklich etwas kostet.** Erst geht es den normalen Weg ab, mit den echten
  Eingaben, die dein System erzeugt, bevor es auch nur eine Minute an exotische Randfälle
  verschwendet. Datenverlust, stillschweigend falsche Ergebnisse und kaputte Hauptabläufe kommen
  zuerst; Stil steht gar nicht auf der Liste.
- **Jeder Befund muss sich seinen Platz verdienen.** Zu jedem steht, wie ein echter Nutzer
  dorthin kommt, was kaputtgeht, und ein ehrlicher Versuch, ihn zu widerlegen. Nichts, was der
  Reviewer sagt, wird gestrichen oder weichgespült; ein vermuteter Fehlalarm wird markiert, nicht
  versteckt.
- **Streicht, bevor es ergänzt.** Zuerst listet es auf, was die Änderung hinzugefügt hat, ohne
  dass es jemand brauchte, und hält „muss jetzt behoben werden“ getrennt von „außerdem gefunden“.
  So wird aus einem Review nie ein Haufen neuer Code.
- **Kann auch Dokumente.** Spezifikationen, Pläne und Migrationsmanifeste bekommen einen
  strukturierten Bericht: was einen Umsetzer dazu bringen würde, das Falsche auszuliefern.

*Nimm es, wenn:* du mit einer Änderung, einem Plan oder einer Spezifikation fertig bist und sie geprüft haben willst, bevor sie landet.

#### [less-is-more](../../skills/J-peer-review-and-audit/less-is-more/) — so wenig Code wie möglich, und ein Messer für den Rest

- **Steigt eine Leiter hoch, bevor es eine Zeile schreibt:** Braucht es das überhaupt? Gibt es
  das schon im Repository? Kann es die Standardbibliothek, die Plattform, eine schon installierte
  Abhängigkeit? Erst dann kommt der minimale Code, der funktioniert.
- **Schneidet weg, was ein Agent überbaut hat:** Interfaces mit genau einer Implementierung,
  Konfigschalter für Werte, die sich nie ändern, Gerüste „für später“, Prüfungen und Sperren, die
  die eigentliche Arbeit blockieren.
- **Geht klug mit deinem Testbudget um:** der kleinste Test, der die Änderung belegt, statt einer
  kompletten Suite zur Beruhigung.
- **Arbeitet von selbst in beide Richtungen:** „write“ oder „fix“ baut, „review“ oder „simplify“
  schneidet, und nach dem Bauen kürzt es den eigenen Diff, bevor es ihn abgibt.

*Nimm es, wenn:* du irgendeine Coding-Aufgabe hast, oder wenn du sagst „zu komplex“ oder „was können wir löschen“.

#### [owner-intent-audit](../../skills/J-peer-review-and-audit/owner-intent-audit/) — meintest du das wirklich so?

- **Prüft Bedeutung, nicht Wortlaut.** Ein Plan kann all deine Begriffe behalten und trotzdem ein
  anderes Produkt beschreiben. Das hier fängt eine Bedingung, die plötzlich bedingungslos gilt,
  ein Beispiel, das zur ganzen Grenze geworden ist, ein Verbot, das still und leise verschwunden ist.
- **Findet die Altlasten, die Agenten hinterlassen:** Arbeit, um die keiner gebeten hat,
  Dokumente, die nicht mehr zur Realität passen, Entscheidungen, an die keiner mehr rankommt, und
  „fertig“-Behauptungen ohne jeden Beleg.
- **Pläne wie Code:** Anforderungsdokumente, Designs, Aufgabenlisten, Testpläne oder ein Diff, den
  ein Agent geschrieben hat.

*Nimm es:* bevor du einen Plan freigibst oder die Arbeit eines Agenten mergst.

#### [agentic-walkthrough](../../skills/J-peer-review-and-audit/agentic-walkthrough/) — alles meldet „Erfolg“, und du traust dem Frieden trotzdem nicht

- **Für das stille Scheitern, das kein Test fängt:** ein Job, der startet, endet, einen Trace
  schreibt, seine eigenen Prüfungen besteht und nichts anfasst.
- **Setzt sich auf den Platz des Programms:** geht den Weg Station für Station ab und findet
  jeden Schalter, jeden Default und jeden Fallback, der die Arbeit in ein stilles No-op
  verwandeln kann.
- **Lässt jede Station sich selbst beweisen,** mit einer engen Beobachtung, die nur das Echte
  erzeugen kann: die gespeicherte Zeile, die tatsächlich geöffnete Datenbankdatei, der API-Aufruf,
  der wirklich rausging.

*Nimm es, wenn:* ein Lauf Erfolg meldet und du einen Beleg brauchst, dass er die Arbeit wirklich getan hat.

#### [first-principles-review](../../skills/J-peer-review-and-audit/first-principles-review/) — die Idee hinterfragen, bevor sie zu Code wird

- **Recherchiert zuerst** und leitet dann neu her, was du wirklich brauchst, ohne sich bei der
  vorgeschlagenen Lösung zu bedienen.
- **Sortiert jede Randbedingung** in harte Grenze, Vorliebe des Owners oder geerbte Gewohnheit,
  und prüft jede tragende Annahme an Belegen.
- **Endet mit einem klaren Urteil:** weitermachen, neu rahmen, vereinfachen, ersetzen, aufteilen,
  erst testen oder stoppen, dazu eine empfohlene Richtung und die Belege, die sie kippen würden.
- **Übergibt sauber:** ein schriftlicher Bericht und eine strukturierte Zusammenfassung, fertig
  für den, der als Nächstes die Anforderungen schreibt.

*Nimm es, wenn:* eine Design- oder Produktidee gerade zum Plan erstarrt. Du startest es namentlich.

#### [e2e](../../skills/J-peer-review-and-audit/e2e/) — End-to-End-Läufe, die nur aus echten Gründen scheitern

- **`e2e-environment-preflight`** prüft externe Dienste, Hosts, Browser-Sitzungen,
  Modell-Endpunkte und Agenten, bevor der erste Test läuft. So scheitert eine lange Suite nie an
  einer toten Abhängigkeit.
- **`e2e-red-triage`** kümmert sich um den seltenen Fehler, den die Prüfungen nicht vorhersehen
  konnten. Es beendet das Raten und zerlegt das Ergebnis in seine zwei Hälften (angenommen oder
  erledigt, gestoppt oder abgestürzt, leer oder unlesbar) und entscheidet dann: Produktfehler
  oder eine neue Umgebungsprüfung.

*Nimm es, wenn:* du End-to-End-Suites gegen echte Dienste laufen lässt.

#### [test-writer](../../skills/J-peer-review-and-audit/test-writer/) — Tests, die wirklich rot werden können

- **Echt statt gemockt:** der echte Parser, das echte Dateisystem, die echte Datenbank oder der
  echte Dienst, wann immer das Repo sie hergibt; ein Mock steht nie für das, was getestet wird.
- **Jede Assertion kann scheitern:** Geprüft werden zurückgegebene Inhalte, gespeicherter Zustand
  und echte Nebenwirkungen, keine Aufrufzähler, und eine Assertion wird nie gelockert, nur damit
  der Test durchgeht.
- **Führt aus, was es geschrieben hat, und sonst nichts:** der engste Befehl für den geänderten
  Test, nicht die ganze Suite, und der Bericht sagt, was lief und was dabei herauskam.

*Nimm es, wenn:* du einen Agenten Tests, Fixtures oder Evals schreiben oder reparieren lässt. Es
läuft eigenständig, ohne Sno Station.

#### [cross-vendor-security-audit](../../skills/J-peer-review-and-audit/cross-vendor-security-audit/) — ein Security-Audit, das noch mal liest, was es aussortiert hat

**Drei Claude-Durchgänge übersahen einen veröffentlichten Bug hoher Schwere. Ein Codex-Durchgang
über das, was Claude aussortiert hatte, fand ihn.** Bei diesem Bug wiederholte jeder weitere
Claude-Durchgang nur Claudes eigene Begründung fürs Verwerfen; der zweite Anbieter brachte eine
andere mit.

Wir haben follow-redirects 1.16.1 auditiert, das einen bekannten Bug hat
([GHSA-mrwp-f3q8-3g9p](https://github.com/advisories/GHSA-mrwp-f3q8-3g9p), Schwere hoch, behoben in 1.16.2):
Eine Liste geheimer Header, die in einem anderen JavaScript-Realm erstellt wurde, wird als leer
behandelt. So folgt der API-Schlüssel des Aufrufers einer Weiterleitung auf einen anderen Host.

- Claude, erstes Audit: hat ihn nie gesehen.
- Claude, zweites Audit: hat ihn gesehen und dann als „Härtung, kein Befund“ abgelegt.
- Ein frischer Claude, der alles Aussortierte noch einmal las: stimmte zu, „Fehlbedienung durch den Aufrufer“.
- Codex, allein auditierend: hat ihn nie gesehen.
- **Codex beim Nachlesen dessen, was Claude aussortiert hatte: widersprach, verfolgte den Bug
  durch den Quellcode und schickte ihn zur Validierung zurück.**

Genau dieser letzte Schritt ist das, was dieser Skill dem Security-Audit-Skill von Cloudflare
hinzufügt (verwendet unter dessen MIT-Lizenz; gleiches Audit, gleiche Beweislatte, gleiche
Validatoren, gleicher Bericht). Vor dem Bericht liest ein Modell des anderen Anbieters jeden
Punkt, den das Audit beiseitegelegt hat, noch einmal, nur lesend, und muss zu jedem eine Antwort
geben; alles, was es zurückbringt, wird erneut validiert. Lehnt die Validierung es wieder ab,
führt der Bericht es unter „Reviewers disagree“ mit beiden Begründungen auf, und du entscheidest.

Zwei Projekte, drei bekannte Bugs: eine Geschichte, keine Quote. Im anderen Projekt hat der
Reviewer jedes der beiden Anbieter den Bug wiedergefunden. Wo Claudes erstes Audit sich den Bug
nie angeschaut hatte, fand ihn auch das Nachlesen dieses Audits nicht.

*Nimm es, wenn:* du ein komplettes Security-Audit einer Codebasis willst. Mit Sno Station nimmt es
den Reviewer des anderen Anbieters, der noch Kontingent hat; ohne Sno Station ruft es Codex aus
Claude Code oder Claude Code aus Codex auf und sagt dazu, wenn nur ein Anbieter verfügbar war.

### M · Aufbau & Rollout

*Das Team auf jeder Workstation in einem Schritt einrichten, bauen, was die Arbeit braucht, und es dann auf jeden Rechner ausrollen.*

Das Setup selbst ist der Befehl `sno setup`, kein Skill. Zwei dieser Skills halten den Rechner
gesund und machen den `sno`-Befehl für deine Agenten leicht bedienbar; der Rest schreibt den
Code: einer reicht ihn an Codex weiter, vier schreiben in Shell, TypeScript, Python oder Rust.

#### [medic](../../skills/M-build-and-rollout/medic/) — ist mein Agententeam gesund? Eine Zeile pro Antwort.

- **Prüft alles, was ein Team braucht,** in etwa zehn Sekunden: Tools installiert, Skills
  installiert, Skill-Befehle ausführbar, Hooks konfiguriert, Messaging aktiv, das Kontingent
  beider Anbieter lesbar, genug freier Temp-Speicher.
- **Zu jedem Problem gibt es die Lösung:** `WARN` oder `FAIL`, was falsch ist, und der exakte
  Befehl, der es behebt.
- **Liest nur, fasst nichts an.** Es installiert, repariert, startet und stoppt nichts. Was
  repariert wird, entscheidest du.

*Nimm es:* auf einem neuen Rechner, wenn Agenten sich nicht mehr erreichen oder ein langer Lauf
nicht starten will.

#### [sno-cli](../../skills/M-build-and-rollout/sno-cli/) — dein Agent bedient `sno` auf Anhieb richtig

- **Nie veraltet:** Der Agent liest die exakten Befehle und Flags aus dem installierten `sno`
  selbst, nicht aus dem Gedächtnis.
- **Eine Aufgabenkarte und Rezepte** für Installation, Update, Health-Checks, Accounts, Skills
  und die nächtliche Runde.
- **Deine Entscheidungen bleiben deine:** Es bedient das Tool, aber es legt deine Einstellungen
  nicht für dich fest.

*Nimm es, wenn:* du einen Agenten Sno installieren, aktualisieren, prüfen oder konfigurieren lässt.

#### [codex-coder](../../skills/M-build-and-rollout/codex-coder/) — Claude plant, Codex schreibt den Code

- **Eine Sitzung, zwei Anbieter:** Claude Code behält den Plan und das Gespräch und startet fürs
  Programmieren einen schlichten `codex exec`-Lauf. So ist das teure Modell nicht das, das tippt.
- **Wählt die Sprache für dich:** Shell, TypeScript, Python oder Rust, je nach den Dateien, die
  die Aufgabe berührt; hast du einen eigenen Sprach-Skill installiert, wird der verwendet.
- **Ein hängender Lauf fällt auf:** Claude Code bekommt Fortschrittsmeldungen, während der Lauf
  arbeitet, und ein Lauf, der 15 Minuten lang nichts geschrieben hat, wird beendet und noch einmal
  gestartet.

*Nimm es, wenn:* dir mitten im Coden das Claude-Kontingent ausgeht oder Codex schreiben soll, was
Claude geplant hat. Auf der Claude-Code-Seite braucht es `heartbeat` von Sno Station.

#### [shellscript-coder](../../skills/M-build-and-rollout/shellscript-coder/), [ts-coder](../../skills/M-build-and-rollout/ts-coder/), [python-coder](../../skills/M-build-and-rollout/python-coder/), [rust-coder](../../skills/M-build-and-rollout/rust-coder/) — Code, der ins Repo passt, in dem er landet

- **Liest, bevor er schreibt:** Laufzeit, Versionen, Helfer, Aufrufer und Tests des Repos kommen
  zuerst, damit der neue Code aussieht wie der Code drumherum.
- **Absichtlich klein:** keine Kompatibilitäts-Shims, keine Optionen, um die keiner gebeten hat,
  kein Helfer, den es zwei Dateien weiter schon gibt.
- **Fertig heißt, ein Befehl ist durchgelaufen:** Jede Aussage im Bericht geht auf eine Prüfung
  zurück, die wirklich in deinem Repo lief; bei einer fehlschlagenden Prüfung meldet er nie „fertig“.

*Nimm sie, wenn:* ein Agent Produktionscode in einer dieser vier Sprachen schreiben oder ändern
soll. Sie laufen eigenständig, ohne Sno Station, und `codex-coder` sucht für jede Aufgabe den
passenden aus.

### S · Kommunikation & Übergabe

*Man redet über einen gemeinsamen Posteingang, und wenn einer weg ist, übernimmt der andere mit vollem Kontext.*

Diese Skills laufen auf Sno Reach, der Messaging-Schicht, die Sno Station installiert: Jeder
Agent bekommt eine Adresse, schickt gespeicherte Nachrichten in die Posteingänge anderer Agenten
und kann einen anderen Agenten wecken, damit er sie liest. Kein Daemon, kein Server.

#### [handoff](../../skills/S-communication-and-handoff/handoff/) — eine Aufgabe übergeben, ohne dass etwas verloren geht

- **Hält den ganzen Stand fest:** was fertig ist, was halb fertig ist, nicht committete
  Änderungen, die Entscheidungen, die du schon getroffen hast, und was tabu ist.
- **Der Empfänger schreibt nichts, bis die Freigabe bestätigt ist,** damit nie zwei Agenten
  gleichzeitig an derselben Arbeit editieren.
- **Der Absender geht wirklich.** Nach der Freigabe hört er auf; kein zweiter Besitzer, der noch
  herumschwirrt.
- **Klappt sogar, wenn der Absender schon weg ist** (Kontingent verweigert, Absturz, Fenster zu):
  Der Fortschrittsdatensatz von `sno handoff-checkpoint` lässt einen frischen Agenten ab der
  ersten unerledigten Aufgabe weitermachen.

*Nimm es, wenn:* ein Agent seine Aufgabe an einen anderen abgeben muss.

#### [rotate-agent](../../skills/S-communication-and-handoff/rotate-agent/) — nie wieder einen langen Lauf ans Kontingentlimit verlieren

- **Handelt, solange der Absender noch lebt.** Es schaut alle paar Minuten aufs verbleibende
  Kontingent und übergibt an einer Schwelle, nicht erst nach der Ablehnung, wenn es für ein
  Briefing zu spät ist.
- **In beide Richtungen:** von Codex zu Claude Code oder von Claude Code zu Codex.
- **Begrenzt:** Es löst einmal aus, und du kannst festlegen, wie lange die Überwachung läuft.
- **Ein Netz für verpasste Fenster:** Wurde das Fenster verpasst, startet
  `sno rotate-agent-resume` den Ersatz aus dem Fortschrittsdatensatz auf der Platte.

*Nimm es, wenn:* ein langer Lauf fertig werden muss, auch wenn einem Anbieter das Kontingent
ausgeht. Braucht beide CLIs angemeldet und tmux.

#### [subscription-quota-check](../../skills/S-communication-and-handoff/subscription-quota-check/) — wie viel Kontingent noch übrig ist, ohne etwas davon zu verbrauchen

- **Schluss mit der schlimmsten Angewohnheit:** herauszufinden, dass das Kontingent alle ist,
  indem man einen echten Aufruf macht und die Fehlermeldung liest.
- **Liest Claude Code und Codex zusammen** in etwa acht Sekunden und sagt dir, wann das
  Kontingent zurückgesetzt wird.
- **Ehrlich bei alten Zahlen:** Es prüft, ob der Wert aktuell oder nur der zuletzt bekannte ist,
  und sagt dir, welcher.
- **Fragt nie von sich aus ab** und läuft deshalb auch nie in ein eigenes Rate-Limit.

*Nimm es, wenn:* du fragst, oder direkt nachdem ein Anbieter Arbeit abgelehnt hat.

#### [heartbeat](../../skills/S-communication-and-handoff/heartbeat/) — Fortschrittsmeldungen langer Läufe, direkt ins Gespräch

- **Zwei Formen:** alle N Minuten berichten (Training, ein langer Build, eine
  Generierungs-Queue) oder beobachten, bis etwas fertig ist.
- **Eine Aufgabe zu fester Zeit:** Nenn dem Agenten ein Datum oder eine Uhrzeit, einmalig oder
  wiederkehrend. Er schreibt die Aufgabe auf, und zu dieser Zeit startet ein Agent, auch wenn das
  Gespräch längst geschlossen ist.
- **Die Meldungen landen da, wo du bist:** Jeder Messwert kommt im Gespräch des Agenten an, nicht
  in einem Log, das keiner liest.
- **Schwer falsch zu benutzen:** Intervalle sind in Minuten, und eine Zahl in Sekundengröße wird
  abgelehnt, statt deinen Agenten stillschweigend alle paar Sekunden zu wecken.

*Nimm es, wenn:* etwas Langes unbeaufsichtigt läuft und du davon hören willst, oder wenn eine
Aufgabe zu einer Zeit passieren muss, zu der du nicht da bist.

#### [reach](../../skills/S-communication-and-handoff/reach/) — Agenten reden miteinander

- **Startet einen Claude-Code- oder Codex-Agenten** mit eigener Adresse und eigenem Arbeitsordner.
- **Arbeit schicken und Antworten lesen** über gespeicherte Nachrichten, oder sofort mit einem
  laufenden Agenten sprechen.
- **Nachrichten verleihen keine zusätzliche Befugnis:** Eine Nachricht erweitert nie die Aufgabe,
  die du vergeben hast.

*Nimm es, wenn:* ein Agent einen anderen kontaktieren, starten oder auf ihn warten muss.

#### [join-talk](../../skills/S-communication-and-handoff/join-talk/) — jeden Agenten mit einem Befehl erreichbar machen

- **Eine Zeile Ausgabe:** `joined <address>`. Gib anderen Agenten diese Adresse, und sie
  erreichen dieses Terminal.
- **Beliebig wiederholbar:** Erneutes Ausführen im selben Terminal ändert nichts.
- **Klare Absagen:** Wenn es nicht geht, sagt es genau, warum.

*Nimm es, wenn:* du einen Agenten von Hand geöffnet hast und andere ihn erreichen sollen.

#### [tag-team](../../skills/S-communication-and-handoff/tag-team/) — zwei Agenten, eine Aufgabe: einer baut, einer prüft

- **Ein Befehl:** `sno reach pair "the task"` startet beide Agenten im aktuellen Ordner, jeden
  in einem tmux-Fenster, das du öffnen und beobachten kannst.
- **Ausdiskutiert, bevor es bei dir landet.** Der Reviewer liest das Ergebnis und die geänderten
  Dateien und antwortet mit konkreten Mängeln oder ausdrücklich ohne Mängel; die beiden tauschen
  Fixes und Reviews unter sich aus, und dein Agent fragt den Reviewer, bevor er es für sauber erklärt.
- **Sagt dir, welche Art von Review du bekommen hast.** Bist du bei zwei Anbietern angemeldet,
  kommt das Review vom jeweils anderen. Bei nur einem läuft das Paar trotzdem und sagt dir, dass
  das Review innerhalb dieses Anbieters geblieben ist.
- **Erklärt nichts zu früh für sauber.** Ein erstes Review mit Befunden wird als offen gemeldet;
  kein dritter Reviewer, und kein zweites Paar, nur weil das erste Review noch nicht da war.

*Nimm es, wenn:* eine Aufgabe eine zweite Meinung wert ist und du sie nicht selbst zwischen den
Agenten hin- und hertragen willst.

### H · Berichte & Überblick

*Jeder sieht, was erledigt ist, wer was abgefangen hat, wer für wen eingesprungen ist und was gerade läuft.*

#### [away-brief](../../skills/H-reporting-and-visibility/away-brief/) — eine Seite, wenn du zurückkommst

- **Vier Abschnitte, höchstens 60 Zeilen:** Erledigt, Hängt, Braucht dich, Kosten.
- **Was auf dich wartet, wird nie** von einer langen Liste erledigter Arbeit von der Seite gedrängt.
- **„Erledigt“ ist nur, was echt ist:** in git, in einem gelieferten Arbeitsauftrag oder in einem
  abgeschlossenen Fortschrittsdatensatz. Nicht, was ein Agent behauptet.
- **Zeigt, was die Nacht gekostet hat:** Führ `sno away-brief mark` aus, bevor du gehst, und die
  nächste Seite zeigt das seitdem verbrauchte Kontingent.

*Nimm es:* nach dem Schlafen, nach einem Meeting oder nach einem langen unbeaufsichtigten Lauf.

#### [catch-report](../../skills/H-reporting-and-visibility/catch-report/) — lohnt sich der zweite Agent? Hier sind die Zahlen.

- **Zwei Zählungen nebeneinander:** Probleme, die das andere Modell im Review gefunden hat, und
  Momente, in denen ein Agent seinen eigenen Fehler bemerkt hat.
- **Nie aufgeblasen:** Die beiden bleiben getrennt und werden nie addiert, und wenn sich ein Teil
  nicht messen ließ, steht das da, statt einer Null.
- **Zitiert die größten Funde** mit Titel, aus den Review-Aufzeichnungen, die schon auf deinem
  Rechner liegen.

*Nimm es, wenn:* du die Review-Ergebnisse der Woche sehen willst oder begründen musst, warum zwei Agenten laufen.

#### [agentic-time-estimate](../../skills/H-reporting-and-visibility/agentic-time-estimate/) — echte Schätzungen für Agentenarbeit

- **Agenten-Laufzeit, nicht Entwicklerzeit:** wie lange ein Agent dafür braucht und wie lange der
  laufende Job noch braucht. Erst gemessen, dann geschätzt.
- **Uhrzeiten, auf die du dich verlassen kannst:** Jede Zeit, die du zu sehen bekommst, kommt von
  `sno report-time`, in deiner eigenen Zeitzone mit UTC daneben.

*Nimm es, wenn:* du fragst „wie lange noch?“ oder „wann ist es fertig?“

### T · Delegation & Arbeitsaufträge

*Eine Leitung verteilt Arbeit als Arbeitsaufträge und entscheidet, wer welchen Job übernimmt.*

#### [charter](../../skills/T-delegation-and-work-orders/charter/) — eine Datei, die sagt, was fertig heißt

- **Bleibt bei deinen Worten.** Es erfindet nie eine Entscheidung, einen Fakt oder eine
  Anforderung und stellt nur dann eine Frage, immer eine auf einmal, wenn die Antwort das
  Ergebnis ändern würde.
- **Erfolgsprüfungen, die man ausführen kann:** Jede nennt, was beobachtet wird, wo und wie, und
  wird mit bestanden oder nicht bestanden beantwortet.
- **Kein Zeremoniell:** Nichts kommt rein, solange niemand den Fehler benennen kann, den es abfängt.
- **Jede Art von Projekt:** Software, Dokumente, Kampagnen, Recherche, Betrieb.

*Nimm es, wenn:* Arbeit ein schriftliches Briefing braucht, bevor jemand anderes sie erledigt.

#### [deliver](../../skills/T-delegation-and-work-orders/deliver/) — eine Charter bis zum belegten Ergebnis durchziehen

- **Die Prüfungen der Charter sind die Definition of Done,** und sonst nichts.
- **Jede Prüfung belegt durch einen aufgezeichneten echten Lauf,** nachverfolgt mit `sno deliver-proof`.
- **Ein unabhängiges Review,** dann ein ehrlicher Abschluss: was bestanden hat, was nicht und warum.
- **Macht weiter, wo jemand anderes aufgehört hat:** Hat ein früherer Agent einen
  Fortschrittsdatensatz hinterlassen, geht es ab dem nächsten unerledigten Schritt weiter, statt
  von vorn anzufangen.

*Nimm es, wenn:* eine Charter freigegeben ist und jemand sie umsetzen muss.

#### [pl](../../skills/T-delegation-and-work-orders/pl/) — ein Projektleiter-Agent (Project Lead) für einen Arbeitsstrang

- **Führt bis zu vier ausführende Agenten,** jeden mit einer Charter, nacheinander oder parallel.
- **Eine Familie aus fünf weiteren Skills:** `pl-dispatch` eröffnet und plant die Arbeit,
  `pl-watch` beaufsichtigt laufende Agenten, `pl-audit` prüft die Abnahme, bevor irgendetwas
  geschlossen wird, `pl-env` repariert die Umgebung, in der die Arbeit läuft, und `pl-analyze`
  schreibt die Ursachenanalyse, wenn etwas schiefgeht.

*Nimm es, wenn:* ein Projekt mehrere Agenten unter einer Leitung braucht. Du startest es namentlich.

#### [cos](../../skills/T-delegation-and-work-orders/cos/) — ein Chief of Staff: der eine Agent, mit dem du redest

- **Ein Gespräch für dich,** in deiner Sprache. Er koordiniert ein bis drei Projektleiter
  parallel und bringt dir nur die harten Entscheidungen: Geld, Richtung, rote Linien.
- **Eine Familie aus drei weiteren Skills:** `cos-watch` hält jeden Projektleiter am Leben und im
  Zeitplan, `cos-review` geht die Entscheidungen der Nacht in einem Durchgang durch, wenn du
  zurückkommst, und `cos-evolve` macht aus Führungsfehlern, die sich wiederholen, verbindliche Regeln.

*Nimm es, wenn:* du mehrere Arbeitsstränge hast und einen einzigen Ansprechpartner willst. Du startest es namentlich.

### R · Rückblick & Verbesserung

*Das Team schaut auf die eigene Arbeit zurück und macht aus Lektionen Regeln und bessere Praxis.*

#### [rem-reflect](../../skills/R-recursive-self-improvement/rem-reflect/) — die nächtliche Runde: deine Agenten lernen aus ihren eigenen Sitzungen

- **Einmal am Tag** liest es die Agentensitzungen dieses Rechners (Claude Code, Codex, Cursor, Hermes Agent und OpenClaw), findet Fehler und
  Korrekturen, die sich wiederholen, und macht daraus Lektionen und vorgeschlagene Skill-Änderungen.
- **Du gibst alles frei:** `sno rem-reflect accept`, `reject` oder `tbd` für jeden Vorschlag. Ohne
  dein Accept ändert sich nichts.
- **Lektionen kommen zurück, wenn sie zählen:** Eine angenommene Lektion wird dem Agenten zu
  Beginn der nächsten Sitzung gezeigt, für dieses Projekt oder für alle.
- **Du entscheidest, was den Rechner verlässt.** Im Modus `local-first` geht nichts an Sno; ein
  paar Sitzungen der Nacht gehen nur an dein eigenes Claude-Code- oder Codex-Konto, um die
  Lektionen zu entwerfen. In den beiden anderen Modi lädt es auf deren Standard-Freigabestufe Sitzungstext (gängige Secrets vorher geschwärzt, nach bestem Bemühen)
  und deine installierten Skills in die Cloud von Sno hoch, für treffsicherere Urteile. Das Hochladen
  kannst du jederzeit mit `sno station consent off` abschalten. Der Skill listet genau auf, was er liest und sendet.

Die Familien-Skills `pl-analyze` (Vorfallanalyse für den Projektleiter) und `cos-evolve`
(wiederkehrende Fehler werden zu Regeln) gehören auch hierher; sie werden mit `pl` und `cos` ausgeliefert.

*Nimm es:* Es läuft immer, sobald `sno setup` den täglichen Lauf scharf geschaltet hat.

## Vertrauen ist gut, Kontrolle ist besser

Jede Einheit eines Releases hat vor der Veröffentlichung dieselben Prüfungen bestanden:

1. Das Repository enthält seine `LICENSE` und `NOTICE`.
2. Die Einheit wird vollständig kopiert, mit ihren Familienmitgliedern und den Unterschieden pro
   Agent.
3. Nichts Persönliches bleibt übrig: keine Home-Pfade, Owner-Namen, internen Hosts oder fest
   verdrahteten Modelle, und keine chinesischen, japanischen oder koreanischen Schriftzeichen.
4. Der Header jedes Skills lässt sich parsen, und seine Deklaration dessen, was er vom Agenten
   braucht, ist gültig.
5. Die eigenen Selbsttests jedes Skills bestehen auf dieser sauberen Kopie, nicht auf dem Rechner
   des Autors.
6. Ein Stempel, `PUBLISHED.json`, wird als Letztes geschrieben, mit der Anzahl der Selbsttests und
   Digests von Vertrag und Nutzlast.

Ein Skill, der eine Prüfung nicht besteht, wird nicht veröffentlicht. Den Stempel schreibt der
Release-Build, nie eine Hand. Der gesamte Skill-Text ist auf Englisch, und dein Agent befolgt ihn
in jeder Sprache, in der du mit ihm sprichst.

## Die Skills und Sno Station

Die Skills sind die Gewohnheiten. [Sno Station](https://github.com/sno-ai/sno-station) ist die Workstation, auf der sie laufen:
das gemeinsame Gedächtnis, die Kontingent-Überwachung, die eine Übergabe auslöst, die Nachrichten
zwischen den Agenten und der nächtliche Lauf, der die Lektionen schreibt. Installier Sno Station,
und jeder Skill hier ist mit dabei.

| Du willst | Hier entlang |
|---|---|
| Die ganze Workstation, und was heute auf welchem Agenten läuft | [sno-ai/sno-station](https://github.com/sno-ai/sno-station#what-you-can-use-today-and-where-it-stops) |
| Agenten, die sich Nachrichten schicken, über Fenster und Rechner hinweg | [Sno Reach](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md) |
| Arbeit, die zu einer Zeit startet, die du nennst | [Finish](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md) |
| Jeden `sno`-Befehl, den die Skills aufrufen | [Befehlsreferenz](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md) |
| Die Rohdaten hinter den Geschichten oben | [Evidence-Ordner](https://github.com/sno-ai/sno-station/tree/main/docs/evidence) |
| Etwas fragen oder zeigen, was du gebaut hast | [Discussions](https://github.com/sno-ai/sno-station-skills/discussions) |
| Eine kleine erste Änderung | [Good first issues](https://github.com/sno-ai/sno-station-skills/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) und [CONTRIBUTING.md](../../CONTRIBUTING.md) |

**Und lass bei beiden Repositories einen Stern da.** Sno Station bauen wir mit genau diesen Skills.
Was wir in unseren eigenen Nachtschichten lernen, landet hier, Release für Release.

## Für Skill-Autoren

### Struktur

```
skills/
  README.md                     the category index
  <category>/<unit>/
    skill/                      one skill: SKILL.md, references/, scripts/
    skills/<member>/            or a family of skills that ship together
    overlay/claude|codex/       per-agent differences, when a skill needs them
    public-bin/                 one file per `sno <file name>` command the skill provides
    PUBLISHED.json              the stamp, written into the release archive by the build
registry.yaml                   unit -> category code (and tier)
scripts/
  requirements-contract.json    the contract every requires: block is checked against
LICENSE                         Apache-2.0
```

Die Kategoriecodes sind fest, in dieser Reihenfolge: J M S H T R. Sie stehen in den
Verzeichnisnamen und in `registry.yaml`.

### Deklarieren, was ein Skill braucht

Jede `SKILL.md` beginnt mit einem `requires:`-Block. `sno setup` liest ihn und entscheidet pro
Agent, ob der Skill installiert wird:

```yaml
requires:
  programs: [reach]                          # Sno Station programs the skill calls
  harness:
    - {slot: 4.shell, need: required}        # what the agent itself must be able to do
```

- **programs** sind Programme von Sno Station, die neben den Skills installiert und als
  `sno <name>` ausgeführt werden: `reach`, `heartbeat`, `subscription-quota-check`, `report-time`.
- **slots** benennen eine Fähigkeit des Agenten: `4.shell` (Shell-Befehle ausführen),
  `4.file-read-write` (Dateien lesen und schreiben), `4.background-processes` (einen Befehl im
  Hintergrund ausführen), `2.pre-turn-context-injection` (vor jedem Turn Text in den Kontext des
  Agenten einfügen) und `3.reader-to-agent-delivery` (die Ausgabe eines Hintergrund-Readers
  erreicht den Agenten).
- **need** ist `required` (ein Agent ohne den Slot bekommt den Skill nicht), `preferred` (der
  Skill wird installiert und funktioniert eingeschränkt) oder `optional` (nur eine Annehmlichkeit).

## Lizenz

Apache-2.0. Open Source, von vorn bis hinten. Siehe [LICENSE](../../LICENSE).
