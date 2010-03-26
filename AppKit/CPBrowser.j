/*
 * CPBrowser.j
 * AppKit
 *
 * Created by Ross Boucher.
 * Copyright 2010, 280 North, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

@import "CPControl.j"
@import "CPImage.j"
@import "CPTableView.j"
@import "CPScrollView.j"

/*! 
    @ingroup appkit
    @class CPBrowser    
*/

@implementation CPBrowser : CPControl
{
    id              _delegate;
    CPString        _pathSeparator;

    CPView          _contentView;
    CPScrollView    _horizontalScrollView;
    CPView          _prototypeView;

    CPArray         _tableViews;
    CPArray         _tableDelegates;

    id              _rootItem;

    BOOL            _delegateSupportsImages;

    SEL             _doubleAction @accessors(property=doubleAction);

    BOOL            _allowsMultipleSelection;
    BOOL            _allowsEmptySelection;

    Class           _tableViewClass @accessors(property=tableViewClass);

    float           _rowHeight;
    float           _imageWidth;
    float           _leafWidth;
    float           _minColumnWidth;
    float           _defaultColumnWidth @accessors(property=defaultColumnWidth);

    CPArray         _columnWidths;
}

+ (CPImage)branchImage
{
    return [[CPImage alloc] initWithContentsOfFile:[[CPBundle bundleForClass:[self class]] 
                                                    pathForResource:"browser-leaf.png"]
                                              size:CGSizeMake(9,9)];
}

+ (CPImage)highlightedBranchImage
{
    return [[CPImage alloc] initWithContentsOfFile:[[CPBundle bundleForClass:[self class]] 
                                                    pathForResource:"browser-leaf-highlighted.png"]
                                              size:CGSizeMake(9,9)];
}

- (id)initWithFrame:(CGRect)aFrame
{
    if (self = [super initWithFrame:aFrame])
    {
        _rowHeight = 23.0;
        _defaultColumnWidth = 140.0;
        _minColumnWidth = 80.0;
        _imageWidth = 23.0;
        _leafWidth = 13.0;
        _columnWidths = [];

        _pathSeparator = "/";
        _tableViews = [];
        _tableDelegates = [];
        _allowsMultipleSelection = YES;
        _allowsEmptySelection = YES;
        _tableViewClass = [_CPBrowserTableView class];

        _prototypeView = [[CPTextField alloc] initWithFrame:CGRectMakeZero()];
        [_prototypeView setVerticalAlignment:CPCenterVerticalTextAlignment];
        [_prototypeView setValue:[CPColor whiteColor] forThemeAttribute:"text-color" inState:CPThemeStateSelected];

        _horizontalScrollView = [[CPScrollView alloc] initWithFrame:[self bounds]];

        [_horizontalScrollView setHasVerticalScroller:NO];
        [_horizontalScrollView setAutohidesScrollers:YES];
        [_horizontalScrollView setAutoresizingMask:CPViewWidthSizable|CPViewHeightSizable];
        
        _contentView = [[CPView alloc] initWithFrame:CGRectMake(0, 0, 0, CGRectGetHeight([self bounds]))];
        [_contentView setAutoresizingMask:CPViewHeightSizable];
        
        [_horizontalScrollView setDocumentView:_contentView];

        [self addSubview:_horizontalScrollView];
    }

    return self;
}

- (void)setPrototypeView:(CPView)aPrototypeView
{
    _prototypeView = [CPKeyedUnarchiver unarchiveObjectWithData:
                        [CPKeyedArchiver archivedDataWithRootObject:aPrototypeView]];
}

- (CPView)prototypeView
{
    return [CPKeyedUnarchiver unarchiveObjectWithData:
            [CPKeyedArchiver archivedDataWithRootObject:_prototypeView]];
}

- (void)setDelegate:(id)anObject
{    
    _delegate = anObject;
    _delegateSupportsImages = [_delegate respondsToSelector:@selector(browser:imageValueForItem:)];

    [self loadColumnZero];
}

- (id)delegate
{
    return _delegate;
}

