--------------------------------------------------------------------------------
-- The quest fly-to's camera path (v0.4.2.4), on its own so it can be tested: van Wijk and Nuij's
-- "smooth and efficient zooming and panning" (the path d3's interpolateZoom uses). From one view to
-- another the camera zooms out as far as the distance needs, travels, and zooms back in: one curve,
-- no stops. A view is a centre (x, y) and its width w, in the same units (Map/WorldMap.lua: world px,
-- x = u * W, y = v * H; w = the view's width there). Short hops barely zoom out; far ones rise to the
-- continent or the world.
--   P.New(x0, y0, w0, x1, y1, w1[, rho])  the path: .S (its length), :At(t) -> x, y, w (t 0..1 along it)
--   P.ZoomOut(... , factor)                the same, rising at least `factor` times out from the wider end
--   P.Duration(S, speed)                   seconds: clamp(0.45 + 0.30 S, 0.6, 2.0) x the speed's factor
--   P.Ease(t)                              ease in-out cubic
--   P.Flight(path, dur)                    the flight in time, its slow-frame guard: :Step(elapsed) -> x, y, w, done
--------------------------------------------------------------------------------

local _, ns = ...
local P = {}
ns.FlyPath = P

P.RHO = 1.4                     -- how far out a trip rises (van Wijk's rho; d3's default is sqrt 2)
P.SPEED = { slow = 1.5, normal = 1, fast = 0.6 }
P.BASE, P.PER, P.LEAST, P.MOST = 0.45, 0.30, 0.6, 2.0   -- duration at Normal: BASE + PER x S, in LEAST .. MOST
P.SLOW_FRAME = 0.05             -- a frame this long (s) is a slow one
P.SLOW_FRAMES = 2               -- this many and the rest of the flight is cut to
P.SLOW_REST = 0.3               -- this long (s)
P.FIRST_FRAME = 1 / 30          -- the first frame counts as at most this long (the map's opening frame can be long)

local exp, log, sqrt, abs = math.exp, math.log, math.sqrt, math.abs
local function cosh(x) return (exp(x) + exp(-x)) / 2 end
local function sinh(x) return (exp(x) - exp(-x)) / 2 end
local function tanh(x) local a, b = exp(x), exp(-x) return (a - b) / (a + b) end

local Path = {}
Path.__index = Path

function P.New(x0, y0, w0, x1, y1, w1, rho)
	rho = rho or P.RHO
	local p = setmetatable({ x0 = x0, y0 = y0, w0 = w0, x1 = x1, y1 = y1, w1 = w1, rho = rho }, Path)
	local dx, dy = x1 - x0, y1 - y0
	local d2 = dx * dx + dy * dy
	p.dx, p.dy = dx, dy
	-- (a hop much shorter than the view: a pure zoom, with the centre carried straight across)
	if d2 < 1e-12 * math.max(w0, w1) ^ 2 then
		p.pure = true
		p.S = log(w1 / w0) / rho
		return p
	end
	local d1, r2 = sqrt(d2), rho * rho
	local b0 = (w1 * w1 - w0 * w0 + r2 * r2 * d2) / (2 * w0 * r2 * d1)
	local b1 = (w1 * w1 - w0 * w0 - r2 * r2 * d2) / (2 * w1 * r2 * d1)
	local r0 = log(sqrt(b0 * b0 + 1) - b0)
	local r1 = log(sqrt(b1 * b1 + 1) - b1)
	p.d1, p.r0, p.r1 = d1, r0, r1
	p.S = (r1 - r0) / rho
	return p
end

-- the view at t (0..1 along the path's length); the ends exact
function Path:At(t)
	if t <= 0 then return self.x0, self.y0, self.w0 end
	if t >= 1 then return self.x1, self.y1, self.w1 end
	local rho = self.rho
	if self.pure then
		return self.x0 + t * self.dx, self.y0 + t * self.dy, self.w0 * exp(rho * t * self.S)
	end
	local s, r0 = t * self.S, self.r0
	local c = cosh(r0)
	local u = self.w0 / (rho * rho * self.d1) * (c * tanh(rho * s + r0) - sinh(r0))
	return self.x0 + u * self.dx, self.y0 + u * self.dy, self.w0 * c / cosh(rho * s + r0)
end

-- the widest view on the way (the furthest out it goes)
function Path:Peak()
	local w = math.max(self.w0, self.w1)
	if not self.pure and self.r0 <= 0 and self.r1 >= 0 then w = math.max(w, self.w0 * cosh(self.r0)) end
	return w
end

-- the path's length for its duration (a zoom in or out is as long either way)
function Path:Length() return abs(self.S) end

-- "Always zoom out": rho raised until the path rises at least `factor` times out from its wider end
-- (a hop to the same spot has nowhere to travel: it stays a pure zoom)
function P.ZoomOut(x0, y0, w0, x1, y1, w1, factor)
	local p = P.New(x0, y0, w0, x1, y1, w1)
	factor = factor or 1
	if p.pure or p:Peak() >= factor * math.max(w0, w1) then return p end
	local lo, hi = P.RHO, P.RHO
	for _ = 1, 40 do
		hi = hi * 2
		p = P.New(x0, y0, w0, x1, y1, w1, hi)
		if p:Peak() >= factor * math.max(w0, w1) then break end
	end
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		if P.New(x0, y0, w0, x1, y1, w1, mid):Peak() >= factor * math.max(w0, w1) then hi = mid else lo = mid end
	end
	return P.New(x0, y0, w0, x1, y1, w1, hi)
end

function P.Duration(S, speed)
	local k = P.SPEED[speed] or 1
	local d = P.BASE + P.PER * abs(S or 0)
	return math.min(math.max(d, P.LEAST), P.MOST) * k
end

function P.Ease(t)
	if t <= 0 then return 0 elseif t >= 1 then return 1 end
	if t < 0.5 then return 4 * t * t * t end
	local f = -2 * t + 2
	return 1 - f * f * f / 2
end

-- a flight along a path in time. Two slow frames (a big addon redrawing its icons each step) and the
-- rest of the flight is cut to SLOW_REST, so a slow machine isn't left watching a slideshow
local Flight = {}
Flight.__index = Flight
function P.Flight(path, dur)
	return setmetatable({ path = path, dur = dur, t = 0, rate = 1 / math.max(dur, 1e-3), slow = 0, first = true }, Flight)
end
function Flight:Step(elapsed)
	elapsed = math.max(0, elapsed or 0)
	if self.first then
		self.first = false
		elapsed = math.min(elapsed, P.FIRST_FRAME)
	elseif elapsed > P.SLOW_FRAME then
		self.slow = self.slow + 1
		if self.slow == P.SLOW_FRAMES then self.rate = math.max(self.rate, (1 - self.t) / P.SLOW_REST) self.cut = true end
	end
	self.t = math.min(1, self.t + elapsed * self.rate)
	local x, y, w = self.path:At(P.Ease(self.t))
	return x, y, w, self.t >= 1
end
