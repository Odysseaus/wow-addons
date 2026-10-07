local _, NS = ...

-- Mocked route matching approved mockups (Barrens Loop / Smart Drinks).
-- Used when quest log empty or /qg mock (P1 live is Quests.lua).

NS.MockRoute = {
  name = "Barrens Loop",
  index = 1,
  total = 7,
  segments = 5,
  filled = 1,
  step = {
    title = "Smart Drinks",
    distance = "142 yd",
    bearing = "ahead",
    approx = "approx.",
    zone = "Lushwater Oasis",
  },
  tracker = {
    label = "Smart Drinks · Wailing Essence",
    count = 0,
    total = 6,
  },
  status = {
    state = "In progress",
    last = "2m ago",
    count = "7 quests",
  },
  rewardsText = "+1240 XP",
  -- North, so the mock compass arrow still points when the log is empty.
  bearingDeg = 0,
  askPlaceholder = "Where do I turn in Smart Drinks?",
}