- (CPTableView)tableViewInColumn:(unsigned)index
{
    return _tableViews[index];
}

- (unsigned)columnOfTableView:(CPTableView)aTableView
{
    return [_tableViews indexOfObject:aTableView];
}

- (void)loadColumnZero
{
    if ([_delegate respondsToSelector:@selector(rootItemForBrowser:)])
        _rootItem = [_delegate rootItemForBrowser:self];
    else
        _rootItem = nil;

    [self setLastColumn:-1];
    [self addColumn];
}

- (void)setLastColumn:(int)columnIndex
{
    if (columnIndex >= _tableViews.length)
        return;

    var oldValue = _tableViews.length - 1;

    // unloads all later columns.
    var indexPlusOne = columnIndex + 1;

    [[_tableViews.slice(indexPlusOne) valueForKey:"enclosingScrollView"] 
      makeObjectsPerformSelector:@selector(removeFromSuperview)];

    _tableViews = _tableViews.slice(0, indexPlusOne);
    _tableDelegates = _tableDelegates.slice(0, indexPlusOne);

    if ([_delegate respondsToSelector:@selector(browser:didChangeLastColumn:toColumn:)])
        [_delegate browser:self didChangeLastColumn:oldValue toColumn:columnIndex];

    [self tile];
}

- (int)lastColumn
{
    return _tableViews.length - 1;
}

- (void)addColumn
{
    var lastIndex = [self lastColumn],
        lastColumn = _tableViews[lastIndex],
        selectionIndexes = [lastColumn selectedRowIndexes];

    if (lastIndex >= 0 && [selectionIndexes count] > 1)
        [CPException raise:CPInvalidArgumentException 
                    reason:"Can't add column, column "+lastIndex+" has invalid selection."];

    var index = lastIndex+1,
        item = index === 0 ? _rootItem : [_tableDelegates[lastIndex] childAtIndex:[selectionIndexes firstIndex]];

    if (index > 0 && item && [self isLeafItem:item])
        return;

    var table = [[_tableViewClass alloc] initWithFrame:CGRectMakeZero() browser:self];

    [table setHeaderView:nil];
    [table setCornerView:nil];
    [table setAllowsMultipleSelection:_allowsMultipleSelection];
    [table setAllowsEmptySelection:_allowsEmptySelection];
    [table registerForDraggedTypes:[self registeredDraggedTypes]];

    [self _addTableColumnsToTableView:table forColumnIndex:index];

    var delegate = [[_CPBrowserTableDelegate alloc] init];

    [delegate _setDelegate:_delegate];
    [delegate _setBrowser:self];
    [delegate _setIndex:index];
    [delegate _setItem:item];

    _tableViews[index] = table;
    _tableDelegates[index] = delegate;

    [table setDelegate:delegate];
    [table setDataSource:delegate];
    [table setTarget:delegate];
    [table setAction:@selector(_tableViewClicked:)];
    [table setDoubleAction:@selector(_tableViewDoubleClicked:)];
    [table setDraggingDestinationFeedbackStyle:CPTableViewDraggingDestinationFeedbackStyleRegular];
    
    var scrollView = [[_CPBrowserScrollView alloc] initWithFrame:CGRectMakeZero()];
    [scrollView _setBrowser:self];
    [scrollView setDocumentView:table];
    [scrollView setHasHorizontalScroller:NO];
    [scrollView setAutoresizingMask:CPViewHeightSizable];

    [_contentView addSubview:scrollView];

    [self tile];

    [self scrollColumnToVisible:index];
}

