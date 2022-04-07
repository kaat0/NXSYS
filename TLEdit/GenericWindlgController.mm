//
//  GenericWindlgController.m
//  NXSYSMac
//
//  Created by Bernard Greenberg on 9/19/14.
//  Copyright (c) 2014 Bernard Greenberg. All rights reserved.
//
typedef void *HWND;
#import "TLWindowsSide.h"

#import "GenericWindlgController.h"
#include "MessageBox.h"
#include "WinMacCalls.h"
#include "STLExtensions.h"
#include <unordered_map>
#include <exception>
#include <map>

/* While I am proud of this piece of work, it is a but a kludge to reconcile the
 respective deficiencies of the Windows and Macintosh dialog systems.
 The Windows system requires defining a file full of batty control ID numbers, which,
 from their header file lairs, act in both resource definitions and your code, yet 
 easily inspectable, maintainable, etc., while requiring an army of middlepersons,
 e.g., GetDlgItemInt, to interpret them.
 
 The Mac system is 'much better': you create variables into which solid (or not so solid)
 references to your controls are seamlessly inserted by the Interface Builder and its
 runtime, the NIB loader.  You must be aware of each control you intend to stuff or read
 or (buttons) be activated by, although not others (e.g., labels).  No numbers, no shim agents.
 
 But my system doesn't want to supply code for each dialog; the code already exists in C++,
 and deals in middlepersons, whom we must, and do, implement in the WindowsDlg protocol
 regime.  The hard part is identifying the controls.  We do not want to make variables
 for each control, because that must be done at design/build time, and is a major pain in the
 Interface Builder if you have more than 2 or 3 of them.  Doing so would require special-case
 code for each dialog to interpret windows control ID's as tickets to its variables.
 
 Mac allows you to store "tags" in controls, but they are limited to integers, and cannot
 be symbolic references or strings.  Managing these integers, e.g., to be Windows resource ID's
 (done in the Stop Policy dialog in the main app), has already proven beyond human capacity,
 and lacks basic maintainability: one can't search for uses.
 
 [OBSOLETE: The tack chosen here is to search the list of instantiated controls for "key" text strings, or
 little snippets of them (and find input controls by their labels and the "tab order"). While 
 proclaimed a "no no" by wise engineers, as it defeats localizability, c'est la vie, 
 mein guter amigo. ]
 
 3-24-2022
 
 Nevertheless, we can use that strategy to stuff the "tags" fields programmatically, which, while
 not solving the dialog specification design problem, at least greatly simplifies the
 taking of the desired action at button-push time.  Making hash-tables of strong pointers to
 integers, which would be otherwise required, is quite difficult.  Linear lookup wasn't bad,
 but this is better.

4-4-2022
 
 This house was cleaned from basement to spire by taking advantage of the (new since 2014)
 "identifier" field in Cocoa controls, where not only can we store an arbitrary string, but
 the string turns up in Xcode searches!  The new system puts the actual name of the intended
 Windows resource ID in it (e.g., "IDC_EDIT_SWITCH"), which is supplied by macros with the
 corresponding value in the calls to instantiate this class (and its progeny). The entire
 system of searching label texts and tracking container hierarchy names is gone. The
 numeric resource codes are stored in the tag fields by the code below at dialog creation time.
 With this scheme, the code now can diagnose missing, unknown, and duplicate tags/id's!

*/

static std::map<std::string, int> ByTitle{{"OK", IDOK}, {"Cancel", IDCANCEL}};

struct GenericWindlgException : public std::exception {};

@interface GenericWindlgController () // () means append to def. given already.
{
    /* Finally, here is how you "do" instance variables:  { } at the beginning of @interface. */
    std::unordered_map<NSInteger,HWND> CtlidToHWND;
    std::map<NSString*, int, CompareNSString> RIDValMap;
}
@end

@implementation GenericWindlgController

/* Usage by the macro is
 [[xxxxWindlgController alloc] initWithNibAndObjectAndRIDs: nibname nxgobject rids].showModal();
 The boundary between the two methods is arbitrary and stylistic. One would suffice.
*/

-(GenericWindlgController*)initWithNibAndRIDs:(NSString*)nibName rids:(RIDVector&)rids
{
    //  nibName = @"Bad-Nib-Name"; // for testing, remove leading //

    /* Make the RID map. It is worth it because it is going to be searched
    n times (n = number of entries) when dialog is recursively-scanned */

    for (auto p : rids)
        RIDValMap[[NSString stringWithUTF8String:p.Symbol]] = p.resource_id;

    self = [super initWithWindowNibName:nibName]; //will never fail to return a controller

    try {
        /* This call [self window] will side-effect call windowDidLoad if and only if the window
        did, in fact, load.  So all of the barf: errors will throw and be caught at this point. */

        if (![self window])
            [self barf: FormatString("Cannot load NIB \"%s\"", nibName.UTF8String)];

        return self;

    } catch (GenericWindlgException e) {
        /* Message already messageboxed by barf: */
        return nil;   //OfferGenericWindlg will not show if so.
    }

}

