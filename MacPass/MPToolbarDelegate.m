//
//  MPToolbarDelegate.m
//  MacPass
//
//  Created by michael starke on 18.02.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "MPToolbarDelegate.h"

#import "MPToolbarButton.h"
#import "MPToolbarItem.h"
#import "MPContextButton.h"
#import "MPAddEntryContextMenuDelegate.h"
#import "MPEntryContextMenuDelegate.h"

#import "MPActionHelper.h"
#import "MPContextMenuHelper.h"
#import "MPIconHelper.h"

#import "MPDocumentWindowController.h"
#import "MPDocument.h"

#import "NSApplication+MPAdditions.h"
#import "MPAppDelegate.h"

NSString *const MPToolbarItemIdentifierLock         = @"TOOLBAR_LOCK";
NSString *const MPToolbarItemIdentifierAddGroup     = @"TOOLBAR_ADD_GROUP";
NSString *const MPToolbarItemIdentifierAddEntry     = @"TOOLBAR_ADD_ENTRY";
NSString *const MPToolbarItemIdentifierDelete       = @"TOOLBAR_DELETE";
NSString *const MPToolbarItemIdentifierAction       = @"TOOLBAR_ACTION";
NSString *const MPToolbarItemIdentifierInspector    = @"TOOLBAR_INSPECTOR";
NSString *const MPToolbarItemIdentifierSearch       = @"TOOLBAR_SEARCH";
NSString *const MPToolbarItemIdentifierCopyUsername = @"TOOLBAR_COPY_USERNAME";
NSString *const MPToolbarItemIdentifierCopyPassword = @"TOOLBAR_COPY_PASSWORD";
NSString *const MPToolbarItemIdentifierHistory      = @"TOOLBAR_HISTORY";
NSString *const MPToolbarItemIdentifierAutotype     = @"TOOLBAR_AUTOTYPE";

@interface MPToolbarDelegate() {
  MPAddEntryContextMenuDelegate *_addEntryMenuDelegate;
  BOOL _didShowToolbarForSearch;
  BOOL _didAddSearchfieldForSearch;
  NSToolbarDisplayMode _displayModeBeforeSearch;
}

@property (strong) NSMutableDictionary *toolbarItems;
@property (strong) NSArray *toolbarIdentifiers;
@property (strong) NSArray *defaultToolbarIdentifiers;
@property (strong) NSDictionary *toolbarImages;
@property (weak) NSSearchField *searchField;
@property (strong) NSLayoutConstraint *searchFieldWidthConstraint;
@property CGFloat lastWindowWidth;

@end

static const CGFloat MPSearchFieldMinWidth = 140;
/* what is left of a flexible space next to the search field */
static const CGFloat MPSearchFieldFlexibleSpaceWidth = 8;
/* measuring again after a change settles in one pass, the limit only guards against a loop */
static const NSUInteger MPSearchFieldWidthPasses = 4;

@implementation MPToolbarDelegate

- (id)init {
  self = [super init];
  if (self) {
    _didShowToolbarForSearch = NO;
    _didAddSearchfieldForSearch = NO;
    _toolbarIdentifiers = @[ MPToolbarItemIdentifierAddEntry,
                             MPToolbarItemIdentifierDelete,
                             MPToolbarItemIdentifierAddGroup,
                             MPToolbarItemIdentifierAction,
                             MPToolbarItemIdentifierCopyPassword,
                             MPToolbarItemIdentifierCopyUsername,
                             NSToolbarFlexibleSpaceItemIdentifier,
                             MPToolbarItemIdentifierSearch,
                             MPToolbarItemIdentifierLock,
                             MPToolbarItemIdentifierInspector,
                             MPToolbarItemIdentifierHistory,
                             MPToolbarItemIdentifierAutotype ];
    _defaultToolbarIdentifiers = @[ MPToolbarItemIdentifierAddEntry,
                                    MPToolbarItemIdentifierDelete,
                                    MPToolbarItemIdentifierAddGroup,
                                    MPToolbarItemIdentifierAutotype,
                                    MPToolbarItemIdentifierAction,
                                    NSToolbarFlexibleSpaceItemIdentifier,
                                    MPToolbarItemIdentifierSearch,
                                    NSToolbarFlexibleSpaceItemIdentifier,
                                    MPToolbarItemIdentifierLock,
                                    MPToolbarItemIdentifierInspector ];
    _toolbarImages = [self createToolbarImages];
    _toolbarItems = [[NSMutableDictionary alloc] initWithCapacity:[self.toolbarIdentifiers count]];
    _addEntryMenuDelegate = [[MPAddEntryContextMenuDelegate alloc] init];
  }
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}


- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
  NSToolbarItem *item = self.toolbarItems[itemIdentifier];
  if(!item) {
    item = [[MPToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    NSString *itemLabel = [self _localizedLabelForToolbarItemIdentifier:itemIdentifier];
    item.label = itemLabel;
    item.paletteLabel = itemLabel;
    
    if([itemIdentifier isEqualToString:MPToolbarItemIdentifierAction]) {
      NSPopUpButton *popupButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 50, 32) pullsDown:YES];
      popupButton.bezelStyle = NSTexturedRoundedBezelStyle;
      popupButton.focusRingType = NSFocusRingTypeNone;
      popupButton.title = @"";
      popupButton.imageScaling = NSImageScaleProportionallyDown;
      [popupButton sizeToFit];
      
      NSRect newFrame = popupButton.frame;
      newFrame.size.width += 20;
      
      NSMenu *menu = [[NSMenu alloc] init];
      NSMenuItem *actionImageItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
      actionImageItem.image = self.toolbarImages[MPToolbarItemIdentifierAction];
      [menu addItem:actionImageItem];
      NSArray *menuItems = [MPContextMenuHelper contextMenuItemsWithItems:MPContextMenuExtended|MPContextMenuShowGroupInOutline];
      for(NSMenuItem *item in menuItems) {
        [menu addItem:item];
      }
      NSMenuItem *menuRepresentation = [[NSMenuItem alloc] initWithTitle:itemLabel
                                                                  action:[self _actionForToolbarItemIdentifier:itemIdentifier]
                                                           keyEquivalent:@""];
      menuRepresentation.submenu = menu;
      
      popupButton.frame = newFrame;
      popupButton.menu = menu;
      menu.delegate = NSApp.mp_delegate.itemActionMenuDelegate;
      item.menuFormRepresentation = menuRepresentation;
      item.view = popupButton;
      item.visibilityPriority = NSToolbarItemVisibilityPriorityHigh - 1;
    }
    else if( [itemIdentifier isEqualToString:MPToolbarItemIdentifierAddEntry]) {
      MPContextButton *button = [[MPContextButton alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
      button.action = [self _actionForToolbarItemIdentifier:itemIdentifier];
      NSImage *image = self.toolbarImages[itemIdentifier];
      image.size = NSMakeSize(16, 16);
      [button setImage:image];
      [button sizeToFit];
      
      NSMenu *menu = [[NSMenu alloc] init];
      [menu addItemWithTitle:NSLocalizedString(@"UNKNOWN_TOOLBAR_ITEM", @"") action:NULL keyEquivalent:@""];
      menu.delegate = _addEntryMenuDelegate;
      button.contextMenu = menu;
      
      NSRect fittingRect = button.frame;
      fittingRect.size.width = MAX( (CGFloat)32.0,fittingRect.size.width);
      button.frame = fittingRect;
      item.view = button;
      /* Create the Contextual Menu button */
      NSMenuItem *menuRepresentation = [[NSMenuItem alloc] initWithTitle:itemLabel
                                                                  action:[self _actionForToolbarItemIdentifier:itemIdentifier]
                                                           keyEquivalent:@""];
      item.menuFormRepresentation = menuRepresentation;
    }
    else if( [itemIdentifier isEqualToString:MPToolbarItemIdentifierSearch]){
      NSSearchField *searchField = [[NSSearchField alloc] init];
      searchField.action = @selector(updateSearch:);
      NSSearchFieldCell *cell = searchField.cell;
      cell.cancelButtonCell.action = @selector(exitSearch:);
      cell.cancelButtonCell.target = nil;
      searchField.recentsAutosaveName = @"RecentEntrySearches";
      item.view = searchField;
      item.visibilityPriority = NSToolbarItemVisibilityPriorityHigh;
      
      if(@available(macOS 11, *)) {
        /* Newer toolbars stop a resizable search field at about 330 pt, short of the Lock button.
         They keep a width set by a constraint, which -_updateSearchFieldWidthWithPasses: fits to the room around the field */
        NSLayoutConstraint *width = [searchField.widthAnchor constraintEqualToConstant:MPSearchFieldMinWidth];
        width.priority = NSLayoutPriorityDefaultHigh;
        width.active = YES;
        self.searchFieldWidthConstraint = width;
      }
      else {
        /* Use default size base on documentation */
        item.minSize = NSMakeSize(MPSearchFieldMinWidth, 32);
        item.maxSize = NSMakeSize(400, 32);
      }
      
      NSMenu *templateMenu = [self _allocateSearchMenuTemplate];
      searchField.searchMenuTemplate = templateMenu;
      searchField.placeholderString = NSLocalizedString(@"SEARCH_EVERYWHERE", @"Placeholder string displayed in the search field in the toolbar");
      searchField.delegate = self;
      self.searchField = searchField;
    }
    else {
      NSButton *button = [[MPToolbarButton alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
      NSImage *image = self.toolbarImages[itemIdentifier];
      image.size = NSMakeSize(16, 16);
      [button setImage:image];
      [button sizeToFit];
      button.action = [self _actionForToolbarItemIdentifier:itemIdentifier];
      
      NSRect fittingRect = [button frame];
      fittingRect.size.width = MAX( (CGFloat)32.0,fittingRect.size.width);
      button.frame = fittingRect;
      item.view = button;
      NSMenuItem *menuRepresentation = [[NSMenuItem alloc] initWithTitle:itemLabel
                                                                  action:[self _actionForToolbarItemIdentifier:itemIdentifier]
                                                           keyEquivalent:@""];
      item.menuFormRepresentation = menuRepresentation;
    }
    self.toolbarItems[itemIdentifier] = item;
  }
  return item;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
  return self.defaultToolbarIdentifiers;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
  return self.toolbarIdentifiers;
}

- (NSDictionary *)createToolbarImages {
  NSDictionary *imageDict = @{ MPToolbarItemIdentifierLock: [NSImage imageNamed:NSImageNameLockLockedTemplate],
                               MPToolbarItemIdentifierAddEntry: [MPIconHelper icon:MPIconAddEntry],
                               MPToolbarItemIdentifierAddGroup: [MPIconHelper icon:MPIconAddFolder],
                               MPToolbarItemIdentifierCopyUsername : [MPIconHelper icon:MPIconIdentity],
                               MPToolbarItemIdentifierCopyPassword : [MPIconHelper icon:MPIconPassword],
                               MPToolbarItemIdentifierDelete: [MPIconHelper icon:MPIconTrash],
                               MPToolbarItemIdentifierAction: [NSImage imageNamed:NSImageNameActionTemplate],
                               MPToolbarItemIdentifierInspector: [MPIconHelper icon:MPIconSidebar],
                               MPToolbarItemIdentifierHistory: [MPIconHelper icon:MPIconHistory],
                               MPToolbarItemIdentifierAutotype : [MPIconHelper icon:MPIconKeyboard]
  };
  return imageDict;
}


- (void)registerNotificationsForDocument:(MPDocument *)document {
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didExitSearch:) name:MPDocumentDidExitSearchNotification object:document];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didEnterSearch:) name:MPDocumentDidEnterSearchNotification object:document];
}