- (void)_addTableColumnsToTableView:(CPTableView)aTableView forColumnIndex:(unsigned)index
{
    if (_delegateSupportsImages)
    {
        var column = [[CPTableColumn alloc] initWithIdentifier:@"Image"],
            view = [[CPImageView alloc] initWithFrame:CGRectMakeZero()];

        [view setImageScaling:CPScaleProportionally];

        [column setDataView:view];
        [column setResizingMask:CPTableColumnNoResizing];

        [aTableView addTableColumn:column];
    }

    var column = [[CPTableColumn alloc] initWithIdentifier:@"Content"];

    [column setDataView:_prototypeView];
    [column setResizingMask:CPTableColumnNoResizing];

    [aTableView addTableColumn:column];

    var column = [[CPTableColumn alloc] initWithIdentifier:@"Leaf"],
        view = [[_CPBrowserLeafView alloc] initWithFrame:CGRectMakeZero()];

    [view setBranchImage:[[self class] branchImage]];
    [view setHighlightedBranchImage:[[self class] highlightedBranchImage]];
    
    [column setDataView:view];
    [column setResizingMask:CPTableColumnNoResizing];
    
    [aTableView addTableColumn:column];
}

- (void)reloadColumn:(int)column
{
    [[self tableViewInColumn:column] reloadData];
}

- (void)tile
{
    var xOrigin = 0,
        scrollerWidth = [CPScroller scrollerWidth],
        height = CGRectGetHeight([_contentView bounds]);

    for (var i = 0, count = _tableViews.length; i < count; i++)
    {
        var tableView = _tableViews[i],
            scrollView = [tableView enclosingScrollView],
            width = [self widthOfColumn:i],
            tableHeight = CGRectGetHeight([tableView bounds]);

        [[tableView tableColumnWithIdentifier:"Image"] setWidth:_imageWidth];
        [[tableView tableColumnWithIdentifier:"Content"] setWidth:width - (_leafWidth + _delegateSupportsImages ? _imageWidth : 0) - scrollerWidth - scrollerWidth];
        [[tableView tableColumnWithIdentifier:"Leaf"] setWidth:_leafWidth];

        [tableView setRowHeight:_rowHeight];
        [tableView setFrameSize:CGSizeMake(width - scrollerWidth, tableHeight)];
        [scrollView setFrameOrigin:CGPointMake(xOrigin, 0)];
        [scrollView setFrameSize:CGSizeMake(width, height)];

        xOrigin += width;
    }

    [_contentView setFrameSize:CGSizeMake(xOrigin, height)];
}

// ITEMS

- (id)itemAtRow:(int)row inColumn:(int)column
{
    return [_tableDelegates[column] childAtIndex:row];
}

- (BOOL)isLeafItem:(id)item
{
    return [_delegate respondsToSelector:@selector(browser:isLeafItem:)] && [_delegate browser:self isLeafItem:item];
}

- (id)parentForItemsInColumn:(int)column
{
    return [_tableDelegates[column] _item];
}

// CLICK EVENTS

- (void)_column:(unsigned)columnIndex clickedRow:(unsigned)rowIndex
{
    [self setLastColumn:columnIndex];

    if (rowIndex >= 0)
        [self addColumn];

    [self doClick:self];
}

- (void)sendAction
{
    [self sendAction:_action to:_target];
}

- (void)doClick:(id)sender
{
    [self sendAction:_action to:_target];
}

- (void)doDoubleClick:(id)sender
{
    [self sendAction:_doubleAction to:_target];
}

// SIZING

- (float)columnContentWidthForColumnWidth:(float)aWidth
{
    return aWidth - (_leafWidth + _delegateSupportsImages ? _imageWidth : 0) - [CPScroller scrollerWidth];
}

- (float)columnWidthForColumnContentWidth:(float)aWidth
{
    return aWidth + (_leafWidth + _delegateSupportsImages ? _imageWidth : 0) + [CPScroller scrollerWidth];
}

- (void)setImageWidth:(float)aWidth
{
    _imageWidth = aWidth;
    [self tile];
}

- (float)imageWidth
{
    return _imageWidth;
}

- (void)setMinColumnWidth:(float)minWidth
{
    _minColumnWidth = minWidth;
    [self tile];
}

- (float)minColumnWidth
{
    return _minColumnWidth;
}

- (void)setWidth:(float)aWidth ofColumn:(unsigned)column
{
    _columnWidths[column] = aWidth;

    if ([_delegate respondsToSelector:@selector(browser:didResizeColumn:)])
        [_delegate browser:self didResizeColumn:column];

    [self tile];
}

