# divinggame — Jeu de plongée sous-marine (Roblox, V1)

Prototype Luau/Roblox : le joueur plonge dans un océan, explore 4 zones (0–500 m),
ramasse des trésors en gérant son oxygène, remonte pour vendre et s'équiper.

## Architecture

Le code est organisé par système, avec des ModuleScripts partagés dans
`ReplicatedStorage/Shared/Config` et `ReplicatedStorage/Shared/Modules` (constantes
et fonctions pures réutilisées par le client et le serveur, ex. `DepthUtils`,
`ZonesConfig`).

### Construit en V1

- **Déplacement / nage** — `SwimController.client.lua` : nage libre en 3D,
  déplacement horizontal + vertical piloté par la caméra (regarder en haut/bas en
  avançant fait monter/descendre), Espace/Ctrl en contrôle vertical manuel
  additionnel, maintien de profondeur physique (`LinearVelocity`), orientation du
  corps cohérente avec la direction réelle de déplacement, posture de repos
  verticale en Idle. Seul système à piloter la rotation du personnage pendant la
  nage (`Humanoid.AutoRotate` désactivé pour éviter tout conflit avec le Shift
  Lock).
- **Océan & plage** — `OceanGenerator.server.lua` : océan de 500 m de profondeur
  sur 2000×2000 studs (Terrain Water), plage naturelle au niveau de la mer avec
  transition en pente douce vers le large, ambiance lumière/eau de base.
