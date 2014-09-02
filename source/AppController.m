/*
    AppController.m

    This file is in the public domain.
*/

#import <Cocoa/Cocoa.h>
#import <mach/mach_host.h>

#import "SystemIncludes.h"

#import "AppController.h"
#import "ListUtils.h"
#import "PPCProcessor.h"
#import "PPC64Processor.h"
#import "SmoothViewAnimation.h"
#import "SysUtils.h"
#import "UserDefaultKeys.h"
#import "X86Processor.h"
#import "X8664Processor.h"

#define UNIFIED_TOOLBAR_DELTA           12
#define CONTENT_BORDER_SIZE_TOP         2
#define CONTENT_BORDER_SIZE_BOTTOM      10
#define CONTENT_BORDER_MARGIN_BOTTOM    4

#define PROCESS_SUCCESS @"PROCESS_SUCCESS"

@implementation AppController

//  initialize
// ----------------------------------------------------------------------------

+ (void)initialize
{
    NSUserDefaultsController*   theController   =
        NSUserDefaultsController.sharedUserDefaultsController;
    NSDictionary*               theValues       =
        @{AskOutputDirKey:          @"1",
          DemangleCppNamesKey:      @"YES",
          EntabOutputKey:           @"NO",
          OpenOutputFileKey:        @"YES",
          OutputAppKey:             @"BBEdit",
          OutputFileExtensionKey:   @"txt",
          OutputFileNameKey:        @"output",
          SeparateLogicalBlocksKey: @"NO",
          ShowDataSectionKey:       @"NO",
          ShowIvarTypesKey:         @"YES",
          ShowLocalOffsetsKey:      @"YES",
          ShowMD5Key:               @"YES",
          ShowMethodReturnTypesKey: @"YES",
          ShowReturnStatementsKey:  @"YES",
          UseCustomNameKey:         @"0",
          VerboseMsgSendsKey:       @"YES"};
    
    theController.initialValues = theValues;
    [theController.defaults registerDefaults: theValues];
}

//  init
// ----------------------------------------------------------------------------

- (instancetype)init
{
    if ((self = [super init]) == nil)
        return nil;

    return self;
}

//  dealloc
// ----------------------------------------------------------------------------


#pragma mark -
//  openExe:
// ----------------------------------------------------------------------------
//  Open from File menu. Packages are treated as directories, so we can get
//  at frameworks, bundles etc.

- (IBAction)openExe: (id)sender
{
    NSOpenPanel*    thePanel    = [NSOpenPanel openPanel];

    thePanel.treatsFilePackagesAsDirectories = YES;

    if ([thePanel runModal] != NSFileHandlingPanelOKButton)
        return;

    NSString*   theName = thePanel.URL.path;

    [self newOFile: [NSURL fileURLWithPath: theName] needsPath: YES];
}

//  newPackageFile:
// ----------------------------------------------------------------------------
//  Attempt to drill into the package to the executable. Fails when the exe is
//  unreadable.

- (void)newPackageFile: (NSURL*)inPackageFile
{

    iOutputFilePath = inPackageFile.path;

    NSBundle*   exeBundle   = [NSBundle bundleWithPath: iOutputFilePath];

    if (!exeBundle)
    {
        fprintf(stderr, "otx: [AppController newPackageFile:] "
            "unable to get bundle from path: %s\n", UTF8STRING(iOutputFilePath));
        return;
    }

    NSString*   theExePath  = exeBundle.executablePath;

    if (!theExePath)
    {
        fprintf(stderr, "otx: [AppController newPackageFile:] "
            "unable to get executable path from bundle: %s\n",
            UTF8STRING(iOutputFilePath));
        return;
    }

    [self newOFile: [NSURL fileURLWithPath: theExePath] needsPath: NO];
}

//  newOFile:needsPath:
// ----------------------------------------------------------------------------

- (void)newOFile: (NSURL*)inOFile
       needsPath: (BOOL)inNeedsPath
{


    iObjectFile  = inOFile;

    if (inNeedsPath)
    {

        iOutputFilePath = iObjectFile.path;
    }

    if ([NSWorkspace.sharedWorkspace isFilePackageAtPath: iOutputFilePath])
        iExeName    = iOutputFilePath.lastPathComponent.stringByDeletingPathExtension;
    else
        iExeName    = iOutputFilePath.lastPathComponent;


    [self refreshMainWindow];
    [self syncOutputText: nil];
    [self syncSaveButton];
}

#pragma mark -
//  setupMainWindow
// ----------------------------------------------------------------------------

- (void)setupMainWindow
{
    if (OS_IS_POST_TIGER)
    {   // Adjust main window for Leopard.
        // Save the resize masks and apply new ones.
        NSUInteger  origMainViewMask    = iMainView.autoresizingMask;
        NSUInteger  origProgViewMask    = iProgView.autoresizingMask;

        iMainView.autoresizingMask = NSViewMaxYMargin;
        iProgView.autoresizingMask = NSViewMaxYMargin;

        NSRect  curFrame    = iMainWindow.frame;
        NSSize  maxSize     = iMainWindow.contentMaxSize;
        NSSize  minSize     = iMainWindow.contentMinSize;

        curFrame.size.height    -= UNIFIED_TOOLBAR_DELTA;
        minSize.height          -= UNIFIED_TOOLBAR_DELTA - CONTENT_BORDER_MARGIN_BOTTOM;
        maxSize.height          -= UNIFIED_TOOLBAR_DELTA - CONTENT_BORDER_MARGIN_BOTTOM;

        iMainWindow.contentMinSize = minSize;
        [iMainWindow setFrame: curFrame
                      display: YES];
        iMainWindow.contentMaxSize = maxSize;

        // Grow the prog view for the gradient.
        iMainView.autoresizingMask = NSViewMinYMargin | NSViewNotSizable;
        iProgView.autoresizingMask = NSViewHeightSizable | NSViewMaxYMargin;

        curFrame.size.height += CONTENT_BORDER_MARGIN_BOTTOM;
        [iMainWindow setFrame: curFrame
                      display: YES];

        iMainView.autoresizingMask = origMainViewMask;
        iProgView.autoresizingMask = origProgViewMask;

        // Set up smaller gradients.
        [iMainWindow setAutorecalculatesContentBorderThickness: NO
                                                       forEdge: NSMaxYEdge];
        [iMainWindow setAutorecalculatesContentBorderThickness: NO
                                                       forEdge: NSMinYEdge];
        [iMainWindow setContentBorderThickness: CONTENT_BORDER_SIZE_TOP
                                       forEdge: NSMaxYEdge];
        [iMainWindow setContentBorderThickness: CONTENT_BORDER_SIZE_BOTTOM
                                       forEdge: NSMinYEdge];

        // Set up text shadows.
        NSCell *(^cell)(NSControl *) = ^NSCell *(NSControl *control) { return (NSCell *)control.cell; };
        cell(iPathText).backgroundStyle = NSBackgroundStyleRaised;
        cell(iPathLabelText).backgroundStyle = NSBackgroundStyleRaised;
        cell(iTypeText).backgroundStyle = NSBackgroundStyleRaised;
        cell(iTypeLabelText).backgroundStyle = NSBackgroundStyleRaised;
        cell(iOutputLabelText).backgroundStyle = NSBackgroundStyleRaised;
        cell(iProgText).backgroundStyle = NSBackgroundStyleRaised;
    }
    else
    {
        NSImage*    bgImage = [NSImage imageNamed: @"Main Window Background"];

        iMainWindow.backgroundColor = [NSColor colorWithPatternImage: bgImage];

        // Set up text shadows.
        [self applyShadowToText: iPathLabelText];
        [self applyShadowToText: iTypeLabelText];
        [self applyShadowToText: iOutputLabelText];
    }

    // At this point, the window is still brushed metal. We can get away with
    // not setting the background image here because hiding the prog view
    // resizes the window, which results in our delegate saving the day.
    [self hideProgView: NO openFile: NO];

    iMainWindow.frameAutosaveName = iMainWindow.title;
//    [iArchPopup selectItemWithTag: iSelectedArchCPUType];
}