- (float)widthOfColumn:(unsigned)column
{
    var width = _columnWidths[column];

    if (width == null)
        width = _defaultColumnWidth;

    return MAX([CPScroller scrollerWidth], MAX(_minColumnWidth, width));
}

- (void)setRowHeight:(float)aHeight
{
    _rowHeight = aHeight;
}

- (float)rowHeight
{
    return _rowHeight;
}

// SCROLLERS

- (void)scrollColumnToVisible:(unsigned)columnIndex
{
    [_contentView scrollRectToVisible:[[[self tableViewInColumn:columnIndex] enclosingScrollView] frame]];
}

– (void)scrollRowToVisible:(unsigned)rowIndex inColumn:(unsigned)columnIndex
{
    [self scrollColumnToVisible:columnIndex];
    [[self tableViewInColumn:columnIndex] scrollRowToVisible:rowIndex];
}

- (BOOL)autohidesScroller
{
    return [_horizontalScrollView autohidesScrollers];
}

- (void)setAutohidesScroller:(BOOL)shouldHide
{
    [_horizontalScrollView setAutohidesScrollers:shouldHide];
}

// SELECTION

- (unsigned)selectedRowInColumn:(unsigned)columnIndex
{
    if (columnIndex > [self lastColumn] || columnIndex < 0)
        return -1;

    return [_tableViews[columnIndex] selectedRow];
}

- (unsigned)selectedColumn
{
    var column = [self lastColumn],
        row = [self selectedRowInColumn:column];

    if (row >= 0)
        return column;
    else
        return column - 1;
}

- (void)selectRow:(unsigned)row inColumn:(unsigned)column
{
    var selectedIndexes = row === -1 ? [CPIndexSet indexSet] : [CPIndexSet indexSetWithIndex:row];
    [self selectRowIndexes:selectedIndexes inColumn:column];
}

- (BOOL)allowsMultipleSelection
{
    return _allowsMultipleSelection;
}

- (void)setAllowsMultipleSelection:(BOOL)shouldAllow
{
    if (_allowsMultipleSelection === shouldAllow)
        return;

    _allowsMultipleSelection = shouldAllow;
    [_tableViews makeObjectsPerformSelector:@selector(setAllowsMultipleSelection:) withObject:shouldAllow];
}

- (BOOL)allowsEmptySelection
{
    return _allowsEmptySelection;
}

- (void)setAllowsEmptySelection:(BOOL)shouldAllow
{
    if (_allowsEmptySelection === shouldAllow)
        return;

    _allowsEmptySelection = shouldAllow;
    [_tableViews makeObjectsPerformSelector:@selector(setAllowsEmptySelection:) withObject:shouldAllow];
}

- (CPIndexSet)selectedRowIndexesInColumn:(unsigned)column
{
    return [[self tableViewInColumn:column] selectedRowIndexes];
}

- (void)selectRowIndexes:(CPIndexSet)indexSet inColumn:(unsigned)column
{
    if (column < 0 || column > [self lastColumn] + 1)
        return;

    if ([_delegate respondsToSelector:@selector(browser:selectionIndexesForProposedSelection:inColumn:)])
        indexSet = [_delegate browser:self selectionIndexesForProposedSelection:indexSet inColumn:column];

    if ([_delegate respondsToSelector:@selector(browser:shouldSelectRowIndexes:inColumn:)] && 
       ![_delegate browser:self shouldSelectRowIndexes:indexSet inColumn:column])
        return;

    if ([_delegate respondsToSelector:@selector(browserSelectionIsChanging:)])
        [_delegate browserSelectionIsChanging:self];

    if (column > [self lastColumn])
        [self addColumn];

    [self setLastColumn:column];

    [[self tableViewInColumn:column] selectRowIndexes:indexSet byExtendingSelection:NO];
    [[self window] makeFirstResponder:[self tableViewInColumn:[self lastColumn]]];

    [self scrollColumnToVisible:column];

    if ([_delegate respondsToSelector:@selector(browserSelectionDidChange:)])
        [_delegate browserSelectionDidChange:self];
}

