-- Equip This!'s windows are the game's own Settings design (Settings.lua, shared with the author's
-- other addons), whatever UI is installed. Here: the one window of its own, a text to copy.
local _, ns = ...
local UI = {}
ns.UI = UI

-- A window with text to copy (several lines), selected and ready: Ctrl+C. onClose (optional): called
-- once when it closes (to bring back the window it was opened from).
function UI.ShowText(name, title, note, text, onClose)
  local win = _G[name]
  if not win then
    win = UI.Popup(name, 560, 340, "")
    win.note = UI.Note(win, "", 520)
    win.note:SetPoint("TOPLEFT", 20, -36)
    local scroll = CreateFrame("ScrollFrame", nil, win, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -84); scroll:SetPoint("BOTTOMRIGHT", -36, 48)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(490)
    scroll:SetScrollChild(edit)
    edit:SetScript("OnEscapePressed", function() win:Hide() end)
    edit:SetScript("OnTextChanged", function(self, user) if user and self:GetText() ~= win.text then self:SetText(win.text); self:HighlightText() end end)
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    win.edit = edit
    local close = UI.Button(win, CLOSE or "Close", 96, function() win:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 16)
    win:HookScript("OnHide", function() local fn = win.onClose; win.onClose = nil; if fn then fn() end end)
  end
  win.onClose = onClose
  win.text = text
  win:SetTitle(title)
  win.note:SetText(note or "")
  win.edit:SetText(text)
  win:Place(); win:Show()
  win.edit:SetFocus()
  win.edit:HighlightText()
end
