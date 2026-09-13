-- AUTO-GENERATED from Plans/manifest.json (Archipel des Profondeurs V2 pack).
-- Real room/door/stair/cave-graph/navigation data, converted with the same
-- Blender->Roblox axis remap and scale as the pack's own export_archipel.py
-- (x,y,z)->(x,z,-y), SCALE=1 (patched from the pack's default 1/0.28 so 500 m
-- of depth lands on this game's existing 500-stud ZonesConfig.MaxDepth,
-- instead of the pack's own human-scale 1786 studs -- see ArchipelPlacement
-- .server.lua's header for why), plus a +(380,0,480) world offset clearing
-- the existing beach at the origin. Do not hand-edit; regenerate from the
-- source pack's Plans/manifest.json instead.
return {
	CaveNodes = {
		{Name="Porte des Marées",Center=Vector3.new(453.000,-213.000,574.000),Radius=16.00,Height=12.00},
		{Name="Vestibule des Ancres",Center=Vector3.new(493.000,-255.000,523.000),Radius=20.00,Height=15.00},
		{Name="Carrefour Bleu",Center=Vector3.new(544.000,-295.000,479.000),Radius=27.00,Height=21.00},
		{Name="Cathédrale Abyssale",Center=Vector3.new(608.000,-420.000,458.000),Radius=34.00,Height=28.00},
		{Name="Puits des Echos",Center=Vector3.new(546.000,-467.000,411.000),Radius=20.00,Height=19.00},
		{Name="Jardin des Méduses",Center=Vector3.new(654.000,-450.000,377.000),Radius=30.00,Height=24.00},
		{Name="Cheminée des Racines",Center=Vector3.new(678.000,-310.000,439.000),Radius=18.00,Height=20.00},
		{Name="Galerie du Titan",Center=Vector3.new(337.000,-255.000,512.000),Radius=16.00,Height=13.00},
		{Name="Siphon Violet",Center=Vector3.new(478.000,-370.000,405.000),Radius=19.00,Height=15.00},
		{Name="Coude des Cendres",Center=Vector3.new(312.000,-250.000,595.000),Radius=14.00,Height=12.00},
		{Name="Porte du Titan",Center=Vector3.new(247.000,-200.000,576.000),Radius=13.00,Height=11.00},
		{Name="Galerie des Racines",Center=Vector3.new(640.000,-310.000,550.000),Radius=17.00,Height=14.00},
	},
	CliffPortals = {
		{Key="A",Position=Vector3.new(440.449,-263.203,721.123),OpeningDiameter=17.40},
		{Key="G",Position=Vector3.new(851.001,-288.101,447.760),OpeningDiameter=17.40},
		{Key="K",Position=Vector3.new(247.000,-199.075,561.202),OpeningDiameter=17.40},
	},
	Navigation = {
		{Name="Navire — pont supérieur",Position=Vector3.new(299.136,-178.315,520.000)},
		{Name="Navire — machines",Position=Vector3.new(295.732,-204.572,520.000)},
		{Name="Montagne — station sismique",Position=Vector3.new(591.000,-92.923,405.000)},
		{Name="Ruines — ancien camp",Position=Vector3.new(674.000,-170.178,499.000)},
		{Name="Grottes — Porte des Marées",Position=Vector3.new(453.000,-213.000,574.000)},
		{Name="Grottes — Vestibule des Ancres",Position=Vector3.new(493.000,-255.000,523.000)},
		{Name="Grottes — Carrefour Bleu",Position=Vector3.new(544.000,-295.000,479.000)},
		{Name="Grottes — Cathédrale Abyssale",Position=Vector3.new(608.000,-420.000,458.000)},
		{Name="Grottes — Puits des Echos",Position=Vector3.new(546.000,-467.000,411.000)},
		{Name="Grottes — Jardin des Méduses",Position=Vector3.new(654.000,-450.000,377.000)},
		{Name="Grottes — Cheminée des Racines",Position=Vector3.new(678.000,-310.000,439.000)},
		{Name="Grottes — Galerie du Titan",Position=Vector3.new(337.000,-255.000,512.000)},
		{Name="Grottes — Siphon Violet",Position=Vector3.new(478.000,-370.000,405.000)},
		{Name="Grottes — Coude des Cendres",Position=Vector3.new(312.000,-250.000,595.000)},
		{Name="Grottes — Porte du Titan",Position=Vector3.new(247.000,-200.000,576.000)},
		{Name="Grottes — Galerie des Racines",Position=Vector3.new(640.000,-310.000,550.000)},
		{Name="Falaise — accès A",Position=Vector3.new(439.001,-268.997,738.103)},
		{Name="Falaise — accès G",Position=Vector3.new(868.836,-285.844,448.663)},
		{Name="Falaise — accès K",Position=Vector3.new(247.000,-197.952,543.237)},
		{Name="Surface — accueil classique",Position=Vector3.new(355.000,7.700,567.000)},
		{Name="Surface — quai de plongée",Position=Vector3.new(355.000,3.000,617.000)},
	},
	ShipDeckRooms = {
		{Usage="BALLAST",Center=Vector3.new(370.910,-205.183,520.000),Size=Vector3.new(223.597,21.186,30.100)},
		{Usage="MACHINES",Center=Vector3.new(370.593,-199.993,520.000),Size=Vector3.new(223.597,21.186,34.420)},
		{Usage="LABORATOIRES",Center=Vector3.new(370.275,-194.803,520.000),Size=Vector3.new(223.597,21.186,34.420)},
		{Usage="HABITATS",Center=Vector3.new(369.958,-189.612,520.000),Size=Vector3.new(223.597,21.186,34.420)},
		{Usage="PROMENADE",Center=Vector3.new(369.640,-184.422,520.000),Size=Vector3.new(223.597,21.186,34.420)},
		{Usage="INFIRMERIE",Center=Vector3.new(369.323,-179.232,520.000),Size=Vector3.new(223.597,21.186,34.420)},
		{Usage="PASSERELLE",Center=Vector3.new(392.960,-172.576,520.000),Size=Vector3.new(175.687,18.256,29.200)},
	},
	Offset = Vector3.new(380.000,0.000,480.000),
}