- (void)setBackgroundColor:(CPColor)aColor
{
    [super setBackgroundColor:aColor];
    [_contentView setBackgroundColor:aColor];
}

// DRAG AND DROP

- (void)registerForDraggedTypes:(CPArray)types
{
    [super registerForDraggedTypes:types];
    [_tableViews makeObjectsPerformSelector:@selector(registerForDraggedTypes:) withObject:types];
}

- (BOOL)canDragRowsWithIndexes:(CPIndexSet)rowIndexes inColumn:(int)columnIndex withEvent:(CPEvent)dragEvent
{
    if ([_delegate respondsToSelector:@selector(browser:canDragRowsWithIndexes:inColumn:withEvent:)])
        return [_delegate browser:self canDragRowsWithIndexes:rowIndexes inColumn:columnIndex withEvent:dragEvent];

    return YES;
}

- (CPImage)draggingImageForRowsWithIndexes:(CPIndexSet)rowIndexes inColumn:(int)columnIndex withEvent:(CPEvent)dragEvent offset:(CGPoint)dragImageOffset
{
    if ([_delegate respondsToSelector:@selector(browser:draggingImageForRowsWithIndexes:inColumn:withEvent:offset:)])
        return [_delegate browser:self draggingImageForRowsWithIndexes:rowIndexes inColumn:columnIndex withEvent:dragEvent offset:dragImageOffset];

    return nil;
}

- (CPView)draggingViewForRowsWithIndexes:(CPIndexSet)rowIndexes inColumn:(int)columnIndex withEvent:(CPEvent)dragEvent offset:(CGPoint)dragImageOffset
{
    if ([_delegate respondsToSelector:@selector(browser:draggingViewForRowsWithIndexes:inColumn:withEvent:offset:)])
        return [_delegate browser:self draggingViewForRowsWithIndexes:rowIndexes inColumn:columnIndex withEvent:dragEvent offset:dragImageOffset];

    return nil;
}

@end

@implementation _CPBrowserResizeControl : CPView
{
    CGPoint     _mouseDownX;
    CPBrowser   _browser;
    unsigned    _index;
    unsigned    _width;
}

- (void)mouseDown:(CPEvent)anEvent
{
    _mouseDownX = [anEvent locationInWindow].x;
    _browser = [[self superview] _browser];
    _index = [_browser columnOfTableView:[[self superview] documentView]];
    _width = [_browser widthOfColumn:_index];
}

- (void)mouseDragged:(CPEvent)anEvent
{
    var deltaX = [anEvent locationInWindow].x - _mouseDownX;
    [_browser setWidth:_width + deltaX ofColumn:_index];
}

@end

var _CPBrowserResizeControlBackgroundImage = nil;

@implementation _CPBrowserScrollView : CPScrollView
{
    _CPBrowserResizeControl  _resizeControl;
    CPBrowser                _browser @accessors;
}

+ (CPImage)backgroundImage
{
    if (!_CPBrowserResizeControlBackgroundImage)
    {
        var path = [[CPBundle bundleForClass:[self class]] pathForResource:"browser-resize-control.png"];
        _CPBrowserResizeControlBackgroundImage = [[CPImage alloc] initWithContentsOfFile:path
                                                                                    size:CGSizeMake(15, 14)];
    }

    return _CPBrowserResizeControlBackgroundImage;
}

- (void)initWithFrame:(CGRect)aFrame
{
    if (self = [super initWithFrame:aFrame])
    {
        _resizeControl = [[_CPBrowserResizeControl alloc] initWithFrame:CGRectMakeZero()];
        [_resizeControl setBackgroundColor:[CPColor colorWithPatternImage:[[self class] backgroundImage]]];
        [self addSubview:_resizeControl];
    }

    return self;
}

- (void)reflectScrolledClipView:(CPClipView)aClipView
{
    [super reflectScrolledClipView:aClipView];

    var frame = [_verticalScroller frame];
    frame.size.height = CGRectGetHeight([self bounds]) - 14.0 - frame.origin.y;
    [_verticalScroller setFrameSize:frame.size];

    var resizeFrame = CGRectMake(CGRectGetMinX(frame), CGRectGetMaxY(frame), [CPScroller scrollerWidth], 14.0);
    [_resizeControl setFrame:resizeFrame];
}

