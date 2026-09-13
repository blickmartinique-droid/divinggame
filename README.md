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
  comportement Passive/Skittish/Predator, vitesses, dégâts, taille réelle et
  nom du modèle importé), `CreatureBrain.lua` (errance / fuite / poursuite /
  attaque) et `CreatureSpawner.server.lua` (spawn par régions ou repli
  procédural, tick à faible fréquence avec LOD distance, `AnimationController`
  pour les rigs importés). Les 5 espèces correspondent 1:1 aux 5 modèles
  riggés/animés du pack « Archipel des Profondeurs V2 » :
  `PoissonRecif`, `TortueMarine`, `RaieManta`, `RequinRecif`,
  `MeduseLumineuse`. Corps placeholder tant que le modèle n'est pas importé —
  voir « Importer les animaux » ci-dessous.
- **Épave géante (`MegaWreckShip`)** — `Workspace/World/Underwater/WreckZone/
  MegaWreckShip`, un navire massif (~724×254×131 studs à l'échelle actuelle,
  9 salles nommées sur plusieurs ponts, mâts, canons, escaliers, corridors
  élargis). Reconstruit à partir de `MegaWreckShipData.lua` (table
  auto-générée, 645 entrées : nom/catégorie/position/rotation/taille/couleur,
  une par pièce du modèle source) par `MegaWreckShip.server.lua`. Voir le
  commentaire en tête de ce script pour la limite technique qui a motivé
  cette approche (boîtes orientées plutôt que le maillage réel) et comment la
  remplacer pièce par pièce par de vrais `MeshPart` si le modèle est importé
  plus tard dans Studio. Brèches dans la coque (`EntryPoints`), salles de
  loot (`LootSpots`, déjà taguées `SpawnRegion` pour `TreasureSpawner`), une
  zone de spawn de créatures (`RequinRecif`/`RaieManta`) et des repères (`Landmarks`,
  `InteractionPoints`) sont déjà en place. Éclairage intérieur complet sous
  `MegaWreckShip/Lighting` (`CorridorLights`/`RoomLights`/`EntranceLights`/
  `NavigationLights`/`AmbientLights`, ~60 `PointLight` au total, palette
  bleu/cyan sombre avec accent chaud dans les 3 salles majeures) — voir le
  commentaire "Interior lighting rework" dans le script pour le détail.
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

- **Assets** : placer les modèles dans
  `ReplicatedStorage/Assets/Creatures/<ModelName>` (un `Model` avec
  `PrimaryPart`) — le spawner les clone à la place du placeholder. Le `<Id>` de
  l'espèce fonctionne aussi, si le modèle a été renommé après import. Ne rien
  mettre à la main dans `ReplicatedStorage/Shared` ni dans les dossiers
  synchronisés par Rojo : ils sont écrasés à chaque sync.
- **Zones de spawn** : n'importe quel Part avec le tag `SpawnRegion` (Tag
  Editor) et les Attributes `RegionKind` (`Treasure` / `Creature`),
  `RegionCount`, `RegionSpecies` (`"PoissonRecif,TortueMarine"` ; les anciens
  noms `Sardine`/`Tortue`/`Raie`/`Requin`/`Baudroie` restent valides via
  `CreaturesConfig.Aliases`), `RegionEnabled`. Sa boîte
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

#### Importer les animaux (FBX -> Studio) et publier leurs animations

Les modèles et leurs clips viennent du pack « Archipel des Profondeurs V2 ».
Tout ce qui décrit l'animal lui-même dans `CreaturesConfig.lua` (taille, nom du
mesh, nom des clips) vient du rapport de vérification du pack, pas d'une
estimation. **Les identifiants d'animation sont volontairement `nil`** : un
asset id n'existe qu'après publication sous le compte/groupe propriétaire du
jeu, il ne peut pas être deviné. Tant qu'ils sont `nil`, tout fonctionne — la
créature nage simplement sans animation de corps.

