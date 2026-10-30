local BOOKS_PER_PAGE = 18;

function Library_OnLoad(self)
	Mixin(self, SetShownMixin);
	Mixin(self.SubscriptionStatus, SetShownMixin);
	self.mostRecentCollectedBookID = UIParent.mostRecentCollectedBookID or nil;
	self.newBooks = UIParent.newBooks or {};

	Library_UpdatePages();
	Library_UpdateProgressBar(self);

	ezCollections:UIDropDownMenu_Initialize(self.bookOptionsMenu, BookOptionsMenu_Init, "MENU");

	ezCollections:RegisterEvent(self, "LIBRARY_UPDATED");

	self.OnPageChanged = function(userAction)
		PlaySound("igAbiliityPageTurn");
		CloseDropDownMenus();
		Library_UpdateButtons();
	end

	UIPanelWindows["ItemTextFrame"].pushable = 1;
	ItemTextFrame:SetAttribute("UIPanelLayout-pushable", 1);
end

function Library_OnEvent(self, event, bookID, new)
	if ( event == "LIBRARY_UPDATED" ) then
		if (new) then
			self.mostRecentCollectedBookID = bookID;
			if ( not CollectionsJournal:IsShown() ) then
				CollectionsJournal_SetTab(CollectionsJournal, 4);
			end
			self.newBooks[bookID] = true;
		end

		C_Library.RefreshBooks();
		Library_UpdatePages();
		Library_UpdateProgressBar(self);
		Library_UpdateButtons();

		if (new) then
			self.newBooks[bookID] = true;
		end
	end
end

function Library_OnShow(self)
	SetPortraitToTexture(CollectionsJournalPortrait, [[Interface\AddOns\ezCollections\Interface\Icons\INV_7xp_Inscription_TalentTome01]]);
    ezCollections:RaiseEvent("LIBRARY_UPDATED");

	C_Library.RefreshBooks();
	Library_UpdatePages();
	Library_UpdateProgressBar(self);
	Library_UpdateButtons();
	LibraryResetFiltersButton_UpdateVisibility();
	CollectionsClickCollect:Attach(CollectionsJournal, self.iconsFrame.OverlayLayer, ezCollections.L["ClickCollect.Library.Header"], ezCollections.L["ClickCollect.Library.Text"]);
end

function Library_FindPageForBookID(bookID)
	for i = 1, C_Library.GetNumFilteredBooks() do
		if C_Library.GetBookFromIndex(i) == bookID then
			return math.floor((i - 1) / BOOKS_PER_PAGE) + 1;
		end
	end

	return nil;
end

function Library_OnMouseWheel(self, value)
	Library.PagingFrame:OnMouseWheel(value);
end

function BookOptionsMenu_Init(self, level)
	local info = UIDropDownMenu_CreateInfo();
	info.notCheckable = true;
	info.disabled = nil;

	local isFavorite = Library.menuBookID and C_Library.GetIsFavorite(Library.menuBookID);

	if (isFavorite) then
		info.text = BATTLE_PET_UNFAVORITE;
		info.func = function()
			C_Library.SetIsFavorite(Library.menuBookID, false);
		end
	else
		info.text = BATTLE_PET_FAVORITE;
		info.func = function()
			C_Library.SetIsFavorite(Library.menuBookID, true);
			Library.favoriteHelpBox:Hide();
		end
	end

	UIDropDownMenu_AddButton(info, level);
	info.disabled = nil;

	info.text = CANCEL;
	info.func = nil;
	UIDropDownMenu_AddButton(info, level);

	if ezCollections.Developer then
		info = UIDropDownMenu_CreateInfo();
		info.text = " ";
		info.disabled = true;
		UIDropDownMenu_AddButton(info);

		info = UIDropDownMenu_CreateInfo();
		info.text = "Developer";
		info.isTitle = true;
		info.notCheckable = true;
		UIDropDownMenu_AddButton(info);

		info = UIDropDownMenu_CreateInfo();
		info.text = ezCollections:HasBook(Library.menuBookID) and "Lock" or "Unlock";
		info.notCheckable = true;
		info.func = function() ezCollections:SendAddonMessage(format("DEV:%sLOCKBOOK:%d", ezCollections:HasBook(Library.menuBookID) and "" or "UN", Library.menuBookID)); end;
		UIDropDownMenu_AddButton(info);

		local book = ezCollections:GetBookInfo(Library.menuBookID);
		for _, source in ezCollections:IterateOverTableOrValue(book.sources) do
			if source > 0 then
				info = UIDropDownMenu_CreateInfo();
				info.text = "Add Item";
				info.notCheckable = true;
				info.func = function() ezCollections:SendAddonCommand(format(".additem %d", source)); end;
				UIDropDownMenu_AddButton(info);

				info = UIDropDownMenu_CreateInfo();
				info.text = "Delete Item";
				info.notCheckable = true;
				info.func = function() ezCollections:SendAddonCommand(format(".additem %d -1", source)); end;
				UIDropDownMenu_AddButton(info);
			elseif source < 0 then
				info = UIDropDownMenu_CreateInfo();
				info.text = "Teleport To Object";
				info.notCheckable = true;
				info.func = function() ezCollections:SendAddonCommand(format(".go object id %d", -source)); end;
				UIDropDownMenu_AddButton(info);
			end
		end
	end