- (void)registerNotificationsForWindow:(NSWindow *)window {
  self.lastWindowWidth = NSWidth(window.frame);
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_windowDidResize:) name:NSWindowDidResizeNotification object:window];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_toolbarDidChangeItems:) name:NSToolbarWillAddItemNotification object:self.toolbar];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_toolbarDidChangeItems:) name:NSToolbarDidRemoveItemNotification object:self.toolbar];
  [self _scheduleSearchFieldWidthUpdate];
}

#pragma mark - Search field width

- (void)_windowDidResize:(NSNotification *)notification {
  NSWindow *window = notification.object;
  CGFloat width = NSWidth(window.frame);
  /* shrink the field before the toolbar lays out, else it moves items into the overflow menu */
  if(width < self.lastWindowWidth) {
    NSLayoutConstraint *fieldWidth = self.searchFieldWidthConstraint;
    fieldWidth.constant = MAX(MPSearchFieldMinWidth, fieldWidth.constant - (self.lastWindowWidth - width));
  }
  self.lastWindowWidth = width;
  [self _scheduleSearchFieldWidthUpdate];
}

- (void)_toolbarDidChangeItems:(NSNotification *)notification {
  [self _scheduleSearchFieldWidthUpdate];
}

- (void)_scheduleSearchFieldWidthUpdate {
  [self _scheduleSearchFieldWidthUpdateWithPasses:MPSearchFieldWidthPasses];
}

