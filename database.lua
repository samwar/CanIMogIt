--[[
    global = {
        "appearances" = {
            appearanceID:INVTYPE_HEAD = {
                "sources" = {
                    sourceID = {
                        "subClass" = "Mail",
                        "classRestrictions" = {"Mage", "Priest", "Warlock"}
                    }
                }
            }
        }
    }
]]

local L = CanIMogIt.L


CanIMogIt_DatabaseVersion = 1.3


local default = {
    global = {
        appearances = {},
        setItems = {}
    }
}


------------------------------------------------------------
-- Database Migration Functions
------------------------------------------------------------


local function IsBadKey(key)
    -- Good key: 12345:SOME_TYPE

    -- If it's a number: 12345
    if type(key) == 'number' then
        -- Get the appearance hash for the source
        return true
    end

    -- If it has two :'s in it: 12345:SOME_TYPE:SOME_TYPE
    local _, count = string.gsub(key, ":", "")
    if count >= 2 then
        return true
    end
end


local function CheckBadDB()
    --[[
        Check if the database has been corrupted by a bad update or going
        back too many versions.
    ]]
    local showPopup = false
    -- If the database is older than 1.2
    if CanIMogIt.db.global.databaseVersion and CanIMogIt.db.global.databaseVersion < 1.2 then
        showPopup = true
    end
    -- if there are broken keys in the database
    if CanIMogIt.db.global.appearances and CanIMogIt.db.global.databaseVersion then
        for key, _ in pairs(CanIMogIt.db.global.appearances) do
            if IsBadKey(key) then
                showPopup = true
            end
        end
    end
    if showPopup then
        StaticPopupDialogs["CANIMOGIT_BAD_DATABASE"] = {
            text = "Can I Mog It?" .. "\n\n" .. L["Sorry! Your database has corrupted entries. This will cause errors and give incorrect results. Please click below to reset the database."],
            button1 = L["Okay"],
            button2 = L["Ask me later"],
            OnAccept = function () CanIMogIt:DBReset() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
        }
        StaticPopup_Show("CANIMOGIT_BAD_DATABASE")
    end
end


local function UpdateTo1_1()
    return
end


local function UpdateTo1_2()
    return
end


local versionMigrationFunctions = {
    [1.1] = UpdateTo1_1,
    [1.2] = UpdateTo1_2
}


local function UpdateToVersion(version)
    CanIMogIt:Print(L["Migrating Database version to:"], version)
    versionMigrationFunctions[version]()
    CanIMogIt.db.global.databaseVersion = version
    CanIMogIt:Print(L["Database migrated to:"], version)
end


local function UpdateDatabase()
    -- Disabled due to a bug. Anything below 1.2 is also many years old, so not worried about it.
    -- if CanIMogIt.db.global.databaseVersion < 1.2 then
    --     CanIMogIt.CreateMigrationPopup("CANIMOGIT_DB_MIGRATION_1_2", function () UpdateToVersion(1.2) end)
    -- end
    if CanIMogIt.db.global.databaseVersion < 1.3 then
        CanIMogIt:FixMissingClassRestrictions()
    end
    -- CanIMogIt.db.global.databaseVersion = CanIMogIt_DatabaseVersion
end


local function UpdateDatabaseIfNeeded()
    CheckBadDB()
    if next(CanIMogIt.db.global.appearances) and
            (CanIMogIt.db.global.databaseVersion == nil
            or CanIMogIt.db.global.databaseVersion < CanIMogIt_DatabaseVersion) then
        UpdateDatabase()
    end
    if CanIMogIt.db.global.databaseVersion == nil then
        -- There is no database, add the default.
        CanIMogIt.db.global.databaseVersion = CanIMogIt_DatabaseVersion
    end
end


-- Create a popup for the one-time database fix for FixMissingClassRestrictions
function CanIMogIt.CreateBugFixPopup(dialogName, onAcceptFunc, estimatedTime)
    StaticPopupDialogs[dialogName] = {
        text = "Can I Mog It?" .. "\n\n" .. string.format(L["We need to update our database. This will cause about %s minutes of short lag spikes while we update the database."], estimatedTime),
        button1 = L["Okay"],
        button2 = L["Ask me later"],
        OnAccept = onAcceptFunc,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    }
    StaticPopup_Show(dialogName)
end


local delay = 1
local buffer = 50
local displayCounter = 0
local itemsToFix = {}

local function SetItemClassRestrictions(itemLink, hash, sourceID)
    -- manually set the class restrictions for the item.
    -- this will fix any items that are missing class restrictions or have wrong data.
    local classRestrictions = CanIMogIt:GetItemClassRestrictions(itemLink)
    if classRestrictions then
        CanIMogIt.db.global.appearances[hash].sources[sourceID].classRestrictions = classRestrictions
    else
        CanIMogIt.db.global.appearances[hash].sources[sourceID].classRestrictions = nil
    end
