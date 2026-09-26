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
- **Construction du monde (ordre garanti)** — `World/WorldBootstrap.server.lua`
  est le seul script qui construit le monde : il exécute les modules de
  `World/Builders/` dans un ordre fixe (`Ocean` → `Seabed` → `Caves` →
  `LavaTubes` → `Shipwreck` → `WreckGraveyard` → `Liner` → `Hub` → `IslandLife` → `Currents` →
  `BiomeDecor` → `Biomes`) puis lève
  `Workspace.WorldReady`, que les spawners attendent. Avant, ces étapes
  étaient des scripts indépendants sans ordre garanti par Roblox (le
  remplissage d'eau pouvait noyer les grottes, les spawners rater les zones
  de l'épave). `WorldLayout` partage les volumes réservés (épave, montagnes,
  courants, plage) et la hauteur du sol, pour que rien ne traverse le relief, et un `Random`
  à graine fixe : la carte est identique à chaque démarrage.
- **Océan & plage** — `Builders/Ocean.lua` : vide d'abord tout terrain
  resté dans la place, puis océan de 500 m sur 2000×2000 studs (Terrain
  Water) sur un fond rocheux, plage naturelle en pente douce, ambiance,
  et murs invisibles au bord de l'océan (plus de sortie dans le vide).
  Le plan de destruction de Roblox (`FallenPartsDestroyHeight`, -500 par
  défaut = exactement le fond marin) est abaissé à -1000 via
  `default.project.json` (propriété réservée aux plugins, pas aux scripts).