- (void)_scheduleSearchFieldWidthUpdateWithPasses:(NSUInteger)passes {
  /* run after the toolbar has laid out its items */
  __weak MPToolbarDelegate *welf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [welf _updateSearchFieldWidthWithPasses:passes];
  });
}

/* Let the search field take the room of the flexible spaces around it, from the item before it to the one after it (Lock by default) */
- (void)_updateSearchFieldWidthWithPasses:(NSUInteger)passes {
  NSLayoutConstraint *fieldWidth = self.searchFieldWidthConstraint;
  NSView *searchViewer = self.searchField.superview;
  NSWindow *window = searchViewer.window;
  if(!fieldWidth || !window) {
    return;
  }
  [window layoutIfNeeded];
  NSArray<NSToolbarItem *> *items = self.toolbar.items;
  NSUInteger searchIndex = [items indexOfObjectPassingTest:^BOOL(NSToolbarItem *item, NSUInteger idx, BOOL *stop) {
    return [item.itemIdentifier isEqualToString:MPToolbarItemIdentifierSearch];
  }];
  if(searchIndex == NSNotFound) {
    return;
  }
  /* the items with a view on either side, and the flexible spaces between them and the field */
  NSView *leftViewer = nil;
  NSView *rightViewer = nil;
  NSUInteger flexibleSpaces = 0;
  for(NSInteger index = (NSInteger)searchIndex - 1; index >= 0 && !leftViewer; index--) {
    leftViewer = items[index].view.superview;
    flexibleSpaces += [items[index].itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier];
  }
  for(NSUInteger index = searchIndex + 1; index < items.count && !rightViewer; index++) {
    rightViewer = items[index].view.superview;
    flexibleSpaces += [items[index].itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier];
  }
  if(flexibleSpaces == 0) {
    return; // without flexible spaces the toolbar gives the room elsewhere
  }
  if(leftViewer.window != window || rightViewer.window != window) {
    return; // no item on that side, or it is in the overflow menu
  }
  CGFloat left = NSMaxX([leftViewer convertRect:leftViewer.bounds toView:nil]);
  CGFloat right = NSMinX([rightViewer convertRect:rightViewer.bounds toView:nil]);
  CGFloat padding = NSWidth(searchViewer.frame) - NSWidth(self.searchField.frame);
  CGFloat width = MAX(MPSearchFieldMinWidth, floor(right - left - padding - flexibleSpaces * MPSearchFieldFlexibleSpaceWidth));
  if(fabs(width - fieldWidth.constant) >= 1) {
    fieldWidth.constant = width;
    /* the new width can move the items around it, measure again */
    if(passes > 1) {
      [self _scheduleSearchFieldWidthUpdateWithPasses:passes - 1];
    }
  }
}