-(void)showModal: (GraphicObject*)object
{
    if (!CtlidToHWND.size()) //will happen if init failed for any reason
        return;

    try {
        _NXGObject = object;   //

        /* Compute and set dialog position */
        NSPoint p = NXViewToScreen(NXGOLocAsPoint(_NXGObject)); //whole panel -> whole mac screen
        NSPoint placement = NSMakePoint(p.x-150, p.y-60); //mac coord "y=up".
        [self.window setFrameTopLeftPoint:placement];

        /* Now run all the Windows code that uses the stuff set before we were called */
        callWndProcInitDialog(_hWnd, _NXGObject);

        /* Show the window */
        [self showWindow:self]; // runModalFW doesn't do this for you ....

        /* And run (accept user interaction calling back in) */
        [NSApp runModalForWindow:self.window];

    } catch (GenericWindlgException e) {
        /* Errors can be thrown by user interaction during [NSApp runModal...]
         as well as WndProcInitDialog */
        //pass;
    }
}
-(void)DestroyWindow
{
    assert(!"DestroyWindow in GenericWindlgController shouldn't be called.");
}

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    return self;
}
-(void)real_deall
{

  /* this will get called at exit time because the hWnd is weak and not retaining us. */

    for (auto& iterator : CtlidToHWND) // not deleting from map here, but in clear(), no skip-step.
         DeleteHwndObject(iterator.second);
    CtlidToHWND.clear(); // probably not necessary, hope C++ dtor will do it.
    if(_hWnd) // can be null in error situations
        DeleteHwndObject(_hWnd);
}
-(void)windowDidLoad
{
    /* This will get called during the benign-looking [self window] in the init method
     if and only if the window did load from the nib. All error throws will be caught
     by the init method. */

    [super windowDidLoad];   //Do whatever Cocoa needs/wants (probably nothing, I read)

    [self createControlMap];  //Set up all the HWND and resource-id linkages.

    /* we are retained on the stack, not in C++ code */
    _hWnd = WinWrapNoRetain(self, self.window.contentView, @"Generic Dialog");
}

-(void)barf:(std::string) message
{
    /* These are not user errors, but logic/coding resource-tagging errors that should be
     debugged out.  Nevertheless, it is better to say something that a user can report, something
     better than "Internal logic error... please do so and so ..." Breakpoint here
     to debug. */

    MessageBoxS(NULL, message, "Generic Windlg Controller internal error", MB_OK|MB_ICONSTOP);
    throw GenericWindlgException();  //caught by init method or runModal method
}

-(bool)maybeRegisterView:(NSView*)view
{
    /* Controls of any type which have a non-_ "identifier" string get registered
       by the value of the Windows symbol so named.  Allow unknown identifiers
       if they don't start with IDC_.
     */
    if (!view.identifier)  // test for null -- not sure it can happen.
        return false;

    NSString* identifier = (NSString*)view.identifier;
    
    /* Avoid hash search if Cocoa internal. No Windows RID starts with _. */
    if ([identifier characterAtIndex:0] == '_')
        return false;

    if (RIDValMap.count(identifier)) {  //If we have it
        int resource_id = RIDValMap[identifier];
        if (CtlidToHWND.count(resource_id))
            [self barf: FormatString("More than one control has identifier: %s", identifier.UTF8String)];

        /* Create and link an HWND object to the control, and register it in the
         resource_id to HWND map. Insert the numeric ID into the control's "tag" attribute. */
        CtlidToHWND[resource_id] = WinWrapControl(self, view, resource_id, @"Generic Windlg");
        [(NSControl*)view setTag: resource_id];
        return true;
    }
    /* Not found.  Diagnose IDC_ (but not IDCANCEL!). Leave others alone. */
    if (identifier.length >= 4)
        if ([[identifier substringToIndex:4] isEqualTo:@"IDC_"])
            [self barf: FormatString("Identifier %s in control not known to RID table.", identifier.UTF8String)];
    return false;
}

-(void)createControlMapRecurse:(NSView*)parentView
{
    for (NSView* view in parentView.subviews) {
        if ([self maybeRegisterView: view]) {
            // "pass;"
        }
        else if ([view isKindOfClass:[NSBox class]]) {
            [self createControlMapRecurse: view.subviews[0]];
        }
        /* Necessary until all OK/Cancel buttons supplied witn "identifier"s.
         Don't even need entry in CtlidToHWND. */
        else if ([view isKindOfClass:[NSButton class]]) {
            NSButton* button = (NSButton*)view;
            std::string title =  button.title.UTF8String; // hashing on "NSCFString" doesn't work.
            if (ByTitle.count(title)) {
                [button setTag:ByTitle[title]]; //Install numeric Windows resource_id.
                [button setTarget: self];    //should be redundant for current controls
                [button setAction: @selector(activeButton:)];  //but this will be different!
            }
        }
        else if ([view isKindOfClass:[NSMatrix class]]) {
            NSMatrix * matrix = (NSMatrix*)view;
            for (NSButtonCell* cell in matrix.cells) {
                if ([self maybeRegisterView: (NSView*)cell])
                    [cell setState: NO];  // not clear if this be useful
            }
        }
    }
}