- **Zones** — `ZonesConfig.lua` définit 4 tranches de profondeur (0–100 Récif,
  100–250 Grottes, 250–400 Épave, 400–500 Entrée de l'abysse), chacune avec ses
  propres réglages de brouillard/luminosité. `ZoneAnnouncer.client.lua` interpole
  ces réglages en continu selon la profondeur réelle du joueur (pas de saut
  brutal aux limites de zone) et fait descendre une carte « ZONE n · plage
  de profondeur » au changement de zone, soulignée à la couleur de la zone.
- **Ambiance sous-marine** — `UnderwaterAmbience.client.lua` : sédiments et
  bulles d'ambiance très discrets, suivant le joueur, actifs uniquement sous
  l'eau.
- **Profondeur** — `DepthTracker.server.lua` : calcule et réplique la profondeur
  de chaque joueur (autoritatif serveur).
- **Oxygène** — `OxygenManager.server.lua` : consomme/régénère l'oxygène selon la
  profondeur (autoritatif serveur), avec `MaxOxygen`/`OxygenDrainPerSecond` par
  joueur (fixés par l'équipement porté), remis au maximum à
  chaque réapparition. Tue le joueur (`Humanoid.Health = 0`) à 0.
- **Butin** — `PlayerInventory.lua` + `InventoryManager.server.lua` : un
  trésor ramassé va dans le **sac** (`CarriedValue`/`CarriedCount`), vendu
  automatiquement en remontant à la surface (`leaderstats.Pièces`), **perdu**
  à la mort. Le HUD affiche le sac, les pièces et une notification à chaque
  événement (`ReplicatedStorage.LootEvent`).
- **Trésors** — `TreasureSpawner.server.lua` : des « emplacements » qui se
  re-remplissent 90–150 s après chaque ramassage (l'océan ne se vide plus).
  Chaque `SpawnRegion` Treasure (salles de l'épave, cavernes) fournit ses
  emplacements ; chaque zone de profondeur est complétée en pleine eau
  jusqu'à 15 trésors minimum, hors des volumes réservés. Rareté croissante
  avec la profondeur. **15 trésors modélisés** (`TreasureModels.lua`, trois
  par rareté) : pièces d'or, bouteille à la mer, conque / bague sertie,
  perle géante dans sa coquille, boussole / coffret, calice, longue-vue /
  idole d'or, couronne, sablier / trident des abysses, crâne de cristal,
  Cœur de l'Océan — chacun un petit modèle détaillé avec lumière et
  étincelles à la couleur de sa rareté, qui flotte, tourne et tangue
  (`TreasureAnimator.client.lua`).
- **Hub de l'île** — `Builders/Hub.lua` : un village de plongée autour du
  spawn. **Centre de plongée** au toit de chaume (comptoir-boutique, Marius
  le moniteur, bouteilles, combinaisons, palmes et lampes exposées),
  **ponton** au-dessus du lagon jusqu'à une plateforme de mise à l'eau
  (pavillon « plongeur en immersion », échelle) avec le **bateau du club**
  amarré, deux **bungalows sur pilotis**, un **phare** rouge et blanc dont
  la lampe tourne, une place avec feu de camp et bancs, torches tiki, un
  **panneau indicateur** vers chaque site (avec la distance) et le tableau
  **« Meilleurs plongeurs »** (`HubLeaderboard.server.lua`).
- **Équipement et boutique** — `EquipmentConfig.lua` : 4 catégories,
  18 articles. **Bouteilles** (autonomie 60 → 260 s, jusqu'au recycleur),
  **tenues** (consommation d'air −10 % → −48 %, du shorty au scaphandre
  abyssal), **palmes** (vitesse +12 % → +40 %), **lampes** (une vraie
  lumière frontale, portée 40 → 110). `EquipmentService.server.lua` valide
  chaque achat côté serveur (`ReplicatedStorage.EquipmentRequest`) et
  applique les effets ; `EquipmentVisuals.lua` **habille le personnage**
  (bouteille ou bi-bouteille sur le dos, harnais, détendeur, masque — ou
  casque en laiton avec le scaphandre —, palmes, lampe frontale,
  combinaison aux couleurs de la tenue). `DiveShop.client.lua` : la
  boutique moderne qui s'ouvre au comptoir (onglets, cartes, barre de
  stats, acheter / équiper / équipé). **Sauvegarde** (`PlayerData.lua`,
  DataStore) : pièces, équipement acheté et porté, gardés d'une session à
  l'autre (sans accès aux API dans Studio, un avertissement et le jeu
  continue sans sauvegarde).
- **Vie sur l'île** — `Builders/IslandLife.lua` : palmiers courbés à noix de
  coco, bananiers, fougères, hibiscus, oiseaux de paradis, herbes hautes,
  rochers moussus ; coquillages, étoiles de mer, bois flotté et noix de
  coco sur la plage, parasol et transats. Faune animée par
  `IslandCritters.client.lua` : crabes et bernard-l'ermite qui trottinent
  de côté (et fuient le joueur), mouettes qui tournent au-dessus de l'île,
  papillons autour des fleurs, perroquets perchés dans les palmiers,
  dauphins qui sautent dans le lagon.
- **Interface** — un seul langage visuel (`UITheme.lua` : panneaux « verre »
  sombres translucides, coins arrondis, liseré fin, une couleur par sens —
  cyan oxygène, or butin, rouge danger — et mise à l'échelle automatique
  selon l'écran, du téléphone au 4K). `GameplayHUD.client.lua` : **jauge de
  profondeur verticale** à gauche peinte aux couleurs des 4 zones, avec un
  curseur qui glisse et la profondeur + le nom de zone ; **capsule
  d'oxygène** en bas au centre (secondes restantes, dégradé, contour rouge
  qui pulse sous 25 %, vignette rouge et « ↑ REMONTE À LA SURFACE ») ;
  **pièces** (compteur qui défile) et **sac** en haut à droite ; **cartes de
  notification** qui glissent à chaque trésor (barre à la couleur de la
  rareté), vente ou perte ; **puce de courant** en haut au centre (nom + force).
  L'UI ne fait qu'afficher les valeurs serveur.
- **Écran de mort** — `DeathScreen.client.lua` : flou + voile rouge, carte
  qui indique la **cause** (attribut `LastDeathCause` posé par le serveur :
  noyade, ou l'espèce qui a porté le dernier coup), la profondeur max de la
  plongée, le butin perdu, et une barre de réapparition.

- **Courants sous-marins** — trois formes (`Directional` : boîte orientée,
  `Circular` : vortex, `Path` : chemin à nœuds `CurrentPoint_01..N` — droit,
  vertical, diagonal, virages, plusieurs segments), entièrement décrites par des
  Attributes (`CurrentTier`, `CurrentMaxSpeed`, `CurrentAcceleration`,
  `CurrentExitDeceleration`, `CurrentCentering`, `CurrentWidth`,
  `CurrentVisualIntensity`, `CurrentDisplayName`, `CurrentSoundId`… voir
  `CurrentsConfig.lua`). `Builders/Currents.lua` construit les visuels de
  tout ce qui se trouve dans `Workspace/Currents` (exemples générés **et**
  courants posés à la main) ; `UnderwaterCurrents.client.lua` calcule la poussée
  (entrée/sortie progressives, direction lissée, recentrage sur la trajectoire,
  plafond de sécurité) et la publie via `CurrentField` (vitesse, courant
  dominant, signaux `Entered`/`Exited`/`Changed`). `CurrentVisualAnimator.client.lua`
  anime les anneaux de trajectoire et les vortex côté client ; les
  trajectoires sont **lissées en splines** et portent des **rubans de flux**
  (trois bandes scintillantes qui s'enroulent autour de l'axe, texture qui
  défile à la vitesse du courant), avec une **balise lumineuse** et un
  panneau à chaque entrée ; `CurrentRiders.client.lua` fait voyager des
  **bancs de poissons** dans les courants. **Une circulation naturelle,
  pas des taxis** (aucun courant ne mène de l'île à un site) : six
  **veines** générées (`vein` : un cap qui serpente au bruit, une hauteur
  qui suit le relief à une distance qui « respire », qui monte et plonge,
  qui contourne épaves et entrées) — la **Rivière bleue** entre deux eaux,
  la **Veine froide** qui remonte des profondeurs, la **Dérive des
  mantas**, le **Plongeon du large** qui descend vers le fond, le
  **Courant de fond** au ras de la plaine, la **Veine chaude** qui monte de
  la faille ; **Le Grand Courant**, le tourbillon du volcan, qui ondule
  entre 140 et 250 m ; la **Remontée** et la **Cascade du tombant** le long
  de la falaise ; le **Courant du lagon** et **La Passe** qui vide le
  lagon vers le large ; des **panaches hydrothermaux** qui montent de la
  faille ; le **Grand Tourbillon** et le **Remous de l'Éperon** ; et des
  **marées** dans les tunnels du volcan et au Porche (`CurrentTidePeriod`) :
  l'eau entre (flot), ralentit (étale), puis ressort (jusant), sur une
  horloge commune à tous les joueurs, tunnels déphasés entre eux — la
  physique, les rubans, les anneaux, les poissons et le HUD suivent la
  marée ;
  `CurrentFeedback.client.lua` gère le léger élargissement du FOV, les traits de
  vitesse et le son optionnel.
- **Créatures** — `CreaturesConfig.lua` (espèces : profondeur, rareté,
  comportement Passive/Skittish/Predator, vitesses, dégâts, taille réelle,
  `SchoolSize` pour les bancs, `Bob` pour la dérive pulsée des méduses),
  `CreatureBrain.lua` (errance / fuite / poursuite / attaque, **bancs** qui
  nagent en formation et s'égaillent devant un plongeur) et
  `CreatureSpawner.server.lua` (spawn par régions ; une espèce qu'aucune
  région n'accueille garde sa population en pleine eau ; une région ne fait
  naître que des espèces vivant à sa profondeur ; `RegionWanderRadius`
  garde les habitants des grottes dans leur caverne). Les 5 espèces
  correspondent 1:1 aux 5 modèles du pack « Archipel des Profondeurs V2 » :
  `PoissonRecif`, `TortueMarine`, `RaieManta`, `RequinRecif`,
  `MeduseLumineuse`. **Tant que les FBX ne sont pas importés**, chaque animal
  est dessiné par `CreatureBodies.lua` : corps **lissés** (une suite
  d'ellipsoïdes qui suit un profil effilé, ventre plus clair), **nageoires,
  queues et ailes en vrais triangles** (paires de wedges), yeux avec iris,
  pupille et reflet, nage **articulée** (le corps fléchit avant la queue,
  l'aile de la raie ondule jusqu'à la pointe, la nageoire de la tortue plie
  au coude, les tentacules de la méduse ondulent en trois segments) ; un
  vrai corps détaillé par espèce
  (poisson tropical rayé en 5 palettes — clown, chirurgien bleu, jaune,
  ange, gramma —, requin gris à pointes noires, raie manta à chevrons
  blancs, tortue à carapace écaillée, méduse translucide lumineuse à
  tentacules), articulé par des `Motor6D` que `CreatureAnimator.client.lua`
  anime localement (queue qui bat, ailes, nageoires, tentacules ; rythme
  doublé en fuite/chasse). Voir « Importer les animaux » ci-dessous.
- **Relief sous-marin** — `Builders/Seabed.lua` : l'île est le sommet d'un
  mont volcanique. Crête du récif puis **tombant** (falaise jusqu'à ~110 m),
  flancs ravinés jusqu'à la plaine abyssale, **terrasse de sable à ~330 m**
  (nord-est) où gît l'épave, **éperon rocheux** (nord-ouest) qui abrite les
  grottes, et **faille abyssale** (deux crêtes de basalte, un canyon). Champ
  de hauteur (bruit déterministe `Noise.lua`) écrit en colonnes de Terrain,
  matériau de surface selon profondeur et pente (calcaire de récif, sable,
  roche, vase et basalte au fond) et strates d'ardoise sur les falaises.
  `layout:GroundHeight` sert à tout poser sur le vrai sol.
- **Épave : « La Sirène Noire »** — `Builders/Shipwreck.lua`, un galion à
  trois mâts géant (~380 studs de long, 92 de large, grand mât de 170)
  posé sur la terrasse, gîte vers l'aval et ensablé.
  Coque réellement courbe, bordée planche par planche (surface paramétrique
  échantillonnée en stations × virures), cale, pont des canons avec canons
  aux sabords, pont principal effondré autour du grand mât brisé, gaillard
  d'avant, cabine du capitaine sous la dunette (table, coffre, lanterne,
  fenêtres de poupe). Grande brèche bâbord (entrée de la cale, membrures
  visibles), trou tribord, mât d'artimon cassé, misaine debout aux voiles
  déchirées, beaupré et figure de proue, gouvernail. Coraux et éponges sur
  la coque, kelp sur le pont, lueurs bioluminescentes dedans ; le haut du
  grand mât gît sur le sable avec sa voile, ancre et cargaison dispersées.
  Butin : cale, pont des canons, cabine ; requins et méduses autour.
- **Biome « Cimetière de la Sirène »** — `Builders/WreckGraveyard.lua` : la
  terrasse est une longue corniche courbe qui suit le flanc (~680 studs de
  long, même distance du sommet sur toute sa longueur, donc sans effet de
  table). Autour de la Sirène Noire gisent le **Brick chaviré** (retourné,
  quille vers le ciel, une brèche dans la coque et la poupe ouverte pour se
  glisser dessous), la **Chaloupe brisée** (proue et poupe séparées, mât
  tombé entre les deux) et **le Squelette** (quille et membrures). Une
  traînée de débris court sur toute la corniche : tonneaux, caisses,
  canons, boulets, amphores, coffres à demi enfouis, ancres et chaînes,
  roue de gouvernail, cloche, lanternes englouties encore allumées. Vie des
  profondeurs : gorgones-fouets, corail noir, éponges de verre, anémones
  et plumes de mer lumineuses, gorgones sur les coques. Butin dans le brick,
  la chaloupe et les coffres ; requins, méduses et raies manta.
- **Paquebot « L'Impératrice »** — `Builders/Liner.lua` : un paquebot de
  900 studs brisé en deux dans la plaine abyssale (~500 m), au-delà de la
  Sirène Noire. Proue debout, nez dans la vase : coque en tôles rivetées,
  hublots (certains encore allumés), brèche à tribord vers les cales, nom en
  lettres de laiton, passerelle, deux étages de superstructure, **grand
  escalier sous une verrière**, salle de bal (lustres, piano), salle à
  manger, cheminées (debout, penchée, effondrée), mât de misaine tombé,
  bossoirs, stalactites de rouille, colonies bioluminescentes. Poupe 330
  studs plus loin, tordue, flanc arraché, machines à nu, trois hélices en
  bronze. Entre les deux : chaudières, quatrième cheminée, charbon, tôles,
  valises, vaisselle, transats, baignoire, lustres, coffres-forts du
  commissaire de bord. Biome dédié qui voit plus loin dans le noir.
- **Biomes nommés** — `Builders/Biomes.lua` publie des volumes nommés dans
  `ReplicatedStorage.Biomes` (Lagon, Tombant du récif, Forêt de kelp, Kelp
  doré, Grand Bleu, Cimetière de la Sirène, Faille abyssale, Plaine
  abyssale, et chaque salle des grottes). `BiomeLookup` trouve le biome
  d'un point ; une carte annonce chaque biome à l'entrée (nom, description,
  couleur) et le HUD affiche son nom sous la profondeur.
- **Grottes de l'Éperon** — `Builders/Caves.lua`, un réseau creusé dans
  l'éperon. Accès le plus simple : le **Trou Bleu**, un puits qui s'ouvre
  directement au bord du lagon et plonge vers la Salle des Cristaux. Chaque
  entrée est posée sur la vraie paroi (là où le tunnel entre dans la roche),
  s'ouvre en large porche évasé et, sur les entrées latérales, une faille
  est taillée dans la paroi au-dessus : on la voit d'en haut. Anneau de
  perles lumineuses, lumière et panneau « ⛰ nom » visible de loin. Réseau : **Porche du Récif** (~118 m) → **Salle des Cristaux** (géode de
  cristaux lumineux) → **La Cathédrale** (~185 m, piliers de roche, puits de
  lumière du jour tombant d'une cheminée, autel ancien et idole) → sortie
  **Fenêtre** ; → **Grotte aux Méduses** (~312 m, bassin bioluminescent) →
  **Sortie des Abysses**. Tunnels sinueux (splines), salles organiques à sol
  de sable, stalactites, champignons et vers luisants posés sur les surfaces
  calculées. Un courant aspire vers le Porche. Tout est creusé en `Air`
  puis rempli d'eau : avec les *Shorelines* (défaut Roblox), un simple
  remplissage `Water` laisse la roche en place. Aucun décor ne se pose
  dans une bouche de grotte.
- **Réseau du Volcan** — `Builders/LavaTubes.lua` : l'île est un ancien
  volcan et ses **tunnels de lave** forment le vrai réseau sous-marin. Sous
  l'île, une salle immense, **le Cœur du volcan**, abrite un **temple
  englouti** (trois gradins, colonnes debout, brisées ou tombées en
  tambours, statues gardiennes aux yeux luisants, autel et orbe tournant,
  fissures de lave dans le sable). Six tunnels en partent : le **Puits du
  Lagon** (un second trou bleu juste au large de la plage, l'entrée depuis
  le hub), le tunnel de l'**Éperon** (rejoint la Salle des Cristaux), celui
  de l'**Épave** (par la **Galerie des Échos** et ses cristaux pâles), de la
  **Forêt de kelp**, du **Kelp doré**, et celui des **Abysses** (par la
  **Salle des Orgues** et ses colonnes de basalte) jusqu'à la faille.
  Parois en basalte, **arches de pierre** à runes lumineuses et panneau à
  chaque ouverture (dehors comme dans le Cœur), **balises runiques** tout le
  long des tunnels pour ne jamais se perdre. Butin dans le temple et les
  salles, tortues, requins et méduses.
- **Biomes** — `Builders/BiomeDecor.lua` : récif du lagon (coraux branchus,
  cerveaux, tables, éventails, éponges, anémones, oursins, étoiles de mer,
  bénitiers, herbiers, kelp), gorgones et éponges sur le tombant, **forêt de
  kelp géant** sur le flanc ouest, **cheminées hydrothermales** fumantes
  avec vers tubicoles et roche en fusion dans la faille, plumes de mer et
  éponges de verre sur la plaine, **jardins de corail** sur les flancs,
  champs d'anémones, **kelp doré** sur le flanc est, crinoïdes. Plantes
  animées par `FloraAnimator.client.lua`. Faune : régions de créatures dans
  chaque biome (poissons et tortues au lagon, tortues et raies dans les
  jardins et le kelp, raies et requins en pleine eau, méduses sur la plaine
  abyssale et dans la faille), plus des **bancs de poissons d'ambiance**
  (`AmbientFish.client.lua`, purement visuels, côté client, nombre selon la
  qualité graphique) qui suivent le relief et s'égaillent devant le plongeur.

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

Sac (capacité), morphologies (Petit / Moyen / Grand), harpon, évitement
d'obstacles des créatures (elles traversent le terrain).

L'architecture 500 m est conçue pour être étendue plus tard (1000/2000/3000/4000 m)
sans réécriture, mais ces paliers ne sont **pas** développés en V1.

## Tests

Il n'y a pas de runtime Roblox hors de Studio, donc `tests/` monte **tous**
les scripts du jeu, là où Rojo les placerait, au-dessus d'un faux minimal et
strict de l'API Roblox (`tests/stub.lua` — un `Enum` inexistant lève une
erreur comme dans Studio, le Terrain enregistre chaque remplissage et suit
la règle des *Shorelines* de Roblox : de l'eau versée dans de la roche ne la
retire pas, seul un remplissage `Air` creuse) et les
**exécute** avec le CLI `luau` :

```sh
python3 tests/build_tests.py
luau tests/creature_test.lua   # 126 vérifications
luau tests/world_test.lua      # 266 vérifications
luau tests/ui_test.lua         # 62 vérifications
```

- `creature_test` : cohérence de `CreaturesConfig`, machine à états du
  cerveau, orientation des modèles, anciens noms d'espèces, clips de nage,
  règle de population par espèce.
- `world_test` : exécute le vrai `WorldBootstrap` puis les spawners et
  vérifie la géométrie obtenue : sol continu sous la plage, tombant, fond
  sans trou, hauteur du sol conforme au terrain écrit ; salles des grottes
  ouvertes, fermées par un toit, sol de sable, tunnels dégagés de bout en
  bout, entrées débouchant en eau libre, posées sur la paroi et ouvertes
  vers le haut, décors posés sur la roche ; coque
  bordée, quille posée dans le sable, entrées de l'épave en eau libre ;
  épaves du cimetière posées sur la corniche, sans chevaucher la Sirène,
  brick à l'envers ouvert sur l'eau ; réseau du volcan (salles fermées
  sous la roche, tunnels dégagés et dans la roche, sorties en eau libre,
  puits du lagon sans eau au-dessus de la mer, tunnel relié aux Cristaux,
  temple posé au sol, arches, balises) ; réseau de courants (boucle fermée
  autour du volcan, remontées qui montent, départ au ponton, rubans et
  balises ; aucun courant-taxi vers un site, des courants qui montent,
  d'autres qui descendent, des veines qui ondulent, des marées déphasées) ;
  paquebot (taille, quille dans la
  vase, ouvertures, rien ne le traverse) ; biomes nommés aux bons endroits ;
  hub (pilotis jusqu'au sol, bateau à flot, rien dans les bâtiments), vie
  sur l'île sur la terre ferme, achats/équipement (prix, effets,
  vêtements, sauvegarde) ;
  chaque courant ne traverse que de l'eau et jamais l'épave ; kelp enraciné ;
  15 trésors minimum par zone, aucun trésor ni créature dans la roche, les
  5 espèces présentes.
- `ui_test` : lance le HUD, l'annonceur de zone et l'écran de mort avec un
  faux joueur local et les fait vivre une plongée (profondeur, entrée dans
  un biome, oxygène bas, trésor, vente, boutique, animaux de l'île, mort,
  réapparition) en vérifiant ce
  qu'ils affichent, accents compris (`UITheme.Upper`).

Analyse statique en complément, avec les types Roblox :
`luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src`
(sourcemap générée par `rojo sourcemap default.project.json`).

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