end

local function FixClassRestrictions()
    -- Pause the database scan while we fix the class restrictions.
    CanIMogIt:PauseDatabaseScan(L["Pausing the database scan while we upgrade!"])

    -- Get the list of items to fix.
    for hash, appearance in pairs(CanIMogIt.db.global.appearances) do
        for sourceID, source in pairs(appearance["sources"]) do
            local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
            itemsToFix[sourceID] = {hash, itemLink}
        end
    end

    -- iterate over the itemsToFix table with a buffer
    -- with a delay between each batch.
    local function FixItems()
        local totalSources = 0
        for hash, appearance in pairs(CanIMogIt.db.global.appearances) do
            for sourceID, source in pairs(appearance["sources"]) do
                totalSources = totalSources + 1
            end
        end
        local i = 0
        for sourceID, data in pairs(itemsToFix) do
            local hash = data[1]
            local itemLink = data[2]
            if itemLink == nil then
                -- if the itemLink is nil, just remove it from the table and continue.
                itemsToFix[sourceID] = nil
            elseif GetItemInfo(itemLink) then
                -- If GetItemInfo returns real stuff, then we can set the class restrictions.
                SetItemClassRestrictions(itemLink, hash, sourceID)
                itemsToFix[sourceID] = nil
                i = i + 1
            end
            if i >= buffer then
                break
            end
        end
        --[[
            If the itemsToFix table doesn't decrease, it means there are items that aren't
            getting item data back from Blizzard. These are probably deprecated items. For now,
            we will just make sure their format is correct and ignore them. We can't tell what
            Blizzard will do with them in the future, so we are leaving them alone.
        --]]
        if i == 0 then
            for sourceID, data in pairs(itemsToFix) do
                local hash = data[1]
                CanIMogIt.db.global.appearances[hash].sources[sourceID].classRestrictions = nil
                itemsToFix[sourceID] = nil
            end
        end
        if next(itemsToFix) ~= nil then
            -- The buffer was reached, but there are still items to fix.
            local countOfItemsToFix = 0
            for itemLink, data in pairs(itemsToFix) do
                countOfItemsToFix = countOfItemsToFix + 1
            end
            displayCounter = displayCounter + 1
            if displayCounter == 10 then
                CanIMogIt:Print("Still upgrading the database. "..countOfItemsToFix.." of "..totalSources.. " entries to update.")
                displayCounter = 0
            end
            C_Timer.After(delay, FixItems)
        else
            -- We're done, update the database version and show a popup.
            CanIMogIt:Print(L["Finished updating the database!"])
            CanIMogIt.db.global.databaseVersion = CanIMogIt_DatabaseVersion
            StaticPopupDialogs["CanIMogIt_BugFixComplete"] = {
                text = L["Can I Mog It has finished updating the database. Please reload your UI to save the changes."],
                button1 = L["Okay, reload now"],
                button2 = L["I'll reload later"],
                OnAccept = ReloadUI,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
            }
            StaticPopup_Show("CanIMogIt_BugFixComplete")
        end
    end
    FixItems()
end

function CanIMogIt:FixMissingClassRestrictions()
    -- Run DBAddItem again for all items in the database.
    -- This will fix any items that are missing class restrictions.
    local totalSources = 0
    for hash, appearance in pairs(self.db.global.appearances) do
        for sourceID, source in pairs(appearance["sources"]) do
            totalSources = totalSources + 1
        end
    end

    -- estimate the time it will take to fix the database, rounded up to the nearest minute.
    local estimatedTime = math.ceil(totalSources / buffer * delay / 60)

    CanIMogIt.CreateBugFixPopup("CanIMogIt_FixMissingClassRestrictions", FixClassRestrictions, estimatedTime)
end


function CanIMogIt:OnInitialize()
    if (not CanIMogItDatabase) then
        StaticPopup_Show("CANIMOGIT_NEW_DATABASE")
    end
    self.db = LibStub("AceDB-3.0"):New("CanIMogItDatabase", default)
end

------------------------------------------------------------
-- Database Functions
------------------------------------------------------------

function CanIMogIt:GetAppearanceHash(appearanceID, itemLink)
    if not appearanceID or not itemLink then return end
    local slot = self:GetItemSlotName(itemLink)
    return appearanceID .. ":" .. slot
end

local function SourcePassesRequirement(source, requirementName, requirementValue)
    if source[requirementName] then
        if type(source[requirementName]) == "string" then
            -- single values, such as subClass = Plate
            if source[requirementName] ~= requirementValue then
                return false
            end
        elseif type(source[requirementName]) == "table" then
            -- multi-values, such as classRestrictions = Shaman, Hunter
            local found = false
            for index, sourceValue in pairs(source[requirementName]) do
                if sourceValue == requirementValue then
                    found = true
                end
            end
            if not found then
                return false
            end
        else
            return false
        end
    end
    return true