#pragma mark - NSSearchFieldDelegate
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
  if(control != self.searchField) {
    return NO;
  }
  if(commandSelector == @selector(insertNewline:) || commandSelector == @selector(moveDown:)) {
    /* Dispatch the focus loss since doing it now will break recent search storage */
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSApp targetForAction:@selector(focusEntries:) to:nil from:self] focusEntries:self];
    });
  }
  if(commandSelector == @selector(cancelOperation:) ) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSApp targetForAction:@selector(exitSearch:) to:nil from:self] exitSearch:nil];
    });
  }
  return NO;
}

#pragma mark - Private
- (NSString *)_localizedLabelForToolbarItemIdentifier:(NSString *)identifier {
  static NSDictionary *labelDict;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    labelDict = @{ MPToolbarItemIdentifierLock: NSLocalizedString(@"LOCK", @"Toolbar item to Lock the database"),
                   MPToolbarItemIdentifierAction: NSLocalizedString(@"ACTION", @"Toolbar item with action menu"),
                   MPToolbarItemIdentifierAddEntry: NSLocalizedString(@"NEW_ENTRY", @"Toolbar item new entry"),
                   MPToolbarItemIdentifierAddGroup: NSLocalizedString(@"NEW_GROUP", @"Toolbar item new group"),
                   MPToolbarItemIdentifierCopyPassword: NSLocalizedString(@"COPY_PASSWORD", @"Toolbar item copy password"),
                   MPToolbarItemIdentifierCopyUsername: NSLocalizedString(@"COPY_USERNAME", @"Toolbar item copy username"),
                   MPToolbarItemIdentifierDelete: NSLocalizedString(@"DELETE", @"Toolbar item delete item"),
                   MPToolbarItemIdentifierInspector: NSLocalizedString(@"INSPECTOR", @"Toolbar item toggle inspector"),
                   MPToolbarItemIdentifierSearch: NSLocalizedString(@"SEARCH", @"Search input in Toolbar "),
                   MPToolbarItemIdentifierHistory: NSLocalizedString(@"SHOW_HISTORY", @"Toolbar item to toggle history display"),
                   MPToolbarItemIdentifierAutotype: NSLocalizedString(@"TOOLBAR_PERFORM_AUTOTYPE_FOR_ENTRY", @"Toolbar item to perform autotype")
    };
  });
  return labelDict[identifier];
}

- (SEL)_actionForToolbarItemIdentifier:(NSString *)identifier {
  static NSDictionary *actionDict;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    actionDict = @{ MPToolbarItemIdentifierLock: @(MPActionLock),
                    MPToolbarItemIdentifierAddEntry: @(MPActionAddEntry),
                    MPToolbarItemIdentifierAddGroup: @(MPActionAddGroup),
                    MPToolbarItemIdentifierDelete: @(MPActionDelete),
                    MPToolbarItemIdentifierCopyPassword: @(MPActionCopyPassword),
                    MPToolbarItemIdentifierCopyUsername: @(MPActionCopyUsername),
                    MPToolbarItemIdentifierInspector: @(MPActionToggleInspector),
                    MPToolbarItemIdentifierHistory: @(MPActionShowEntryHistory),
                    MPToolbarItemIdentifierAutotype: @(MPActionPerformAutotypeForSelectedEntry)
    };
  });
  MPActionType actionType = (MPActionType)[actionDict[identifier] integerValue];
  return [MPActionHelper actionOfType:actionType];
}

