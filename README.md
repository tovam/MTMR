# MMTMR

MMTMR est un fork de MTMR centré sur deux choses : une configuration JSON stricte et un éditeur web local intégré à l’application.

La source de vérité est toujours :

```text
~/.mtmr.json
```

L’éditeur est servi par MMTMR sur :

```text
http://127.0.0.1:8787
```

MMTMR continue de fonctionner normalement lorsque le navigateur est fermé.

## Prérequis

- macOS 14 ou plus récent ;
- Xcode complet avec un compilateur Swift 6.2 ;
- Node.js et npm pour construire l’éditeur embarqué ;
- autorisation Accessibilité accordée à `MMTMR.app` pour les frappes et actions système.

Le minimum macOS est 14 car HummingbirdWebSocket 2.7.0 déclare lui-même macOS 14 comme plateforme minimale.

## Configuration

Le fichier est un document JSON UTF-8 RFC 8259. Les commentaires, virgules finales, clés dupliquées, propriétés inconnues et types inconnus sont refusés.

Exemple avec injection Unicode native immédiate :

```json
{
  "formatVersion": 1,
  "notes": "Mes caractères Unicode",
  "items": [
    {
      "actions": [
        {
          "action": "typeText",
          "text": "ž",
          "trigger": "singleTap"
        },
        {
          "action": "typeText",
          "text": "Ž",
          "trigger": "longTap"
        }
      ],
      "align": "left",
      "bordered": false,
      "id": "letter-z",
      "title": "ž",
      "type": "staticButton",
      "width": 18
    }
  ]
}
```

`typeText` envoie directement les unités UTF-16 avec `CGEvent`. Il n’utilise ni AppleScript, ni le presse-papiers, ni un collage Commande-V.

Chaque item possède un `id` stable et unique. Cet identifiant est utilisé par le runtime pour ne reconstruire que les éléments réellement modifiés.

Les chemins relatifs sont résolus depuis le dossier contenant le fichier de configuration. Les chemins commençant par `~/` restent acceptés.

### Premier lancement et migration

Si `~/.mtmr.json` n’existe pas, MMTMR importe le premier fichier disponible dans cet ordre :

1. `~/Library/Application Support/MTMR/items.json` ;
2. `~/Library/Application Support/MTMR tovam/items.json` ;
3. le preset livré avec l’application.

Le migrateur accepte uniquement à cette étape les commentaires et virgules finales historiques. Il convertit `action` et `longAction` vers `actions`, génère les identifiants manquants et écrit un nouveau JSON strict sans modifier l’ancien fichier.

Une modification externe invalide ne remplace jamais la dernière barre valide : les diagnostics sont publiés dans l’éditeur et le serveur reste disponible pour réparer le fichier.

## Éditeur web

Le menu de la barre de statut contient :

- `Ouvrir l’éditeur` ;
- `Ouvrir ~/.mtmr.json` ;
- l’état et l’adresse du serveur ;
- le changement du port local.

Le shell Preact est entièrement en flex, sans défilement global. Seules la palette, le panneau actif, l’inspecteur et la prévisualisation horizontale possèdent leur propre défilement.

Fonctions principales :

- palette d’items et inspecteur générés depuis le schéma ;
- drag-and-drop entre les zones gauche, centre et droite ;
- formulaire, JSON brut, simulation et journal d’événements ;
- brouillon local, undo/redo et autosave avec contrôle de révision ;
- diagnostics en ligne et conservation locale d’un JSON invalide ;
- aperçu optimiste, puis géométrie autoritaire renvoyée par AppKit ;
- simulation descriptive des actions, sans exécution système.

## Serveur local

Le serveur Hummingbird écoute uniquement sur `127.0.0.1`. Il ne bascule pas sur un autre port si le port demandé est occupé.

Routes :

- `GET /` ;
- `GET /api/v1/status` ;
- `GET /api/v1/schema` ;
- `GET /api/v1/config` ;
- `POST /api/v1/validate` ;
- `PUT /api/v1/config` avec `If-Match` ;
- `POST /api/v1/preview/context` ;
- `POST /api/v1/preview/action` ;
- `WS /api/v1/events`.

Événements WebSocket : `config.changed`, `config.invalid`, `runtime.snapshot`, `simulation.changed` et `server.error`.

La session utilise un secret renouvelé au lancement, un cookie `HttpOnly` et `SameSite=Strict`, des contrôles stricts de `Host` et `Origin`, une CSP locale, des limites de corps et de fréquence, et aucun CORS. Le serveur n’expose aucun navigateur de fichiers.

## Développement

L’éditeur se trouve dans [`Web/`](Web/).

```bash
cd Web
npm ci
npm run check
npm run build
```

Le build Vite produit `Web/dist`. La phase de build Xcode reconstruit l’éditeur puis copie son contenu dans `MMTMR.app/Contents/Resources/Editor`.

Les options suivantes sont réservées aux tests et builds Debug :

```text
--config /chemin/vers/config.json
--editor-port 8787
```

## Construction et tests

Ouvrir `MTMR.xcodeproj`, sélectionner le schéma `MMTMR`, puis construire l’application. Les scripts équivalents sont :

```bash
./build.sh
./test.sh
```

Ils refusent explicitement de s’exécuter lorsque seuls les Command Line Tools sont installés, car l’application AppKit et les tests Hummingbird nécessitent un Xcode complet.
Tous leurs caches et DerivedData sont placés dans `build-checks/` à la racine du dépôt.

Les dépendances serveur sont fixées sur :

- Hummingbird 2.25.0 ;
- ServiceLifecycle 2.11.0 ;
- HummingbirdWebSocket 2.7.0 et son module WSCore 1.6.1, conservés dans
  `Vendor/` avec un correctif de compatibilité Swift 6.2/macOS 14 documenté
  dans `Vendor/README.md`.

Sparkle a été retiré du fork MMTMR.