end

function Library_ShowLibraryDropdown(bookID, anchorTo, offsetX, offsetY)
	Library.menuBookID = bookID;
	CloseDropDownMenus();
	ToggleDropDownMenu(1, nil, Library.bookOptionsMenu, anchorTo, offsetX, offsetY);
	PlaySound("igMainMenuOptionCheckBoxOn");
end

function Library_HideLibraryDropdown()
	if (UIDropDownMenu_GetCurrentDropDown() == Library.bookOptionsMenu) then
		HideDropDownMenu(1);
	end
end

function LibrarySpellButton_OnShow(self)
	self:RegisterEvent("ITEM_TEXT_BEGIN");
	self:RegisterEvent("ITEM_TEXT_READY");
	self:RegisterEvent("ITEM_TEXT_CLOSED");
	ezCollections:RegisterEvent(self, "LIBRARY_UPDATED");
	ezCollections:RegisterEvent(self, "LIBRARY_CURRENT_UPDATE");

	CollectionsSpellButton_OnShow(self);
end

function LibrarySpellButton_OnHide(self)
	CollectionsSpellButton_OnHide(self);

	self:UnregisterEvent("ITEM_TEXT_BEGIN");
	self:UnregisterEvent("ITEM_TEXT_READY");
	self:UnregisterEvent("ITEM_TEXT_CLOSED");
	ezCollections:UnregisterEvent(self, "LIBRARY_UPDATED");
	ezCollections:UnregisterEvent(self, "LIBRARY_CURRENT_UPDATE");
end

