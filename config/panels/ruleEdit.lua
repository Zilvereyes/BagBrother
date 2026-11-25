--[[
	Panel for editing custom rules.
	All Rights Reserved
--]]

local L, ADDON, Addon, Config = select(2, ...).Addon()
local Frame = CreateFrame('Frame', nil, nil, 'IconSelectorPopupFrameTemplate')
Addon.RuleEdit = Frame
Addon.RuleEdit:Hide()


--[[ Sharing ]]--

local IMPORT_LIMIT = 65536
local IMPORT_FIELDS = {title = 'string', search = 'string', macro = 'string', icon = 'icon'}
local DECODE_ESCAPES = {
	a = string.char(7), b = string.char(8), f = string.char(12), n = '\n',
	r = '\r', t = '\t', v = string.char(11), ['\\'] = '\\', ['"'] = '"'
}
local ENCODE_ESCAPES = {
	[string.char(7)] = '\\a', [string.char(8)] = '\\b', [string.char(12)] = '\\f',
	['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t', [string.char(11)] = '\\v',
	['\\'] = '\\\\', ['"'] = '\\"'
}

local function Quote(value)
	return '"' .. value:gsub('[%c\\"]', function(char)
		return ENCODE_ESCAPES[char] or format('\\%03d', string.byte(char))
	end) .. '"'
end

function Frame:Decode(encoded)
	if type(encoded) ~= 'string' or #encoded > IMPORT_LIMIT then return end

	local cursor, size = 1, #encoded
	local function skipWhitespace()
		while cursor <= size and encoded:sub(cursor, cursor):match('%s') do
			cursor = cursor + 1
		end
	end

	local function consume(expected)
		skipWhitespace()
		if encoded:sub(cursor, cursor) == expected then
			cursor = cursor + 1
			return true
		end
	end

	local function readIdentifier()
		skipWhitespace()
		local first, last, identifier = encoded:find('([%a_][%w_]*)', cursor)
		if first ~= cursor then return end

		cursor = last + 1
		return identifier
	end

	local function readString()
		skipWhitespace()
		if encoded:sub(cursor, cursor) ~= '"' then return end

		local value = {}
		cursor = cursor + 1
		while cursor <= size do
			local char = encoded:sub(cursor, cursor)
			if char == '"' then
				cursor = cursor + 1
				return table.concat(value), true
			elseif char == '\\' then
				local escaped = encoded:sub(cursor + 1, cursor + 1)
				if DECODE_ESCAPES[escaped] then
					tinsert(value, DECODE_ESCAPES[escaped])
					cursor = cursor + 2
				elseif escaped:match('%d') then
					local digits = escaped
					for offset = 2, 3 do
						local digit = encoded:sub(cursor + offset, cursor + offset)
						if not digit:match('%d') then break end
						digits = digits .. digit
					end

					local byte = tonumber(digits)
					if byte > 255 then return end
					tinsert(value, string.char(byte))
					cursor = cursor + 1 + #digits
				else
					return
				end
			elseif char == '\n' or char == '\r' then
				return
			else
				tinsert(value, char)
				cursor = cursor + 1
			end
		end
	end

	local function readNumber()
		skipWhitespace()
		local start = cursor
		while encoded:sub(cursor, cursor):match('[%d%.eE%+%-]') do
			cursor = cursor + 1
		end

		local token = encoded:sub(start, cursor - 1)
		local integer = token:match('^%-?%d+$')
		local decimal = token:match('^%-?%d+%.%d*$') or token:match('^%-?%d*%.%d+$')
		local exponent = token:match('^%-?%d+[eE][%+%-]?%d+$')
			or token:match('^%-?%d+%.%d*[eE][%+%-]?%d+$')
			or token:match('^%-?%d*%.%d+[eE][%+%-]?%d+$')
		if not (integer or decimal or exponent) then return end

		local value = tonumber(token)
		if value == math.huge or value == -math.huge then return end
		return value, true
	end

	local function readValue()
		skipWhitespace()
		if encoded:sub(cursor, cursor) == '"' then
			return readString()
		end
		return readNumber()
	end

	if not consume('{') then return end

	local rule, seen = {}, {}
	repeat
		local key = readIdentifier()
		local expected = key and IMPORT_FIELDS[key]
		if not expected or seen[key] or not consume('=') then return end

		local value, valid = readValue()
		if not valid or expected == 'string' and type(value) ~= 'string' then return end
		if expected == 'icon' and type(value) ~= 'string'
			and (type(value) ~= 'number' or value < 0 or value % 1 ~= 0) then return end

		rule[key], seen[key] = value, true
		skipWhitespace()
		local delimiter = encoded:sub(cursor, cursor)
		if delimiter == '}' then
			cursor = cursor + 1
			break
		elseif delimiter ~= ',' then
			return
		end
		cursor = cursor + 1
	until false

	skipWhitespace()
	local code = rule.search or rule.macro
	if cursor <= size or type(rule.title) ~= 'string' or rule.title:match('^%s*$')
		or type(code) ~= 'string' or code:match('^%s*$') or rule.search and rule.macro then return end

	return rule
end

function Frame:Encode(rule)
	local codeKey = rule.search ~= nil and 'search' or 'macro'
	local code = rule[codeKey]
	if type(rule.title) ~= 'string' or type(code) ~= 'string' then return end

	local encoded = format('{title=%s,%s=%s', Quote(rule.title), codeKey, Quote(code))
	if rule.icon ~= nil then
		local kind = type(rule.icon)
		if kind ~= 'string' and (kind ~= 'number' or rule.icon < 0 or rule.icon % 1 ~= 0) then return end
		local icon = kind == 'string' and Quote(rule.icon) or tostring(rule.icon)
		encoded = encoded .. ',icon=' .. icon
	end
	return encoded .. '}'
end


--[[ Menu ]]--

function Frame:OpenMenu(anchor)
	MenuUtil.CreateContextMenu(anchor, function(_, drop)
		drop:SetScrollMode(600)
		drop:SetTag(ADDON .. 'RuleEdit')
		drop:CreateTitle(L.InstalledFilters)

		self:SetParent(anchor)
		self:CreateCheckboxes(drop, Addon.Rules.Registry)

		if #Addon.sets.customRules > 0 then
			drop:CreateDivider()
			drop:CreateTitle(L.CustomFilters)
			self:CreateCheckboxes(drop, Addon.sets.customRules)
		end

		drop:CreateDivider()
		
		local new = drop:CreateButton(format('%s |cnPURE_GREEN_COLOR:%s|r', CreateAtlasMarkup('editmode-new-layout-plus'), L.NewFilter))
		new:CreateButton(' ' .. SEARCH, function() self:Create {title = L.NewSearch, search = ''} end)
		new:CreateButton(' ' .. MACRO, function() self:Create {title = L.NewMacro} end)
		new:CreateButton(' ' .. L.Import, function()
			LibStub('Sushi-3.2').Popup:New {
				id = ADDON .. 'ImportFilter',
				button1 = OKAY, button2 = CANCEL,
				text = L.ImportPopup,
				editBox = '',

				OnAccept = function(_, encoded)
					local rule = self:Decode(encoded)
					if rule then self:Import(rule) end
				end
			}
		end)
	end)
end

function Frame:CreateCheckboxes(drop, rules)
	local isInstalled = function(id)
		return Addon.Rules:Get(id) and 1 or 0 end

	local anchor = self:GetParent()
	local enabled, frame = anchor.rules, anchor.frame

	local sorted = GetPairsArray(rules)
	sort(sorted, function(a, b)
		return a.value.title < b.value.title end)

	for i, entry in pairs(sorted) do 
		local rule, id = entry.value, entry.key
		local title = rule:GetValue('title', frame)
		local icon = rule:GetIconMarkup(16, frame)

		local isEnabled = GenerateClosure(tContains, enabled, id)
		local toggle = function()
			(isEnabled() and tDeleteItem or tinsert)(enabled, id)
			frame:SendFrameSignal('FILTERS_CHANGED')
		end

		local check = drop:CreateCheckbox(icon ..' '.. title, isEnabled, toggle)
		check:SetCanSelect(function() return AccumulateOp(enabled, isInstalled) > 1 or not isEnabled() end)
		check:AddInitializer(function(check, _, menu)
			local edit = MenuTemplates.AttachAutoHideGearButton(check)
			edit:SetPoint('RIGHT')
			edit:SetScript('OnClick', function()
				self:Display(rule)
				menu:Close()
			end)

			MenuUtil.HookTooltipScripts(edit, function(tip)
				GameTooltip_SetTitle(tip, EDIT)
			end)
		end)
	end
end


--[[ Editing ]]--

function Frame:Create(rule)
	tinsert(Addon.sets.customRules, setmetatable(rule, Addon.Rules))
	self:Display(rule)
end

function Frame:Import(rule)
	if rule.macro then
		LibStub('Sushi-3.2').Popup:New {
			id = ADDON .. 'ImportMacroFilter',
			button1 = OKAY, button2 = CANCEL,
			text = L.ImportMacroPopup,
			OnAccept = function() self:Review(rule) end
		}
	else
		self:Create(rule)
	end
end

function Frame:Review(rule)
	self:Display(setmetatable(rule, Addon.Rules), true)
end

function Frame:Display(rule, pending)
	self:ClearAllPoints()
	self:Startup()
	self:Show()

	local frame = self:GetParent().frame
	if frame:IsFarRight() then
		self:SetPoint('TOPRIGHT', frame, 'TOPLEFT', -38,0)
	else
		self:SetPoint('TOPLEFT', frame, 'TOPRIGHT', 38,0)
	end

	self.rule = rule
	self.pending = pending and rule or nil
	self.BorderBox.IconSelectorEditBox:SetText(rule:GetValue('title', frame))
	self.CodeHeader:SetText(rule.search and L.EnterSearch or ENTER_MACRO_LABEL)
	self.Code.EditBox:SetText(gsub(rule.macro or rule.search or '', '\t', '  '))

	self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(rule.icon)
	self.IconSelector:SetSelectedIndex(self:GetIndexOfIcon(rule.icon))
	self.IconSelector:ScrollToSelectedIndex()

	self.BorderBox.DeleteButton:SetShown(not self.rule.id)
	self.BorderBox.ShareButton:SetShown(not self.rule.id)
end

function Frame:Done()
	self.pending = nil
	Addon:SendSignal('RULES_CHANGED')
	self:Hide()
end


--[[ Editing Events ]]--

function Frame:Startup()
	self.BorderBox.IconSelectionText:ClearAllPoints()
	self.BorderBox.IconSelectionText:SetPoint('BOTTOMLEFT', self.IconSelector, 'TOPLEFT', 0,10)
	self.BorderBox.IconSelectorEditBox:SetScript('OnTextChanged', GenerateClosure(self.Refresh, self))

	self.BorderBox.IconTypeDropdown:ClearAllPoints()
	self.BorderBox.IconTypeDropdown:SetPoint('BOTTOMRIGHT', self.IconSelector, 'TOPRIGHT', -33,0)
	self.BorderBox.EditBoxHeaderText:SetText('Enter Filter Name:')

	self.BorderBox.DeleteButton = CreateFrame('Button', nil, self.BorderBox, 'UIPanelButtonNoTooltipTemplate')
	self.BorderBox.DeleteButton:SetScript('OnClick', GenerateClosure(self.OnDelete, self))
	self.BorderBox.DeleteButton:SetPoint('BOTTOMLEFT', 13, 13)
	self.BorderBox.DeleteButton:SetTextToFit(DELETE)

	self.BorderBox.ShareButton = CreateFrame('Button', nil, self.BorderBox, 'UIPanelButtonNoTooltipTemplate')
	self.BorderBox.ShareButton:SetScript('OnClick', GenerateClosure(self.OnShare, self))
	self.BorderBox.ShareButton:SetPoint('LEFT', self.BorderBox.DeleteButton, 'RIGHT', 0,0)
	self.BorderBox.ShareButton:SetTextToFit(SOCIAL_SHARE_TEXT)

	self.CodeHeader = self:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
	self.CodeHeader:SetPoint('TOPLEFT', 21, -78)
	self.CodeHeader:SetJustifyH('LEFT')
	self.CodeHeader:SetSize(200, 0)
	self.CodeHeader:SetMaxLines(1)

	self.Code = CreateFrame('ScrollFrame', nil, self, 'InputScrollFrameTemplate')
	self.Code.EditBox:SetScript('OnTextChanged', GenerateClosure(self.Refresh, self))
	self.Code:SetPoint('TOPLEFT', self.CodeHeader, 'BOTTOMLEFT', 7, -10)
	self.Code:SetSize(470, 55)
	self.Code.hideCharCount = true
	InputScrollFrame_OnLoad(self.Code)

	self.Help = CreateFrame('Button', nil, self, 'UIPanelInfoButton')
	self.Help:SetScript('OnClick', GenerateClosure(self.OnHelp, self))
	self.Help:SetPoint('BOTTOMRIGHT', self.Code, 'TOPRIGHT', 0, 10)
	
	MenuUtil.HookTooltipScripts(self.Help, function(tip)
		GameTooltip_SetTitle(tip, GAMEMENU_HELP)
	end)

	self.iconDataProvider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.None)
	self.IconSelector:SetSelectionsDataProvider(GenerateClosure(self.GetIconByIndex, self), GenerateClosure(self.GetNumIcons, self))
	self.IconSelector:SetPoint('TOPLEFT', self.BorderBox, 'TOPLEFT', 21, -196)
	self.IconSelector:SetSelectedCallback(function(_, icon)
		self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(icon)
	end)

	self:SetSize(525, 594)
	self.Startup = nop