//  showMainWindow
// ----------------------------------------------------------------------------

- (IBAction)showMainWindow: (id)sender
{
    if (!iMainWindow)
    {
        fprintf(stderr, "otx: failed to load MainMenu.nib\n");
        return;
    }

    [iMainWindow makeKeyAndOrderFront: nil];
}

//  applyShadowToText:
// ----------------------------------------------------------------------------

- (void)applyShadowToText: (NSTextField*)inText
{
    if (OS_IS_TIGER)    // not needed on Leopard
    {
        NSMutableAttributedString*  newString   =
            [[NSMutableAttributedString alloc] initWithAttributedString:
            inText.attributedStringValue];

        [newString addAttribute: NSShadowAttributeName value: iTextShadow
            range: NSMakeRange(0, newString.length)];
        inText.attributedStringValue = newString;
    }
}

#pragma mark -
//  selectArch:
// ----------------------------------------------------------------------------

- (IBAction)selectArch: (id)sender
{
    CPUID*  selectedCPU = (CPUID*)iArchPopup.selectedItem.tag;

    iSelectedArchCPUType        = selectedCPU->type;
    iSelectedArchCPUSubType     = selectedCPU->subtype;
    const NXArchInfo* archInfo  = NXGetArchInfoFromCpuType(
        iSelectedArchCPUType, iSelectedArchCPUSubType);

    iOutputFileLabel = [NSString stringWithFormat: @"_%s", archInfo->name];

    switch (iSelectedArchCPUType)
    {
        case CPU_TYPE_POWERPC:
            iVerifyButton.enabled = NO;
            break;
        case CPU_TYPE_I386:
            iVerifyButton.enabled = YES;
            break;
        case CPU_TYPE_POWERPC64:
            iVerifyButton.enabled = NO;
            break;
        case CPU_TYPE_X86_64:
            iVerifyButton.enabled = YES;
            break;

        default:
            break;
    }

    [self syncOutputText: nil];
    [self syncSaveButton];
}

//  attemptToProcessFile:
// ----------------------------------------------------------------------------

- (IBAction)attemptToProcessFile: (id)sender
{
    gCancel = NO;    // Fresh start.

    NSTimeInterval interval = 0.0333;

    if (OS_IS_PRE_SNOW)
        interval = 0.0;

    if (iIndeterminateProgBarMainThreadTimer)
    {
        [iIndeterminateProgBarMainThreadTimer invalidate];
    }

    iIndeterminateProgBarMainThreadTimer = [NSTimer scheduledTimerWithTimeInterval: interval
        target: self selector: @selector(nudgeIndeterminateProgBar:)
        userInfo: nil repeats: YES];

    if (!iObjectFile)
    {
        fprintf(stderr, "otx: [AppController attemptToProcessFile]: "
            "tried to process nil object file.\n");
        return;
    }


    iOutputFileName = iOutputText.stringValue;

    NSString*   theTempOutputFilePath   = iOutputFilePath;

    if ([NSUserDefaults.standardUserDefaults boolForKey: AskOutputDirKey])
    {
        NSSavePanel*    thePanel    = [NSSavePanel savePanel];

        thePanel.nameFieldStringValue = iOutputFileName;
        thePanel.treatsFilePackagesAsDirectories = YES;

        if ([thePanel runModal]  != NSFileHandlingPanelOKButton)
            return;

        iOutputFilePath = thePanel.URL.path;
    }
    else
    {
        iOutputFilePath =
            [theTempOutputFilePath.stringByDeletingLastPathComponent
            stringByAppendingPathComponent: iOutputText.stringValue];
    }

    [self processFile];
}

//  processFile
// ----------------------------------------------------------------------------

- (void)processFile
{
    [self reportProgress: @{PRIndeterminateKey: @YES,
                            PRDescriptionKey:   @"Loading executable"}];

    if ([self checkOtool: iObjectFile.path] == NO)
    {
        [self reportError: @"otool was not found."
               suggestion: @"Please install otool and try again."];
        return;
    }

    iProcessing = YES;
    [self adjustInterfaceForMultiThread];
    [self showProgView];
}

//  continueProcessingFile
// ----------------------------------------------------------------------------

- (void)continueProcessingFile
{
    @autoreleasepool {
        Class               procClass   = nil;

        switch (iSelectedArchCPUType)
        {
            case CPU_TYPE_POWERPC:
                procClass = PPCProcessor.class;
                break;

            case CPU_TYPE_POWERPC64:
                procClass = PPC64Processor.class;
                break;

            case CPU_TYPE_I386:
                procClass = X86Processor.class;
                break;

            case CPU_TYPE_X86_64:
                procClass = X8664Processor.class;
                break;

            default:
                fprintf(stderr, "otx: [AppController continueProcessingFile]: "
                    "unknown arch type: %d", iSelectedArchCPUType);
                break;
        }

        if (!procClass)
        {
            [self performSelectorOnMainThread: @selector(processingThreadDidFinish:)
                                   withObject: @"Unsupported architecture."
                                waitUntilDone: NO];
            return;
        }

        // Save defaults into the ProcOptions struct.
        NSUserDefaults* theDefaults = NSUserDefaults.standardUserDefaults;
        ProcOptions     opts        = {0};

        opts.localOffsets           =
            [theDefaults boolForKey: ShowLocalOffsetsKey];
        opts.entabOutput            =
            [theDefaults boolForKey: EntabOutputKey];
        opts.dataSections           =
            [theDefaults boolForKey: ShowDataSectionKey];
        opts.checksum               =
            [theDefaults boolForKey: ShowMD5Key];
        opts.verboseMsgSends        =
            [theDefaults boolForKey: VerboseMsgSendsKey];
        opts.separateLogicalBlocks  =
            [theDefaults boolForKey: SeparateLogicalBlocksKey];
        opts.demangleCppNames       =
            [theDefaults boolForKey: DemangleCppNamesKey];
        opts.returnTypes            =
            [theDefaults boolForKey: ShowMethodReturnTypesKey];
        opts.variableTypes          =
            [theDefaults boolForKey: ShowIvarTypesKey];
        opts.returnStatements       =
            [theDefaults boolForKey: ShowReturnStatementsKey];

        id  theProcessor    = [[procClass alloc] initWithURL: iObjectFile
            controller: self options: &opts];

        if (!theProcessor)
        {
            [self performSelectorOnMainThread: @selector(processingThreadDidFinish:)
                                   withObject: @"Unable to create processor."
                                waitUntilDone: NO];
            return;
        }

        if (![theProcessor processExe: iOutputFilePath])
        {
            NSString* resultString = (gCancel == YES) ? PROCESS_SUCCESS :
                [NSString stringWithFormat: @"Unable to process %@.", iObjectFile.path];

            [self performSelectorOnMainThread: @selector(processingThreadDidFinish:)
                                   withObject: resultString
                                waitUntilDone: NO];
            return;
        }

        [self performSelectorOnMainThread: @selector(processingThreadDidFinish:)
                               withObject: PROCESS_SUCCESS
                            waitUntilDone: NO];
    }
}

//  processingThreadDidFinish:
// ----------------------------------------------------------------------------

