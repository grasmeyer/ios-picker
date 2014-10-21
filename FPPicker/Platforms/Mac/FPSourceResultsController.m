//
//  FPSourceResultsController.m
//  FPPicker
//
//  Created by Ruben Nine on 01/09/14.
//  Copyright (c) 2014 Filepicker.io. All rights reserved.
//

#import "FPSourceResultsController.h"
#import "FPInternalHeaders.h"
#import "FPThumbnail.h"
#import "FPTableView.h"

@interface FPSourceResultsController () <FPTableViewDelegate,
                                         NSTableViewDelegate,
                                         NSTableViewDataSource>

@property (nonatomic, weak) IBOutlet FPImageBrowserView *browserView;
@property (nonatomic, weak) IBOutlet FPTableView *tableView;

@property (nonatomic, strong) NSOperationQueue *thumbnailFetchingOperationQueue;
@property (nonatomic, strong) NSCache *thumbnailCache;
@property (readwrite, nonatomic, strong) NSArray *selectedItems;
@property (nonatomic, strong) NSIndexSet *selectionIndexes;

@end

@implementation FPSourceResultsController

#pragma mark - Accessors

- (NSCache *)thumbnailCache
{
    if (!_thumbnailCache)
    {
        _thumbnailCache = [NSCache new];
        _thumbnailCache.countLimit = 4096;
    }

    return _thumbnailCache;
}

- (NSOperationQueue *)thumbnailFetchingOperationQueue
{
    if (!_thumbnailFetchingOperationQueue)
    {
        _thumbnailFetchingOperationQueue = [NSOperationQueue new];
        _thumbnailFetchingOperationQueue.maxConcurrentOperationCount = 5;
    }

    return _thumbnailFetchingOperationQueue;
}

- (void)setItems:(NSArray *)items
{
    // Cancel any pending thumbnail image requests before re-setting items

    [self.thumbnailFetchingOperationQueue cancelAllOperations];

    _items = items;

    [self preloadThumbnailsForItems:_items];
    [self reloadData];
}

- (void)setAllowsMultipleSelection:(BOOL)allowsMultipleSelection
{
    _allowsFileSelection = allowsMultipleSelection;

    // Sync browserView's and tableView's allowsMultipleSelection

    self.browserView.allowsMultipleSelection = allowsMultipleSelection;
    self.tableView.allowsMultipleSelection = allowsMultipleSelection;
}

#pragma mark - Public Methods

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        self.allowsFileSelection = YES;
        self.allowsMultipleSelection = YES;
    }

    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];

    self.browserView.constrainsToOriginalSize = YES;
    self.browserView.cellsStyleMask = IKCellsStyleTitled;

    NSDictionary *titleAttributes = @{
        NSFontAttributeName:[NSFont fontWithName:@"Helvetica" size:12],
        NSForegroundColorAttributeName:[NSColor blackColor]
    };

    NSDictionary *highlightedTitleAttributes = @{
        NSFontAttributeName:[NSFont fontWithName:@"Helvetica" size:12],
        NSForegroundColorAttributeName:[NSColor whiteColor]
    };

    [self.browserView setValue:titleAttributes
                        forKey:IKImageBrowserCellsTitleAttributesKey];

    [self.browserView setValue:highlightedTitleAttributes
                        forKey:IKImageBrowserCellsHighlightedTitleAttributesKey];

    [self.tableView sizeToFit];

    self.tableView.doubleAction = @selector(doubleClickedOnTable:);
    self.tableView.target = self;
}

- (void)reloadData
{
    [self.browserView reloadData];
    [self.tableView reloadData];
}

- (void)appendItems:(NSArray *)items
{
    @synchronized(self.items)
    {
        _items = [_items arrayByAddingObjectsFromArray:items];

        [self preloadThumbnailsForItems:_items];
        [self reloadData];
    }
}

#pragma mark - Actions

- (IBAction)doubleClickedOnTable:(id)sender
{
    [self performActionOnSelection];
}

#pragma mark - IKImageBrowser delegate

- (void)imageBrowserSelectionDidChange:(FPImageBrowserView *)browser
{
    [self selectionInViewDidChange:self.browserView];
}

- (void)           imageBrowser:(FPImageBrowserView *)aBrowser
    cellWasDoubleClickedAtIndex:(NSUInteger)index
{
    [self performActionOnSelection];
}

- (void)          imageBrowser:(FPImageBrowserView *)browser
    cellWasRightClickedAtIndex:(NSUInteger)index
                     withEvent:(NSEvent *)event
{
    // No-op
}