end

function Frame:Refresh()
	local function hasContent(box) return box:GetText():match('^%s*$') == nil end
	local valid = not self.rule.id and hasContent(self.BorderBox.IconSelectorEditBox)
	                               and hasContent(self.Code.EditBox)

	self.BorderBox.ShareButton:SetEnabled(valid)
	self.BorderBox.OkayButton:SetEnabled(valid)
end

function Frame:OkayButton_OnClick()
	if self.BorderBox.OkayButton:IsEnabled() then
		self.rule[self.rule.search and 'search' or 'macro'] = self.Code.EditBox:GetText()
		self.rule.icon = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
		self.rule.title = self.BorderBox.IconSelectorEditBox:GetText()
		if self.pending == self.rule then
			tinsert(Addon.sets.customRules, self.rule)
		end
		self:Done()
	else
		self.pending = nil
		self:Hide()
	end
end

function Frame:OnDelete()
	if self.pending ~= self.rule then
		tDeleteItem(Addon.sets.customRules, self.rule)
	end
	self:Done()
end

function Frame:OnShare()
	LibStub('Sushi-3.2').Popup:New {
		id = ADDON .. 'ShareFilter',
		text = L.SharePopup, button1 = OKAY,
		editBox = self:Encode(self.rule)
	}
end

function Frame:OnHelp()
	LibStub('Sushi-3.2').Popup:External('https://youtu.be/sie39ZW8uZo')
end