- (void)processingThreadDidFinish: (NSString*)result
{
    iProcessing = NO;
    [iIndeterminateProgBarMainThreadTimer invalidate];
    iIndeterminateProgBarMainThreadTimer = nil;

    if ([result isEqualTo: PROCESS_SUCCESS])
    {
        [self hideProgView: YES openFile: (gCancel == YES) ? NO :
            [NSUserDefaults.standardUserDefaults
            boolForKey: OpenOutputFileKey]];
    }
    else
    {
        [self hideProgView: YES openFile: NO];
        [self reportError: @"Error processing file."
               suggestion: result];
    }
}


#pragma mark -
//  adjustInterfaceForMultiThread
// ----------------------------------------------------------------------------
//  In future, we may allow the user to do more than twiddle prefs and resize
//  the window. For now, just disable the fun stuff.

- (void)adjustInterfaceForMultiThread
{
    [self syncSaveButton];

    iArchPopup.enabled = NO;
    iThinButton.enabled = NO;
    iVerifyButton.enabled = NO;
    iOutputText.enabled = NO;
    [iMainWindow standardWindowButton: NSWindowCloseButton].enabled = NO;

    [iMainWindow display];
}

//  adjustInterfaceForSingleThread
// ----------------------------------------------------------------------------

- (void)adjustInterfaceForSingleThread
{
    [self syncSaveButton];

    iArchPopup.enabled = iExeIsFat;
    iThinButton.enabled = iExeIsFat;
    iVerifyButton.enabled = (iSelectedArchCPUType == CPU_TYPE_I386) ||
                            (iSelectedArchCPUType == CPU_TYPE_X86_64);
    iOutputText.enabled = YES;
    [iMainWindow standardWindowButton: NSWindowCloseButton].enabled = YES;

    [iMainWindow display];
}

#pragma mark -
//  showProgView
// ----------------------------------------------------------------------------

- (void)showProgView
{
    // Set up the target window frame.
    NSRect  targetWindowFrame   = iMainWindow.frame;
    NSRect  progViewFrame       = iProgView.frame;

    targetWindowFrame.origin.y      -= progViewFrame.size.height;
    targetWindowFrame.size.height   += progViewFrame.size.height;

    // Save the resize masks and apply new ones.
    NSUInteger  origMainViewMask    = iMainView.autoresizingMask;
    NSUInteger  origProgViewMask    = iProgView.autoresizingMask;

    iMainView.autoresizingMask = NSViewMinYMargin;
    iProgView.autoresizingMask = NSViewMinYMargin;

    // Set up an animation.
    NSMutableDictionary*    newWindowItem =
        [NSMutableDictionary dictionaryWithCapacity: 8];

    // Standard keys
    newWindowItem[NSViewAnimationTargetKey] = iMainWindow;
    newWindowItem[NSViewAnimationEndFrameKey] = [NSValue valueWithRect: targetWindowFrame];

    NSNumber*   effect          = @(
        NSXViewAnimationUpdateResizeMasksAtEndEffect       |
        NSXViewAnimationUpdateWindowMinMaxSizesAtEndEffect |
        NSXViewAnimationPerformSelectorAtEndEffect);
    NSNumber*   origMainMask    = @(origMainViewMask);
    NSNumber*   origProgMask    = @(origProgViewMask);

    // Custom keys
    newWindowItem[NSXViewAnimationCustomEffectsKey] = effect;
    newWindowItem[NSXViewAnimationResizeMasksArrayKey] = @[origMainMask, origProgMask];
    newWindowItem[NSXViewAnimationResizeViewsArrayKey] = @[iMainView, iProgView];

    // Since we're about to grow the window, first adjust the max height.
    NSSize  maxSize = iMainWindow.contentMaxSize;
    NSSize  minSize = iMainWindow.contentMinSize;

    maxSize.height  += progViewFrame.size.height;
    minSize.height  += progViewFrame.size.height;

    iMainWindow.contentMaxSize = maxSize;

    // Set the min size after the animation completes.
    NSValue*    minSizeValue    = [NSValue valueWithSize: minSize];

    newWindowItem[NSXViewAnimationWindowMinSizeKey] = minSizeValue;

    // Continue processing after the animation completes.
    SEL continueSel = @selector(continueProcessingFile);

    newWindowItem[NSXViewAnimationSelectorKey] = [NSValue value: &continueSel withObjCType: @encode(SEL)];
    newWindowItem[NSXViewAnimationPerformInNewThreadKey] = @YES;

    SmoothViewAnimation*    theAnim = [[SmoothViewAnimation alloc]
        initWithViewAnimations: @[newWindowItem]];

    theAnim.delegate = self;
    theAnim.duration = kMainAnimationTime;
    theAnim.animationCurve = NSAnimationLinear;

    // Do the deed.
    [theAnim startAnimation];
    //[theAnim autorelease];
}

//  hideProgView:
// ----------------------------------------------------------------------------

- (void)hideProgView: (BOOL)inAnimate
            openFile: (BOOL)inOpenFile
{
    NSRect  targetWindowFrame   = iMainWindow.frame;
    NSRect  progViewFrame       = iProgView.frame;

    targetWindowFrame.origin.y      += progViewFrame.size.height;
    targetWindowFrame.size.height   -= progViewFrame.size.height;

    NSUInteger  origMainViewMask    = iMainView.autoresizingMask;
    NSUInteger  origProgViewMask    = iProgView.autoresizingMask;

    NSNumber*   origMainMask    = @(origMainViewMask);
    NSNumber*   origProgMask    = @(origProgViewMask);

    iMainView.autoresizingMask = NSViewMinYMargin;
    iProgView.autoresizingMask = NSViewMinYMargin;

    NSSize  maxSize = iMainWindow.contentMaxSize;
    NSSize  minSize = iMainWindow.contentMinSize;

    maxSize.height  -= progViewFrame.size.height;
    minSize.height  -= progViewFrame.size.height;

    iMainWindow.contentMinSize = minSize;

    if (inAnimate)
    {
        NSMutableDictionary*    newWindowItem =
            [NSMutableDictionary dictionaryWithCapacity: 10];

        newWindowItem[NSViewAnimationTargetKey] = iMainWindow;
        newWindowItem[NSViewAnimationEndFrameKey] = [NSValue valueWithRect: targetWindowFrame];

        uint32_t  effects =
            NSXViewAnimationUpdateResizeMasksAtEndEffect        |
            NSXViewAnimationUpdateWindowMinMaxSizesAtEndEffect  |
            NSXViewAnimationPerformSelectorAtEndEffect;

        if (inOpenFile)
        {
            effects |= NSXViewAnimationOpenFileWithAppAtEndEffect;
            newWindowItem[NSXViewAnimationFilePathKey] = iOutputFilePath;
            newWindowItem[NSXViewAnimationAppNameKey] = [[NSUserDefaults standardUserDefaults]
                                                         objectForKey: OutputAppKey];
        }

        // Custom keys
        newWindowItem[NSXViewAnimationCustomEffectsKey] = @(effects);
        newWindowItem[NSXViewAnimationResizeMasksArrayKey] = @[origMainMask, origProgMask];
        newWindowItem[NSXViewAnimationResizeViewsArrayKey] = @[iMainView, iProgView];

        SEL adjustSel   = @selector(adjustInterfaceForSingleThread);

        newWindowItem[NSXViewAnimationSelectorKey] = [NSValue value: &adjustSel withObjCType: @encode(SEL)];

        NSValue*    maxSizeValue    =
            [NSValue valueWithSize: maxSize];

        newWindowItem[NSXViewAnimationWindowMaxSizeKey] = maxSizeValue;

        SmoothViewAnimation*    theAnim = [[SmoothViewAnimation alloc]
            initWithViewAnimations: @[newWindowItem]];

        theAnim.delegate = self;
        theAnim.duration = kMainAnimationTime;
        theAnim.animationCurve = NSAnimationLinear;

        // Do the deed.
        [theAnim startAnimation];
        //[theAnim autorelease];
    }
    else
    {
        [iMainWindow setFrame: targetWindowFrame display: NO];
        iMainWindow.contentMaxSize = maxSize;
        iMainView.autoresizingMask = origMainViewMask;
        iProgView.autoresizingMask = origProgViewMask;
    }   
}

