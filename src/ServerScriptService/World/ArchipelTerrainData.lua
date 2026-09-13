-- AUTO-GENERATED from Archipel_des_Profondeurs.blend's 4 large sculpted terrain
-- meshes (cliff massif, island surface, cave network, abyssal cathedral). Each of
-- those meshes' real world-space vertices was clustered along its own dominant
-- axis into a chain of (centroid, radius) nodes -- an accurate medial-axis
-- approximation of the sculpted shape, not a hand-placed blockout. Radius is the
-- 85th percentile of PERPENDICULAR distance from each point to the segment's own
-- spine axis (not raw 3D distance to centroid, which would double-count the
-- bucket's own length along the spine as if it were thickness -- an earlier
-- version did exactly that and produced grossly oversized spheres). "mass"
-- chains (Falaises_Massif_Sous_Marin, Ile_Classique_Surface) are filled solid;
-- "carve" chains (Grottes_Creusees_Continues, Cathedrale_Creusee_Continue) are
-- carved out of that solid afterwards -- ArchipelWorld.server.lua fills mass
-- chains before carve chains for exactly that reason, and connects consecutive
-- nodes with a tapered FillCylinder rather than leaving each node an isolated
-- FillBall, so the result reads as one continuous ridge/tunnel instead of a
-- string of separate balls. Do not hand-edit; regenerate from the source .blend
-- instead.
return {
	Falaises_Massif_Sous_Marin = {
		Role = "mass",
		Material = "Rock",
		Chain = {
			{Center=Vector3.new(10.159,-501.000,251.879),Radius=38.121},
			{Center=Vector3.new(50.667,-409.943,264.968),Radius=181.650},
			{Center=Vector3.new(81.225,-329.805,258.101),Radius=164.671},
			{Center=Vector3.new(111.105,-308.583,276.091),Radius=183.810},
			{Center=Vector3.new(144.131,-265.264,312.335),Radius=215.788},
			{Center=Vector3.new(173.905,-239.356,313.503),Radius=232.311},
			{Center=Vector3.new(208.611,-228.928,270.196),Radius=240.063},
			{Center=Vector3.new(241.941,-227.107,293.002),Radius=250.677},
			{Center=Vector3.new(274.351,-221.068,298.656),Radius=245.410},
			{Center=Vector3.new(306.517,-219.441,308.465),Radius=241.554},
			{Center=Vector3.new(339.286,-216.994,295.192),Radius=248.892},
			{Center=Vector3.new(371.567,-218.675,332.553),Radius=214.125},
			{Center=Vector3.new(402.528,-206.621,290.513),Radius=212.236},
			{Center=Vector3.new(435.293,-188.746,289.675),Radius=198.290},
			{Center=Vector3.new(468.308,-182.909,295.585),Radius=254.640},
			{Center=Vector3.new(501.257,-179.146,290.686),Radius=235.987},
			{Center=Vector3.new(533.716,-205.052,314.919),Radius=246.359},
			{Center=Vector3.new(566.089,-215.314,276.684),Radius=234.749},
			{Center=Vector3.new(599.237,-231.860,284.297),Radius=224.095},
			{Center=Vector3.new(632.165,-243.625,294.670),Radius=221.542},
			{Center=Vector3.new(664.318,-244.955,293.446),Radius=203.372},
			{Center=Vector3.new(697.730,-260.919,288.427),Radius=194.525},
			{Center=Vector3.new(731.245,-288.886,290.764),Radius=167.333},
			{Center=Vector3.new(763.192,-311.495,261.465),Radius=149.874},
			{Center=Vector3.new(788.012,-396.144,274.435),Radius=174.099},
			{Center=Vector3.new(826.288,-501.000,229.477),Radius=59.979},
		},
	},
	Ile_Classique_Surface = {
		Role = "mass",
		Material = "Ground",
		Chain = {
			{Center=Vector3.new(226.542,-2.153,381.421),Radius=17.236},
			{Center=Vector3.new(240.451,1.171,386.886),Radius=29.073},
			{Center=Vector3.new(254.933,2.877,386.772),Radius=34.494},
			{Center=Vector3.new(270.875,4.703,386.624),Radius=28.159},
			{Center=Vector3.new(278.165,4.153,386.917),Radius=32.341},
			{Center=Vector3.new(295.067,2.877,386.772),Radius=34.494},
			{Center=Vector3.new(309.549,1.171,386.886),Radius=29.073},
			{Center=Vector3.new(323.458,-2.153,381.421),Radius=17.236},
		},
	},
	Grottes_Creusees_Continues = {
		Role = "carve",
		Material = "Water",
		Chain = {
			{Center=Vector3.new(163.511,-201.175,393.958),Radius=12.633},
			{Center=Vector3.new(175.484,-201.774,393.785),Radius=14.203},
			{Center=Vector3.new(193.520,-222.891,404.868),Radius=15.871},
			{Center=Vector3.new(206.063,-235.319,403.844),Radius=13.040},
			{Center=Vector3.new(226.172,-247.085,410.729),Radius=14.872},
			{Center=Vector3.new(238.912,-251.752,398.668),Radius=57.074},
			{Center=Vector3.new(255.392,-253.776,335.945),Radius=17.675},
			{Center=Vector3.new(268.641,-253.825,332.974),Radius=10.488},
			{Center=Vector3.new(299.124,-253.962,336.770),Radius=10.610},
			{Center=Vector3.new(319.249,-255.368,329.278),Radius=8.260},
			{Center=Vector3.new(350.366,-258.718,425.350),Radius=114.938},
			{Center=Vector3.new(364.182,-234.126,439.913),Radius=103.080},
			{Center=Vector3.new(377.814,-236.306,379.318),Radius=83.799},
			{Center=Vector3.new(396.143,-319.301,277.015),Radius=102.207},
			{Center=Vector3.new(409.939,-298.706,300.945),Radius=106.965},
			{Center=Vector3.new(423.812,-283.924,319.939),Radius=138.408},
			{Center=Vector3.new(443.070,-346.245,277.029),Radius=114.652},
			{Center=Vector3.new(458.020,-374.403,267.604),Radius=106.564},
			{Center=Vector3.new(471.509,-390.599,261.522),Radius=100.941},
			{Center=Vector3.new(486.230,-359.633,285.043),Radius=113.292},
			{Center=Vector3.new(504.003,-395.285,279.030),Radius=50.026},
			{Center=Vector3.new(516.446,-385.363,286.604),Radius=96.002},
			{Center=Vector3.new(537.453,-369.479,300.402),Radius=87.501},
			{Center=Vector3.new(550.853,-340.610,333.506),Radius=124.866},
			{Center=Vector3.new(565.043,-330.103,343.687),Radius=49.135},
			{Center=Vector3.new(582.482,-343.294,266.230),Radius=99.618},
			{Center=Vector3.new(596.609,-319.134,259.305),Radius=32.124},
			{Center=Vector3.new(611.307,-307.214,260.656),Radius=14.266},
			{Center=Vector3.new(624.363,-307.693,262.310),Radius=10.630},
			{Center=Vector3.new(642.382,-302.783,264.983),Radius=13.164},
			{Center=Vector3.new(664.018,-302.515,260.813),Radius=10.251},
			{Center=Vector3.new(690.339,-298.895,261.680),Radius=10.642},
			{Center=Vector3.new(715.853,-292.427,271.335),Radius=8.000},
			{Center=Vector3.new(731.855,-293.022,265.819),Radius=8.665},
			{Center=Vector3.new(756.324,-292.693,267.335),Radius=10.490},
			{Center=Vector3.new(770.207,-288.445,267.882),Radius=8.928},
		},
	},
	Cathedrale_Creusee_Continue = {
		Role = "carve",
		Material = "Water",
		Chain = {
			{Center=Vector3.new(528.025,-420.005,306.881),Radius=20.387},
			{Center=Vector3.new(527.977,-419.975,296.865),Radius=28.080},
			{Center=Vector3.new(523.954,-412.047,286.476),Radius=35.681},
			{Center=Vector3.new(525.004,-414.447,276.866),Radius=34.191},
			{Center=Vector3.new(520.815,-426.234,266.451),Radius=35.106},
			{Center=Vector3.new(529.319,-426.994,254.999),Radius=27.440},
			{Center=Vector3.new(533.674,-422.606,246.963),Radius=16.552},
			{Center=Vector3.new(569.001,-446.987,222.578),Radius=16.855},
			{Center=Vector3.new(569.300,-439.695,214.135),Radius=27.805},
			{Center=Vector3.new(575.870,-438.585,202.644),Radius=34.205},
			{Center=Vector3.new(573.998,-450.014,194.644),Radius=27.464},
			{Center=Vector3.new(575.011,-449.979,181.997),Radius=24.667},
			{Center=Vector3.new(572.774,-449.990,171.980),Radius=19.372},
		},
	},
}