end


function CanIMogIt:DBHasAppearanceForRequirements(appearanceID, itemLink, requirements)
    --[[
        @param requirements: a table of {requirementName: value}, which will be
            iterated over for each known item to determine if all requirements are met.
            If the requirements are not met for any item, this will return false.
            For example, {"classRestrictions": "Druid"} would filter out any that don't
            include Druid as a class restriction. If the item doesn't have a restriction, it
            is assumed to not be a restriction at all.
    ]]
    if not self:DBHasAppearance(appearanceID, itemLink) then
        return false
    end
    for sourceID, source in pairs(self:DBGetSources(appearanceID, itemLink)) do
        for name, value in pairs(requirements) do
            if SourcePassesRequirement(source, name, value) then
                return true
            end
        end
    end
    return false
end


function CanIMogIt:DBHasAppearance(appearanceID, itemLink)
    local hash = self:GetAppearanceHash(appearanceID, itemLink)
    return self.db.global.appearances[hash] ~= nil
end


function CanIMogIt:DBAddAppearance(appearanceID, itemLink)
    if not self:DBHasAppearance(appearanceID, itemLink) then
        local hash = CanIMogIt:GetAppearanceHash(appearanceID, itemLink)
        self.db.global.appearances[hash] = {
            ["sources"] = {},
        }
    end
end


function CanIMogIt:DBRemoveAppearance(appearanceID, itemLink, dbHash)
    local hash = dbHash or self:GetAppearanceHash(appearanceID, itemLink)
    self.db.global.appearances[hash] = nil
end


function CanIMogIt:DBHasSource(appearanceID, sourceID, itemLink)
    if appearanceID == nil or sourceID == nil then return end
    if CanIMogIt:DBHasAppearance(appearanceID, itemLink) then
        local hash = self:GetAppearanceHash(appearanceID, itemLink)
        return self.db.global.appearances[hash].sources[sourceID] ~= nil
    end
    return false
end


function CanIMogIt:DBGetSources(appearanceID, itemLink)
    -- Returns the table of sources for the appearanceID.
    if self:DBHasAppearance(appearanceID, itemLink) then
        local hash = self:GetAppearanceHash(appearanceID, itemLink)
        return self.db.global.appearances[hash].sources
    end
end


CanIMogIt.itemsToAdd = {}

local function LateAddItems(event, itemID, success)
    if event == "GET_ITEM_INFO_RECEIVED" and itemID then
        -- The 8.0.1 update is causing this event to return a bunch of itemID=0
        if not success or itemID <= 0 then
            return
        end
        -- If the itemID is in itemsToAdd, first remove it from the table, then add it to the database.
        if CanIMogIt.itemsToAdd[itemID] then
            for sourceID, _ in pairs(CanIMogIt.itemsToAdd[itemID]) do
                local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
                local appearanceID = CanIMogIt:GetAppearanceIDFromSourceID(sourceID)
                CanIMogIt.itemsToAdd[itemID][sourceID] = nil
                CanIMogIt:DBAddItem(itemLink, appearanceID, sourceID)
            end
            if next(CanIMogIt.itemsToAdd[itemID]) == nil then
                CanIMogIt.itemsToAdd[itemID] = nil
            end
        end
    end
end
CanIMogIt.frame:AddEventFunction(LateAddItems)

function CanIMogIt:_DBSetItem(itemLink, appearanceID, sourceID)
    -- Sets the item in the database, or at least schedules for it to be set
    -- when we get item info back.
    if GetItemInfo(itemLink) then
        local hash = self:GetAppearanceHash(appearanceID, itemLink)
        if self.db.global.appearances[hash] == nil then
            return
        end
        local subClass = self:GetItemSubClassName(itemLink)
        local classRestrictions = self:GetItemClassRestrictions(itemLink)

        self.db.global.appearances[hash].sources[sourceID] = {
            ["subClass"] = subClass,
        }
        if classRestrictions then
            self.db.global.appearances[hash].sources[sourceID]["classRestrictions"] = classRestrictions
        else
            self.db.global.appearances[hash].sources[sourceID]["classRestrictions"] = nil
        end
        if subClass == nil then
            CanIMogIt:Print("nil subclass: " .. itemLink)
        end
        if CanIMogItOptions['databaseDebug'] then
            -- enabled/disabled via the `/cimi printdb` command
            CanIMogIt:Print("New item found: " .. itemLink .. " itemID: " .. CanIMogIt:GetItemID(itemLink) .. " sourceID: " .. sourceID .. " appearanceID: " .. appearanceID)
        end
    else
        local itemID = CanIMogIt:GetItemID(itemLink)
        if not CanIMogIt.itemsToAdd[itemID] then
            CanIMogIt.itemsToAdd[itemID] = {}
        end
        CanIMogIt.itemsToAdd[itemID][sourceID] = true
    end