- (BOOL)          imageBrowser:(FPImageBrowserView *)aBrowser
    shouldForwardKeyboardEvent:(NSEvent *)event
{
    if (event.modifierFlags & NSCommandKeyMask)
    {
        if (event.keyCode == 0x7E)
        {
            // Cmd+Up pressed

            if (self.delegate &&
                [self.delegate respondsToSelector:@selector(sourceResultsWantsToGoUpOneDirectory:)])
            {
                [self.delegate sourceResultsWantsToGoUpOneDirectory:self];
            }

            return NO;
        }
        else if (event.keyCode == 0x7D)
        {
            // Cmd+Down pressed

            if (self.selectedItems.count > 0)
            {
                [self performActionOnSelection];
            }

            return NO;
        }
    }

    return YES;
}

#pragma mark - IKImageBrowser data source

- (NSUInteger)numberOfItemsInImageBrowser:(FPImageBrowserView *)browser
{
    return self.items.count;
}

- (id)imageBrowser:(FPImageBrowserView *)browser
       itemAtIndex:(NSUInteger)index
{
    NSDictionary *item = self.items[index];
    NSString *itemUID = item[@"link_path"];
    FPThumbnail *thumb = [self.thumbnailCache objectForKey:itemUID];

    return thumb;
}

#pragma mark - FPTableViewDelegate Methods

- (BOOL)             tableView:(FPTableView *)tableView
    shouldForwardKeyboardEvent:(NSEvent *)event
{
    if (event.modifierFlags & NSCommandKeyMask)
    {
        if (event.keyCode == 0x7E)
        {
            // Cmd+Up pressed

            if (self.delegate &&
                [self.delegate respondsToSelector:@selector(sourceResultsWantsToGoUpOneDirectory:)])
            {
                [self.delegate sourceResultsWantsToGoUpOneDirectory:self];
            }

            return NO;
        }
        else if (event.keyCode == 0x7D)
        {
            // Cmd+Down pressed

            if (self.selectedItems.count > 0)
            {
                [self performActionOnSelection];
            }

            return NO;
        }
    }

    return YES;
}

#pragma mark - NSTableViewDataSource Methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.items.count;
}

#pragma mark - NSTableViewDelegate Methods

- (NSView *) tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)row
{
    NSString *identifier = tableColumn.identifier;
    NSDictionary *item = self.items[row];

    if ([identifier isEqualToString:@"Filename"])
    {
        NSTableCellView *cellView;

        cellView = [tableView makeViewWithIdentifier:identifier
                                               owner:tableView];

        NSString *itemUID = item[@"link_path"];
        FPThumbnail *thumb = [self.thumbnailCache objectForKey:itemUID];
        NSString *itemTitle = [item[@"display_name"] length] > 0 ? item[@"display_name"] : item[@"filename"];

        cellView.imageView.image = thumb.icon;
        cellView.textField.stringValue = itemTitle;
        cellView.textField.toolTip = itemTitle;

        return cellView;
    }
    else if ([identifier isEqualToString:@"Size"])
    {
        NSTableCellView *cellView;

        cellView = [tableView makeViewWithIdentifier:identifier
                                               owner:tableView];

        BOOL isDirectory = [item[@"is_dir"] boolValue];

        NSString *filesizeAsString = isDirectory ? @"N/A" : item[@"size"];

        cellView.textField.stringValue = filesizeAsString;
        cellView.textField.toolTip = filesizeAsString;

        if (isDirectory)
        {
            cellView.textField.textColor = [NSColor disabledControlTextColor];
        }

        return cellView;
    }
    else if ([identifier isEqualToString:@"Last Modified"])
    {
        NSTableCellView *cellView;

        cellView = [tableView makeViewWithIdentifier:identifier
                                               owner:tableView];

        NSString *lastModified = item[@"modified"];

        if (lastModified.length == 0)
        {
            lastModified = @"N/A";
            cellView.textField.textColor = [NSColor disabledControlTextColor];
        }

        cellView.textField.stringValue = lastModified;
        cellView.textField.toolTip = lastModified;

        return cellView;
    }
    else
    {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Tablecolumn: %@ not handled", tableColumn];
    }

    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self selectionInViewDidChange:self.tableView];
}

#pragma mark - Private Methods

- (void)performActionOnSelection
{
    // User wants to perform an action on current selection.
    // This can typically originate from a mouse double-click event or a Cmd+Down keyboard event.
    // It can also originally from triggering the action button (i.e., 'Save' or 'Open' on the dialog)

    NSArray *items = [self selectedItems];

    // User wants to enter a directory

    if ((items.count == 1) &&
        [items[0][@"is_dir"] boolValue])
    {
        if (self.delegate &&
            [self.delegate respondsToSelector:@selector(sourceResults:wantsToEnterDirectoryAtPath:)])
        {
            [self.delegate sourceResults:self
             wantsToEnterDirectoryAtPath:items[0][@"link_path"]];
        }

        return;
    }

    // User wants to perform an action on selected items...

    if (self.delegate &&
        [self.delegate respondsToSelector:@selector(sourceResults:doubleClickedOnItems:)])
    {
        [self.delegate sourceResults:self
                doubleClickedOnItems:items];
    }
}