@end

@implementation _CPBrowserTableView : CPTableView
{
    CPBrowser   _browser;
}

- (id)initWithFrame:(CGRect)aFrame browser:(CPBrowser)aBrowser
{
    if (self = [super initWithFrame:aFrame])
        _browser = aBrowser;

    return self;
}

- (CPView)browserView
{
    return _browser;
}

- (BOOL)canDragRowsWithIndexes:(CPIndexSet)rowIndexes atPoint:(CGPoint)mouseDownPoint
{
    return [_browser canDragRowsWithIndexes:rowIndexes inColumn:[_browser columnOfTableView:self] withEvent:[CPApp currentEvent]];
}

- (CPImage)dragImageForRowsWithIndexes:(CPIndexSet)dragRows tableColumns:(CPArray)theTableColumns event:(CPEvent)dragEvent offset:(CPPointPointer)dragImageOffset
{
    return [_browser draggingImageForRowsWithIndexes:dragRows inColumn:[_browser columnOfTableView:self] withEvent:dragEvent offset:dragImageOffset] ||
           [super dragImageForRowsWithIndexes:dragRows tableColumns:theTableColumns event:dragEvent offset:dragImageOffset];
}

- (CPView)dragViewForRowsWithIndexes:(CPIndexSet)dragRows tableColumns:(CPArray)theTableColumns event:(CPEvent)dragEvent offset:(CPPoint)dragViewOffset
{
    var count = theTableColumns.length;
    while (count--)
    {
        if ([theTableColumns[count] identifier] === "Leaf")
            [theTableColumns removeObject:theTableColumns[count]];
    }

    return [_browser draggingViewForRowsWithIndexes:dragRows inColumn:[_browser columnOfTableView:self] withEvent:dragEvent offset:dragViewOffset] ||
           [super dragViewForRowsWithIndexes:dragRows tableColumns:theTableColumns event:dragEvent offset:dragViewOffset];
}

- (void)moveUp:(id)sender
{
    [super moveUp:sender];
    [_browser selectRow:[self selectedRow] inColumn:[_browser selectedColumn]];
}

- (void)moveDown:(id)sender
{
    [super moveDown:sender];
    [_browser selectRow:[self selectedRow] inColumn:[_browser selectedColumn]];
}

- (void)moveLeft:(id)sender
{    
    var previousColumn = [_browser selectedColumn] - 1,
        selectedRow = [_browser selectedRowInColumn:previousColumn];

    [_browser selectRow:selectedRow inColumn:previousColumn];
}

- (void)moveRight:(id)sender
{    
    [_browser selectRow:0 inColumn:[_browser selectedColumn] + 1];
}

@end

@implementation _CPBrowserTableDelegate : CPObject
{
    CPBrowser   _browser @accessors;
    unsigned    _index @accessors;
    id          _delegate @accessors;
    id          _item @accessors;
}

- (unsigned)numberOfRowsInTableView:(CPTableView)aTableView
{
    return [_delegate browser:_browser numberOfChildrenOfItem:_item];
}

- (void)tableView:(CPTableView)aTableView objectValueForTableColumn:(CPTableColumn)column row:(unsigned)row
{
    if ([column identifier] === "Image")
        return [_delegate browser:_browser imageValueForItem:[self childAtIndex:row]];
    else if ([column identifier] === "Leaf")
        return ![_browser isLeafItem:[self childAtIndex:row]];
    else
        return [_delegate browser:_browser objectValueForItem:[self childAtIndex:row]];
}

- (void)_tableViewDoubleClicked:(CPTableView)aTableView
{
    [_browser doDoubleClick:self];
}

- (void)_tableViewClicked:(CPTableView)aTableView
{
    var selectedIndexes = [aTableView selectedRowIndexes];
    [_browser _column:_index clickedRow:[selectedIndexes count] === 1 ? [selectedIndexes firstIndex] : -1];
}