#pragma mark -
//  thinFile:
// ----------------------------------------------------------------------------
//  Use lipo to separate out the currently selected arch from a unibin.

- (IBAction)thinFile: (id)sender
{
    NSString*   theThinOutputPath   = nil;
    NSString*   archExt             = nil;

    switch (iSelectedArchCPUType)
    {
        case CPU_TYPE_POWERPC:
            archExt  = @"_ppc";
            break;
        case CPU_TYPE_POWERPC64:
            archExt  = @"_ppc64";
            break;
        case CPU_TYPE_I386:
            archExt  = @"_i386";
            break;
        case CPU_TYPE_X86_64:
            archExt  = @"_x86_64";
            break;

        default:
            break;
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey: AskOutputDirKey])
    {
        NSSavePanel*    thePanel    = [NSSavePanel savePanel];
        NSString*       theFileName =
            [iExeName stringByAppendingString: archExt];

        thePanel.nameFieldStringValue = theFileName;
        thePanel.treatsFilePackagesAsDirectories = YES;

        if ([thePanel runModal]  != NSFileHandlingPanelOKButton)
            return;

        theThinOutputPath   = thePanel.URL.path;
    }
    else
    {
        theThinOutputPath   =
            [iOutputFilePath.stringByDeletingLastPathComponent
            stringByAppendingPathComponent:
            [iExeName stringByAppendingString: archExt]];
    }

    const NXArchInfo* selectedArchInfo = NXGetArchInfoFromCpuType(
        iSelectedArchCPUType, iSelectedArchCPUSubType);

    if (selectedArchInfo == NULL)
    {
        printf("otx: Unable to get arch info for CPU type %u, subtype %u\n",
            iSelectedArchCPUType, iSelectedArchCPUSubType);
        return;
    }

    NSString*   lipoString  = [NSString stringWithFormat:
        @"lipo \"%@\" -output \"%@\" -thin %s", iObjectFile.path,
        theThinOutputPath, selectedArchInfo->name];

    if (system(UTF8STRING(lipoString)) != 0)
        [self reportError: @"lipo was not found."
               suggestion: @"Please install lipo and try again."];
}

#pragma mark -
//  verifyNops:
// ----------------------------------------------------------------------------
//  Create an instance of xxxProcessor to search for obfuscated nops. If any
//  are found, let user decide to fix them or not.

- (IBAction)verifyNops: (id)sender
{
    switch (iSelectedArchCPUType)
    {
        case CPU_TYPE_I386:
        case CPU_TYPE_X86_64:
        {
            ProcOptions     opts    = {0};
            X86Processor*   theProcessor    =
                [[X86Processor alloc] initWithURL: iObjectFile controller: self
                options: &opts];

            if (!theProcessor)
            {
                fprintf(stderr, "otx: -[AppController verifyNops]: "
                    "unable to create processor.\n");
                return;
            }

            unsigned char** foundList   = nil;
            uint32_t          foundCount  = 0;
            NSAlert*        theAlert    = [[NSAlert alloc] init];

            if ([theProcessor verifyNops: &foundList
                numFound: &foundCount])
            {
                NopList*    theInfo = malloc(sizeof(NopList));

                theInfo->list   = foundList;
                theInfo->count  = foundCount;

                [theAlert addButtonWithTitle: @"Fix"];
                [theAlert addButtonWithTitle: @"Cancel"];
                theAlert.messageText = @"Broken nop's found.";
                theAlert.informativeText = [NSString stringWithFormat:
                    @"otx found %d broken nop's. Would you like to save "
                    @"a copy of the executable with fixed nop's?",
                    foundCount];
                [theAlert beginSheetModalForWindow: iMainWindow
                    modalDelegate: self didEndSelector:
                    @selector(nopAlertDidEnd:returnCode:contextInfo:)
                    contextInfo: theInfo];
            }
            else
            {
                [theAlert addButtonWithTitle: @"OK"];
                theAlert.messageText = @"No broken nop's.";
                theAlert.informativeText = @"The executable is healthy.";
                [theAlert beginSheetModalForWindow: iMainWindow
                    modalDelegate: nil didEndSelector: nil contextInfo: nil];
            }

            break;
        }

        default:
            break;
    }
}

//  nopAlertDidEnd:returnCode:contextInfo:
// ----------------------------------------------------------------------------
//  Respond to user's decision to fix obfuscated nops.

- (void)nopAlertDidEnd: (NSAlert*)alert
            returnCode: (int)returnCode
           contextInfo: (void*)contextInfo
{
    if (returnCode == NSAlertSecondButtonReturn)
        return;

    if (!contextInfo)
    {
        fprintf(stderr, "otx: tried to fix nops with nil contextInfo\n");
        return;
    }

    NopList*    theNops = (NopList*)contextInfo;

    if (!theNops->list)
    {
        fprintf(stderr, "otx: tried to fix nops with nil NopList.list\n");
        free(theNops);
        return;
    }

    switch (iSelectedArchCPUType)
    {
        case CPU_TYPE_I386:
        {
            ProcOptions     opts    = {0};
            X86Processor*   theProcessor    =
                [[X86Processor alloc] initWithURL: iObjectFile controller: self
                options: &opts];

            if (!theProcessor)
            {
                fprintf(stderr, "otx: -[AppController nopAlertDidEnd]: "
                    "unable to create processor.\n");
                return;
            }

            NSURL* fixedFile = [theProcessor fixNops: theNops toPath: iOutputFilePath];
            if (fixedFile)
            {
                iIgnoreArch = YES;
                [self newOFile: fixedFile needsPath: YES];
            }
            else
                fprintf(stderr, "otx: unable to fix nops\n");

            break;
        }

        default:
            break;
    }

    free(theNops->list);
    free(theNops);
}

//  validateMenuItem:
// ----------------------------------------------------------------------------

- (BOOL)validateMenuItem: (NSMenuItem*)menuItem
{
    if (menuItem.action == @selector(attemptToProcessFile:))
    {
        NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;

        if ([defaults boolForKey: AskOutputDirKey])
            menuItem.title = [NSString stringWithFormat: @"Save..."];
        else
            menuItem.title = @"Save";

        return iFileIsValid;
    }

    return YES;
}

//  dupeFileAlertDidEnd:returnCode:contextInfo:
// ----------------------------------------------------------------------------

#pragma mark -
- (void)dupeFileAlertDidEnd: (NSAlert*)alert
                 returnCode: (int)returnCode
                contextInfo: (void*)contextInfo
{
    if (returnCode == NSAlertSecondButtonReturn)
        return;

    [self processFile];
}

#pragma mark -
//  refreshMainWindow
// ----------------------------------------------------------------------------