- (void)preloadThumbnailsForItems:(NSArray *)items
{
    [items enumerateObjectsUsingBlock: ^(id obj,
                                         NSUInteger idx,
                                         BOOL *stop) {
        NSDictionary *item = obj;
        NSString *itemUID = item[@"link_path"];
        FPThumbnail *thumb = [self.thumbnailCache objectForKey:itemUID];
        BOOL isDir = [item[@"is_dir"] boolValue];

        if (!thumb)
        {
            thumb = [FPThumbnail new];

            thumb.UID = itemUID;
            thumb.title = [item[@"display_name"] length] > 0 ? item[@"display_name"] : item[@"filename"];
            thumb.isDimmed = self.allowsFileSelection ? NO : !isDir;

            [self.thumbnailCache setObject:thumb
                                    forKey:itemUID];
        }

        if (!thumb.icon)
        {
            // Let's display directories using OS X's generic folder icon

            if (isDir)
            {
                thumb.icon = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)];

                [self.thumbnailCache setObject:thumb
                                        forKey:itemUID];
            }
            else
            {
                // Any other icons will be downloaded

                NSURL *iconURL = [NSURL URLWithString:item[@"thumbnail"]];
                NSURLRequest *iconURLRequest = [NSURLRequest requestWithURL:iconURL];

                AFHTTPRequestOperation *requestOperation = [[AFHTTPRequestOperation alloc] initWithRequest:iconURLRequest];

                AFRequestOperationSuccessBlock successOperationBlock = ^(AFHTTPRequestOperation *operation,
                                                                         id responseObject) {
                    thumb.icon = responseObject;

                    [self.thumbnailCache setObject:thumb
                                            forKey:itemUID];

                    // Refresh the affected browser's cell view

                    NSRect cellFrame = [self.browserView itemFrameAtIndex:idx];

                    [self.browserView setNeedsDisplayInRect:cellFrame];

                    // Refresh the affected table's cell view

                    // NOTE: The alternative method for redrawing cell using tableView's
                    // frameOfCellAtColumn:row and then calling setNeedsDisplayInRect: does nothing,
                    // so we will refresh the tableView by reloading the affected table's row and index.

                    NSIndexSet *columnIndexSet = [NSIndexSet indexSetWithIndex:0];
                    NSIndexSet *rowIndexSet = [NSIndexSet indexSetWithIndex:idx];

                    [self.tableView reloadDataForRowIndexes:rowIndexSet
                                              columnIndexes:columnIndexSet];
                };

                AFRequestOperationFailureBlock failureOperationBlock = ^(AFHTTPRequestOperation *operation,
                                                                         NSError *error) {
                    DLog(@"Thumbnail image %@ load error: %@", itemUID, error);
                };

                [requestOperation setCompletionBlockWithSuccess:successOperationBlock
                                                        failure:failureOperationBlock];

                requestOperation.responseSerializer = [AFImageResponseSerializer serializer];

                [self.thumbnailFetchingOperationQueue addOperation:requestOperation];
            }
        }
    }];
}

- (void)selectionInViewDidChange:(NSView *)view
{
    NSMutableArray *items = [NSMutableArray array];
    NSIndexSet *selectedIndexes;

    if (view == self.tableView)
    {
        selectedIndexes = self.tableView.selectedRowIndexes;
    }
    else if (view == self.browserView)
    {
        selectedIndexes = self.browserView.selectionIndexes;
    }
    else
    {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Unhandled view type: %@", view];
    }

    [selectedIndexes enumerateIndexesUsingBlock: ^(NSUInteger idx,
                                                   BOOL *stop) {
        NSDictionary *item = self.items[idx];

        [items addObject:item];
    }];

    if (items.count == 1 &&
        !self.allowsMultipleSelection &&
        !self.allowsFileSelection)
    {
        NSDictionary *item = items[0];

        if (![item[@"is_dir"] boolValue])
        {
            // User has selected a file, but file selection is not supported.
            // ...let's maintain previous selection

            if (view == self.tableView)
            {
                [self.tableView selectRowIndexes:self.selectionIndexes
                            byExtendingSelection:NO];
            }
            else if (view == self.browserView)
            {
                [self.browserView setSelectionIndexes:self.selectionIndexes
                                 byExtendingSelection:NO];
            }

            // ...and notify the delegate about it

            [self.delegate sourceResults:self
                didMomentarilySelectItem:item];

            return;
        }
    }

    self.selectedItems = [items copy];

    [self.delegate sourceResults:self
              selectionDidChange:self.selectedItems];

    self.selectionIndexes = selectedIndexes;
}

@end
