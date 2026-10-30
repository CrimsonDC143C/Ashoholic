C_Library = C_Library or { };

local _bookIDs = { };
local _hiddenBookIDs = { };
local _filteredBookIDs = { };
local _showCollected = nil;
local _showUncollected = nil;
local _showSubscription = nil;
local _showItems = nil;
local _showObjects = nil;
local _sources = { };
local _expansions = { };
local _search = nil;

local function PrepareFilter()
    _showCollected = C_Library.GetCollectedShown();
    _showUncollected = C_Library.GetUncollectedShown();
    _showSubscription = C_Library.GetSubscriptionShown();
    _showItems = C_Library.GetItemsShown();
    _showObjects = C_Library.GetObjectsShown();
    for filterIndex = 1, C_PetJournal.GetNumPetSources() do
        _sources[filterIndex] = not C_Library.IsSourceTypeFilterChecked(filterIndex);
    end
    for filterIndex = 1, GetNumExpansions() do
        _expansions[filterIndex] = not C_Library.IsExpansionTypeFilterChecked(filterIndex);
    end
    _search = ezCollections:PrepareSearchQuery(_search);
end

local function MatchesFilter(bookID)
    local book = ezCollections:GetBookInfo(bookID);
    if not bookID or not book then
        return false;
    end
    local isCollected = ezCollections:HasBook(bookID);
    local viaSubscription = not isCollected and ezCollections:IsActiveLibrarySubscriptionBook(bookID);

    -- Hidden until learned
    if bit.band(book.flags, 0x2) ~= 0 and not isCollected and not viaSubscription and not ezCollections.Config.Wardrobe.BooksShowHidden then
        return false, true;
    end

    if viaSubscription then
        if not _showSubscription then
            return false;
        end
    elseif not (_showCollected and isCollected or _showUncollected and not isCollected) then
        return false;
    end

    if not _showItems or not _showObjects then
        local show = false;
        for _, source in ezCollections:IterateOverTableOrValue(book.sources) do
            if source > 0 and _showItems or source < 0 and _showObjects then
                show = true;
                break;
            end
        end
        if not show then
            return false;
        end
    end

    if not _sources[book.sourceType + 1] then
        return false;
    end

    if not _expansions[book.expansion + 1] then
        return false;
    end

    if _search and not ezCollections:TextMatchesSearch(C_Library.GetBookInfo(bookID) or "", _search) then
        return false;
    end

    return true;
end

function C_Library.RefreshBooks()
    table.wipe(_bookIDs);
    table.wipe(_hiddenBookIDs);
    table.wipe(_filteredBookIDs);

    PrepareFilter();

    for id, info in pairs(ezCollections.Cache.Books) do
        if type(id) == "number" then
            table.insert(_bookIDs, id);
            local matches, hidden = MatchesFilter(id);
            if matches then
                table.insert(_filteredBookIDs, id);
            elseif hidden then
                table.insert(_hiddenBookIDs, id);
            end
        end
    end

    table.sort(_filteredBookIDs, function(a, b)
        local nameA = C_Library.GetBookInfo(a);
        local nameB = C_Library.GetBookInfo(b);
        local isFavoriteA = C_Library.GetIsFavorite(a);
        local isFavoriteB = C_Library.GetIsFavorite(b);

        if isFavoriteA ~= isFavoriteB then
            return isFavoriteA;
        end

        if nameA ~= nameB then
            return nameA < nameB;
        end

        return a < b;
    end);
end

function C_Library.GetBooks()
    return _bookIDs;
end

function C_Library.OpenBook(bookID)
    if ItemTextFrame:IsShown() and ezCollections.CurrentBookID == bookID then
        HideUIPanel(ItemTextFrame);
        return;
    end

    if not ezCollections:HasAvailableBook(bookID) then
        return;
    end

    HideUIPanel(ItemTextFrame);
    ezCollections:SendAddonMessage(format("BOOK:OPEN:%d", bookID));
end

function C_Library.GetBookFromIndex(itemIndex)
    return _filteredBookIDs[itemIndex] or -1;
end

function C_Library.GetNumBooks()
    return #_bookIDs;
end

function C_Library.GetNumFilteredBooks()
    return #_filteredBookIDs;
end

function C_Library.GetNumTotalDisplayedBooks()
    return #_bookIDs - #_hiddenBookIDs;
end

function C_Library.GetNumLearnedDisplayedBooks()
    local collected = 0;
    for _, bookID in ipairs(_bookIDs) do
        if ezCollections:HasBook(bookID) then
            collected = collected + 1;
        end
    end
    return collected;