- (void)refreshMainWindow
{
    [iArchPopup removeAllItems];

    NSFileHandle*   theFileH            =
        [NSFileHandle fileHandleForReadingAtPath: iObjectFile.path];
    NSData* fileData;

    // Read a generous number of bytes from the executable.
    @try
    {
        fileData = [theFileH readDataOfLength:
            MAX(sizeof(mach_header), sizeof(fat_header)) +
            (sizeof(fat_arch) * 10)];
    }
    @catch (NSException* e)
    {
        fprintf(stderr, "otx: -[AppController syncDescriptionText]: "
            "unable to read from executable file. %s\n",
            UTF8STRING(e.reason));
        return;
    }

    if (fileData.length < sizeof(mach_header))
    {
        fprintf(stderr, "otx: -[AppController syncDescriptionText]: "
            "truncated executable file.\n");
        return;
    }

    const char* fileBytes   = fileData.bytes;

    iFileArchMagic = *(uint32_t*)fileBytes;

    // Handle non-Mach-O files
    switch (iFileArchMagic)
    {
        case MH_MAGIC:
        case MH_MAGIC_64:
        case MH_CIGAM:
        case MH_CIGAM_64:
        case FAT_MAGIC:
        case FAT_CIGAM:
            break;
        default:
            return;
    }

    iFileIsValid = YES;
    iPathText.stringValue = iObjectFile.path;
    [self applyShadowToText: iPathText];

    mach_header mh = *(mach_header*)fileBytes;
    NSMenu*     archMenu    = iArchPopup.menu;
    NSMenuItem* menuItem    = NULL;

    iSelectedArchCPUType    = iHostInfo.cpu_type;
    iSelectedArchCPUSubType = 0;

    if (mh.magic == FAT_MAGIC || mh.magic == FAT_CIGAM)
    {
        fat_header* fhp = (fat_header*)fileBytes;
        fat_arch*   fap = (fat_arch*)(fhp + 1);
        NSUInteger      i;

        fat_header  fatHeader   = *fhp;
        fat_arch    fatArch;

#if TARGET_RT_LITTLE_ENDIAN
        swap_fat_header(&fatHeader, OSLittleEndian);
#endif

        memset(iCPUIDs, '\0', sizeof(iCPUIDs));

        for (i = 0; i < fatHeader.nfat_arch; i++, fap += 1)
        {
            fatArch = *fap;

#if TARGET_RT_LITTLE_ENDIAN
            swap_fat_arch(&fatArch, 1, OSLittleEndian);
#endif

            // Save this CPUID for later.
            iCPUIDs[i].type = fatArch.cputype;
            iCPUIDs[i].subtype = fatArch.cpusubtype;

            // Get the arch name for the popup.
            const NXArchInfo* archInfo = NXGetArchInfoFromCpuType(
                fatArch.cputype, fatArch.cpusubtype);

            // Add the menu item with refcon.
            menuItem = [[NSMenuItem alloc] initWithTitle: @(archInfo->name)
                action: NULL keyEquivalent: @""];
            menuItem.tag = (NSInteger)&iCPUIDs[i];
            [archMenu addItem: menuItem];
        }
    }
    else   // Not a unibin, insert a single item into the (disabled) popup.
    {
        if (mh.magic == MH_CIGAM || mh.magic == MH_CIGAM_64)
             swap_mach_header(&mh, OSHostByteOrder());

        // Get the arch name for the popup.
        const NXArchInfo* archInfo = NXGetArchInfoFromCpuType(
            mh.cputype, mh.cpusubtype);
        NSString* archName = nil;

        if (archInfo != NULL)
            archName = @(archInfo->name);

        if (archName)
        {   // Add the menu item with refcon.
            menuItem = [[NSMenuItem alloc] initWithTitle: archName
                action: NULL keyEquivalent: @""];
            [archMenu addItem: menuItem];
            iSelectedArchCPUType = mh.cputype;
            iSelectedArchCPUSubType = mh.cpusubtype;
        }
    }

    BOOL shouldEnableArch = NO;

    if (!theFileH)
    {
        fprintf(stderr, "otx: -[AppController syncDescriptionText]: "
            "unable to open executable file.\n");
        return;
    }

    // If we just loaded a deobfuscated copy, skip the rest.
    if (iIgnoreArch)
    {
        iIgnoreArch = NO;
        return;
    }

    iOutputFileLabel    = nil;

    NSString*   tempString;
    NSString*   menuItemTitleToSelect   = NULL;

    iExeIsFat   = NO;

    switch (mh.magic)
    {
        case MH_CIGAM:
        case MH_CIGAM_64:
            swap_mach_header(&mh, OSHostByteOrder());
        case MH_MAGIC:
        case MH_MAGIC_64:
        {
            const NXArchInfo* archInfo = NXGetArchInfoFromCpuType(mh.cputype, mh.cpusubtype);

            if (iSelectedArchCPUType == mh.cputype)
                iSelectedArchCPUSubType = mh.cpusubtype;

            if (archInfo != NULL)
                tempString = @(archInfo->name);

            break;
        }

        default:
            break;
    }

    switch (iFileArchMagic)
    {
        case MH_MAGIC:
            if (iHostInfo.cpu_type == CPU_TYPE_POWERPC)
                iVerifyButton.enabled = NO;
            else if (iHostInfo.cpu_type == CPU_TYPE_I386)
                iVerifyButton.enabled = YES;

            menuItemTitleToSelect = tempString;

            break;

        case MH_CIGAM:
            if (iHostInfo.cpu_type == CPU_TYPE_POWERPC)
                iVerifyButton.enabled = YES;
            else if (iHostInfo.cpu_type == CPU_TYPE_I386)
                iVerifyButton.enabled = NO;

            menuItemTitleToSelect = tempString;

            break;

        case MH_MAGIC_64:
            if (iHostInfo.cpu_type == CPU_TYPE_POWERPC)
                iVerifyButton.enabled = NO;
            else if (iHostInfo.cpu_type == CPU_TYPE_I386)
                iVerifyButton.enabled = YES;

            menuItemTitleToSelect = tempString;

            break;

        case MH_CIGAM_64:
            if (iHostInfo.cpu_type == CPU_TYPE_POWERPC)
                iVerifyButton.enabled = YES;
            else if (iHostInfo.cpu_type == CPU_TYPE_I386)
                iVerifyButton.enabled = NO;

            menuItemTitleToSelect = tempString;

            break;

        case FAT_MAGIC:
        case FAT_CIGAM:
        {
            fat_header fh = *(fat_header*)fileBytes;

#if __LITTLE_ENDIAN__
            swap_fat_header(&fh, OSHostByteOrder());
#endif

            uint32_t archArraySize = sizeof(fat_arch) * fh.nfat_arch;
            fat_arch* archArray = (fat_arch*)malloc(archArraySize);
            memcpy(archArray, fileBytes + sizeof(fat_header), archArraySize);

#if __LITTLE_ENDIAN__
            swap_fat_arch(archArray, fh.nfat_arch, OSHostByteOrder());
#endif

            fat_arch* fa = NXFindBestFatArch(iHostInfo.cpu_type, iHostInfo.cpu_subtype,
                archArray, fh.nfat_arch);

            if (fa == NULL)
                fa = archArray;

            const NXArchInfo* bestArchInfo = NXGetArchInfoFromCpuType(fa->cputype, fa->cpusubtype);
            NSString* faName = nil;

            if (bestArchInfo != NULL)
                faName = [NSString stringWithFormat: @"%s", bestArchInfo->name];

            if (faName != nil)
            {
                iOutputFileLabel = [NSString stringWithFormat: @"_%@", faName];
                iVerifyButton.enabled = (iHostInfo.cpu_type == CPU_TYPE_I386);
                menuItemTitleToSelect = faName;
            }

            iExeIsFat               = YES;
            shouldEnableArch        = YES;
            tempString              = @"Fat";

            break;
        }

        default:
            iFileIsValid = NO;
            iSelectedArchCPUType = 0;
            tempString = @"Not a Mach-O file";
            iVerifyButton.enabled = NO;
            break;
    }

    iTypeText.stringValue = tempString;
    [self applyShadowToText: iTypeText];

    if (menuItemTitleToSelect != NULL)
        [iArchPopup selectItemWithTitle: menuItemTitleToSelect];

    iThinButton.enabled = shouldEnableArch;
    iArchPopup.enabled = shouldEnableArch;
    [iArchPopup synchronizeTitleAndSelectedItem];
}

