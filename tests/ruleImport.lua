-- Standalone source checks for the custom-rule sharing codec (config/panels/ruleEdit.lua)

local frame = {Hide = function() end}
CreateFrame = function() return frame end
tinsert = table.insert
format = string.format

local addon = {}
local config = {
	Addon = function()
		return {}, 'BagBrother', addon, {}
	end
}

assert(loadfile('config/panels/ruleEdit.lua'))('BagBrother_Config', config)
local codec = addon.RuleEdit

local search = codec:Decode('{title="Equipment",search="quality:epic",icon=134400}')
assert(search.title == 'Equipment')
assert(search.search == 'quality:epic')
assert(search.icon == 134400)

local invoked = false
attack = function() invoked = true end
local macro = codec:Decode('{title="Shared macro",macro="attack()"}')
assert(macro.macro == 'attack()')
assert(not invoked)

assert(codec:Decode('{title=(attack()),search="all"}') == nil)
assert(codec:Decode('setmetatable({title="Bad",search="all"}, {})') == nil)
assert(codec:Decode('{title="Bad",search="all",filter="attack"}') == nil)
assert(codec:Decode('{title="Bad",title="Duplicate",search="all"}') == nil)
assert(codec:Decode('{title="Bad",search="all"}; attack()') == nil)
assert(not invoked)

local original = {title = 'Quotes " and \\', search = 'line\nnext\tpart', icon = 'Atlas-Name'}
local roundtrip = codec:Decode(codec:Encode(original))
assert(roundtrip.title == original.title)
assert(roundtrip.search == original.search)
assert(roundtrip.icon == original.icon)

local oversized = '{title="' .. string.rep('x', 65536) .. '",search="all"}'
assert(codec:Decode(oversized) == nil)

local popup
LibStub = function()
	return {Popup = {New = function(_, options) popup = options end}}
end
addon.Rules = {}
addon.sets = {customRules = {}}

local reviewed
codec.Review = function(_, rule) reviewed = rule end
codec:Import(macro)
assert(#addon.sets.customRules == 0)
assert(reviewed == nil)
popup.OnAccept()
assert(reviewed == macro)

local created
codec.Create = function(_, rule) created = rule end
codec:Import(search)
assert(created == search)