end

function C_Library.GetBookInfo(bookID)
    local book = ezCollections:GetBookInfo(bookID);
    local icon;
    if book.icon then
        icon = [[Interface\Icons\]]..book.icon;
    else
        for _, source in ezCollections:IterateOverTableOrValue(book.sources) do
            if source > 0 then
                icon = GetItemIcon(source);
            end
        end
    end
    return book.name or "", icon or "";
end

function C_Library.GetBookLink(bookID)
    local book = ezCollections:GetBookInfo(bookID);
    for _, source in ezCollections:IterateOverTableOrValue(book.sources) do
        if source > 0 then
            return select(2, GetItemInfo(source)) or book.name or "";
        end
    end
    return book.name or "";
end

function C_Library.SetCollectedShown(checked)
    ezCollections:SetCVarBitfield("libraryCollectedFilters", 1, not checked);
end

function C_Library.SetUncollectedShown(checked)
    ezCollections:SetCVarBitfield("libraryCollectedFilters", 2, not checked);
end

function C_Library.SetSubscriptionShown(checked)
    ezCollections:SetCVarBitfield("libraryCollectedFilters", 4, not checked);
end

function C_Library.SetItemsShown(checked)
    ezCollections:SetCVarBitfield("libraryCollectedFilters", 5, not checked);
end

function C_Library.SetObjectsShown(checked)
    ezCollections:SetCVarBitfield("libraryCollectedFilters", 6, not checked);
end

function C_Library.GetCollectedShown()
    return not ezCollections:GetCVarBitfield("libraryCollectedFilters", 1);
end

function C_Library.GetUncollectedShown()
    return not ezCollections:GetCVarBitfield("libraryCollectedFilters", 2);
end

function C_Library.GetSubscriptionShown()
    return not ezCollections:GetCVarBitfield("libraryCollectedFilters", 4);
end

function C_Library.GetItemsShown()
    return not ezCollections:GetCVarBitfield("libraryCollectedFilters", 5);
end

function C_Library.GetObjectsShown()
    return not ezCollections:GetCVarBitfield("libraryCollectedFilters", 6);
end

function C_Library.SetFilterString(string)
    _search = string;
end

function C_Library.SetSourceTypeFilter(sourceIndex, checked)
    ezCollections:SetCVarBitfield("librarySourceFilters", sourceIndex, not checked);
end

function C_Library.SetExpansionTypeFilter(expansionIndex, checked)
    ezCollections:SetCVarBitfield("libraryExpansionFilters", expansionIndex, not checked);
end

function C_Library.IsSourceTypeFilterChecked(sourceIndex)
    return ezCollections:GetCVarBitfield("librarySourceFilters", sourceIndex);
end

function C_Library.IsExpansionTypeFilterChecked(expansionIndex)
    return ezCollections:GetCVarBitfield("libraryExpansionFilters", expansionIndex);
end

function C_Library.SetAllSourceTypeFilters(checked)
    for filterIndex = 1, C_PetJournal.GetNumPetSources() do
        ezCollections:SetCVarBitfield("librarySourceFilters", filterIndex, not checked);
    end
end

function C_Library.SetAllExpansionTypeFilters(checked)
    for filterIndex = 1, GetNumExpansions() do
        ezCollections:SetCVarBitfield("libraryExpansionFilters", filterIndex, not checked);
    end
end

function C_Library.SetDefaultFilters()
    ezCollections:SetCVar("libraryCollectedFilters", 0);
    ezCollections:SetCVar("librarySourceFilters", 0);
    ezCollections:SetCVar("libraryExpansionFilters", 0);
end

function C_Library.IsUsingDefaultFilters()
    return ezCollections:GetCVar("libraryCollectedFilters") == 0
        and ezCollections:GetCVar("librarySourceFilters") == 0
        and ezCollections:GetCVar("libraryExpansionFilters") == 0;
end

function C_Library.SetIsFavorite(itemID, value)
    ezCollections:GetLibraryFavoritesContainer()[itemID] = value and true or nil;
    ezCollections:RaiseEvent("LIBRARY_UPDATED");
end

function C_Library.GetIsFavorite(itemID)
    return ezCollections:GetLibraryFavoritesContainer()[itemID] and true or false;
end

function C_Library.HasFavorites()
    return next(ezCollections:GetLibraryFavoritesContainer()) ~= nil;
end