//  syncSaveButton
// ----------------------------------------------------------------------------

- (void)syncSaveButton
{
    iSaveButton.enabled = iFileIsValid && !iProcessing &&
        iOutputText.stringValue.length > 0;
}

//  syncOutputText:
// ----------------------------------------------------------------------------

- (IBAction)syncOutputText: (id)sender
{
    if (!iFileIsValid || iProcessing)
        return;

    NSUserDefaults* theDefaults = NSUserDefaults.standardUserDefaults;
    NSString*       theString   = nil;

    if ([theDefaults boolForKey: UseCustomNameKey])
        theString   = [theDefaults objectForKey: OutputFileNameKey];
    else
        theString   = iExeName;

    if (!theString)
        theString   = @"error";

    NSString*   theExt  = [theDefaults objectForKey: OutputFileExtensionKey];

    if (!theExt)
        theExt  = @"error";

    if (iOutputFileLabel)
        theString   = [theString stringByAppendingString: iOutputFileLabel];

    theString   = [theString stringByAppendingPathExtension: theExt];

    if (theString)
        iOutputText.stringValue = theString;
    else
        iOutputText.stringValue = @"ERROR.FUKT";
}

#pragma mark -
//  setupPrefsWindow
// ----------------------------------------------------------------------------

- (void)setupPrefsWindow
{
    // Setup toolbar.
    NSToolbar*  toolbar = [[NSToolbar alloc]
        initWithIdentifier: OTXPrefsToolbarID];

    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    toolbar.delegate = self;

    iPrefsWindow.toolbar = toolbar;
    iPrefsWindow.showsToolbarButton = NO;

    // Load views.
    NSUInteger  numViews    = toolbar.items.count;

    iPrefsViews     = [[NSMutableArray alloc] initWithCapacity:numViews];
    iPrefsViews[0]  = iPrefsGeneralView;
    iPrefsViews[1]  = iPrefsOutputView;

    // Set the General panel as selected.
    toolbar.selectedItemIdentifier = PrefsGeneralToolbarItemID;

    // Set window size.
    // Maybe it's just me, but when I have to tell an object something by
    // first asking the object something, I always think there's an instance
    // method missing.
    [iPrefsWindow setFrame: [iPrefsWindow frameRectForContentRect:
                             ((NSView *)iPrefsViews[iPrefsCurrentViewIndex]).frame] display: NO];

    for (NSView *view in iPrefsViews)
        [iPrefsWindow.contentView addSubview: view];
}

//  showPrefs
// ----------------------------------------------------------------------------

- (IBAction)showPrefs: (id)sender
{
    // Set window position only if the window is not already onscreen.
    if (!iPrefsWindow.visible)
        [iPrefsWindow center];

    [iPrefsWindow makeKeyAndOrderFront: nil];
}

//  switchPrefsViews:
// ----------------------------------------------------------------------------

- (IBAction)switchPrefsViews: (id)sender
{
    NSToolbarItem*  item        = (NSToolbarItem*)sender;
    NSInteger          newIndex    = [item tag];

    if (newIndex == iPrefsCurrentViewIndex)
        return;

    NSRect  targetViewFrame = [iPrefsViews[newIndex] frame];

    // Calculate the new window size.
    NSRect  origWindowFrame     = [iPrefsWindow frame];
    NSRect  targetWindowFrame   = origWindowFrame;

    targetWindowFrame.size.height   = targetViewFrame.size.height;
    targetWindowFrame               =
        [iPrefsWindow frameRectForContentRect: targetWindowFrame];

    float   windowHeightDelta   =
        targetWindowFrame.size.height - origWindowFrame.size.height;

    targetWindowFrame.origin.y  -= windowHeightDelta;

    // Create dictionary for new window size.
    NSMutableDictionary*    newWindowDict =
        [NSMutableDictionary dictionaryWithCapacity: 5];

    newWindowDict[NSViewAnimationTargetKey] = iPrefsWindow;
    newWindowDict[NSViewAnimationEndFrameKey] = [NSValue valueWithRect: targetWindowFrame];

    newWindowDict[NSXViewAnimationCustomEffectsKey] = @(NSXViewAnimationFadeOutAndSwapEffect);
    newWindowDict[NSXViewAnimationSwapOldKey] = iPrefsViews[iPrefsCurrentViewIndex];
    newWindowDict[NSXViewAnimationSwapNewKey] = iPrefsViews[newIndex];

    // Create animation.
    SmoothViewAnimation*    windowAnim  = [[SmoothViewAnimation alloc]
        initWithViewAnimations: @[newWindowDict]];

    windowAnim.delegate = self;
    windowAnim.duration = kPrefsAnimationTime;
    windowAnim.animationCurve = NSAnimationLinear;

    iPrefsCurrentViewIndex  = newIndex;

    // Do the deed.
    [windowAnim startAnimation];
    //[windowAnim autorelease];
}

#pragma mark -
//  cancel:
// ----------------------------------------------------------------------------

- (IBAction)cancel: (id)sender
{
    NSDictionary*   progDict    =
        @{PRIndeterminateKey: @YES,
          PRDescriptionKey:   @"Cancelling"};

    [self reportProgress: progDict];

    gCancel = YES;
}

#pragma mark -
//  nudgeIndeterminateProgBar:
// ----------------------------------------------------------------------------

- (void)nudgeIndeterminateProgBar: (NSTimer*)timer
{
    if (iProgBar.indeterminate)
        [iProgBar startAnimation: self];
}

#pragma mark -
#pragma mark ErrorReporter protocol
//  reportError:suggestion:
// ----------------------------------------------------------------------------

- (void)reportError: (NSString*)inMessageText
         suggestion: (NSString*)inInformativeText
{
    NSAlert*    theAlert    = [[NSAlert alloc] init];

    [theAlert addButtonWithTitle: @"OK"];
    theAlert.messageText = inMessageText;
    theAlert.informativeText = inInformativeText;
    [theAlert beginSheetModalForWindow: iMainWindow
        modalDelegate: nil didEndSelector: nil contextInfo: nil];
}

#pragma mark -
#pragma mark ProgressReporter protocol
//  reportProgress:
// ----------------------------------------------------------------------------

- (void)reportProgress: (NSDictionary*)inDict
{
    if (!inDict)
    {
        fprintf(stderr, "otx: [AppController reportProgress:] nil inDict\n");
        return;
    }

    NSString*   description     = inDict[PRDescriptionKey];
    NSNumber*   indeterminate   = inDict[PRIndeterminateKey];
    NSNumber*   value           = inDict[PRValueKey];

    if (description)
    {
        iProgText.stringValue = description;
        [self applyShadowToText: iProgText];
    }

    if (value)
        iProgBar.doubleValue = value.doubleValue;

    if (indeterminate)
        iProgBar.indeterminate = indeterminate.boolValue;

    // This is a workaround for the bug mentioned by Mike Ash here:
    // http://mikeash.com/blog/pivot/entry.php?id=25 In our case, it causes
    // the progress bar to freeze when processing more than once per launch.
    // In other words, the first time you process an exe, everything is fine.
    // Subsequent processing of any exe displays a retarded progress bar.
    NSEvent*    pingUI  = [NSEvent otherEventWithType: NSApplicationDefined
        location: NSMakePoint(0, 0) modifierFlags: 0 timestamp: 0
        windowNumber: 0 context: nil subtype: 0 data1: 0 data2: 0];

    [[NSApplication sharedApplication] postEvent: pingUI atStart: NO];
}

