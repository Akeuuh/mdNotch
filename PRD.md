# mdNotch — PRD

## Problem Statement

Convertir un document (PDF, Word, Excel…) en Markdown pour le coller dans un chat LLM, des notes ou un éditeur demande aujourd'hui d'installer des outils en ligne de commande, un environnement Python et des dépendances, puis de jongler entre terminal, fichiers intermédiaires et copier-coller. Pour un geste aussi fréquent que « je veux ce document en Markdown, maintenant », la friction est disproportionnée — surtout pour un utilisateur non technique qui ne peut ou ne veut rien installer d'autre qu'une app.

## Solution

Une app macOS invisible au repos qui vit sous la notch. L'utilisateur glisse un ou plusieurs documents vers le haut de l'écran : une zone de drop s'étend sous la notch, convertit chaque document en Markdown, place le texte dans le presse-papier prêt à coller, et enregistre un fichier `.md` par document. Une coche verte confirme, une croix rouge signale les échecs. Aucune dépendance à installer, aucun réseau requis, aucune configuration obligatoire.

## User Stories

1. En tant qu'utilisateur Mac, je veux glisser un PDF sur la notch et obtenir son contenu en Markdown dans mon presse-papier, afin de le coller immédiatement dans un chat LLM ou mes notes.
2. En tant qu'utilisateur, je veux que la conversion produise aussi un fichier `.md` par document déposé, afin de garder une trace réutilisable de la conversion.
3. En tant qu'utilisateur, je veux déposer des fichiers DOCX, PPTX, XLSX/XLS, HTML, CSV, JSON, XML, EPUB ou ZIP et obtenir le même résultat qu'avec un PDF, afin de ne pas avoir à me demander quel outil couvre quel format.
4. En tant qu'utilisateur, je veux qu'une archive ZIP soit convertie récursivement en un seul `.md` concaténé, afin de traiter un lot de documents d'un seul geste.
5. En tant qu'utilisateur, je veux déposer plusieurs fichiers d'un coup et obtenir un `.md` par fichier plus un presse-papier concaténé (séparé par le nom de chaque fichier), afin de compiler plusieurs sources en un seul collage.
6. En tant qu'utilisateur, je veux qu'un fichier en échec n'empêche pas la conversion des autres fichiers du même drop, afin de ne pas perdre le travail du lot entier pour un fichier corrompu.
7. En tant qu'utilisateur, je veux une erreur claire « Unsupported format » quand je dépose une image, un audio ou tout format non couvert, afin de comprendre immédiatement pourquoi rien n'a été copié.
8. En tant qu'utilisateur, je veux qu'une conversion qui dépasse 60 secondes soit interrompue avec une erreur explicite, afin que l'app ne reste jamais bloquée sur un fichier pathologique.
9. En tant qu'utilisateur, je veux que l'app soit totalement invisible au repos, afin qu'elle ne vole aucun pixel de mon écran.
10. En tant qu'utilisateur, je veux que la zone de drop apparaisse dès que je traîne un fichier vers le haut-centre de l'écran, afin de découvrir naturellement où déposer.
11. En tant qu'utilisateur, je veux un retour visuel pendant la conversion (spinner + glow autour de la zone), afin de savoir que le travail est en cours.
12. En tant qu'utilisateur, je veux une coche verte « Copied » qui se replie seule après ~2 s au succès, afin d'avoir confirmation sans avoir à cliquer.
13. En tant qu'utilisateur, je veux une croix rouge avec un message court nommant le fichier en échec, qui se replie au clic ou après ~4 s, afin d'identifier le problème sans fenêtre ni notification système.
14. En tant qu'utilisateur d'un Mac sans notch (iMac, Mac mini, écran externe), je veux le même comportement ancré en haut-centre de l'écran, afin de profiter de l'app quel que soit mon matériel.
15. En tant qu'utilisateur, je veux que le `.md` soit enregistré par défaut à côté du fichier source, afin de retrouver la conversion là où vit le document.
16. En tant qu'utilisateur, je veux pouvoir choisir dans les réglages un dossier fixe de destination, afin de centraliser toutes mes conversions au même endroit.
17. En tant qu'utilisateur, je veux qu'un conflit de nom produise un suffixe automatique (`rapport-1.md`) sans dialogue ni écrasement, afin de ne jamais perdre un fichier existant ni casser mon geste.
18. En tant qu'utilisateur, je veux une icône discrète dans la barre de menus (Réglages, Launch at login, Quit), afin de toujours pouvoir configurer ou quitter l'app.
19. En tant qu'utilisateur, je veux un engrenage qui apparaît au survol de la zone notch, afin d'accéder aux réglages depuis le lieu même où j'utilise l'app.
20. En tant qu'utilisateur, je veux que l'app se lance au démarrage par défaut (désactivable), afin qu'elle soit toujours prête sans y penser.
21. En tant qu'utilisateur non technique, je veux installer l'app en glissant un `.app` depuis un DMG, sans Python, Homebrew ni terminal, afin de l'utiliser immédiatement.
22. En tant qu'utilisateur, je veux que l'app fonctionne entièrement hors ligne, afin que mes documents ne quittent jamais ma machine.
23. En tant qu'utilisateur macOS, je veux une app signée Developer ID et notarisée, afin de l'ouvrir sans avertissement Gatekeeper.
24. En tant qu'utilisateur francophone ou anglophone, je veux l'interface et les messages d'erreur dans ma langue, afin de comprendre chaque retour de l'app.