| Espèce (`Id`) | Modèle à importer (`ModelName`) | Mesh | Os |
| --- | --- | --- | --- |
| `PoissonRecif` | `01_Poisson_Recif` | `01_Poisson_Recif_Mesh` | 5 |
| `RequinRecif` | `02_Requin_Recif` | `02_Requin_Recif_Mesh` | 6 |
| `RaieManta` | `03_Raie_Manta` | `03_Raie_Manta_Mesh` | 7 |
| `TortueMarine` | `04_Tortue_Marine` | `04_Tortue_Marine_Mesh` | — |
| `MeduseLumineuse` | `05_Meduse_Lumineuse` | `05_Meduse_Lumineuse_Mesh` | — |

1. **Modèle** — *Avatar → 3D Importer*, charger le `.fbx` de l'espèce, importer
   le rig (pas d'avatar/`Humanoid`). Renommer le `Model` obtenu exactement comme
   la colonne `ModelName`, définir son `PrimaryPart` sur le mesh, et le placer
   dans `ReplicatedStorage/Assets/Creatures`.
2. **Animations** — chaque `.fbx` d'espèce contient **deux** takes,
   `Nage_Lente` et `Nage_Rapide` (30 fps). L'importeur d'animations de Roblox
   n'accepte qu'un cycle par fichier : utiliser les fichiers mono-clip du
   dossier `Roblox_Animations/` du pack, un par take. Ouvrir chaque clip dans
   l'*Animation Editor*, puis *Publish to Roblox* sous le compte/groupe qui
   possède le jeu.
3. **Ids** — coller les ids obtenus dans `CreaturesConfig.lua`,
   `SlowSwimAnimationId` (= `Nage_Lente`) et `FastSwimAnimationId`
   (= `Nage_Rapide`), au format `"rbxassetid://..."`. Le cerveau choisit seul le
   clip : lent en errance, rapide en fuite ou en poursuite. Un id faux ou non
   publié produit un `warn` et la créature nage sans animation — il ne fait
   jamais tomber le spawner.
4. **Orientation** — les modèles du pack regardent vers `-X` alors que Roblox
   pilote vers `-Z`. `ModelYawOffsetDegrees = -90` corrige ça, uniquement pour
   les rigs importés (le placeholder est déjà construit face à `-Z`). Si un
   animal nage de travers après import, c'est ce champ qu'il faut ajuster (le
   pack ne confirme la convention `-X` que pour le poisson et le requin).
5. **Échelle** — le pack est en mètres à `1 m = 1/0.28 stud` (`StudsPerMetre`).
   Les `Size` de la config sont les dimensions mesurées converties à ce taux
   (requin 16,85 studs de long, raie 14,57 studs d'envergure). C'est
   volontairement **différent** de la convention « 1 stud = 1 m » utilisée pour
   la profondeur : à 1 stud/m un requin de récif serait plus petit qu'un
   avatar.

### Pas encore construit

Inventaire, vente / argent (Coins), équipements (Bouteille, Combinaison, Palmes,
Lampe, Sac), morphologies (Petit / Moyen / Grand), harpon, évitement d'obstacles
des créatures (elles traversent le terrain), décoration détaillée des zones
(Récif/Grottes/Épave/Abysses — volontairement laissée simple pour l'instant),
sauvegarde (DataStoreService).

L'architecture 500 m est conçue pour être étendue plus tard (1000/2000/3000/4000 m)
sans réécriture, mais ces paliers ne sont **pas** développés en V1.

## Tests

Il n'y a pas de runtime Roblox hors de Studio, donc `tests/` assemble les
vrais modules du jeu au-dessus d'un faux minimal de l'API Roblox
(`tests/stub.lua`) et les **exécute** avec le CLI `luau` :

```sh
python3 tests/build_creature_test.py && luau tests/creature_test.lua
```

123 vérifications sur le système de créatures : cohérence de
`CreaturesConfig` (bandes de profondeur sans trou entre 5 et 495 m, poursuite
toujours plus lente que le sprint du joueur, conversion mètres→studs), machine
à états du cerveau (errance / fuite / poursuite / attaque + cooldown),
orientation des modèles importés vs placeholder, résolution des anciens noms
d'espèces, et chargement/bascule des clips de nage. Le fake est volontairement
strict — un `Enum` inexistant y lève une erreur comme dans Studio, ce qu'une
analyse statique ne voit pas.

Analyse statique en complément : `luau-analyze $(find src -name "*.lua")`.

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