#pragma mark -
#pragma mark DropBox delegates
//  dropBox:dragDidEnter:
// ----------------------------------------------------------------------------

- (NSDragOperation)dropBox: (DropBox*)inDropBox
              dragDidEnter: (id <NSDraggingInfo>)inItem
{
    if (inDropBox != iDropBox || iProcessing)
        return NSDragOperationNone;

    NSPasteboard*   pasteBoard  = inItem.draggingPasteboard;

    // Bail if not a file.
    if (![pasteBoard.types containsObject: NSFilenamesPboardType])
        return NSDragOperationNone;

    NSArray*    files   = [pasteBoard
        propertyListForType: NSFilenamesPboardType];

    // Bail if not a single file.
    if (files.count != 1)
        return NSDragOperationNone;

    // Bail if a folder.
    NSFileManager*  fileMan = NSFileManager.defaultManager;
    BOOL            isDirectory = NO;
    NSString*       filePath = files[0];
    NSString*       oFilePath = filePath;

    if ([fileMan fileExistsAtPath: filePath
        isDirectory: &isDirectory] == YES)
    {
        if (isDirectory)
        {
            if ([NSWorkspace.sharedWorkspace isFilePackageAtPath: filePath])
            {
                NSBundle*   exeBundle   = [NSBundle bundleWithPath: filePath];

                oFilePath = exeBundle.executablePath;

                if (oFilePath == nil)
                    return NSDragOperationNone;
            }
            else
                return NSDragOperationNone;
        }
    }
    else
        return NSDragOperationNone;

    // Bail if not a Mach-O file.
    NSFileHandle*   oFile = [NSFileHandle fileHandleForReadingAtPath: oFilePath];
    NSData* fileData;
    uint32_t magic;

    @try
    {
        fileData = [oFile readDataOfLength: sizeof(uint32_t)];
    }
    @catch (NSException* e)
    {
        fprintf(stderr, "otx: -[AppController dropBox:dragDidEnter:]: "
            "unable to read from executable file: %s\n", filePath.UTF8String);
        return NSDragOperationNone;
    }

    magic = *(uint32_t*)fileData.bytes;

    switch (magic)
    {
        case MH_MAGIC:
        case MH_MAGIC_64:
        case MH_CIGAM:
        case MH_CIGAM_64:
        case FAT_MAGIC:
        case FAT_CIGAM:
            break;

        default:
            return NSDragOperationNone;
    }

    NSDragOperation sourceDragMask  = inItem.draggingSourceOperationMask;

    // Bail if modifier keys pressed.
    if (!(sourceDragMask & NSDragOperationLink))
        return NSDragOperationNone;

    return NSDragOperationLink;
}

//  dropBox:didReceiveItem:
// ----------------------------------------------------------------------------

- (BOOL)dropBox: (DropBox*)inDropBox
 didReceiveItem: (id<NSDraggingInfo>)inItem
{
    if (inDropBox != iDropBox || iProcessing)
        return NO;

    NSURL*  theURL  = [NSURL URLFromPasteboard: inItem.draggingPasteboard];

    if (!theURL)
        return NO;

    if ([NSWorkspace.sharedWorkspace isFilePackageAtPath: theURL.path])
        [self newPackageFile: theURL];
    else
        [self newOFile: theURL needsPath: YES];

    return YES;
}

#pragma mark -
#pragma mark NSAnimation delegates
//  animationShouldStart:
// ----------------------------------------------------------------------------
//  We're only hooking this to perform custom effects with NSViewAnimations,
//  not to determine whether to start the animation. For this reason, we
//  always return YES, even if a sanity check fails.

- (BOOL)animationShouldStart: (NSAnimation*)animation
{
    if (![animation isKindOfClass: NSViewAnimation.class])
        return YES;

    NSArray*    animatedViews   = ((NSViewAnimation*)animation).viewAnimations;

    if (!animatedViews)
        return YES;

    NSWindow*   animatingWindow = animatedViews[0][NSViewAnimationTargetKey];

    if (animatingWindow != iMainWindow  &&
        animatingWindow != iPrefsWindow)
        return YES;

    for (id animObject in animatedViews)
    {
        if (!animObject)
            continue;

        NSNumber*   effectsNumber   =
            animObject[NSXViewAnimationCustomEffectsKey];

        if (!effectsNumber)
            continue;

        uint32_t  effects = [effectsNumber unsignedIntValue];

        if (effects & NSXViewAnimationSwapAtBeginningEffect)
        {   // Hide/show 2 views.
            NSView* oldView = animObject[NSXViewAnimationSwapOldKey];
            NSView* newView = animObject[NSXViewAnimationSwapNewKey];

            if (oldView)
                oldView.hidden = YES;

            if (newView)
                newView.hidden = NO;
        }
        else if (effects & NSXViewAnimationSwapAtBeginningAndEndEffect)
        {   // Hide a view.
            NSView* oldView = animObject[NSXViewAnimationSwapOldKey];

            if (oldView)
                oldView.hidden = YES;
        }
        else if (effects & NSXViewAnimationFadeOutAndSwapEffect)
        {  // Fade out a view.
            NSView* oldView = animObject[NSXViewAnimationSwapOldKey];

            if (oldView)
            {   // Create a new animation to fade out the view.
                NSMutableDictionary* newAnimDict = [NSMutableDictionary dictionary];

                newAnimDict[NSViewAnimationTargetKey] = oldView;
                newAnimDict[NSViewAnimationEffectKey] = NSViewAnimationFadeOutEffect;

                SmoothViewAnimation *viewFadeOutAnim = [[SmoothViewAnimation alloc]
                    initWithViewAnimations: @[newAnimDict]];

                viewFadeOutAnim.duration = animation.duration;
                viewFadeOutAnim.animationCurve = animation.animationCurve;
                viewFadeOutAnim.animationBlockingMode = animation.animationBlockingMode;
                viewFadeOutAnim.frameRate = animation.frameRate;

                // Do the deed.
                [viewFadeOutAnim startAnimation];
                //[viewFadeOutAnim autorelease];
            }
        }
    }

    return YES;
}

//  animationDidEnd:
// ----------------------------------------------------------------------------

