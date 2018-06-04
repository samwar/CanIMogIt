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


CanIMogIt_DatabaseVersion = 1.2


local default = {
    global = {
        databaseVersion = CanIMogIt_DatabaseVersion,
        appearances = {},
        setItems = {}
    }
}


local function UpdateTo1_1()
    local appearancesTable = copyTable(CanIMogIt.db.global.appearances)
    for appearanceID, appearance in pairs(appearancesTable) do
        local sources = appearance.sources
        for sourceID, source in pairs(sources) do
            -- Get the appearance hash for the source
            local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
            local hash = CanIMogIt:GetAppearanceHash(appearanceID, itemLink)
            -- Add the source to the appearances with the new hash key
            if not CanIMogIt.db.global.appearances[hash] then
                CanIMogIt.db.global.appearances[hash] = {
                    ["sources"] = {},
                }
            end
            CanIMogIt.db.global.appearances[hash].sources[sourceID] = source
        end
        -- Remove the old one
        CanIMogIt.db.global.appearances[appearanceID] = nil
    end
end


local function UpdateTo1_2()
    for hash, sources in pairs(CanIMogIt.db.global.appearances) do
        for sourceID, source in pairs(sources["sources"]) do
            local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
            local appearanceID = CanIMogIt:GetAppearanceIDFromSourceID(sourceID)
            if sourceID and appearanceID and itemLink then
                CanIMogIt:_DBSetItem(itemLink, appearanceID, sourceID)
            end
        end
    end
end


local function UpdateDatabase()
    CanIMogIt:Print("Migrating Database version to: " .. CanIMogIt_DatabaseVersion)
    if not CanIMogIt.db.global.databaseVersion then
        CanIMogIt.db.global.databaseVersion = 1.0
    end
    if  CanIMogIt.db.global.databaseVersion < 1.1 then
        UpdateTo1_1()
    end
    if CanIMogIt.db.global.databaseVersion < 1.2 then
        UpdateTo1_2()
    end
    CanIMogIt.db.global.databaseVersion = CanIMogIt_DatabaseVersion
    CanIMogIt:Print("Database migrated!")
end


local function UpdateDatabaseIfNeeded()
    if next(CanIMogIt.db.global.appearances) and
            (not CanIMogIt.db.global.databaseVersion
            or CanIMogIt.db.global.databaseVersion < CanIMogIt_DatabaseVersion) then
        UpdateDatabase()
    end
end


function CanIMogIt:OnInitialize()
    if (not CanIMogItDatabase) then
        StaticPopup_Show("CANIMOGIT_NEW_DATABASE")
    end
    self.db = LibStub("AceDB-3.0"):New("CanIMogItDatabase", default)
end


function CanIMogIt:GetAppearanceHash(appearanceID, itemLink)
    if not appearanceID or not itemLink then return end
    local slot = self:GetItemSlotName(itemLink)
    return appearanceID .. ":" .. slot
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


function CanIMogIt:DBRemoveAppearance(appearanceID, itemLink)
    local hash = self:GetAppearanceHash(appearanceID, itemLink)
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

local function LateAddItems(event, itemID)
    if event == "GET_ITEM_INFO_RECEIVED" and itemID then
        if CanIMogIt.itemsToAdd[itemID] then
            for sourceID, _ in pairs(CanIMogIt.itemsToAdd[itemID]) do
                local appearanceID = CanIMogIt:GetAppearanceIDFromSourceID(sourceID)
                local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
                CanIMogIt:_DBSetItem(itemLink, appearanceID, sourceID)
            end
            table.remove(CanIMogIt.itemsToAdd, itemID)
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
        self.db.global.appearances[hash].sources[sourceID] = {
            ["subClass"] = self:GetItemSubClassName(itemLink),
            ["classRestrictions"] = self:GetItemClassRestrictions(itemLink),
        }
        if self:GetItemSubClassName(itemLink) == nil then
            CanIMogIt:Print("nil subclass: " .. itemLink)
        end
        -- For testing:
        -- CanIMogIt:Print("New item found: " .. itemLink .. " itemID: " .. CanIMogIt:GetItemID(itemLink) .. " sourceID: " .. sourceID .. " appearanceID: " .. appearanceID)
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


function CanIMogIt:DBRemoveItem(appearanceID, sourceID, itemLink)
    local hash = self:GetAppearanceHash(appearanceID, itemLink)
    if self.db.global.appearances[hash] == nil then return end
    if self.db.global.appearances[hash].sources[sourceID] ~= nil then
        self.db.global.appearances[hash].sources[sourceID] = nil
        if next(self.db.global.appearances[hash].sources) == nil then
            self:DBRemoveAppearance(appearanceID, itemLink)
        end
        -- For testing:
        -- CanIMogIt:Print("Item removed: " .. CanIMogIt:GetItemLinkFromSourceID(sourceID) .. " itemID: " .. CanIMogIt:GetItemID(itemLink) .. " sourceID: " .. sourceID .. " appearanceID: " .. appearanceID)
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
    if transmogEvents[event] then
        -- Get the appearanceID from the sourceID
        if event == "TRANSMOG_COLLECTION_SOURCE_ADDED" then
            local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
            local appearanceID = CanIMogIt:GetAppearanceIDFromSourceID(sourceID)
            CanIMogIt:DBAddItem(itemLink, appearanceID, sourceID)
        elseif event == "TRANSMOG_COLLECTION_SOURCE_REMOVED" then
            local itemLink = CanIMogIt:GetItemLinkFromSourceID(sourceID)
            local appearanceID = CanIMogIt:GetAppearanceIDFromSourceID(sourceID)
            CanIMogIt:DBRemoveItem(appearanceID, sourceID, itemLink)
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
