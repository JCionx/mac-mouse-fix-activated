//
// --------------------------------------------------------------------------
// ScrollControl.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2020
// Licensed under MIT
// --------------------------------------------------------------------------
//

#import "ScrollControl.h"
#import "DeviceManager.h"
#import "SmoothScroll.h"
#import "RoughScroll.h"
#import "TouchSimulator.h"
#import "ScrollModifiers.h"
#import "MainConfigInterface.h"
#import "ScrollUtility.h"
#import "Utility_Helper.h"
#import "WannabePrefixHeader.h"
#import "ScrollAnalyzer.h"
#import "ScrollConfigInterface.h"
#import <Cocoa/Cocoa.h>
#import "Queue.h"
#import "Mac_Mouse_Fix_Helper-Swift.h"

@implementation ScrollControl

#pragma mark - Variables

static CFMachPortRef _eventTap;
static CGEventSourceRef _eventSource;

static dispatch_queue_t _scrollQueue;

static AXUIElementRef _systemWideAXUIElement; // TODO: should probably move this to MainConfigInterface or some sort of OverrideManager class
+ (AXUIElementRef) systemWideAXUIElement {
    return _systemWideAXUIElement;
}

#pragma mark - Public functions

+ (void)load_Manual {
    
    // Load SmoothScroll
    [SmoothScroll load_Manual];
    
    // Setup dispatch queue
    //  For multithreading while still retaining control over execution order.
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, -1);
    _scrollQueue = dispatch_queue_create(NULL, attr);
    
    // Create AXUIElement for getting app under mouse pointer
    _systemWideAXUIElement = AXUIElementCreateSystemWide();
    // Create Event source
    if (_eventSource == nil) {
        _eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    }
    // Create/enable scrollwheel input callback
    if (_eventTap == nil) {
        CGEventMask mask = CGEventMaskBit(kCGEventScrollWheel);
        _eventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, eventTapCallback, NULL);
        DDLogInfo(@"_eventTap: %@", _eventTap);
        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _eventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        CGEventTapEnable(_eventTap, false); // Not sure if this does anything
    }
}

/// When scrolling is in progress, there are tons of variables holding global state. This resets some of them.
/// I determined the ones it resets through trial and error. Some misbehaviour/bugs might be caused by this not resetting all of the global variables.
+ (void)resetDynamicGlobals {
    [ScrollAnalyzer resetState];
    [SmoothScroll resetDynamicGlobals];
}

/// Routes the event back to the eventTap where it originally entered the program.
///
/// Use this when internal parameters change while processing an event.
/// This will essentially restart the evaluation of the event while respecting the new internal parameters.
/// You probably wanna return after calliing this.
// TODO: This shouldn't be neede anymore. Delete if so.
+ (void)rerouteScrollEventToTop:(CGEventRef)event {
    eventTapCallback(nil, 0, event, nil);
}

/// Either activate SmoothScroll or RoughScroll or stop scroll interception entirely
/// Call this whenever a value which the decision depends on changes
+ (void)decide {
    BOOL disableAll =
    ![DeviceManager devicesAreAttached];
    //|| (!_isSmoothEnabled && _scrollDirection == 1);
//    || isEnabled == NO;
    
    if (disableAll) {
        DDLogInfo(@"Disabling scroll interception");
        // Disable scroll interception
        if (_eventTap) {
            CGEventTapEnable(_eventTap, false);
        }
        // Disable other scroll classes
        [SmoothScroll stop];
        [RoughScroll stop];
        [ScrollModifiers stop];
    } else {
        // Enable scroll interception
        CGEventTapEnable(_eventTap, true);
        // Enable other scroll classes
        [ScrollModifiers start];
        if (ScrollConfigInterface.smoothEnabled) {
            DDLogInfo(@"Enabling SmoothScroll");
            [SmoothScroll start];
            [RoughScroll stop];
        } else {
            DDLogInfo(@"Enabling RoughScroll");
            [SmoothScroll stop];
            [RoughScroll start];
        }
    }
}

