-- Plain-Lua tests for the 0.1.37 counter catch-up (Codec.AdoptSeq).
-- Run from wow-grok/: lua addon/tests/seq_test.lua [slot-data-file session expected]
dofile("addon/WoWGrok/Codec.lua")
local C = WoWGrok_Codec
local fails = 0
local function eq(got, want, what)
	if got ~= want then
		fails = fails + 1
		print("FAIL " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	else
		print("ok   " .. what)
	end
end

local seqs = { d92acc52a9fe49 = 314, other = 900 }
eq(C.AdoptSeq(309, seqs, "d92acc52a9fe49"), 314, "rewound counter jumps to the bridge's last seq")
eq(C.AdoptSeq(320, seqs, "d92acc52a9fe49"), 320, "never moves the counter backwards")
eq(C.AdoptSeq(314, seqs, "d92acc52a9fe49"), 314, "equal stays")
eq(C.AdoptSeq(5, seqs, "unknown"), 5, "other sessions are ignored")
eq(C.AdoptSeq(5, nil, "d92acc52a9fe49"), 5, "old bridge without seqs: unchanged")
eq(C.AdoptSeq(nil, seqs, "d92acc52a9fe49"), 314, "missing counter counts as 0")
eq(C.AdoptSeq(7, { d92acc52a9fe49 = "x" }, "d92acc52a9fe49"), 7, "junk value ignored")
-- next seq after catching up is past everything the bridge handled
eq(C.AdoptSeq(309, seqs, "d92acc52a9fe49") + 1, 315, "next message gets 315")

local file, session, want = arg[1], arg[2], tonumber(arg[3])
if file then
	WoWGrok_SlotData = nil
	dofile(file)
	local data = WoWGrok_SlotData
	eq(type(data), "table", "bridge slot file loads")
	eq(type(data.now), "number", "slot file keeps the bridge clock")
	eq(C.AdoptSeq(309, data.seqs, session), want, "round trip through the bridge's slot file")
end

if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("all passed")