/*- (id)_targetForToolbarItemIdentifier:(NSString *)identifier {
  static NSDictionary *targetDict;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    targetDict = @{ MPToolbarItemIdentifierLock: nil,
                    MPToolbarItemIdentifierAddEntry: nil,
                    MPToolbarItemIdentifierAddGroup: nil,
                    MPToolbarItemIdentifierDelete: nil,
                    MPToolbarItemIdentifierCopyPassword: nil,
                    MPToolbarItemIdentifierCopyUsername: nil,
                    MPToolbarItemIdentifierInspector: nil,
                    MPToolbarItemIdentifierHistory: nil,
                    MPToolbarItemIdentifierAutotype: nil
    };
  });
  return targetDict[identifier];
}*/

- (NSMenu *)_allocateSearchMenuTemplate {
  NSMenu *menu = [[NSMenu alloc] init];
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"CLEAR_RECENT_SEARCHES", @"Menu to clear recent searches") action:NULL keyEquivalent:@""];
  item.tag = NSSearchFieldClearRecentsMenuItemTag;
  [menu addItem:item];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"RECENT_SEARCHES", @"Recent searches menu item") action:NULL keyEquivalent:@""];
  item.tag = NSSearchFieldRecentsTitleMenuItemTag;
  [menu addItem:item];
  
  item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
  item.tag = NSSearchFieldRecentsMenuItemTag;
  [menu addItem:item];
  
  item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
  item.tag = NSSearchFieldNoRecentsMenuItemTag;
  [menu addItem:item];
  
  return menu;
}

- (void)_didEnterSearch:(NSNotification *)notification {
  /* We enter search. If there is no Item to search in the toolbar, we need to add it */
  NSArray *currentItems = self.toolbar.items;
  NSToolbarItem *searchItem = self.toolbarItems[MPToolbarItemIdentifierSearch];
  if(!searchItem || ![currentItems containsObject:searchItem]) {
    [self.toolbar insertItemWithItemIdentifier:MPToolbarItemIdentifierSearch atIndex:[currentItems count]];
    _didAddSearchfieldForSearch = YES;
  }
  /* Then we should make sure the toolbar is visible. Just to make life easier */
  if(!self.toolbar.visible) {
    _didShowToolbarForSearch = YES;
    self.toolbar.visible = YES;
  }
  _displayModeBeforeSearch = self.toolbar.displayMode;
  if(_displayModeBeforeSearch == NSToolbarDisplayModeLabelOnly) {
    self.toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
  }
  /* only make the searchfield first responder if it's not already in an active search */
  if(![self.searchField currentEditor]) {

    // force search to be enabled since we might end up being called when it's not (yet) enabled
    if(!searchItem.enabled) {
      searchItem.enabled = YES;
    }
    [self.searchField.window makeFirstResponder:self.searchField];
    [self.searchField selectText:self];
  }
}

- (void)_didExitSearch:(NSNotification *)notification {
  self.searchField.stringValue = @"";
  NSWindow *window = [self.searchField window];
  /* Resign first responder form search field only if it was the first responder */
  if(window.firstResponder == [self.searchField currentEditor]) {
    [window makeFirstResponder:nil];
  }
  if(_didAddSearchfieldForSearch) {
    NSToolbarItem *searchItem = self.toolbarItems[MPToolbarItemIdentifierSearch];
    NSUInteger index = [self.toolbar.items indexOfObject:searchItem];
    if(index != NSNotFound) {
      [self.toolbar removeItemAtIndex:index];
      _didAddSearchfieldForSearch = NO;
    }
  }
  if(_displayModeBeforeSearch != self.toolbar.displayMode) {
    self.toolbar.displayMode = _displayModeBeforeSearch;
  }
  if(_didShowToolbarForSearch && self.toolbar.visible) {
    _didShowToolbarForSearch = NO;
    self.toolbar.visible = NO;
  }
}

@end
