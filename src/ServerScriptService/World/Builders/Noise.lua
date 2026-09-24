-- Deterministic gradient noise (Perlin) for the terrain builders. Written
-- in plain Lua instead of math.noise so the test suite reproduces the
-- exact same seabed the game builds.

local Noise = {}
Noise.__index = Noise

local GRAD2 = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Noise.new(seed: number)
	local perm = {}
	for i = 0, 255 do
		perm[i + 1] = i
	end
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	for i = 256, 2, -1 do
		state = (state * 16807) % 2147483647
		local j = state % i + 1
		perm[i], perm[j] = perm[j], perm[i]
	end
	local p = table.create(512)
	for i = 1, 512 do
		p[i] = perm[(i - 1) % 256 + 1]
	end
	return setmetatable({ p = p }, Noise)
end

local function fade(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- 2D Perlin noise, roughly in [-1, 1].
function Noise:Get(x: number, y: number): number
	local p = self.p
	local xi, yi = math.floor(x), math.floor(y)
	local xf, yf = x - xi, y - yi
	xi, yi = xi % 256, yi % 256
	local u, v = fade(xf), fade(yf)
	local aa = p[p[xi + 1] + yi + 1] % 8 + 1
	local ab = p[p[xi + 1] + yi + 2] % 8 + 1
	local ba = p[p[xi + 2] + yi + 1] % 8 + 1
	local bb = p[p[xi + 2] + yi + 2] % 8 + 1
	local g = GRAD2[aa]
	local n00 = g[1] * xf + g[2] * yf
	g = GRAD2[ba]
	local n10 = g[1] * (xf - 1) + g[2] * yf
	g = GRAD2[ab]
	local n01 = g[1] * xf + g[2] * (yf - 1)
	g = GRAD2[bb]
	local n11 = g[1] * (xf - 1) + g[2] * (yf - 1)
	local x1 = n00 + (n10 - n00) * u
	local x2 = n01 + (n11 - n01) * u
	return (x1 + (x2 - x1) * v) * 0.9
end

-- Fractal sum: `octaves` layers, each twice the frequency, half the weight.
function Noise:Fbm(x: number, y: number, octaves: number): number
	local total, amplitude, frequency, norm = 0, 1, 1, 0
	for _ = 1, octaves do
		total += self:Get(x * frequency, y * frequency) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2
	end
	return total / norm
end

-- Ridged variant: sharp crests, for rocky ridges and cliff bands.
function Noise:Ridged(x: number, y: number, octaves: number): number
	return 1 - math.abs(self:Fbm(x, y, octaves)) * 2
end

return Noise