function LibrarySpellButton_OnEnter(self)
	local book = ezCollections:GetBookInfo(self.bookID);
	local link = C_Library.GetBookLink(self.bookID);
	GameTooltip:ClearLines();
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:AddLine((link:gsub("[%[%]]", "")));
	local text = "";
	for _, source in ezCollections:IterateOverTableOrValue(book.sources) do
		local items, objects;
		if source > 0 and not items then
			items = true;
			text = text .. (text == "" and "" or ", ") .. ezCollections.L["Tooltip.Books.Sources.Item"];
		elseif source < 0 and not objects then
			objects = true;
			text = text .. (text == "" and "" or ", ") .. ezCollections.L["Tooltip.Books.Sources.Object"];
		end
	end
	if text ~= "" then
		GameTooltip:AddLine(text, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
	end

	local hasBook = ezCollections:HasBook(self.bookID);
	if not hasBook and ezCollections:IsActiveLibrarySubscriptionBook(self.bookID) then
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine(ezCollections.L["Library.Subscription.Details.Info"], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, 1);
	end
	if not hasBook or ezCollections.Config.Wardrobe.ShowCollectedBookSourceText then
		if book.sourceText then
			GameTooltip:AddLine(" ");
			GameTooltip:AddLine(book.sourceText, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, 1);
		end
	end

	if ezCollections.Developer then
		GameTooltip:AddLine("Book ID: "..self.bookID, 0.5, 0.5, 0.5);
		for _, source in ezCollections:IterateOverTableOrValue(book.sources) do
			GameTooltip:AddLine((source > 0 and "Item" or "Object").." ID: "..abs(source), 0.5, 0.5, 0.5);
		end
	end

	GameTooltip:Show();
	self.UpdateTooltip = LibrarySpellButton_OnEnter;

	if(Library.newBooks[self.bookID] ~= nil) then
		Library.newBooks[self.bookID] = nil;
		LibrarySpellButton_UpdateButton(self);
	end
end

function LibrarySpellButton_OnClick(self, button)
	if ( button ~= "LeftButton" ) then
		if ezCollections:HasAvailableBook(self.bookID) or ezCollections.Developer then
			Library_ShowLibraryDropdown(self.bookID, self, 0, 0);
		end
	else
		if GetCursorInfo() then
			return;
		end
		C_Library.OpenBook(self.bookID);
	end
end

function LibrarySpellButton_OnModifiedClick(self, button)
	if ( IsModifiedClick("CHATLINK") ) then
		local itemLink = C_Library.GetBookLink(self.bookID);
		if ( itemLink ) then
			ChatEdit_InsertLink(itemLink);
		end
	end
end

function LibrarySpellButton_UpdateButton(self)
	local itemIndex = (Library.PagingFrame:GetCurrentPage() - 1) * BOOKS_PER_PAGE + self:GetID();
	self.bookID = C_Library.GetBookFromIndex(itemIndex);

	local libraryString = self.name;
	local libraryNewString = self.new;
	local libraryNewGlow = self.newGlow;
	local iconTexture = self.iconTexture;
	local iconTextureUncollected = self.iconTextureUncollected;
	local slotFrameCollected = self.slotFrameCollected;
	local slotFrameUncollected = self.slotFrameUncollected;
	local slotFrameUncollectedInnerGlow = self.slotFrameUncollectedInnerGlow;
	local iconFavoriteTexture = self.cooldownWrapper.slotFavorite;

	if (self.bookID == -1) then
		self:Hide();
		return;
	end

	self:Show();

	local bookName, icon = C_Library.GetBookInfo(self.bookID);

	if not bookName then
		return;
	end

	if string.len(bookName) == 0 then
		bookName = self.bookID;
	end

	iconTexture:SetTexture(icon);
	iconTextureUncollected:SetTexture(icon);
	iconTextureUncollected:SetDesaturated(true);
	libraryString:SetText(bookName);
	libraryString:Show();

	if (Library.newBooks[self.bookID] ~= nil) then
		libraryNewString:Show();
		libraryNewGlow:Show();
	else
		libraryNewString:Hide();
		libraryNewGlow:Hide();
	end

	if C_Library.GetIsFavorite(self.bookID) then
		iconFavoriteTexture:Show();
	else
		iconFavoriteTexture:Hide();
	end

	if ezCollections:HasAvailableBook(self.bookID) then
		iconTexture:Show();
		iconTextureUncollected:Hide();
		libraryString:SetTextColor(1, 0.82, 0, 1);
		libraryString:SetShadowColor(0, 0, 0, 1);
		slotFrameCollected:Show();
		slotFrameUncollected:Hide();
		slotFrameUncollectedInnerGlow:Hide();

		self.SubscriptionOverlay:SetShown(not ezCollections:HasBook(self.bookID) and ezCollections:IsActiveLibrarySubscriptionBook(self.bookID));
	else
		iconTexture:Hide();
		iconTextureUncollected:Show();
		libraryString:SetTextColor(0.33, 0.27, 0.20, 1);
		libraryString:SetShadowColor(0, 0, 0, 0.33);
		slotFrameCollected:Hide();
		slotFrameUncollected:Show();
		slotFrameUncollectedInnerGlow:Show();
		self.SubscriptionOverlay:Hide();
	end

	self.active:SetShown(ItemTextFrame:IsShown() and ezCollections.CurrentBookID == self.bookID);
end

function Library_UpdateButtons()
	Library.favoriteHelpBox:Hide();
	for i = 1, BOOKS_PER_PAGE do
		local button = Library.iconsFrame["spellButton"..i];
		LibrarySpellButton_UpdateButton(button);
	end

	Library.SubscriptionStatus.SubscriptionInfo:SetShown(ezCollections:IsActiveLibrarySubscription());
	Library.SubscriptionStatus:SetShown(Library.SubscriptionStatus.SubscriptionInfo:IsShown());
end

function Library_UpdatePages()
	local maxPages = 1 + math.floor( math.max((C_Library.GetNumFilteredBooks() - 1), 0) / BOOKS_PER_PAGE);
	Library.PagingFrame:SetMaxPages(maxPages)
	if Library.mostRecentCollectedBookID then
		local bookPage = Library_FindPageForBookID(Library.mostRecentCollectedBookID);
		if bookPage then
			Library.PagingFrame:SetCurrentPage(bookPage);
		end
		Library.mostRecentCollectedBookID = nil;
	end
end

function Library_UpdateProgressBar(self)
	local maxProgress = C_Library.GetNumTotalDisplayedBooks();
	local currentProgress = C_Library.GetNumLearnedDisplayedBooks();

	self.progressBar:SetMinMaxValues(0, maxProgress);
	self.progressBar:SetValue(currentProgress);

	self.progressBar.text:SetFormattedText(TOY_PROGRESS_FORMAT, currentProgress, maxProgress);
end

function Library_OnSearchTextChanged(self)
	SearchBoxTemplate_OnTextChanged(self);
	local oldText = Library.searchString;
	Library.searchString = self:GetText();

	if ( oldText ~= Library.searchString ) then
		C_Library.SetFilterString(Library.searchString);
		C_Library.RefreshBooks();
		Library_UpdatePages();
		Library_UpdateButtons();
	end
end

function Library_CollectAvailableFilters()
	Library.baseFilterTypes = { };
	for i = 1, C_PetJournal.GetNumPetSources() do
		Library.baseFilterTypes[i] = false;
	end
	for _, bookID in ipairs(C_Library.GetBooks()) do
		local sourceType = ezCollections:GetBookInfo(bookID).sourceType;
		Library.baseFilterTypes[sourceType and sourceType + 1 or 12] = true;
	end
end

function LibraryFilterDropDown_OnLoad(self)
	ezCollections:UIDropDownMenu_Initialize(self, LibraryFilterDropDown_Initialize, "MENU");
end

function LibraryUpdateFilteredInformation()
	C_Library.RefreshBooks();
	Library_UpdatePages();
	Library_UpdateButtons();
	LibraryResetFiltersButton_UpdateVisibility();
end

function LibraryFilterDropDown_ResetFilters()
	C_Library.SetDefaultFilters();
	LibraryFilterButton.ResetButton:Hide();
	LibraryUpdateFilteredInformation();
end

function LibraryResetFiltersButton_UpdateVisibility()
	LibraryFilterButton.ResetButton:SetShown(not C_Library.IsUsingDefaultFilters());
end

function LibraryFilterDropDown_Initialize(self, level)
	local info = UIDropDownMenu_CreateInfo();
	info.keepShownOnClick = true;

	if level == 1 then
		info.text = COLLECTED;
		info.func = function(_, _, _, value)
						C_Library.SetCollectedShown(value);
						LibraryUpdateFilteredInformation();
					end
		info.checked = C_Library.GetCollectedShown();
		info.isNotRadio = true;
		UIDropDownMenu_AddButton(info, level);

		info.text = NOT_COLLECTED;
		info.func = function(_, _, _, value)
						C_Library.SetUncollectedShown(value);
						LibraryUpdateFilteredInformation();
					end
		info.checked = C_Library.GetUncollectedShown();
		info.isNotRadio = true;
		UIDropDownMenu_AddButton(info, level);

		if ezCollections:IsActiveLibrarySubscription() then
			info.text = ezCollections.L["Library.Filter.Subscription"];
			info.func = function(_, _, _, value)
							C_Library.SetSubscriptionShown(value);
							LibraryUpdateFilteredInformation();
						end
			info.checked = C_Library.GetSubscriptionShown();
			info.isNotRadio = true;
			UIDropDownMenu_AddButton(info, level);
		end

		info.checked = nil;
		info.isNotRadio = nil;
		info.func = function(self) _G[self:GetName().."Check"]:Hide(); end;
		info.hasArrow = true;
		info.notCheckable = true;

		info.text = ezCollections.L["Tooltip.Books.Sources"];
		info.value = 3;
		UIDropDownMenu_AddButton(info, level);

		info.text = SOURCES;
		info.value = 1;
		UIDropDownMenu_AddButton(info, level);

		info.text = EXPANSION_FILTER_TEXT;
		info.value = 2;
		UIDropDownMenu_AddButton(info, level);
	else
		if UIDROPDOWNMENU_MENU_VALUE == 1 then
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;

			info.text = CHECK_ALL;
			info.func = function()
							C_Library.SetAllSourceTypeFilters(true);
							UIDropDownMenu_Refresh2(LibraryFilterDropDown, 1, 2);
							LibraryUpdateFilteredInformation();
						end
			UIDropDownMenu_AddButton(info, level);

			info.text = UNCHECK_ALL;
			info.func = function()
							C_Library.SetAllSourceTypeFilters(false);
							UIDropDownMenu_Refresh2(LibraryFilterDropDown, 1, 2);
							LibraryUpdateFilteredInformation();
						end
			UIDropDownMenu_AddButton(info, level);

			info.notCheckable = false;
			Library_CollectAvailableFilters();
			local numSources = C_PetJournal.GetNumPetSources();
			for i=1,numSources do
				if Library.baseFilterTypes[i] then
					info.text = _G["BATTLE_PET_SOURCE_"..i];
					info.func = function(_, _, _, value)
								C_Library.SetSourceTypeFilter(i, value);
								LibraryUpdateFilteredInformation();
							end
					info.checked = function() return not C_Library.IsSourceTypeFilterChecked(i) end;
					UIDropDownMenu_AddButton(info, level);
				end
			end
		end
		if UIDROPDOWNMENU_MENU_VALUE == 2 then
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;

			info.text = CHECK_ALL;
			info.func = function()
							C_Library.SetAllExpansionTypeFilters(true);
							UIDropDownMenu_Refresh2(LibraryFilterDropDown, 1, 2);
							LibraryUpdateFilteredInformation();
						end
			UIDropDownMenu_AddButton(info, level);

			info.text = UNCHECK_ALL;
			info.func = function()
							C_Library.SetAllExpansionTypeFilters(false);
							UIDropDownMenu_Refresh2(LibraryFilterDropDown, 1, 2);
							LibraryUpdateFilteredInformation();
						end
			UIDropDownMenu_AddButton(info, level);

			info.notCheckable = false;
			local numExpansions = GetNumExpansions();
			for i=1,numExpansions do
				info.text = _G["EXPANSION_NAME"..i-1]; --Since the global strings for expansion are 0 - Max Expansion
				info.func = function(_, _, _, value)
							C_Library.SetExpansionTypeFilter(i, value);
							LibraryUpdateFilteredInformation();
						end
				info.checked = function() return not C_Library.IsExpansionTypeFilterChecked(i) end;
				UIDropDownMenu_AddButton(info, level);
			end
		end
		if UIDROPDOWNMENU_MENU_VALUE == 3 then
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;

			info.text = CHECK_ALL;
			info.func = function()
							C_Library.SetItemsShown(true);
							C_Library.SetObjectsShown(true);
							UIDropDownMenu_Refresh2(LibraryFilterDropDown, 1, 2);
							LibraryUpdateFilteredInformation();
						end
			UIDropDownMenu_AddButton(info, level);

			info.text = UNCHECK_ALL;
			info.func = function()
							C_Library.SetItemsShown(false);
							C_Library.SetObjectsShown(false);
							UIDropDownMenu_Refresh2(LibraryFilterDropDown, 1, 2);
							LibraryUpdateFilteredInformation();
						end
			UIDropDownMenu_AddButton(info, level);

			info.notCheckable = false;

			info.text = ezCollections.L["Tooltip.Books.Sources.Item"];
			info.func = function(_, _, _, value)
						C_Library.SetItemsShown(value);
						LibraryUpdateFilteredInformation();
					end
			info.checked = function() return C_Library.GetItemsShown() end;
			UIDropDownMenu_AddButton(info, level);

			info.text = ezCollections.L["Tooltip.Books.Sources.Object"];
			info.func = function(_, _, _, value)
						C_Library.SetObjectsShown(value);
						LibraryUpdateFilteredInformation();
					end
			info.checked = function() return C_Library.GetObjectsShown() end;
			UIDropDownMenu_AddButton(info, level);
		end
	end
end
