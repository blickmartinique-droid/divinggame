# divinggame — Jeu de plongée sous-marine (Roblox, V1)

Prototype Luau/Roblox : le joueur plonge dans un océan, explore 4 zones (0–500 m),
ramasse des trésors en gérant son oxygène, remonte pour vendre et s'équiper.

## Architecture prévue (V1)

Le code est organisé par système, avec des ModuleScripts partagés dans
`ReplicatedStorage/Shared` :

- **Joueur / déplacement** ✅ étape 1 (ce commit)
- Océan & zones (0–100 Récif, 100–250 Grottes, 250–400 Épave, 400–500 Abysses)
- Profondeur
- Oxygène
- Trésors
- Inventaire
- Vente / Argent (Coins)
- Équipements (Bouteille, Combinaison, Palmes, Lampe, Sac)
- Morphologies (Petit / Moyen / Grand)
- Créatures (pacifiques, hostiles, géante rare)
- Harpon
- Interface
- Sauvegarde (DataStoreService)

L'architecture 500 m est conçue pour être étendue plus tard (1000/2000/3000/4000 m)
sans réécriture, mais ces paliers ne sont **pas** développés en V1.

## Étape 1 — Déplacement du joueur

- `src/ReplicatedStorage/Shared/Config/MovementConfig.lua` : vitesses de nage
  (horizontale / verticale), lues par le contrôleur et réutilisables plus tard par
  le système de morphologie et d'équipement.
- `src/StarterPlayer/StarterPlayerScripts/SwimController.client.lua` : contrôleur
  de nage libre.
  - **Déplacement horizontal** : ZQSD/WASD, relatif à la caméra (contrôles Roblox
    par défaut, le personnage se tourne automatiquement).
  - **Monter** : Espace.
  - **Descendre** : Ctrl gauche ou C.
  - Le personnage ne tombe pas et ne saute pas : la vitesse verticale est
    entièrement pilotée par l'input, ce qui donne une sensation de flottaison
    neutre (base pour la nage), sans dépendre de l'eau/de l'océan qui arrivera
    à l'étape suivante.

## Ouvrir le projet dans Roblox Studio (via Rojo)

1. Installer [Aftman](https://github.com/LPGhatguy/aftman) puis, à la racine du
   repo :
   ```
   aftman install
   ```
   (installe la version de Rojo épinglée dans `aftman.toml`).
2. Installer le plugin Rojo dans Roblox Studio (Marketplace → "Rojo").
3. Lancer le serveur Rojo :
   ```
   rojo serve
   ```
4. Dans Roblox Studio, ouvrir une place (ou une place existante), ouvrir le
   plugin Rojo, cliquer sur **Connect**.
5. Lancer le mode Play (F5) : ZQSD/WASD pour se déplacer, Espace pour monter,
   Ctrl/C pour descendre.

Ne pas passer à l'étape suivante (océan) avant validation de cette étape.
