# MMTMR Web Editor

Éditeur Preact/TypeScript embarqué par MMTMR. Le serveur natif reste l’unique propriétaire de `~/.mtmr.json`; le navigateur ne touche jamais directement au disque et les simulations n’exécutent aucune action.

## Commandes

```sh
npm install
npm run dev
npm run build
npm test
```

Le build de production est écrit dans `Web/dist/`. En développement, Vite écoute sur `127.0.0.1:5173` et relaie `/api` vers `127.0.0.1:8787`.

## Contrat natif

Le client consomme les routes `/api/v1/status`, `/schema`, `/config`, `/validate`, `/preview/context`, `/preview/action` ainsi que le WebSocket `/api/v1/events`. Les écritures de configuration portent la révision numérique dans `If-Match`; une réponse `409` conserve le brouillon local et affiche le conflit.