- **Zones** — `ZonesConfig.lua` définit 4 tranches de profondeur (0–100 Récif,
  100–250 Grottes, 250–400 Épave, 400–500 Entrée de l'abysse), chacune avec ses
  propres réglages de brouillard/luminosité. `ZoneAnnouncer.client.lua` interpole
  ces réglages en continu selon la profondeur réelle du joueur (pas de saut
  brutal aux limites de zone) et affiche une bannière au changement de zone.
- **Ambiance sous-marine** — `UnderwaterAmbience.client.lua` : sédiments et
  bulles d'ambiance très discrets, suivant le joueur, actifs uniquement sous
  l'eau.
- **Profondeur** — `DepthTracker.server.lua` : calcule et réplique la profondeur
  de chaque joueur (autoritatif serveur).
- **Oxygène** — `OxygenManager.server.lua` : consomme/régénère l'oxygène selon la
  profondeur (autoritatif serveur), avec `MaxOxygen`/`OxygenDrainPerSecond` par
  joueur (prêt pour un futur équipement type Bouteille). Tue le joueur
  (`Humanoid.Health = 0`) si l'oxygène atteint 0.
- **Trésors** — `TreasureSpawner.server.lua` : 60 trésors répartis sur les 4
  zones, ramassage via `ProximityPrompt` server-side, rareté qui augmente avec la
  profondeur. Pas encore d'inventaire : la collecte log seulement pour l'instant.
- **UI de gameplay** — `GameplayHUD.client.lua` : profondeur, barre d'oxygène,
  nom de la zone actuelle (les trois valeurs viennent des systèmes serveur
  ci-dessus, cette UI ne fait qu'afficher).
- **Écran de mort** — `DeathScreen.client.lua` : overlay flou + message,
  déclenché actuellement par la noyade, prêt pour toute future source de dégâts.

- **Courants sous-marins** — trois formes (`Directional` : boîte orientée,
  `Circular` : vortex, `Path` : chemin à nœuds `CurrentPoint_01..N` — droit,
  vertical, diagonal, virages, plusieurs segments), entièrement décrites par des
  Attributes (`CurrentTier`, `CurrentMaxSpeed`, `CurrentAcceleration`,
  `CurrentExitDeceleration`, `CurrentCentering`, `CurrentWidth`,
  `CurrentVisualIntensity`, `CurrentDisplayName`, `CurrentSoundId`… voir
  `CurrentsConfig.lua`). `CurrentGenerator.server.lua` construit les visuels de
  tout ce qui se trouve dans `Workspace/Currents` (exemples générés **et**
  courants posés à la main) ; `UnderwaterCurrents.client.lua` calcule la poussée
  (entrée/sortie progressives, direction lissée, recentrage sur la trajectoire,
  plafond de sécurité) et la publie via `CurrentField` (vitesse, courant
  dominant, signaux `Entered`/`Exited`/`Changed`). `CurrentVisualAnimator.client.lua`
  anime les anneaux de trajectoire et les vortex côté client ;
  `CurrentFeedback.client.lua` gère le léger élargissement du FOV, les traits de
  vitesse et le son optionnel.
- **Créatures** — `CreaturesConfig.lua` (espèces : profondeur, rareté,
  comportement Passive/Skittish/Predator, vitesses, dégâts),
  `CreatureBrain.lua` (errance / fuite / poursuite / attaque) et
  `CreatureSpawner.server.lua` (spawn par régions ou repli procédural, tick à
  faible fréquence avec LOD distance). Corps placeholder tant qu'aucun modèle
  n'est fourni.
- **Épave géante (`MegaWreckShip`)** — `Workspace/World/Underwater/WreckZone/
  MegaWreckShip`, un navire massif (~845×154×296 studs à l'échelle actuelle,
  9 salles nommées sur plusieurs ponts, mâts, canons, escaliers). Reconstruit à
  partir de `MegaWreckShipData.lua` (table auto-générée, 645 entrées :
  nom/catégorie/position/rotation/taille/couleur, une par pièce du modèle
  source) par `MegaWreckShip.server.lua`. Voir le commentaire en tête de ce
  script pour la limite technique qui a motivé cette approche (boîtes
  orientées plutôt que le maillage réel) et comment le remplacer pièce par
  pièce par de vrais `MeshPart` si le modèle est importé plus tard dans
  Studio. Brèches dans la coque (`EntryPoints`), salles de loot
  (`LootSpots`, déjà taguées `SpawnRegion` pour `TreasureSpawner`), une zone
  de spawn de créatures (`Requin`/`Raie`) et des repères (`Landmarks`,
  `InteractionPoints`) sont déjà en place.
- **4 régions montagnes/grottes** — `Workspace/World/Underwater/CaveRegions`,
  reconstruites à partir de 4 modèles source (blockout, v2, v3 avec entrées, v4
  entrées visibles) par `CaveRegionBuilder.lua` (partagé) + `CaveRegion1..4Data.lua`
  (données auto-générées) + `CaveRegions.server.lua` (placement des 4 + courants
  de liaison). Contrairement à `MegaWreckShip` (boîtes), ce sont ici de vrais
  volumes de **Terrain** (Rock plein, Water creusé pour les grottes/tunnels) —
  voir le commentaire en tête de `CaveRegionBuilder.lua` pour pourquoi (modèles
  volontairement "blockout", le Terrain lissé de Roblox rend un résultat organique
  là où des Parts auraient gardé un look cubique). Chaque région a ses vraies
  entrées (jamais de trou visuel sans tunnel derrière — chaque brèche est
  activement creusée jusqu'à la caverne centrale), ses ruines/terrasses/coraux
  (Parts), ses `LootSpots`/zone de créatures (`SpawnRegion`, comme pour l'épave)
  et ne touche jamais à `MegaWreckShip`.

### Intégration du mapping et des assets (Blender / Studio)

- **Assets** : placer les modèles dans `ReplicatedStorage/Assets/Creatures/<Id>`
  (un `Model` avec `PrimaryPart`, orienté vers -Z) — le spawner les clone à la
  place du placeholder. Ne rien mettre à la main dans `ReplicatedStorage/Shared`
  ni dans les dossiers synchronisés par Rojo : ils sont écrasés à chaque sync.
- **Zones de spawn** : n'importe quel Part avec le tag `SpawnRegion` (Tag
  Editor) et les Attributes `RegionKind` (`Treasure` / `Creature`),
  `RegionCount`, `RegionSpecies` (`"Sardine,Tortue"`), `RegionEnabled`. Sa boîte
  (ou sa sphère) est le volume ; il peut vivre dans le modèle de l'épave, de la
  grotte… Dès qu'une région d'un type existe, le placement procédural de ce type
  est désactivé.
- **Courants** : créer le dossier `Workspace/Currents` s'il n'existe pas, y
  placer un Part (`CurrentShape = Directional` : la boîte est la zone, sa face
  avant la direction ; ou `Circular` + `CurrentRadius`) ou un Model
  (`CurrentShape = Path`) contenant des Parts `CurrentPoint_01`, `_02`… ; régler
  `CurrentTier` (`Weak`/`Medium`/`Strong`/`FastLane`) et, si besoin, les
  Attributes individuels. Aucun script à modifier : visuels, physique et HUD
  suivent l'instance. Rien de posé à la main n'est jamais supprimé par le
  générateur.

### Pas encore construit

Inventaire, vente / argent (Coins), équipements (Bouteille, Combinaison, Palmes,
Lampe, Sac), morphologies (Petit / Moyen / Grand), harpon, évitement d'obstacles
des créatures (elles traversent le terrain), décoration détaillée des zones
(Récif/Grottes/Épave/Abysses — volontairement laissée simple pour l'instant),
sauvegarde (DataStoreService).

L'architecture 500 m est conçue pour être étendue plus tard (1000/2000/3000/4000 m)
sans réécriture, mais ces paliers ne sont **pas** développés en V1.

## Ouvrir le projet dans Roblox Studio (via Rojo)

1. Installer [Aftman](https://github.com/LPGhatguy/aftman) puis, à la racine du
   repo :
   ```
   aftman install
   ```
   (installe la version de Rojo épinglée dans `aftman.toml`). Si `aftman
   install` échoue (téléchargement corrompu, etc.), télécharger directement le
   binaire correspondant depuis les
   [releases GitHub de Rojo](https://github.com/rojo-rbx/rojo/releases).
2. Installer le plugin Rojo dans Roblox Studio (Marketplace → "Rojo").
3. Lancer le serveur Rojo :
   ```
   rojo serve
   ```
4. Dans Roblox Studio, ouvrir une place (ou une place existante), ouvrir le
   plugin Rojo, cliquer sur **Connect**.
5. Lancer le mode Play (F5) : ZQSD/WASD pour se déplacer, Espace pour monter,
   Ctrl/C pour descendre, regarder vers le haut/bas en nageant en avant fait
   aussi monter/descendre.

Les animations de nage personnalisées (`SwimAnimationsConfig.lua`) nécessitent
que l'expérience soit publiée et que les permissions d'utilisation des
animations soient accordées depuis le Creator Dashboard, même pour des
animations appartenant au même compte.