end


function CanIMogIt:DBAddItem(itemLink, appearanceID, sourceID)
    -- Adds the item to the database. Returns true if it added something, false otherwise.
    if appearanceID == nil or sourceID == nil then
        appearanceID, sourceID = self:GetAppearanceID(itemLink)
    end
    if appearanceID == nil or sourceID == nil then return end
    self:DBAddAppearance(appearanceID, itemLink)
    if not self:DBHasSource(appearanceID, sourceID, itemLink) then
        CanIMogIt:_DBSetItem(itemLink, appearanceID, sourceID)
        return true
    end
    return false
end


function CanIMogIt:DBRemoveItem(appearanceID, sourceID, itemLink, dbHash)
    -- The specific dbHash can be passed in to bypass trying to generate it.
    -- This is used mainly when Blizzard removes or changes item appearanceIDs.
    local hash = dbHash or self:GetAppearanceHash(appearanceID, itemLink)
    appearanceID = appearanceID or CanIMogIt.Utils.strsplit(":", hash)[1]
    if self.db.global.appearances[hash] == nil then return end
    if self.db.global.appearances[hash].sources[sourceID] ~= nil then
        self.db.global.appearances[hash].sources[sourceID] = nil
        if next(self.db.global.appearances[hash].sources) == nil then
            self:DBRemoveAppearance(appearanceID, itemLink, dbHash)
        end
        if CanIMogItOptions['databaseDebug'] then
            local itemID, itemLink
            if itemLink then
                itemID = CanIMogIt:GetItemID(itemLink)
            else
                itemID = "nil"
            end
            if sourceID then
                itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
            end
            if not itemLink then
                itemLink = "nil"
            end
            CanIMogIt:Print("Item removed: " .. itemLink .. " itemID: " .. itemID .. " sourceID: " .. sourceID .. " appearanceID: " .. appearanceID)
        end
    end
end


function CanIMogIt:DBHasItem(itemLink)
    local appearanceID, sourceID = self:GetAppearanceID(itemLink)
    if appearanceID == nil or sourceID == nil then return end
    return self:DBHasSource(appearanceID, sourceID, itemLink)
end


function CanIMogIt:DBReset()
    CanIMogItDatabase = nil
    CanIMogIt.db = nil
    ReloadUI()
end


function CanIMogIt:SetsDBAddSetItem(set, sourceID)
    if CanIMogIt.db.global.setItems == nil then
        CanIMogIt.db.global.setItems = {}
    end

    CanIMogIt.db.global.setItems[sourceID] = set.setID
end

function CanIMogIt:SetsDBGetSetFromSourceID(sourceID)
    if CanIMogIt.db.global.setItems == nil then return end

    return CanIMogIt.db.global.setItems[sourceID]
end


local function GetAppearancesEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        -- Make sure the database is updated to the latest version
        UpdateDatabaseIfNeeded()
        -- add all known appearanceID's to the database
        CanIMogIt:GetAppearances()
        CanIMogIt:GetSets()
    end
end
CanIMogIt.frame:AddEventFunction(GetAppearancesEvent)


local transmogEvents = {
    ["TRANSMOG_COLLECTION_SOURCE_ADDED"] = true,
    ["TRANSMOG_COLLECTION_SOURCE_REMOVED"] = true,
    ["TRANSMOG_COLLECTION_UPDATED"] = true,
}

local function TransmogCollectionUpdated(event, sourceID, ...)
    if transmogEvents[event] and sourceID then
        -- Get the appearanceID from the sourceID
        if event == "TRANSMOG_COLLECTION_SOURCE_ADDED" then
            local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
            local appearanceID = CanIMogIt:GetAppearanceIDFromSourceID(sourceID)
            if itemLink and appearanceID then
                CanIMogIt:DBAddItem(itemLink, appearanceID, sourceID)
            end
        elseif event == "TRANSMOG_COLLECTION_SOURCE_REMOVED" then
            local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
            local appearanceID = CanIMogIt:GetAppearanceIDFromSourceID(sourceID)
            if itemLink and appearanceID then
                CanIMogIt:DBRemoveItem(appearanceID, sourceID, itemLink)
            end
        end
        if sourceID then
            CanIMogIt.cache:RemoveItemBySourceID(sourceID)
        end
        CanIMogIt.frame:ItemOverlayEvents("BAG_UPDATE")
    end
end

CanIMogIt.frame:AddEventFunction(TransmogCollectionUpdated)


-- function CanIMogIt.frame:GetItemInfoReceived(event, ...)
--     if event ~= "GET_ITEM_INFO_RECEIVED" then return end
--     Database:GetItemInfoReceived()
-- end