#pragma mark - Private functions

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    
    // Handle eventTapDisabled messages
    
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        
        if (type == kCGEventTapDisabledByUserInput) {
            DDLogInfo(@"ScrollControl eventTap was disabled by timeout. Re-enabling");
            CGEventTapEnable(_eventTap, true);
        } else if (type == kCGEventTapDisabledByUserInput) {
            DDLogInfo(@"ScrollControl eventTap was disabled by user input.");
        }
        
        return event;
    }
    
    // Return non-scrollwheel events unaltered
    
    int64_t isPixelBased     = CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous);
    int64_t scrollPhase      = CGEventGetIntegerValueField(event, kCGScrollWheelEventScrollPhase);
    int64_t scrollDeltaAxis1 = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
    int64_t scrollDeltaAxis2 = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2);
    bool isDiagonal = scrollDeltaAxis1 != 0 && scrollDeltaAxis2 != 0;
    if (isPixelBased != 0
        || scrollPhase != 0 // Adding scrollphase here is untested
        || isDiagonal) { // Ignore diagonal scroll-events
        return event;
    }
    
    // Get scrollAxis
    
    MFAxis scrollAxis = [ScrollUtility axisForVerticalDelta:scrollDeltaAxis1 horizontalDelta:scrollDeltaAxis2];
    
    // Get scrollDelta
    
    int64_t scrollDelta = 0; // Only initing this to 0 to silence Xcode warnings
    int64_t scrollDeltaPoint = 0;
    
    if (scrollAxis == kMFAxisVertical) {
        scrollDelta = scrollDeltaAxis1;
        scrollDeltaPoint = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
    } else if (scrollAxis == kMFAxisHorizontal) {
        scrollDelta = scrollDeltaAxis2;
        scrollDeltaPoint = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2);
    } else {
        NSCAssert(NO, @"Invalid scroll axis");
    }
    
    // Run scrollAnalysis
    //  We want to do this here, not in _scrollQueue for more accurate timing
    
    ScrollAnalysisResult scrollAnalysisResult = [ScrollAnalyzer updateWithTickOccuringNowWithDelta:scrollDelta axis:scrollAxis];
    
    //  Executing heavy stuff on a different thread to prevent the eventTap from timing out. We wrote this before knowing that you can just re-enable the eventTap when it times out. But this doesn't hurt.
    
    CGEventRef eventCopy = CGEventCreateCopy(event); // Create a copy, because the original event will become invalid and unusable in the new queue.
    
    dispatch_async(_scrollQueue, ^{
        
        processEvent(eventCopy, scrollAnalysisResult);
    });
    return nil;
}

static void processEvent(CGEventRef event, ScrollAnalysisResult scrollAnalysisResult) {
    
    // Set application overrides
    //  Checking which app is under the mouse pointer is really slow, so we do some optimizations
    
    if (scrollAnalysisResult.consecutiveScrollTickCounter == 0) { // Only do this on the first of each series of consecutive scroll ticks
        [ScrollUtility updateMouseDidMoveWithEvent:event];
        if (!ScrollUtility.mouseDidMove) {
            [ScrollUtility updateFrontMostAppDidChange];
            // Only checking this if mouse didn't move, because of || in (mouseMoved || frontMostAppChanged). For optimization. Not sure if significant.
        }
        if (ScrollUtility.mouseDidMove || ScrollUtility.frontMostAppDidChange) {
            // set app overrides
            BOOL configChanged = [MainConfigInterface applyOverridesForAppUnderMousePointer_Force:NO]; // TODO: `updateInternalParameters_Force:` should (probably) reset stuff itself, if it changes anything. This whole [SmoothScroll stop] stuff is kinda messy
            if (configChanged) {
                [SmoothScroll stop]; // Not sure if useful
                [RoughScroll stop]; // Not sure if useful
            }
        }
    }

    // Process event
    
    // Get pixels to scroll for this event
    
    int64_t pxToScrollForThisTick;
    pxToScrollForThisTick = accelerate(scrollAnalysisResult.ticksPerSecond, ScrollConfigInterface.pxPerTickBase);
//    pxToScrollForThisTick = scrollDeltaPoint;
    
//    DDLogDebug(@"Scroll speed unsmoothed: %f", scrollAnalysisResult.ticksPerSecondUnsmoothed);
//    DDLogDebug(@"Scroll speed: %f", scrollAnalysisResult.ticksPerSecond);
//    DDLogDebug(@"Tick ctr: %lld", scrollAnalysisResult.consecutiveScrollTickCounter);
//    DDLogDebug(@"Swip ctr: %lld", scrollAnalysisResult.consecutiveScrollSwipeCounter);
    
    if (ScrollConfigInterface.smoothEnabled) {
        [SmoothScroll start];   // Not sure if useful
        [RoughScroll stop];     // Not sure if useful
        [SmoothScroll handleInput:event scrollAnalysisResult:scrollAnalysisResult];
    } else {
        [SmoothScroll stop];
        [RoughScroll start];
        [RoughScroll handleInput:event];
    }
    CFRelease(event);
}


/// Accelerate px to scroll for one tick (aka step size)
/// @param ticksPerSecond scrolling speed in ticks per second
/// @param pxPerTickBase minimum (aka base) step size
/// @return Sensitivity. How many px to scroll for one scroll wheel tick.
/// @discussion See the RawAccel guide for more info on acceleration curves https://github.com/a1xd/rawaccel/blob/master/doc/Guide.md
static int64_t accelerate(double ticksPerSecond, int64_t pxPerTickBase) {
    return 0; // TODO change this
}


@end