-(void)createControlMap
{
    [self createControlMapRecurse:self.window.contentView];
 
    for (auto [nss, rid] : RIDValMap)
        if (!CtlidToHWND.count(rid))
            [self barf: FormatString("Did not find control for resource id %d (%s)", rid, nss.UTF8String)];
}

-(void)SetControlText:(NSInteger)ctlid text:(NSString*)text
{
    NSView* view = [self GetControlView:ctlid];
    assert([view isKindOfClass:[NSTextField class]]);
    [(NSTextField*)view setStringValue:text];
}
-(long)GetControlText:(NSInteger)ctlid buf:(char*)buf length:(NSInteger)len
{
    NSView* view = [self GetControlView:ctlid];
    assert([view isKindOfClass:[NSTextField class]]);
    NSString *ns = ((NSTextField *)view).stringValue;
    strncpy(buf, ns.UTF8String, len);
    buf[len-1] = '\0';
    return strlen(buf);
}
-(void)setDlgItemCheckState:(NSInteger)ctl_id value:(NSInteger)yesNo
{
    NSView* view = [self GetControlView:ctl_id];
    assert([view isKindOfClass:[NSButtonCell class]] |[view isKindOfClass:[NSButton class]]);
    [(NSButton*)view setState:yesNo];
}
-(bool)getDlgItemCheckState:(NSInteger)ctl_id
{
    NSView* view = [self GetControlView:ctl_id];
    //checkboxes report as "NSButton", but radios as "NSButtonCell"
    assert([view isKindOfClass:[NSButtonCell class]] |[view isKindOfClass:[NSButton class]]);
    NSButton* button = (NSButton*)view; // don't understand class structure
    return [button state] ? true : false;
}
-(HWND)GetControlHWND:(NSInteger)ctlid
{
    if (CtlidToHWND.count(ctlid) == 0)
        [self barf: FormatString("Received action from Cocoa control tagged %d, for which no emulation exists.", ctlid)];
    return CtlidToHWND[ctlid];
}
-(NSView*)GetControlView:(NSInteger)ctlid
{
    return getHWNDView([self GetControlHWND: ctlid]);
}
-(void)showControl:(NSInteger)control showYes:(NSInteger)yesno
{
    [[self GetControlView:control] setHidden: ((yesno == 0) ? YES : NO)];
}

-(void)reflectCommand:(NSInteger)command
{
    callWndProcGeneralCommandParam(_hWnd, _NXGObject, (int)command, 0);
}

-(void)reflectCommandParam:(NSInteger)command lParam:(NSInteger)param
{
    callWndProcGeneralCommandParam(_hWnd, _NXGObject, (int)command, param);
}
-(void)dealloc
{
 // important to debug here.  This really gets called when you manage
// your strongptrs correctly.
 //   printf("GenericWindlgController dealloc called\n");
    [self real_deall];
}

-(IBAction)activeButton:(id)sender
{
    /* Buttons routed here either by IB action or this code (in some versions) call the
     Windows dialog code responsive to the WM_COMMAND code stored by this code into their "tag"s. */

    if ([sender isKindOfClass:[NSMatrix class]]) {
        NSMatrix * mater = (NSMatrix *)sender;  // juxta filium clamantem
        sender = mater.selectedCell;
    }
    /* The control's "tag" is the Windows resource.h command code for the control */
    /* Might not be NSControl (e.g., for radio-buttons), but if it supports "tag", good enough */

    auto tag = [sender tag];
    assert(tag != 0);
    [self reflectCommand:tag];
}
-(void)EnableControl:(NSInteger)ctl_id yesNo:(NSInteger)yesNo;
{
    NSView* view = [self GetControlView:ctl_id];
    assert([view isKindOfClass:[NSControl class]]);
    NSControl* control = (NSControl*)view;
    [control setEnabled: yesNo ? YES : NO];
}
@end

void OfferGenericWindlg(Class clazz, NSString* nib_name, RIDVector rid_vector, GraphicObject* object) {
    id dialog = [[clazz alloc] initWithNibAndRIDs:nib_name rids:rid_vector];
    if (dialog)   // if any kind of error, including no nib, don't show.
        [dialog showModal:object];
}

/* Can't use static STL -- load time initializes it at unpredictable time compared to our registrees */
/* Can't use structs, either, as funargs get gc'ed if not protected by strong pointer */
/* This is a lot easier. */

/* solution found 3-24-2022 -- create it first time called. */
typedef std::unordered_map<unsigned int, TLEditDlgCreator> t_TabulaCreatorum;
static t_TabulaCreatorum *TabulaCreatorum = nullptr;

int RegisterTLEDitDialog(unsigned int resource_id,  TLEditDlgCreator creator) {
    if (TabulaCreatorum == nullptr)
        TabulaCreatorum = new t_TabulaCreatorum;
    (*TabulaCreatorum)[resource_id] = creator;
    return 0;
}

void MacDialogDispatcher(unsigned int resource_id, GraphicObject * obj) {
    if ((*TabulaCreatorum).count(resource_id) == 0)
        return;  /*this happens sometimes -- clicking on odd things -- just ignore */
    (*TabulaCreatorum)[resource_id](obj);
};
