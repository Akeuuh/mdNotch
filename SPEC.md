# mdNotch — Spécification

App macOS qui vit sous la notch : glisser-déposer un document, il est converti en Markdown, copié dans le presse-papier et enregistré en fichier `.md`. Du texte riche collé (⌘⇧V) est converti de la même façon, sans fichier. Zéro dépendance à installer pour l'utilisateur.

## 1. Plateforme & stack

| Sujet | Décision |
|---|---|
| OS minimum | macOS 14 (Sonoma) |
| Architecture | Apple Silicon uniquement (arm64) |
| UI | SwiftUI + AppKit (fenêtre notch sans bordure) |
| Type d'app | Agent (`LSUIElement`) — pas d'icône Dock |
| Lancement au démarrage | Login item, **activé par défaut**, désactivable dans les réglages |
| Moteur de conversion | [microsoft/markitdown](https://github.com/microsoft/markitdown) gelé en binaire autonome via **PyInstaller**, embarqué dans `Resources/`, invoqué par `Process` depuis Swift |
| Réseau | Aucun. 100 % offline |

### Pourquoi PyInstaller

markitdown est une lib Python. Contrainte « zéro dépendance » ⇒ on embarque le runtime Python gelé dans le `.app`. Coût assumé : bundle ~150–300 Mo. Alternatives rejetées : réécriture native Swift (couverture de formats trop faible), Python système requis (casse la contrainte).

## 2. Comportement notch

- **Au repos : invisible.** Aucun pixel volé.
- **Drag de fichier vers le haut-centre de l'écran** → zone de drop s'étend sous la notch (animation).
- **Mac sans notch** (iMac, Mac mini, écran externe) : même comportement, ancré haut-centre — la notch n'est qu'un ancrage visuel.
- **Survol souris de la zone notch** → petit engrenage apparaît (accès réglages).
- **Drag d'une sélection de texte riche** (navigateur, traitement de texte) → même zone, même conversion. Le texte **brut** est volontairement ignoré comme déclencheur : il n'a rien à convertir, et la zone sortirait à chaque déplacement de phrase dans un éditeur.
- **Raccourci clavier (⌘⇧V par défaut, configurable) ou « Convert clipboard »** (menu barre de menus) → convertit le presse-papier depuis n'importe où, sans drag. La zone sort d'elle-même pour montrer le spinner puis le résultat.

### États visuels

| État | Rendu |
|---|---|
| Repos | Rien |
| Drag à proximité | Zone de drop étendue sous la notch |
| Conversion en cours | Zone ouverte + spinner + **effet glow** autour de la zone |
| Succès | Coche verte + « Copied » → auto-repli après ~2 s |
| Erreur | Croix rouge + message court (ex. « Unsupported format », « Conversion failed: rapport.pdf ») → repli au clic ou après ~4 s |

Pas de notification système, pas de fenêtre classique. Tout se joue dans la zone notch.

## 3. Formats

### Supportés (pur Python, offline)

PDF, DOCX, PPTX, XLSX, XLS, HTML, CSV, JSON, XML, EPUB, ZIP.

- **ZIP** : comportement markitdown par défaut — extraction récursive, un seul `.md` concaténé par archive.

### Rejetés → erreur « Unsupported format »

- **Images** : markitdown seul n'extrait que l'EXIF (via binaire externe `exiftool`) ; la description du contenu exige une clé LLM. Résultat quasi vide sans config ⇒ hors périmètre.
- **Audio** : transcription via API réseau (Google Speech) + `ffmpeg` requis ⇒ casse offline/zéro dépendance.
- Tout autre type non listé.

Extension possible plus tard (v2) si besoin.

## 4. Sortie

Chaque drop produit **deux choses** :

1. **Fichiers `.md`** — un par fichier source.
   - Destination, réglable dans les settings :
     - **« À côté du fichier source »** (défaut)
     - « Dossier fixe » choisi via sélecteur de dossier
   - Conflit de nom (`rapport.md` existe) → suffixe auto `rapport-1.md`, `rapport-2.md`… Jamais d'écrasement, jamais de dialogue.
2. **Presse-papier** — contenu markdown en **texte brut** (pas de fichier).
   - Plusieurs fichiers → concaténation avec séparateur `# nom-du-fichier` avant chaque contenu.

### Texte collé

Un texte collé n'a pas de dossier d'origine : il ne produit **que** le presse-papier, jamais de fichier `.md`. Le réglage de destination ne s'applique pas.

- **HTML** (copie depuis un navigateur, Notion, Google Docs) → converti par markitdown : titres, listes, tableaux et liens survivent.
- **RTF** (Pages, TextEdit, Word) → ré-encodé en HTML avant conversion, pour la même raison.
- **Texte brut** → déjà son propre markdown, recopié tel quel sans invoquer le convertisseur.

Le presse-papier est la source *et* la destination : la conversion se fait sur place et le texte riche d'origine est perdu. Pas d'undo.

### Multi-drop

Plusieurs fichiers acceptés. Conversion de chacun ; un échec n'empêche pas les autres. Les réussites vont dans le presse-papier + fichiers ; les échecs sont signalés dans la zone notch.

### Limites

- **Timeout : 60 s par fichier** → erreur « conversion trop longue » (le fichier est compté en échec, les autres continuent).

## 5. Accès & réglages

Deux points d'entrée :

- **Icône barre de menus** (discrète) : Convert clipboard, Réglages, Launch at login, Quit.
- **Engrenage au survol** de la zone notch → ouvre les réglages.

### Contenu des réglages

- Destination des `.md` : à côté du source / dossier fixe (+ sélecteur).
- Zone de dépôt : encoche (défaut) ou l'un des quatre coins de l'écran, pour
  les setups où une autre app occupe déjà l'encoche. La zone reste collée aux
  bords qu'elle touche ; seuls ses coins tournés vers l'intérieur sont arrondis.
- Écrans actifs : tous les écrans (défaut), l'écran principal uniquement, ou un
  écran précis. L'écran principal est celui qui porte la barre de menus
  (origine du repère global), pas `NSScreen.main` qui suit la fenêtre active.
  Un écran épinglé est retrouvé par `CGDirectDisplayID` puis, si l'ID a changé
  au rebranchement, par son nom ; s'il est déconnecté, la zone retombe sur
  l'écran principal plutôt que de disparaître.
- Raccourci de conversion du presse-papier : **enregistreur** (clic dans le champ
  puis frappe des touches ; ⌫ efface, ⎋ annule). Défaut ⌘⇧V, effaçable.
  Configurable parce que la combinaison peut déjà appartenir à une autre app —
  et ce conflit est **indétectable** de notre côté : quand deux apps enregistrent
  la même combinaison, la première inscrite gagne et la seconde s'inscrit sans
  erreur mais ne se déclenche jamais. L'item de la barre de menus reste
  disponible dans tous les cas, et affiche le raccourci configuré.
  Au moins un modificateur parmi ⌘/⌃/⌥ est exigé : ⇧ seul ferait avaler une
  frappe ordinaire partout. Le raccourci passe par Carbon
  (`RegisterEventHotKey`) : aucune permission Accessibilité demandée. Le code
  touche est **physique**, donc son libellé est relu dans la disposition clavier
  courante (`UCKeyTranslate`) à chaque affichage, jamais stocké.
- Launch at login (on/off, défaut on).

## 6. Localisation

UI et messages d'erreur localisés **anglais + français** (String Catalogs). Anglais = langue de base.

## 7. Distribution

- **Developer ID + notarisation** (compte Apple Developer dispo).
- Livrable : **DMG** téléchargeable.
- **Pas de sandbox** (nécessaire pour écrire le `.md` à côté du source + binaire Python embarqué). Donc pas d'App Store.
- Attention build : le gel PyInstaller produit des centaines de dylibs — toutes doivent être signées pour la notarisation.

## 8. Projet

- Repo git initialisé + repo GitHub perso.
- Nom : **mdNotch**.

## Hors périmètre (v1)

- Images et audio (voir §3).
- URLs (YouTube, pages web).
- Clé API / features LLM.
- Support Intel.
- App Store.
