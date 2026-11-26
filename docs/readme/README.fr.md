# Sno: Des agents futés. Les réflexes des vieux routiers. Un peu meilleurs chaque jour.

**Read in other languages:** [English](../../README.md) · [中文](README.zh-CN.md) · [Deutsch](README.de.md) · [Español](README.es.md) · **Français** · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [繁體中文](README.zh-TW.md)

![Sno Station : agents, rassemblement ! Deux têtes valent mieux qu'une, et au matin elles en savent plus.](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/hero-banner.png)

**Vos agents IA, ce sont des recrues brillantes lâchées sans collègues. Ces skills leur donnent les réflexes d'une équipe qui a déjà livré.** L'un code, l'autre relit. Avant que son quota ne soit à sec, l'un laisse ses consignes et un autre reprend au commit près. « Terminé » ? Seulement avec une vraie exécution à l'appui. Et chaque nuit, ils refont le film de la journée et vous proposent de nouvelles règles. C'est vous qui validez.

Fonctionne avec **Claude Code, Codex, Cursor et Hermes Agent**, et aussi avec OpenClaw. Chaque skill s'installe en entier là où l'agent sait l'exécuter, et dans une version allégée là où il ne le peut pas.

Chaque skill est du texte brut : vous pouvez le lire, le copier, le modifier. Ce sont les skills que [Sno Station](https://github.com/sno-ai/sno-station) installe dans les agents que vous utilisez déjà, et ceux dont nous nous servons tous les jours pour construire Sno Station.

[![Étoiles GitHub](https://img.shields.io/github/stars/sno-ai/sno-station-skills?label=stars&color=eab308&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/stargazers)
[![Dernière version](https://img.shields.io/github/v/release/sno-ai/sno-station-skills?label=release&color=2dd4bf&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/releases/latest)
[![Licence Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-97ca00.svg?labelColor=3b3b3b)](../../LICENSE)
![testé par lui-même avant chaque version](https://img.shields.io/badge/every%20release-self--tested-3b82f6.svg?labelColor=3b3b3b)
![agents Claude Code, Codex, Cursor, Hermes, OpenClaw](https://img.shields.io/badge/agents-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20Cursor%20%C2%B7%20Hermes%20%C2%B7%20OpenClaw-f0a04b.svg?labelColor=3b3b3b)

Pour tout avoir, dites simplement à votre agent :

```text
install sno.ai from GitHub
```

Votre agent installe Sno Station et met en place chaque skill, avec les programmes qu'ils appellent, pour tous les agents compatibles qu'il trouve sur votre ordinateur. Ensuite, essayez-en un :

```text
peer-review this
```

Un autre agent lit votre modification dans une session neuve, qui n'a rien vu de la conversation, et vous dit ce qui casserait en conditions réelles. [Un seul skill, ou plutôt un plugin ?](#installation)

**Vous débarquez ?** Ces skills ne sont qu'une moitié du tableau. L'autre moitié, c'est [Sno Station](https://github.com/sno-ai/sno-station), le poste de travail sur lequel ils tournent : des agents qui [s'envoient des messages](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md), [du travail qui démarre à l'heure dite](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md), et une mémoire qu'ils partagent tous.

[Ce qui change pour vous](#ce-qui-change-pour-vous) · [Pourquoi ces skills](#pourquoi-ces-skills) · [Les galères, et ce qui les règle](#les-galères-et-ce-qui-les-règle) · [Histoires vécues sur notre propre machine](#je-dormais-eux-ont-fait-la-relève) · [Installation](#installation) · [Les skills](#les-skills) · [La confiance n'exclut pas le contrôle](#la-confiance-nexclut-pas-le-contrôle) · [Ces skills et Sno Station](#ces-skills-et-sno-station) · [Pour les auteurs de skills](#pour-les-auteurs-de-skills) · [Licence](#licence)

## Ce qui change pour vous

Vous continuez à travailler exactement comme avant, avec l'agent de votre choix. Et là :

1. **Une modif est prête, il faut un second regard.** Dites « peer-review this ». Un relecteur de
   l'autre éditeur la découvre à froid et vous dit ce qui casserait en conditions réelles. L'auteur
   corrige la cause profonde, tour après tour, jusqu'à ce que la relecture revienne propre.
2. **Une longue tâche tourne, vous allez vous coucher.** Dites « arm rotate-agent ». Si, dans la
   nuit, le quota de l'agent au travail tombe au seuil, il passe la main à un agent tout frais de
   l'autre éditeur. La consigne est vérifiée avant que le moindre fichier soit touché.
3. **Il faut que ce soit fait à une heure précise.** Donnez l'heure : « vérifie le build demain à 9 h »,
   ou « rédige le rapport tous les matins à 7 h ». Un agent démarre à l'heure dite et s'en
   charge, conversation ouverte ou fermée. `sno heartbeat --due` montre ce qui est planifié. Cette
   partie de Sno Station s'appelle Finish ; le [guide](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md)
   donne tous les détails.
4. **Vous revenez.** Dites « away brief ». Une page, 60 lignes au plus : ce qui est fait, ce qui
   bloque et pourquoi, ce qui attend votre réponse, et ce que ça a coûté en quota.
5. **Un travail à confier à quelqu'un d'autre ?** Dites « write a charter ». Vous obtenez un seul fichier
   qui dit quoi livrer, ce qui est hors limites, ce que vous avez déjà tranché, et comment chaque
   critère de réussite sera prouvé. N'importe quel agent peut ensuite le mener à bien avec
   `deliver`, et chaque critère est prouvé par une vraie exécution enregistrée.
6. **Chaque nuit, l'équipe fait son bilan.** La boucle nocturne lit les sessions de la journée de
   tous vos agents, repère les erreurs qui reviennent, et propose des leçons et des modifications
   de skills. Le matin, vous acceptez celles qui vous plaisent avec
   `sno rem-reflect accept <id>`. Sans cet accept, rien ne change.

## Pourquoi ces skills

Un agent IA tout seul, c'est la recrue brillante qu'on a oubliée dans un bureau vide. Il se relit
lui-même, alors forcément, ce qu'il ne voit pas lui échappe. 3 h du matin, quota épuisé : il
s'arrête net, en plein milieu de votre build. Les tests sont verts, il annonce « terminé », et en
réalité il ne s'est rien passé. Trois couches de machinerie que personne n'a demandées ? Il les
empile quand même. Et demain, rebelote, la même erreur qu'aujourd'hui. Personne ne lui a dit
le contraire.

**Sno Station Skills répare l'équipe, pas le modèle.** [Sno Station](https://github.com/sno-ai/sno-station)
installe ces skills dans les agents que vous avez déjà, et leur inculque les réflexes de toute
bonne équipe d'ingénierie. Un deuxième regard, venu d'un autre éditeur. Une passation propre
quand quelqu'un doit partir. Un lead qui distribue le travail avec une définition écrite de
« terminé ». Une page de synthèse à votre retour. Et chaque nuit, une rétro qui fait des erreurs
de la semaine les règles de la suivante.

**Deux agents, deux rôles.** L'un exécute votre tâche, l'autre confronte le résultat à vos
exigences. Peu importe qui fait quoi : Claude Code, Codex, Cursor et Hermes Agent savent tenir les
deux rôles. Quand les deux sont installés, la relecture se fait chez l'autre, dans une session
neuve qui ignore tout de la conversation de l'auteur. Constats et corrections, ils règlent ça
entre eux.

**Du travail qui s'achève pendant que vous dormez.** Vous l'armez avant d'aller vous coucher, et
c'est tout. Quand l'abonnement de l'agent au travail commence à fondre, il rédige une note de
passation tant qu'il en est encore capable, réveille un agent de l'autre éditeur et lui confie la
tâche avec le commit exact d'où repartir. Votre build, lui, se moque bien de savoir quel éditeur
l'a terminé.

**« Terminé » veut dire prouvé.** Chaque tâche peut porter une liste écrite de critères de
réussite, chacun tranché, réussi ou échoué, par une vraie exécution. Rien n'est terminé
simplement parce qu'un agent l'a dit.

**Testé avant d'être livré.** Chaque skill d'une version a passé ses propres autotests sur une
copie propre, a été passé au crible pour traquer chemins personnels et résidus, et porte un
tampon qui en atteste. Un skill qui échoue n'est pas publié.

![Comment ça marche : deux agents, un espace de travail partagé, trois choses que vous y gagnez](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/squad-how-it-works.png)

**Une étoile, tout de suite. Le jour où un agent vous lâche à 2 h du matin, vous serez content de retrouver ce dépôt.**

## Les galères, et ce qui les règle

*Dernière mise à jour : 2026-10-23.* Chaque ligne de la colonne de gauche est une vraie plainte postée sur r/ClaudeCode, r/codex ou r/ClaudeAI pendant la semaine du 20 octobre 2026. La colonne de droite, c'est ce qui tourne sur nos propres machines, gratuit et open source, pour que ça s'arrête.

| Ce qu'on a lu cette semaine | Ce qui règle le problème | Où |
|---|---|---|
| « Ma limite de 5 heures, cramée en 30 minutes. » | Arrêtez d'envoyer le plus gros modèle faire tout le boulot. Opus planifie et relit ; Codex écrit le code, appelé comme agent depuis la même session. Quand un abonnement est à sec, l'autre reprend la tâche à partir de la même mémoire. | `codex-coder`, `sno reach call` |
| « 10 heures de travail de nuit perdues à cause de “this model is at capacity”. » | À 2 % de son quota, l'agent au travail rédige une note de passation et réveille l'agent de l'autre éditeur, qui reprend au commit exact. Vous, vous dormiez. | `rotate-agent` |
| « 1 100 fichiers, 30 000 lignes. Je n'ai pas le budget de tokens pour relire leurs PR. » | Qui pousse relit d'abord : l'auteur lance une relecture par l'autre éditeur, dans une session neuve qui n'a jamais vu la conversation, et corrige ce qui revient avant que quiconque d'autre y jette un œil. | `peer-review` |
| « Un sous-agent relecteur a vérifié chaque commit pendant deux semaines. 86 passages, il en a arrêté exactement un. » | Un harness qui se relit lui-même ne trouve rien de réel. Le relecteur est toujours un autre modèle, dans un autre harness, sans rien du chat de l'auteur. | `peer-review` |
| « Codex ne finit jamais une relecture. » | Des plafonds en dur, écrits dans le skill : 3 tours pour du code, 5 pour un plan, 1 pour des tests, puis il s'arrête et attend un humain. Une exécution qui n'a rien écrit depuis 15 minutes est tuée, considérée comme bloquée. | `peer-review`, `codex-coder`, `heartbeat` |
| « Codex traite chaque octet comme un criminel. » | Garde-fous spéculatifs, blocages et hashes : c'est la première chose que la relecture supprime. Rien n'entre sans un échec observé qui le réclame. | `less-is-more` |
| « Quand Claude dit qu'il ne changera pas quelque chose, est-ce que cette raison est stockée quelque part où Codex la lira la prochaine fois ? » | Chaque constat est enregistré une seule fois, avec un statut que seul un humain fixe. Un constat soulevé à nouveau met à jour sa ligne au lieu de revenir comme neuf, et les décisions antérieures sont transmises à la relecture suivante. | registre des constats de `peer-review` |
| « Il a dit terminé. Il ne s'est rien passé. » | Une tâche porte une liste écrite de critères de réussite, chacun tranché, réussi ou échoué, par une vraie exécution. Un agent qui dit « terminé », ça ne compte pas. | ordres de mission `pl` |
| « Demain, il refera la même erreur qu'aujourd'hui. » | Chaque nuit, un modèle distinct lit les sessions de la journée, transforme vos corrections en leçons d'une ligne, et c'est vous qui validez ce qui reste. Le goulot d'étranglement, c'est nous. | Self Learning (skills `R`) |
| « La moitié de mes sous-agents n'étaient que des one-liners déguisés, avec une fenêtre de contexte toute neuve. » | Les procédures vivent dans des skills, pas dans des sous-agents. Il reste deux agents, l'un pour planifier et exécuter, l'autre pour relire, parce que ce sont ces deux découpages-là qui paient. | tout l'ensemble |

Chaque skill de la colonne de droite se trouve dans ce dépôt, libre de copie dans vos propres agents. La mémoire qu'ils partagent, la veille de quota qui déclenche la passation et la tâche nocturne qui rédige les leçons vivent dans [Sno Station](https://github.com/sno-ai/sno-station) ; installez-le et tous les skills d'ici viennent avec, pour profiter de l'expérience complète d'un coup.

## Je dormais. Eux ont fait la relève.

*Tiré du dépôt de Sno Station, la nuit du 2026-09-18.*

![La veille de quota descend jusqu'au seuil, un relevé toutes les cinq minutes, et la passation se déclenche à 2 %](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rotation-quota-watch-2026-09-18.png)

L'un de nos agents était en plein long build quand son quota hebdomadaire est tombé presque à
zéro. Attendre les bras croisés ? Non. Il a rédigé une note de passation : ce qui était fait, ce
qui l'était à moitié, et le commit exact d'où repartir. Puis il a réveillé un autre agent.

Un accroc, et c'est justement le moment intéressant. Le nouveau venu s'est mis à modifier des
fichiers avant même d'avoir confirmé la passation. Le premier l'a vu, l'a mis en pause, a réécrit
la note et a repassé la main, cette fois dans les règles. Un quart d'heure plus tard, le deuxième
agent était au travail, et il a repris à la première tâche non terminée, pas depuis le début.
Nous, pendant ce temps, on dormait.

Cette nuit-là a tourné sur quatre skills livrés ici : `subscription-quota-check` a lu le quota
sans en consommer, `heartbeat` a pris un relevé toutes les cinq minutes, `rotate-agent` a décidé
quand et à qui, et `handoff` a transféré le travail. Chaque relevé de quota, les deux versions de
la note et les commits sont publiés dans
[le dossier de preuves de Sno Station](https://github.com/sno-ai/sno-station/tree/main/docs/evidence/rotation-2026-09-18).

## Quatre yeux valent mieux que deux.

Demandez à l'un des agents de passer le travail de l'autre en `peer-review`, dans un sens comme
dans l'autre. Le relecteur part toujours d'une session neuve qui n'a jamais vu la conversation, et
dès que vous avez deux agents, c'est l'autre qui relit. Une relecture ne trouve pas forcément
quelque chose. Mais elle continue de dénicher ce que l'auteur ne pouvait pas voir : un agent qui
se relit garde les mêmes œillères que quand il a écrit le code.

Un cas que nous avons publié : trois passes d'un même agent ont raté un bug connu de gravité
élevée, ou l'ont mis de côté, et une seule relecture par l'autre l'a renvoyé en examen. Le
dossier est sous
[cross-vendor-security-audit](#cross-vendor-security-audit--un-audit-de-sécurité-qui-relit-ce-quil-a-écarté).

`catch-report` met des chiffres dessus : combien de problèmes le deuxième agent a attrapés, à
côté du nombre de problèmes que les agents ont attrapés dans leur propre travail, gardés séparés
et jamais additionnés.

## Hier soir, j'ai engueulé mon agent. Il a pris des notes.

Dans la journée, vous reprenez un agent. La nuit venue, le skill `rem-reflect` relit les sessions
du jour, repère les erreurs qui reviennent sans cesse et propose de modifier les skills des agents
eux-mêmes. Le matin, vous validez celles que vous voulez avec
`sno rem-reflect accept <id>`. Sans cet accept, rien ne change.

![Self Learning rend compte de ce qu'il a appris et modifié, 2026-09-18](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-self-repair-2026-09-18.png)

Un vrai rapport, tout droit sorti de notre machine. Deux choses qui avaient agacé le propriétaire
ce soir-là étaient, dès le lendemain matin, des règles dans les skills en service, une fois qu'il
les avait acceptées. Personne ne les a tapées à la main.

Le lendemain, il a corrigé sa propre copie.

![Le lendemain matin : Self Learning mesure si ses propres modifications de la veille ont servi, 2026-09-19](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-skill-impact-2026-09-19.png)

Il a examiné les trois skills qu'il avait modifiés la veille. Les deux qui avaient resservi ne
montraient aucun échec, et le troisième n'avait pas encore été utilisé.

## Installation

### Tous les skills avec Sno Station

Copiez ce prompt dans le chat de votre agent :

```text
Install sno.ai from GitHub.
```

Cela installe Sno Station et met en place chaque skill, avec les programmes qu'ils appellent,
pour tous les agents compatibles trouvés sur votre machine.

Ou collez cette commande dans votre terminal :

```bash
curl -fsSL https://sno.ai/install | sh
```

**Vous avez déjà Sno Station ?** Lancez `sno setup` pour installer les skills dans vos agents.
Relancez-le si vous ajoutez un autre agent plus tard.

### Installer un seul skill

Utilisez le bouton de copie sur l'un des prompts ci-dessous, puis collez-le dans le chat de votre agent.
Votre agent trouve et installe le skill ; vous n'avez rien à télécharger ni à copier vous-même.

**`peer-review`** vérifie code, plans et documents avec un relecteur d'un autre éditeur de modèles.
Il a besoin des programmes de Sno Station et d'un relecteur connecté. Le prompt vérifie ces dépendances en premier.

```text
Install only the peer-review skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
Check its dependencies and tell me what is missing before installing anything else.
```

**`less-is-more`** aide votre agent à écrire moins de code et à retirer la complexité inutile.
Il fonctionne sans Sno Station.

```text
Install only the less-is-more skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
```

**`tag-team`** met deux agents sur une même tâche : l'un construit, l'autre relit, et ils règlent
les constats entre eux. Il a besoin du programme Reach de Sno Station. Le prompt le vérifie en premier.

```text
Install only the tag-team skill from https://github.com/sno-ai/sno-station-skills
for this project. Check that `sno reach pair --help` works and tell me what is missing
before installing anything else.
```

Agents compatibles avec Sno Station : Claude Code, Codex, Cursor, Hermes Agent et OpenClaw. Chaque skill déclare
ce dont il a besoin de la part de l'agent. L'installation s'appuie sur cette déclaration pour l'installer en entier,
l'installer dans une version allégée, ou le laisser de côté quand l'agent ne peut pas l'exécuter.

Les mises à jour arrivent toutes seules : `sno` se met à jour dès qu'il trouve une version plus récente. La
liste complète des commandes se trouve dans la [référence des commandes de Sno Station](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md).

### Installer en plugin

Claude Code :

```bash
claude plugin marketplace add sno-ai/sno-station-skills
claude plugin install sno-station@sno-ai
```

Codex :

```bash
codex plugin marketplace add sno-ai/sno-station-skills
codex plugin add sno-station@sno-ai
```

`sno-station` contient tous les skills ; la plupart appellent des programmes de Sno Station, donc installez aussi Sno Station.
Pour n'avoir que les 12 skills qui tournent sans Sno Station, installez plutôt `sno-station-standalone@sno-ai`.

## Les skills

39 skills, livrés en 30 unités, rangés selon six choses qu'une équipe doit savoir faire. Une unité,
c'est un skill seul ou une petite famille qui s'installe d'un bloc. L'index complet avec les liens est
dans [skills/README.md](../../skills/README.md).

| | Catégorie | Ce que vos agents peuvent en faire |
|---|---|---|
| **J** | [Relecture et audit](#j--relecture-et-audit) | Vérifier le travail les uns des autres, et refuser de déclarer quoi que ce soit terminé tant que ce n'est pas prouvé. |
| **M** | [Construction et déploiement](#m--construction-et-déploiement) | Être opérationnels sur n'importe quelle machine en une étape, et vous dire en quelques lignes claires quand quelque chose ne va pas. |
| **S** | [Communication et passation](#s--communication-et-passation) | S'envoyer des messages, et reprendre le flambeau avec tout le contexte quand l'un doit s'arrêter. |
| **H** | [Comptes rendus et visibilité](#h--comptes-rendus-et-visibilité) | Vous montrer ce qui a été fait, ce qui a été attrapé et ce que ça a coûté. |
| **T** | [Délégation et ordres de mission](#t--délégation-et-ordres-de-mission) | Distribuer le travail avec une définition écrite de « terminé », et diriger d'autres agents. |
| **R** | [Rétrospective et amélioration](#r--rétrospective-et-amélioration) | Apprendre de leurs propres erreurs, chaque changement étant validé par vous. |

### J · Relecture et audit

*Les collègues relisent le travail des autres, et rien n'est terminé tant que l'audit n'est pas passé.*

#### [peer-review](../../skills/J-peer-review-and-audit/peer-review/) — un relecteur de l'autre éditeur, et des allers-retours jusqu'à ce que ce soit propre

- **Vraiment indépendant.** La relecture tourne dans une session neuve, sans rien de la
  conversation de l'auteur, et privilégie la CLI de l'autre éditeur. Avec une seule CLI
  installée, elle tourne quand même, dans une session neuve, et annonce dès la première ligne
  qu'il s'agit d'une relecture par le même éditeur.
- **Traque ce qui vous coûte vraiment.** Elle parcourt d'abord le chemin ordinaire, avec les
  vraies entrées que produit votre système, avant de passer une seule minute sur des cas limites
  exotiques. Perte de données, résultats faux sans bruit et parcours principaux cassés passent en
  premier ; le style n'est même pas sur la liste.
- **Chaque constat doit mériter sa place.** Chacun indique comment un vrai utilisateur y arrive,
  ce qui casse, et une tentative honnête de le réfuter. Rien de ce que dit le relecteur n'est
  supprimé ni édulcoré ; un faux positif présumé est étiqueté, pas caché.
- **Coupe avant d'ajouter.** Elle liste d'abord ce que la modification a ajouté sans que personne
  n'en ait besoin, et sépare « à corriger maintenant » de « trouvé en passant », pour qu'une
  relecture ne tourne jamais en tas de code neuf.
- **Marche aussi sur les documents.** Spécifications, plans et manifestes de migration reçoivent
  un rapport structuré : ce qui pousserait quelqu'un à livrer la mauvaise chose.

*À utiliser quand :* vous avez fini une modification, un plan ou une spec et voulez les faire vérifier avant qu'ils n'atterrissent.

#### [less-is-more](../../skills/J-peer-review-and-audit/less-is-more/) — le moins de code qui marche, et un couteau pour le reste

- **Grimpe une échelle avant d'écrire une ligne :** est-ce seulement nécessaire, est-ce déjà dans
  le dépôt, la bibliothèque standard le fait-elle, la plateforme le fait-elle, une dépendance déjà
  installée le fait-elle. Seulement ensuite, le minimum de code qui marche.
- **Taille dans ce qu'un agent a surconstruit :** interfaces à une seule implémentation, options
  de config pour des valeurs qui ne changent jamais, échafaudages « pour plus tard », contrôles
  et verrous qui bloquent le vrai travail.
- **Dépense votre budget de tests avec discernement :** le plus petit test qui prouve la
  modification, pas une suite complète lancée pour se rassurer.
- **Marche dans les deux sens tout seul :** « write » ou « fix » construit, « review » ou
  « simplify » coupe, et après avoir construit, il taille dans son propre diff avant de le rendre.

*À utiliser quand :* n'importe quelle tâche de code, ou quand vous dites « trop compliqué » ou « qu'est-ce qu'on peut supprimer ».

#### [owner-intent-audit](../../skills/J-peer-review-and-audit/owner-intent-audit/) — est-ce vraiment ce que vous vouliez dire ?

- **Vérifie le sens, pas la formulation.** Un plan peut garder tous vos mots et décrire pourtant
  un autre produit. Ce skill repère une condition devenue inconditionnelle, un exemple devenu à
  lui seul toute la limite, une interdiction qui a discrètement disparu.
- **Trouve les dettes que les agents laissent derrière eux :** du travail que personne n'a
  demandé, des documents qui ne collent plus à la réalité, des décisions que personne ne peut
  retrouver, et des « terminé » sans aucune preuve derrière.
- **Plans comme code :** documents d'exigences, conceptions, listes de tâches, plans de test, ou
  un diff écrit par un agent.

*À utiliser :* avant d'approuver un plan ou de merger le travail d'un agent.

#### [agentic-walkthrough](../../skills/J-peer-review-and-audit/agentic-walkthrough/) — tout affiche « succès », et pourtant vous avez un doute

- **Pour l'échec silencieux qu'aucun test n'attrape :** une tâche qui démarre, se termine, écrit
  une trace, passe ses propres contrôles, et ne touche à rien.
- **Se met à la place du programme :** parcourt le chemin étape par étape, à la recherche de
  chaque interrupteur, valeur par défaut et repli qui peut transformer le travail en no-op
  silencieux.
- **Oblige chaque étape à faire ses preuves,** avec une observation ciblée que seul le vrai
  fonctionnement peut produire : la ligne enregistrée, le fichier de base de données réellement
  ouvert, l'appel d'API réellement parti.

*À utiliser quand :* une exécution annonce un succès et qu'il vous faut la preuve qu'elle a fait le travail.

#### [first-principles-review](../../skills/J-peer-review-and-audit/first-principles-review/) — challenger l'idée avant qu'elle ne devienne du code

- **Se documente d'abord,** puis redéduit ce dont vous avez réellement besoin sans emprunter la
  solution proposée.
- **Classe chaque contrainte** en limite dure, préférence du propriétaire ou habitude héritée, et
  confronte chaque hypothèse porteuse aux preuves.
- **Conclut par un verdict net :** continuer, recadrer, simplifier, remplacer, découper, tester
  d'abord, ou arrêter, avec une direction recommandée et les éléments qui la renverseraient.
- **Passe le relais proprement :** un rapport écrit et un résumé structuré, prêts pour celui qui
  rédigera les exigences ensuite.

*À utiliser quand :* une idée de conception ou de produit est sur le point de se figer en plan. On le lance par son nom.

#### [e2e](../../skills/J-peer-review-and-audit/e2e/) — des tests de bout en bout qui n'échouent que pour de vraies raisons

- **`e2e-environment-preflight`** vérifie les services externes, les hôtes, les sessions de
  navigateur, les endpoints de modèles et les agents avant le premier test, pour qu'une longue
  suite n'échoue jamais sur une dépendance morte.
- **`e2e-red-triage`** prend en charge l'échec rare que les vérifications n'avaient pas pu
  prévoir. Il arrête les suppositions et coupe le résultat en ses deux moitiés (accepté ou fait,
  arrêté ou planté, vide ou illisible), puis tranche : bug produit, ou nouvelle vérification
  d'environnement.

*À utiliser quand :* vous lancez des suites de bout en bout contre de vrais services.

#### [test-writer](../../skills/J-peer-review-and-audit/test-writer/) — des tests qui peuvent vraiment passer au rouge

- **Du réel plutôt que du mock :** le vrai parseur, le vrai système de fichiers, la vraie base de
  données ou le vrai service dès que le dépôt peut les fournir ; un mock ne remplace jamais ce
  qu'on teste.
- **Chaque assertion peut échouer :** il vérifie le contenu renvoyé, l'état enregistré et les
  vrais effets de bord, pas des compteurs d'appels, et ne relâche jamais une assertion pour faire
  passer un test.
- **Lance ce qu'il a écrit, rien de plus :** la commande la plus ciblée pour le test modifié, pas
  toute la suite, et le rapport dit ce qui a tourné et ce que ça a donné.

*À utiliser quand :* vous demandez à un agent d'écrire ou de réparer des tests, des fixtures ou
des evals. Il fonctionne tout seul, sans Sno Station.

#### [cross-vendor-security-audit](../../skills/J-peer-review-and-audit/cross-vendor-security-audit/) — un audit de sécurité qui relit ce qu'il a écarté

**Trois passes de Claude ont raté un bug publié de gravité élevée. Une passe de Codex sur ce que
Claude avait écarté l'a trouvé.** Sur ce bug, chaque passe Claude supplémentaire a répété la
propre raison de Claude de l'écarter ; le second éditeur en a apporté une autre.

Nous avons audité follow-redirects 1.16.1, qui contient un bug connu
([GHSA-mrwp-f3q8-3g9p](https://github.com/advisories/GHSA-mrwp-f3q8-3g9p), gravité élevée, corrigé en 1.16.2) :
une liste d'en-têtes secrets construite dans un autre realm JavaScript est traitée comme vide, si
bien que la clé d'API de l'appelant suit une redirection vers un autre hôte.

- Claude, premier audit : ne l'a jamais vu.
- Claude, deuxième audit : l'a vu, puis l'a classé en « durcissement, pas un constat ».
- Un Claude tout neuf relisant tout ce qui avait été écarté : d'accord, « mauvais usage par l'appelant ».
- Codex, auditant seul : ne l'a jamais vu.
- **Codex relisant ce que Claude avait écarté : en désaccord, l'a suivi dans le code source et
  l'a renvoyé en validation.**

Cette dernière étape, c'est précisément ce que ce skill ajoute au skill d'audit de sécurité de
Cloudflare (utilisé sous sa licence MIT ; même audit, même niveau d'exigence sur les preuves,
mêmes validateurs, même rapport). Avant le rapport, un modèle de l'autre éditeur relit, en
lecture seule, chaque élément que l'audit a mis de côté, et doit répondre sur chacun ; tout ce
qu'il fait remonter est validé à nouveau. Si la validation le rejette encore, le rapport le liste
sous « Reviewers disagree » avec les deux raisons, et c'est vous qui tranchez.

Deux projets, trois bugs connus : une histoire, pas un taux. Sur l'autre projet, le relecteur de
l'un comme de l'autre éditeur a retrouvé le bug. Quand le premier audit de Claude n'avait jamais
regardé le bug, la relecture de cet audit ne l'a pas trouvé non plus.

*À utiliser quand :* vous voulez un audit de sécurité complet d'une base de code. Avec Sno
Station, il choisit le relecteur de l'autre éditeur qui a encore du quota ; sans, il appelle
Codex depuis Claude Code ou Claude Code depuis Codex, et le signale quand un seul éditeur était
disponible.

### M · Construction et déploiement

*Équiper l'équipe sur n'importe quel poste en une étape, construire ce dont le travail a besoin, puis le déployer sur chaque machine.*

L'installation elle-même, c'est la commande `sno setup`, pas un skill. Deux de ces skills
gardent la machine en bonne santé et rendent la commande `sno` facile à piloter pour vos agents ;
les autres écrivent le code : l'un le confie à Codex, quatre l'écrivent en Shell, TypeScript,
Python ou Rust.

#### [medic](../../skills/M-build-and-rollout/medic/) — mon équipe d'agents va-t-elle bien ? Une ligne par réponse.

- **Vérifie tout ce dont une équipe a besoin** en une dizaine de secondes : outils installés,
  skills installés, commandes des skills exécutables, hooks configurés, messagerie active, quota
  des deux éditeurs lisible, espace temporaire disponible.
- **Chaque problème arrive avec son remède :** `WARN` ou `FAIL`, ce qui ne va pas, et la commande
  exacte qui le corrige.
- **Lit, ne touche à rien.** Il n'installe, ne répare, ne démarre et n'arrête rien. C'est vous qui
  décidez quoi corriger.

*À utiliser :* sur une nouvelle machine, quand les agents n'arrivent plus à se joindre, ou quand
une longue exécution refuse de démarrer.

#### [sno-cli](../../skills/M-build-and-rollout/sno-cli/) — votre agent pilote `sno` correctement du premier coup

- **Jamais obsolète :** l'agent lit les commandes et options exactes directement dans le `sno`
  installé, pas de mémoire.
- **Une carte des tâches et des recettes** pour l'installation, la mise à jour, les contrôles de
  santé, les comptes, les skills et la boucle nocturne.
- **Vos choix restent les vôtres :** il manie l'outil, il ne décide pas de vos réglages à votre place.

*À utiliser quand :* vous demandez à un agent d'installer, mettre à jour, vérifier ou configurer Sno.

#### [codex-coder](../../skills/M-build-and-rollout/codex-coder/) — Claude planifie, Codex écrit le code

- **Une session, deux éditeurs :** Claude Code garde le plan et la conversation et lance une
  simple exécution `codex exec` pour le code, pour que le modèle coûteux ne soit pas celui qui
  tape.
- **Choisit le langage à votre place :** Shell, TypeScript, Python ou Rust, selon les fichiers
  que touche la tâche ; si vous avez votre propre skill de langage installé, c'est lui qui sert.
- **Une exécution bloquée est repérée :** Claude Code est tenu au courant de l'avancement pendant
  l'exécution, et une exécution qui n'a rien écrit depuis 15 minutes est tuée puis relancée une fois.

*À utiliser quand :* votre quota Claude s'épuise en plein codage, ou quand vous voulez que Codex
écrive ce que Claude a planifié. Côté Claude Code, il a besoin du `heartbeat` de Sno Station.

#### [shellscript-coder](../../skills/M-build-and-rollout/shellscript-coder/), [ts-coder](../../skills/M-build-and-rollout/ts-coder/), [python-coder](../../skills/M-build-and-rollout/python-coder/), [rust-coder](../../skills/M-build-and-rollout/rust-coder/) — du code qui colle au dépôt où il atterrit

- **Lit avant d'écrire :** le runtime, les versions, les helpers, les appelants et les tests du
  dépôt passent en premier, pour que le nouveau code ressemble au code qui l'entoure.
- **Petit, exprès :** pas de shims de compatibilité, pas d'options que personne n'a demandées,
  pas de helper qui existe déjà deux fichiers plus loin.
- **Terminé veut dire qu'une commande est passée :** chaque affirmation du rapport renvoie à une
  vérification réellement exécutée dans votre dépôt ; il ne déclare jamais terminé par-dessus une
  vérification qui échoue.

*À utiliser quand :* vous voulez qu'un agent écrive ou modifie du code de production dans l'un de
ces quatre langages. Ils fonctionnent seuls, sans Sno Station, et `codex-coder` choisit le bon
pour chaque tâche.

### S · Communication et passation

*On se parle via une boîte de réception partagée, et quand l'un est absent, l'autre reprend avec tout le contexte.*

Ces skills tournent sur Sno Reach, la couche de messagerie qu'installe Sno Station : chaque agent
reçoit une adresse, dépose des messages persistants dans les boîtes de réception des autres
agents, et peut réveiller un autre agent pour qu'il les lise. Pas de démon, pas de serveur.

#### [handoff](../../skills/S-communication-and-handoff/handoff/) — passer une tâche sans rien perdre en route

- **Capture tout l'état :** ce qui est fait, ce qui est à moitié fait, les modifications non
  commitées, les décisions que vous avez déjà prises, et ce qui est hors limites.
- **Le receveur n'écrit rien tant que la libération n'est pas vérifiée,** pour que deux agents ne
  modifient jamais le même travail en même temps.
- **L'émetteur s'en va vraiment.** Après la libération, il s'arrête ; pas de second propriétaire
  qui traîne dans les parages.
- **Fonctionne même quand l'émetteur est déjà parti** (quota refusé, plantage, fenêtre fermée) :
  le relevé d'avancement de `sno handoff-checkpoint` permet à un agent tout frais de reprendre à
  la première tâche non terminée.

*À utiliser quand :* un agent doit confier sa tâche à un autre.

#### [rotate-agent](../../skills/S-communication-and-handoff/rotate-agent/) — ne plus jamais perdre une longue exécution à cause d'une limite de quota

- **Agit tant que l'émetteur est encore en vie.** Il surveille le quota restant toutes les
  quelques minutes et passe la main à un seuil, pas après le refus, quand il est trop tard pour
  rédiger une consigne.
- **Dans les deux sens :** de Codex vers Claude Code, ou de Claude Code vers Codex.
- **Borné :** il se déclenche une seule fois, et vous pouvez limiter la durée de la surveillance.
- **Un filet pour les fenêtres manquées :** si la fenêtre a été ratée, `sno rotate-agent-resume`
  lance le remplaçant à partir du relevé d'avancement sur disque.

*À utiliser quand :* une longue exécution doit aller au bout même si le quota d'un éditeur
s'épuise. Il faut les deux CLI connectées, et tmux.

#### [subscription-quota-check](../../skills/S-communication-and-handoff/subscription-quota-check/) — combien de quota il reste, sans en dépenser

- **Met fin à la pire habitude :** découvrir qu'on n'a plus de quota en faisant un vrai appel et
  en lisant l'erreur.
- **Lit Claude Code et Codex ensemble** en huit secondes environ, et vous dit quand le quota se
  réinitialise.
- **Honnête sur les chiffres périmés :** il vérifie si la valeur est actuelle ou seulement la
  dernière connue, et le dit.
- **N'interroge jamais de lui-même,** donc ne s'attire jamais de limite de débit à lui.

*À utiliser quand :* vous le demandez, ou juste après qu'un éditeur a refusé du travail.

#### [heartbeat](../../skills/S-communication-and-handoff/heartbeat/) — des points d'avancement sur les longues exécutions, livrés dans la conversation

- **Deux formes :** un compte rendu toutes les N minutes (entraînement, long build, file de
  génération), ou une veille jusqu'à ce que quelque chose se termine.
- **Une tâche à heure fixe :** donnez à l'agent une date ou une heure, une fois ou en
  récurrence. Il note la tâche, et un agent démarre à cette heure-là même après la fermeture de
  la conversation.
- **Les relevés arrivent là où vous êtes :** chacun atterrit dans la conversation de l'agent, pas
  dans un journal que personne ne lit.
- **Difficile à mal utiliser :** les intervalles sont en minutes, et un nombre qui ressemble à des
  secondes est refusé plutôt que de réveiller discrètement votre agent toutes les quelques secondes.

*À utiliser quand :* quelque chose de long tourne sans surveillance et vous voulez des
nouvelles, ou qu'une tâche doit avoir lieu à un moment où vous ne serez pas là.

#### [reach](../../skills/S-communication-and-handoff/reach/) — les agents se parlent

- **Lance un agent Claude Code ou Codex** avec sa propre adresse et son propre dossier de travail.
- **Envoie du travail et lit les réponses** via des messages persistants, ou parle tout de suite
  à un agent en cours d'exécution.
- **Les messages ne confèrent aucune autorité supplémentaire :** un message n'élargit jamais la
  tâche que vous avez confiée.

*À utiliser quand :* un agent doit en contacter, en lancer ou en attendre un autre.

#### [join-talk](../../skills/S-communication-and-handoff/join-talk/) — rendre n'importe quel agent joignable en une commande

- **Une seule ligne en sortie :** `joined <address>`. Donnez cette adresse aux autres agents et
  ils pourront joindre ce terminal.
- **Sans risque à répéter :** le relancer depuis le même terminal ne change rien.
- **Des refus clairs :** quand ça ne peut pas marcher, il dit exactement pourquoi.

*À utiliser quand :* vous avez ouvert un agent à la main et voulez que les autres puissent le joindre.

#### [tag-team](../../skills/S-communication-and-handoff/tag-team/) — deux agents sur une tâche, l'un construit, l'autre relit

- **Une commande :** `sno reach pair "the task"` lance les deux agents dans le dossier courant,
  chacun dans une fenêtre tmux que vous pouvez ouvrir pour suivre.
- **Débattu avant de vous arriver.** Le relecteur lit le résultat et les fichiers modifiés, et
  répond avec des défauts concrets ou un « aucun défaut » explicite ; les deux continuent de
  s'échanger correctifs et relectures entre eux, et votre agent consulte le relecteur avant de
  déclarer que c'est propre.
- **Vous dit quel genre de relecture vous avez eu.** Connecté à deux éditeurs, la relecture vient
  de l'autre. Connecté à un seul, la paire tourne quand même et vous indique que la relecture est
  restée chez celui-là.
- **Ne déclare pas propre trop tôt.** Une première relecture avec des constats est signalée comme
  ouverte ; pas de troisième relecteur, et pas de seconde paire parce que la première relecture
  n'était pas encore arrivée.

*À utiliser quand :* une tâche mérite un deuxième avis et que vous ne voulez pas faire la navette
entre les agents.

### H · Comptes rendus et visibilité

*Chacun voit ce qui a été fait, qui a attrapé quoi, qui a couvert qui, et ce qui est en cours.*

#### [away-brief](../../skills/H-reporting-and-visibility/away-brief/) — une page à votre retour

- **Quatre sections, 60 lignes au plus :** Fait, Bloqué, Vous attend, Dépense.
- **Ce qui vous attend n'est jamais repoussé hors de la page** par une longue liste de travail terminé.
- **« Fait » ne désigne que du réel :** dans git, dans un ordre de mission livré, ou dans un relevé
  d'avancement terminé. Pas ce qu'un agent a affirmé.
- **Montre ce que la nuit a coûté :** lancez `sno away-brief mark` avant de partir, et la page
  suivante indique le quota dépensé depuis.

*À utiliser :* au réveil, après une réunion ou après une longue exécution sans surveillance.

#### [catch-report](../../skills/H-reporting-and-visibility/catch-report/) — le deuxième agent vaut-il le coup ? Voici les chiffres.

- **Deux décomptes, côte à côte :** les problèmes que l'autre modèle a attrapés en relecture, et
  les moments où un agent a rattrapé sa propre erreur.
- **Jamais gonflés :** les deux restent séparés, jamais additionnés, et quand une partie n'a pas
  pu être mesurée, il le dit au lieu d'afficher zéro.
- **Cite les plus belles prises** par leur titre, à partir des comptes rendus de relecture déjà
  présents sur votre machine.

*À utiliser quand :* vous voulez les résultats de relecture de la semaine, ou devez justifier de faire tourner deux agents.

#### [agentic-time-estimate](../../skills/H-reporting-and-visibility/agentic-time-estimate/) — de vraies estimations pour le travail des agents

- **Temps réel d'agent, pas temps de développeur humain :** combien de temps cela prendra à un
  agent, et combien de temps il reste à la tâche en cours, mesuré avant d'être deviné.
- **Des heures fiables :** chaque heure qu'on vous affiche vient de `sno report-time`, dans votre
  fuseau horaire avec l'UTC à côté.

*À utiliser quand :* vous demandez « combien de temps ? » ou « ce sera fini quand ? »

### T · Délégation et ordres de mission

*Un lead délègue le travail sous forme d'ordres de mission, et décide qui prend chaque tâche.*

#### [charter](../../skills/T-delegation-and-work-orders/charter/) — un fichier qui dit ce que « terminé » veut dire

- **Garde vos mots.** Il n'invente jamais une décision, un fait ou une exigence, et ne pose une
  question, une à la fois, que lorsque la réponse changerait le résultat.
- **Des critères de réussite exécutables :** chacun dit ce qui sera observé, où et comment, et se
  tranche en réussi ou échoué.
- **Pas de cérémonie :** rien n'entre tant que personne ne peut nommer l'échec qu'il empêche.
- **Tout type de projet :** logiciel, documents, campagnes, recherche, opérations.

*À utiliser quand :* un travail a besoin d'une consigne écrite avant que quelqu'un d'autre s'en charge.

#### [deliver](../../skills/T-delegation-and-work-orders/deliver/) — mener une charte jusqu'à un résultat prouvé

- **Les critères de la charte sont la définition de « terminé »,** et rien d'autre.
- **Chaque critère prouvé par une vraie exécution enregistrée,** suivi avec `sno deliver-proof`.
- **Une relecture indépendante,** puis une clôture honnête : ce qui est passé, ce qui ne l'est pas, et pourquoi.
- **Reprend là où un autre s'est arrêté :** si un agent précédent a laissé un relevé
  d'avancement, il continue à partir de la prochaine étape non terminée au lieu de tout reprendre
  à zéro.

*À utiliser quand :* une charte est publiée et que quelqu'un doit s'en charger.

#### [pl](../../skills/T-delegation-and-work-orders/pl/) — un agent chef de projet (Project Lead) pour un chantier

- **Pilote jusqu'à quatre agents exécutants,** une charte chacun, en série ou en parallèle.
- **Une famille de cinq skills de plus :** `pl-dispatch` ouvre et planifie le travail, `pl-watch`
  supervise les agents en cours de route, `pl-audit` vérifie la recette avant toute clôture,
  `pl-env` répare l'environnement dans lequel le travail tourne, et `pl-analyze` rédige l'analyse
  des causes profondes quand quelque chose tourne mal.

*À utiliser quand :* un projet a besoin de plusieurs agents sous un même lead. On le lance par son nom.

#### [cos](../../skills/T-delegation-and-work-orders/cos/) — un chef de cabinet (Chief of Staff) : le seul agent à qui vous parlez

- **Une seule conversation pour vous,** dans votre langue. Il coordonne d'un à trois chefs de
  projet en parallèle et ne vous remonte que les décisions difficiles : argent, cap, lignes rouges.
- **Une famille de trois skills de plus :** `cos-watch` garde chaque chef de projet en vie et dans
  les temps, `cos-review` passe en revue les décisions de la nuit en une seule fois à votre
  retour, et `cos-evolve` transforme les ratés de management qui se répètent en règles appliquées.

*À utiliser quand :* vous menez plusieurs chantiers et voulez un interlocuteur unique. On le lance par son nom.

### R · Rétrospective et amélioration

*L'équipe revient sur son propre travail et transforme les leçons en règles et en meilleures pratiques.*

#### [rem-reflect](../../skills/R-recursive-self-improvement/rem-reflect/) — la boucle nocturne : vos agents apprennent de leurs propres sessions

- **Une fois par jour,** il lit les sessions d'agents de cette machine (Claude Code, Codex, Cursor, Hermes Agent et OpenClaw), repère les échecs et
  les corrections qui reviennent, et en tire des leçons et des propositions de modification de skills.
- **Vous validez tout :** `sno rem-reflect accept`, `reject` ou `tbd` pour chacune. Sans votre
  accept, rien ne change.
- **Les leçons reviennent quand elles comptent :** une leçon acceptée est montrée à l'agent au
  début de la session suivante, pour ce projet ou pour tous.
- **Vous choisissez ce qui quitte la machine.** En mode `local-first`, rien n'est envoyé à Sno ;
  quelques sessions de la nuit partent uniquement vers votre propre compte Claude Code ou Codex
  pour rédiger les leçons. Dans les deux autres modes, à leur niveau de partage par défaut, il envoie le texte des sessions (secrets courants masqués au préalable, au mieux)
  et vos skills installés vers le cloud de Sno, pour des jugements plus solides. Coupez l'envoi à tout
  moment avec `sno station consent off`. Le skill liste exactement ce qu'il lit et ce qu'il envoie.

Les skills de famille `pl-analyze` (analyse d'incident pour le chef de projet) et `cos-evolve`
(les échecs répétés transformés en règles) relèvent aussi de cette catégorie ; ils sont livrés avec `pl` et `cos`.

*À utiliser :* en permanence, une fois que `sno setup` a armé l'exécution quotidienne.

## La confiance n'exclut pas le contrôle

Chaque unité d'une version a passé les mêmes contrôles avant d'être publiée :

1. le dépôt contient bien son `LICENSE` et son `NOTICE` ;
2. l'unité est copiée en entier, avec les membres de sa famille et ses différences par agent intactes ;
3. rien de personnel ne subsiste : aucun chemin personnel, nom de propriétaire, hôte interne ou
   modèle codé en dur, et aucun caractère chinois, japonais ou coréen ;
4. l'en-tête de chaque skill se parse, et sa déclaration de ce dont il a besoin de la part de
   l'agent est valide ;
5. les autotests propres à chaque skill passent sur cette copie propre, pas sur la machine de l'auteur ;
6. un tampon, `PUBLISHED.json`, est écrit en dernier, avec le nombre d'autotests et les
   empreintes du contrat et du contenu.

Un skill qui échoue à un contrôle n'est pas publié. Le tampon est écrit par le build de version,
jamais à la main. Tout le texte des skills est en anglais, et votre agent le suit dans la langue,
quelle qu'elle soit, dans laquelle vous lui parlez.

## Ces skills et Sno Station

Les skills, ce sont les réflexes. [Sno Station](https://github.com/sno-ai/sno-station), c'est le poste de travail qui les fait tourner :
la mémoire qu'ils partagent, la veille de quota qui déclenche une passation, les messages entre
agents et la tâche nocturne qui rédige les leçons. Installez Sno Station, et tous les skills d'ici viennent avec.

| Vous voulez | C'est par ici |
|---|---|
| Le poste de travail complet, et ce qui tourne sur quel agent aujourd'hui | [sno-ai/sno-station](https://github.com/sno-ai/sno-station#what-you-can-use-today-and-where-it-stops) |
| Des agents qui s'envoient des messages, d'une fenêtre à l'autre et d'un ordinateur à l'autre | [Sno Reach](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md) |
| Du travail qui démarre à l'heure que vous fixez | [Finish](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md) |
| Chaque commande `sno` qu'appellent les skills | [Référence des commandes](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md) |
| Les données brutes derrière les histoires ci-dessus | [Dossier de preuves](https://github.com/sno-ai/sno-station/tree/main/docs/evidence) |
| Poser une question, ou montrer ce que vous avez construit | [Discussions](https://github.com/sno-ai/sno-station-skills/discussions) |
| Une petite première contribution | [Good first issues](https://github.com/sno-ai/sno-station-skills/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) et [CONTRIBUTING.md](../../CONTRIBUTING.md) |

**Et une étoile pour chacun des deux dépôts.** Sno Station, nous le construisons avec ces skills.
Ce que nos propres nuits de travail nous apprennent atterrit ici, version après version.

## Pour les auteurs de skills

### Arborescence

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

Les codes de catégorie sont fixes, dans cet ordre : J M S H T R. On les retrouve dans les noms de
répertoires et dans `registry.yaml`.

### Déclarer ce dont un skill a besoin

Chaque `SKILL.md` commence par un bloc `requires:`. `sno setup` le lit pour décider, agent par
agent, s'il installe le skill :

```yaml
requires:
  programs:
    - {name: reach, min_version: "2.0"}                          # Sno Station programs the skill calls
  harness:
    - {slot: 4.shell, need: required}        # what the agent itself must be able to do
```

- **programs** désigne les programmes de Sno Station installés à côté des skills et lancés sous la
  forme `sno <name>` : `reach`, `heartbeat`, `subscription-quota-check`, `report-time`.
- **min_version** est la version minimale du programme Sno Station nommé que le skill exige.
- **slots** nomme une capacité de l'agent : `4.shell` (exécuter des commandes shell),
  `4.file-read-write` (lire et écrire des fichiers), `4.background-processes` (lancer une commande
  en arrière-plan), `2.pre-turn-context-injection` (ajouter du texte au contexte de l'agent avant
  chaque tour) et `3.reader-to-agent-delivery` (la sortie d'un lecteur en arrière-plan parvient à l'agent).
- **need** vaut `required` (un agent sans ce slot ne reçoit pas le skill), `preferred` (le skill
  est installé et fonctionne en mode réduit) ou `optional` (simple confort).

## Licence

Apache-2.0. Open source, de bout en bout. Voir [LICENSE](../../LICENSE).