## Implementation Decisions

- **Moteur de conversion** : [microsoft/markitdown](https://github.com/microsoft/markitdown) gelé en binaire autonome via PyInstaller, embarqué dans les ressources de l'app, invoqué en sous-processus depuis Swift. Coût assumé : bundle ~150–300 Mo. Alternatives rejetées : réécriture native Swift (couverture de formats trop faible), Python système requis (casse la contrainte zéro dépendance).
- **Plateforme** : macOS 14+, Apple Silicon uniquement (arm64). SwiftUI + AppKit pour la fenêtre notch sans bordure. App agent (`LSUIElement`), pas d'icône Dock. Login item activé par défaut.
- **Architecture en deux modules** :
  - `ConversionPipeline` : orchestrateur. Entrée = liste d'URLs de fichiers + réglages (mode destination). Sortie = résultat par fichier (markdown produit, chemin `.md` écrit, ou erreur typée) + payload presse-papier concaténé. Porte tout le comportement observable : gating des formats, nommage/suffixe, concaténation, échecs partiels, timeout 60 s/fichier.
  - `MarkdownConverter` (protocole) : frontière vers le binaire markitdown. Impl réelle = sous-processus ; substituable par un fake en test.
  - UI notch = couche fine au-dessus du pipeline, sans logique métier.
- **Formats acceptés** : PDF, DOCX, PPTX, XLSX, XLS, HTML, CSV, JSON, XML, EPUB, ZIP (récursif, un `.md` concaténé par archive). Tout le reste → erreur « Unsupported format ». Images exclues (EXIF seul via binaire externe, description exigerait une clé LLM) ; audio exclu (API réseau + ffmpeg requis).
- **Sortie** : un `.md` par fichier source (à côté du source par défaut, ou dossier fixe configurable ; conflit → suffixe `-1`, `-2`, jamais d'écrasement) + presse-papier en texte brut (concaténation avec séparateur `# nom-du-fichier` si plusieurs).
- **Distribution** : Developer ID + notarisation, DMG. Pas de sandbox (écriture à côté du source + binaire embarqué). Pas d'App Store. Toutes les dylibs du gel PyInstaller doivent être signées.
- **Localisation** : anglais (base) + français, via String Catalogs.
- **Réseau** : aucun appel réseau, jamais.

## Testing Decisions

- Un bon test observe le **comportement externe** au seam, jamais l'implémentation : on donne des URLs et des réglages au pipeline, on vérifie les résultats retournés, les fichiers écrits et le payload presse-papier — pas les appels internes.
- **Seam principal — `ConversionPipeline`** (tests unitaires, converter fake en mémoire) : gating des formats, nommage et suffixes en cas de conflit, concaténation multi-fichiers, échecs partiels d'un lot, timeout. Le fake évite le binaire de 300 Mo à chaque test.
- **Seam secondaire — `MarkdownConverter`** (tests d'intégration, vrai binaire gelé) : un fichier échantillon par format supporté + un format rejeté. Lot petit et lent, exécuté séparément.
- **UI notch non testée automatiquement** : états visuels, glow, animations = vérification manuelle. Couche volontairement fine.
- Prior art : aucun (greenfield) — ces tests fondent les conventions du projet.

## Out of Scope

- Images et audio (v2 possible : exiftool/ffmpeg embarqués, clé LLM optionnelle).
- URLs (YouTube, pages web).
- Toute feature nécessitant une clé API ou le réseau.
- Support Intel.
- App Store / sandbox.

## Further Notes

- La notch est une zone morte : l'app affiche une fenêtre sans bordure **sous** la notch, qui n'est qu'un ancrage visuel — d'où le fallback naturel sur les Macs sans notch.
- Le poids du bundle (~150–300 Mo) est un compromis délibéré, documenté dans `SPEC.md` (décisions détaillées issues de la session de grilling).
- Point de vigilance build : la notarisation exige la signature de chaque dylib produite par PyInstaller — à intégrer au script de build dès le départ.