- (id)childAtIndex:(unsigned)index
{
    return [_delegate browser:_browser child:index ofItem:_item];
}

- (BOOL)tableView:(CPTableView)aTableView acceptDrop:(id)info row:(int)row dropOperation:(CPTableViewDropOperation)operation
{
    if ([_delegate respondsToSelector:@selector(browser:acceptDrop:atRow:column:dropOperation:)])
        return [_delegate browser:_browser acceptDrop:info atRow:row column:_index dropOperation:operation];
    else
        return NO;
}

- (CPDragOperation)tableView:(CPTableView)aTableView validateDrop:(id)info proposedRow:(int)row proposedDropOperation:(CPTableViewDropOperation)operation
{
    if ([_delegate respondsToSelector:@selector(browser:validateDrop:proposedRow:column:dropOperation:)])
        [_delegate browser:_browser validateDrop:info proposedRow:row column:_index dropOperation:operation];
    else
        return CPDragOperationNone;
}

- (BOOL)tableView:(CPTableView)aTableView writeRowsWithIndexes:(CPIndexSet)rowIndexes toPasteboard:(CPPasteboard)pboard
{
    if ([_delegate respondsToSelector:@selector(browser:writeRowsWithIndexes:inColumn:toPasteboard:)])
        return [_delegate browser:_browser writeRowsWithIndexes:rowIndexes inColumn:_index toPasteboard:pboard];
    else
        return NO;
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if (aSelector === @selector(browser:writeRowsWithIndexes:inColumn:toPasteboard:))
        return [_delegate respondsToSelector:@selector(browser:writeRowsWithIndexes:inColumn:toPasteboard:)];
    else
        return [super respondsToSelector:aSelector];
}

@end

@implementation _CPBrowserLeafView : CPView
{
    BOOL        _isLeaf @accessors(readonly, property=isLeaf);
    CPImage     _branchImage @accessors(property=branchImage);
    CPImage     _highlightedBranchImage @accessors(property=highlightedBranchImage);
}

- (BOOL)objectValue
{
    return _isLeaf;
}

- (void)setObjectValue:(id)aValue
{
    _isLeaf = !!aValue;
    [self setNeedsLayout];
}

- (CGRect)rectForEphemeralSubviewNamed:(CPString)aName
{
    if (aName === "image-view")
        return CGRectInset([self bounds], 1, 1);

    return [super rectForEphemeralSubviewNamed:aName];
}

- (CPView)createEphemeralSubviewNamed:(CPString)aName
{
    if (aName === "image-view")
        return [[CPImageView alloc] initWithFrame:CGRectMakeZero()];

    return [super createEphemeralSubviewNamed:aName];
}

- (void)layoutSubviews
{
    var imageView = [self layoutEphemeralSubviewNamed:@"image-view"
                                           positioned:CPWindowAbove
                      relativeToEphemeralSubviewNamed:nil];

    var isHighlighted = [self themeState] & CPThemeStateSelected;
    [imageView setImage: _isLeaf ? (isHighlighted ? _highlightedBranchImage : _branchImage) : nil];
    [imageView setImageScaling:CPScaleNone];
}

- (void)encodeWithCoder:(CPCoder)aCoder
{
    [super encodeWithCoder:aCoder];

    [aCoder encodeBool:_isLeaf forKey:"_CPBrowserLeafViewIsLeafKey"];
    [aCoder encodeObject:_branchImage forKey:"_CPBrowserLeafViewBranchImageKey"];
    [aCoder encodeObject:_highlightedBranchImage forKey:"_CPBrowserLeafViewHighlightedBranchImageKey"];
}

- (void)initWithCoder:(CPCoder)aCoder
{
    if (self = [super initWithCoder:aCoder])
    {
        _isLeaf = [aCoder decodeBoolForKey:"_CPBrowserLeafViewIsLeafKey"];
        _branchImage = [aCoder decodeObjectForKey:"_CPBrowserLeafViewBranchImageKey"];
        _highlightedBranchImage = [aCoder decodeObjectForKey:"_CPBrowserLeafViewHighlightedBranchImageKey"];
    }

    return self;
}

@end