- (void)animationDidEnd: (NSAnimation*)animation
{
    if (![animation isKindOfClass: NSViewAnimation.class])
        return;

    NSArray*    animatedViews   = ((NSViewAnimation*)animation).viewAnimations;

    if (!animatedViews)
        return;

    NSWindow*   animatingWindow = animatedViews[0][NSViewAnimationTargetKey];

    if (animatingWindow != iMainWindow  &&
        animatingWindow != iPrefsWindow)
        return;

    for (id animObject in animatedViews)
    {
        if (!animObject)
            continue;

        NSNumber*   effectsNumber   = animObject[NSXViewAnimationCustomEffectsKey];

        if (!effectsNumber)
            continue;

        uint32_t  effects = effectsNumber.unsignedIntValue;

        if (effects & NSXViewAnimationSwapAtEndEffect)
        {   // Hide/show 2 views.
            NSView* oldView = animObject[NSXViewAnimationSwapOldKey];
            NSView* newView = animObject[NSXViewAnimationSwapNewKey];

            if (oldView)
                oldView.hidden = YES;

            if (newView)
                newView.hidden = NO;
        }
        else if (effects & NSXViewAnimationSwapAtBeginningAndEndEffect ||
                 effects & NSXViewAnimationFadeOutAndSwapEffect)
        {   // Show a view.
            NSView* newView = animObject[NSXViewAnimationSwapNewKey];

            if (newView)
                newView.hidden = NO;
        }

        // Adjust multiple views' resize masks.
        if (effects & NSXViewAnimationUpdateResizeMasksAtEndEffect)
        {
            NSArray*    masks   = animObject[NSXViewAnimationResizeMasksArrayKey];
            NSArray*    views   = animObject[NSXViewAnimationResizeViewsArrayKey];

            if (!masks || !views)
                continue;

            NSView*     view;
            NSNumber*   mask;
            NSUInteger      i;
            NSUInteger      numMasks    = masks.count;
            NSUInteger      numViews    = views.count;

            if (numMasks != numViews)
                continue;

            for (i = 0; i < numMasks; i++)
            {
                mask    = masks[i];
                view    = views[i];

                if (!mask || !view)
                    continue;

                view.autoresizingMask = mask.unsignedIntValue;
            }
        }

        // Update the window's min and/or max sizes.
        if (effects & NSXViewAnimationUpdateWindowMinMaxSizesAtEndEffect)
        {
            NSValue*    minSizeValue    = animObject[
                NSXViewAnimationWindowMinSizeKey];
            NSValue*    maxSizeValue    = animObject[
                NSXViewAnimationWindowMaxSizeKey];

            if (minSizeValue)
                animatingWindow.contentMinSize = minSizeValue.sizeValue;

            if (maxSizeValue)
                animatingWindow.contentMaxSize = maxSizeValue.sizeValue;
        }

        // Perform a selector. The method's return value is ignored, and the
        // method must take no arguments. For any other kind of method, use
        // NSInvocation instead.
        if (effects & NSXViewAnimationPerformSelectorAtEndEffect)
        {
            NSValue*    selValue    = animObject[NSXViewAnimationSelectorKey];

            if (selValue)
            {
                SEL theSel;

                [selValue getValue: &theSel];

                NSNumber*   newThread   = animObject[
                    NSXViewAnimationPerformInNewThreadKey];

                if (newThread)
                    [NSThread detachNewThreadSelector: theSel
                        toTarget: self withObject: nil];
                else
                    [self performSelector: theSel];
            }
        }

        // Open a file in another application.
        if (effects & NSXViewAnimationOpenFileWithAppAtEndEffect)
        {
            NSString*   filePath    = animObject[NSXViewAnimationFilePathKey];
            NSString*   appName     = animObject[NSXViewAnimationAppNameKey];

            if (filePath && appName)
                [[NSWorkspace sharedWorkspace] openFile: filePath
                    withApplication: appName];
        }
    }
}

#pragma mark -
#pragma mark NSApplication delegates
//  applicationWillFinishLaunching:
// ----------------------------------------------------------------------------

- (void)applicationWillFinishLaunching: (NSNotification*)inNotification
{
    // Set mArchSelector to the host architecture by default. This code was
    // lifted from http://developer.apple.com/technotes/tn/tn2086.html
    mach_msg_type_number_t  infoCount   = HOST_BASIC_INFO_COUNT;

    host_info(mach_host_self(), HOST_BASIC_INFO,
        (host_info_t)&iHostInfo, &infoCount);

    iSelectedArchCPUType    = iHostInfo.cpu_type;

    if (iSelectedArchCPUType != CPU_TYPE_POWERPC    &&
        iSelectedArchCPUType != CPU_TYPE_I386)
    {   // We're running on a machine that doesn't exist.
        fprintf(stderr, "otx: I shouldn't be here...\n");
    }

    // Setup our text shadow ivar.
    iTextShadow = [[NSShadow alloc] init];

    iTextShadow.shadowColor = [NSColor
        colorWithCalibratedRed: 1.0f green: 1.0f blue: 1.0f alpha: 0.5f];
    iTextShadow.shadowOffset = NSMakeSize(0.0f, -1.0f);
    iTextShadow.shadowBlurRadius = 0.0f;

    // Setup the windows.
    [self setupPrefsWindow];
    [self setupMainWindow];

    // Show the main window.
    [iMainWindow center];
    [self showMainWindow: self];
}

//  application:openFile:
// ----------------------------------------------------------------------------
//  Open by drag n drop from Finder.

- (BOOL)application: (NSApplication*)sender
           openFile: (NSString*)filename
{
    if ([[NSWorkspace sharedWorkspace] isFilePackageAtPath: filename])
        [self newPackageFile: [NSURL fileURLWithPath: filename]];
    else
        [self newOFile: [NSURL fileURLWithPath: filename] needsPath: YES];

    return YES;
}

//  applicationShouldTerminateAfterLastWindowClosed:
// ----------------------------------------------------------------------------

- (BOOL)applicationShouldTerminateAfterLastWindowClosed: (NSApplication*)inApp
{
    return YES;
}

#pragma mark -
#pragma mark NSControl delegates
//  controlTextDidChange:
// ----------------------------------------------------------------------------

- (void)controlTextDidChange: (NSNotification*)inNotification
{
    switch ([inNotification.object tag])
    {
        case kOutputTextTag:
            [self syncSaveButton];
            break;

        case kOutputFileBaseTag:
        case kOutputFileExtTag:
            [self syncOutputText: nil];
            break;

        default:
            break;
    }
}

#pragma mark -
#pragma mark NSToolbar delegates
//  toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:
// ----------------------------------------------------------------------------

- (NSToolbarItem*)toolbar: (NSToolbar*)toolbar
    itemForItemIdentifier: (NSString*)itemIdent
willBeInsertedIntoToolbar: (BOOL)willBeInserted
{
    NSToolbarItem*  item = [[NSToolbarItem alloc]
        initWithItemIdentifier: itemIdent];

    if ([itemIdent isEqual: PrefsGeneralToolbarItemID])
    {
        item.label = @"General";
        item.image = [NSImage imageNamed: @"Prefs General Icon"];
        item.target = self;
        item.action = @selector(switchPrefsViews:);
        item.tag = 0;
    }
    else if ([itemIdent isEqual: PrefsOutputToolbarItemID])
    {
        item.label = @"Output";
        item.image = [NSImage imageNamed: @"Prefs Output Icon"];
        item.target = self;
        item.action = @selector(switchPrefsViews:);
        item.tag = 1;
    }
    else
        item = nil;

    return item;
}

//  toolbarDefaultItemIdentifiers:
// ----------------------------------------------------------------------------

- (NSArray*)toolbarDefaultItemIdentifiers: (NSToolbar*)toolbar
{
    return PrefsToolbarItemsArray;
}

//  toolbarAllowedItemIdentifiers:
// ----------------------------------------------------------------------------

- (NSArray*)toolbarAllowedItemIdentifiers: (NSToolbar*)toolbar
{
    return PrefsToolbarItemsArray;
}

//  toolbarSelectableItemIdentifiers:
// ----------------------------------------------------------------------------

- (NSArray*)toolbarSelectableItemIdentifiers: (NSToolbar*)toolbar
{
    return PrefsToolbarItemsArray;
}

//  validateToolbarItem:
// ----------------------------------------------------------------------------

- (BOOL)validateToolbarItem: (NSToolbarItem*)toolbarItem
{
    return YES;
}

#pragma mark -
#pragma mark NSWindow delegates
//  windowDidResize:
// ----------------------------------------------------------------------------
//  Implemented to avoid artifacts from the NSBox.

- (void)windowDidResize: (NSNotification*)inNotification
{
    if (inNotification.object == iMainWindow)
        [iMainWindow display];
}

@end
