//
// --------------------------------------------------------------------------
// ScrollConfig.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2021
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/LICENSE)
// --------------------------------------------------------------------------
//

import Cocoa
import CocoaLumberjackSwift

@objc class ScrollConfig: NSObject, NSCopying /*, NSCoding*/ {
    
    /// This class has almost all instance properties
    /// You can request the config once, then store it.
    /// You'll receive an independent instance that you can override with custom values. This should be useful for implementing Modifications in Scroll.m
    ///     Everything in ScrollConfigResult is lazy so that you only pay for what you actually use
    
    // MARK: Convenience functions
    ///     For accessing top level dict and different sub-dicts
    
    private static var _scrollConfigRaw: NSDictionary? = nil /// This needs to be static, not an instance var. Otherwise there are weird crashes in Scroll.m. Not sure why.
    private func c(_ keyPath: String) -> NSObject? {
        return ScrollConfig._scrollConfigRaw?.object(forCoolKeyPath: keyPath) /// Not sure whether to use coolKeyPath here?
    }
    
    // MARK: Static functions
    
    @objc private(set) static var shared = ScrollConfig() /// Singleton instance
    
    
    @objc static func reload() {
        
        /// Guard not equal
        
        let newConfigRaw = config("Scroll") as! NSDictionary?
        guard !(_scrollConfigRaw?.isEqual(newConfigRaw) ?? false) else {
            return
        }
        
        /// Notes:
        /// - This should be called when the underlying config (which mirrors the config file) changes
        /// - All the property values are cached in `currentConfig`, because the properties are lazy. Replacing with a fresh object deletes this implicit cache.
        /// - TODO: Make a copy before storing in `_scrollConfigRaw` just to be sure the equality checks always work
        shared = ScrollConfig()
        _scrollConfigRaw = newConfigRaw
        cache = nil
//        ReactiveScrollConfig.shared.handleScrollConfigChanged(newValue: shared)
        SwitchMaster.shared.scrollConfigChanged(scrollConfig: shared)
    }
    private static var cache: [_HP<MFScrollModificationResult, MFAxis>: ScrollConfig]? = nil
    
    @objc static func scrollConfig(modifiers: MFScrollModificationResult, inputAxis: MFAxis, event: CGEvent?) -> ScrollConfig {
        
        // TODO: Make displaySize an input parameter
        
        if cache == nil {
            cache = .init()
        }
        
        let key = _HP(a: modifiers, b: inputAxis)
        
        if let fromCache = cache![key] {
            return fromCache
            
        } else {
            
            DDLogDebug("ScrollConfig - Recalculating overriden config")
            
            ///
            /// Copy og settings
            ///
            let new = shared.copy() as! ScrollConfig
            
            ///
            /// Override settings
            ///
            
            ///
            /// Override scrollConfig based on modifications
            ///
            
            /// inputModifications
            
            if modifiers.inputMod == kMFScrollInputModificationQuick {
                
                /// Set quick acceleration curve
                new.accelerationCurve = new.quickAccelerationCurve;
                
                /// Set animationCurve
                new.animationCurvePreset = kMFScrollAnimationCurvePresetQuickScroll;
                
                /// Make fast scroll easy to trigger
                new.consecutiveScrollSwipeMaxInterval *= 1.2;
                new.consecutiveScrollTickIntervalMax *= 1.2;
                
                /// Amp up fast scroll
                new.fastScrollThreshold_inSwipes = 2;
                new.fastScrollSpeedup = 20;
                
            } else if modifiers.inputMod == kMFScrollInputModificationPrecise {
                
                /// Set slow acceleration curve
                new.accelerationCurve = new.preciseAccelerationCurve;
                
                /// Set animationCurve
                
                new.animationCurvePreset = kMFScrollAnimationCurvePresetPreciseScroll;
                
                /// Turn off fast scroll
                new.fastScrollThreshold_inSwipes = 69; /// This is the haha sex number
                new.fastScrollExponentialBase = 1.0;
                new.fastScrollSpeedup = 0.0;
                
            } else if modifiers.inputMod == kMFScrollInputModificationNone {
                
                /// We do the actual handling of this case below after we handle the effectModifications.
                ///     That's because our standardAccelerationCurve depends on the animationCurve, and the animationCurve can change depending on the effectModifications
                ///     We also can't handle all the effectModifications before all inputModifications, because the animationCurves that the effectModifications prescribe should override the animationCurves that the inputModifications prescribe (if an effectModification and an inputModification are active at the same time)
                
            } else {
                assert(false);
            }
            
            /// effectModifications
            
            if modifiers.effectMod == kMFScrollEffectModificationHorizontalScroll {
                

            } else if modifiers.effectMod == kMFScrollEffectModificationZoom {
                
                new.smoothEnabled = true;
                /// Override animation curve
                new.animationCurvePreset = kMFScrollAnimationCurvePresetTouchDriver;
                
            } else if modifiers.effectMod == kMFScrollEffectModificationRotate {
                
                new.smoothEnabled = true;
                /// Override animation curve
                new.animationCurvePreset = kMFScrollAnimationCurvePresetTouchDriver;
                
            } else if modifiers.effectMod == kMFScrollEffectModificationCommandTab {
                
                new.smoothEnabled = false;
                
            } else if modifiers.effectMod == kMFScrollEffectModificationThreeFingerSwipeHorizontal {
                
                new.smoothEnabled = true;
                /// Override animation curve
                new.animationCurvePreset = kMFScrollAnimationCurvePresetTouchDriverLinear;
                
            } else if modifiers.effectMod == kMFScrollEffectModificationFourFingerPinch {
                
                new.smoothEnabled = true;
                /// Override animation curve
                new.animationCurvePreset = kMFScrollAnimationCurvePresetTouchDriverLinear;
                
            } else if modifiers.effectMod == kMFScrollEffectModificationNone {
            } else if modifiers.effectMod == kMFScrollEffectModificationAddModeFeedback {
                /// We don't wanna scroll at all in this case but I don't think it makes a difference.
            } else {
                assert(false);
            }
            
            /// Input modifications (pt2)
            
            if (modifiers.inputMod == kMFScrollInputModificationNone) {
            
                /// Get display under mouse pointer
                var displayUnderMousePointer: CGDirectDisplayID = 0
                SharedUtility.displayUnderMousePointer(&displayUnderMousePointer, with: event)

                /// Get display height/width
                var displayDimension: size_t
                if inputAxis == kMFAxisHorizontal
                    || modifiers.effectMod == kMFScrollEffectModificationHorizontalScroll {
                    
                    displayDimension = CGDisplayPixelsWide(displayUnderMousePointer);
                } else if inputAxis == kMFAxisVertical {
                    displayDimension = CGDisplayPixelsHigh(displayUnderMousePointer);
                } else {
                    fatalError()
                }
                
                /// Calculate accelerationCurve
                new.accelerationCurve = new.standardAccelerationCurve(withScreenSize: displayDimension)
            }
            
            ///
            /// Cache & return
            ///
            cache![key] = new
            return new
            
        }
    }
    
    // MARK: ???
    
    @objc static var linearCurve: Bezier = { () -> Bezier in
        
        let controlPoints: [P] = [_P(0,0), _P(0,0), _P(1,1), _P(1,1)]
        
        return Bezier(controlPoints: controlPoints, defaultEpsilon: 0.001) /// The default defaultEpsilon 0.08 makes the animations choppy
    }()
    
//    @objc static var stringToEventFlagMask: NSDictionary = ["command" : CGEventFlags.maskCommand,
//                                                            "control" : CGEventFlags.maskControl,
//                                                            "option" : CGEventFlags.maskAlternate,
//                                                            "shift" : CGEventFlags.maskShift]
    
    // MARK: General
    
    
    @objc lazy var smoothEnabled: Bool = {
        /// Does this really have to exist?
        return u_smoothness != kMFScrollSmoothnessOff
    }()
    @objc lazy var useAppleAcceleration: Bool = {
        return u_speed == kMFScrollSpeedSystem
    }()
    
//    @objc private var u_killSwitch: Bool { c("General.scrollKillSwitch") as? Bool ?? false } /// Not cached cause it's just used to calc the other vars
//    @objc var killSwitch: Bool { u_killSwitch /*|| HelperState.isLockedDown */ } /// Should probably move this into SwitchMaster. Edit: Moved lockDown stuff into switchMaster
    
    // MARK: Invert Direction
    
    @objc lazy var u_invertDirection: MFScrollInversion = {
        /// This can be used as a factor to invert things. kMFScrollInversionInverted is -1.
        
//        if HelperState.isLockedDown { return kMFScrollInversionNonInverted }
        return c("reverseDirection") as! Bool ? kMFScrollInversionInverted : kMFScrollInversionNonInverted
    }()
    
    // MARK: Old Invert Direction
    /// Rationale: We used to have the user setting be "Natural Direction" but we changed it to being "Reverse Direction". This is so it's more transparent to the user when Mac Mouse Fix is intercepting the scroll input and also to have the SwitchMaster more easily decide when to turn the scrolling tap on or off. Also I think the setting is slightly more intuitive this way.
    
//    @objc func scrollInvert(event: CGEvent) -> MFScrollInversion {
//        /// This can be used as a factor to invert things. kMFScrollInversionInverted is -1.
//
//        if HelperState.isLockedDown { return kMFScrollInversionNonInverted }
//
//        if self.u_direction == self.semanticScrollInvertSystem(event) {
//            return kMFScrollInversionNonInverted
//        } else {
//            return kMFScrollInversionInverted
//        }
//    }
    
//    lazy private var u_direction: MFSemanticScrollInversion = {
//        c("naturalDirection") as! Bool ? kMFSemanticScrollInversionNatural : kMFSemanticScrollInversionNormal
//    }()
//    private func semanticScrollInvertSystem(_ event: CGEvent) -> MFSemanticScrollInversion {
//
//        /// Accessing userDefaults is actually surprisingly slow, so we're using NSEvent.isDirectionInvertedFromDevice instead... but NSEvent(cgEvent:) is slow as well...
//        ///     .... So we're using our advanced knowledge of CGEventFields!!!
//
////            let isNatural = UserDefaults.standard.bool(forKey: "com.apple.swipescrolldirection") /// User defaults method
////            let isNatural = NSEvent(cgEvent: event)!.isDirectionInvertedFromDevice /// NSEvent method
//        let isNatural = event.getIntegerValueField(CGEventField(rawValue: 137)!) != 0; /// CGEvent method
//
//        return isNatural ? kMFSemanticScrollInversionNatural : kMFSemanticScrollInversionNormal
//    }
    
    // MARK: Inverted from device flag
    /// This flag will be set on GestureScroll events and will invert some interactions like scrolling to delete messages in Mail
    
    @objc let invertedFromDevice = false;
    
    // MARK: Analysis
    
    /// Note:
    ///     We tuned all these parameters for highInertia. However, they made fastScroll feel bad for lowInertia, so we added all these `switch _animationCurvePreset` statements as a bandaid. to make lowInertia feel good, too.
    ///     TODO: Think about: 1. Is this elegant? 2. What about the inertias between high and low? Is fast scroll even used with any of them?
    
    @objc lazy var scrollSwipeThreshold_inTicks: Int = 2 /*other["scrollSwipeThreshold_inTicks"] as! Int;*/ /// If `scrollSwipeThreshold_inTicks` consecutive ticks occur, they are deemed a scroll-swipe.
    
    @objc lazy var fastScrollThreshold_inSwipes: Int = { /// On the `fastScrollThreshold_inSwipes`th consecutive swipe, fast scrolling kicks in
        /*other["fastScrollThreshold_inSwipes"] as! Int*/
            
        switch animationCurvePreset {
        case kMFScrollAnimationCurvePresetHighInertia, kMFScrollAnimationCurvePresetQuickScroll:
            return 3
        default:
            return 4
            
        }
    }()
    
    @objc lazy var scrollSwipeMax_inTicks: Int = 11 /// Max number of ticks that we think can occur in a single swipe naturally (if the user isn't using a free-spinning scrollwheel). (See `consecutiveScrollSwipeCounter_ForFreeScrollWheel` definition for more info)
    
    @objc lazy var consecutiveScrollTickIntervalMax: TimeInterval = 160/1000
    /// ^ If more than `_consecutiveScrollTickIntervalMax` seconds passes between two scrollwheel ticks, then they aren't deemed consecutive.
    ///        other["consecutiveScrollTickIntervalMax"] as! Double;
    ///     msPerStep/1000 <- Good idea but we don't want this to depend on msPerStep
    
    @objc lazy var consecutiveScrollTickIntervalMin: TimeInterval = 15/1000
    /// ^ 15ms seemst to be smallest scrollTickInterval that you can naturally produce. But when performance drops, the scrollTickIntervals that we see can be much smaller sometimes.
    ///     This variable can be used to cap the observed scrollTickInterval to a reasonable value
    
    
    @objc lazy var consecutiveScrollSwipeMaxInterval: TimeInterval = {
        /// If more than `_consecutiveScrollSwipeIntervalMax` seconds passes between two scrollwheel swipes, then they aren't deemed consecutive.
        
        /// Not sure this switch makes sense. Quick bandaid. Might wanna change.
        
        switch animationCurvePreset {
        case kMFScrollAnimationCurvePresetLowInertia, kMFScrollAnimationCurvePresetNoInertia, kMFScrollAnimationCurvePresetTouchDriver, kMFScrollAnimationCurvePresetTouchDriverLinear, kMFScrollAnimationCurvePresetPreciseScroll:
            return 350/1000
        case kMFScrollAnimationCurvePresetMediumInertia:
            return 475/1000
        case kMFScrollAnimationCurvePresetHighInertia, kMFScrollAnimationCurvePresetHighInertiaPlusTrackpadSim, kMFScrollAnimationCurvePresetQuickScroll:
            return 600/1000
        default:
            fatalError()
        }
    }()
    
    @objc lazy var consecutiveScrollSwipeMinTickSpeed: Double = {
        switch animationCurvePreset {
        case kMFScrollAnimationCurvePresetHighInertia, kMFScrollAnimationCurvePresetQuickScroll:
            return 12.0
        default:
            return 16.0
        }
    }()
    
    @objc lazy private var consecutiveScrollTickInterval_AccelerationEnd: TimeInterval = consecutiveScrollTickIntervalMin
    /// ^ Used to define accelerationCurve. If the time interval between two ticks becomes less than `consecutiveScrollTickInterval_AccelerationEnd` seconds, then the accelerationCurve becomes managed by linear extension of the bezier instead of the bezier directly.
    
    /// Note: We are just using RollingAverge for smoothing, not ExponentialSmoothing, so this is currently unused.
    @objc lazy var ticksPerSecond_DoubleExponentialSmoothing_InputValueWeight: Double = 0.5
    @objc lazy var ticksPerSecond_DoubleExponentialSmoothing_TrendWeight: Double = 0.2
    @objc lazy var ticksPerSecond_ExponentialSmoothing_InputValueWeight: Double = 0.5
    /// ^       1.0 -> Turns off smoothing. I like this the best
    ///     0.6 -> On larger swipes this counteracts acceleration and it's unsatisfying. Not sure if placebo
    ///     0.8 ->  Nice, light smoothing. Makes  scrolling slightly less direct. Not sure if placebo.
    ///     0.5 -> (Edit) I prefer smoother feel now in everything. 0.5 Makes short scroll swipes less accelerated which I like
    
    // MARK: Fast scroll
    /// See the function on Desmos: https://www.desmos.com/calculator/e3qhvipmu0
    
    @objc lazy var fastScrollFactor = 1.0 /*other["fastScrollFactor"] as! Double*/
    /// ^ With the introduction of fastScrollSpeedup, this should always be 1.0. (So that the speedup is even and doesn't have a dip/hump at the start?)
    
    @objc lazy var fastScrollExponentialBase = 1.1 /* other["fastScrollExponentialBase"] as! Double; */
    /// ^ This seems to do the same thing as `fastScrollSpeedup`. Setting it close to 1 makes fastScrollSpeeup less sensitive. which allows us to be more precise
    ///     Needs to be > 1 for there to be any speedup
    
    @objc lazy var fastScrollSpeedup: Double = { /// Needs to be > 0 for there to be any speedup
        switch animationCurvePreset {
        case kMFScrollAnimationCurvePresetHighInertia, kMFScrollAnimationCurvePresetQuickScroll:
            return 7.0
        default:
            return 5.0
        }
    }()
    
    // MARK: Animation curve
    
    /// User setting
    
    private lazy var u_smoothness: MFScrollSmoothness = {
        switch c("smooth") as! String {
        case "off": return kMFScrollSmoothnessOff
        case "regular": return kMFScrollSmoothnessRegular
        case "high": return kMFScrollSmoothnessHigh
        default: fatalError()
        }
    }()
    private lazy var u_trackpadSimulation: Bool = {
        return c("trackpadSimulation") as! Bool
    }()
    
    private lazy var _animationCurvePreset = {
        
        /// Maybe we should move the trackpad sim settings out of the MFScrollAnimationCurvePreset, (because that's weird?)
        
        switch u_smoothness {
        case kMFScrollSmoothnessOff: return kMFScrollAnimationCurvePresetNoInertia
        case kMFScrollSmoothnessRegular: return kMFScrollAnimationCurvePresetLowInertia
        case kMFScrollSmoothnessHigh:
            return u_trackpadSimulation ? kMFScrollAnimationCurvePresetHighInertiaPlusTrackpadSim : kMFScrollAnimationCurvePresetHighInertia
        default: fatalError()
        }
    }()
    
    @objc var animationCurvePreset: MFScrollAnimationCurvePreset {
        
        set {
            _animationCurvePreset = newValue
            self.animationCurveParams = self.animationCurveParams(forPreset: animationCurvePreset)
        } get {
            return _animationCurvePreset
        }
    }
    
    @objc private(set) lazy var animationCurveParams = { self.animationCurveParams(forPreset: self.animationCurvePreset) }() /// Updates automatically to match `self.animationCurvePreset`
    
    /// Define storage class for animationCurve params
    
    @objc class MFScrollAnimationCurveParameters: NSObject { /// Does this have to inherit from NSObject?
        
        /// Notes:
        /// - I don't really think it make sense for sendGestureScrolls and sendMomentumScrolls to be part of the animation curve, but it works so whatever
        
        /// baseCurve params
        @objc let baseCurve: Bezier?
        @objc let baseMsPerStep: Int /// When using dragCurve that will make the actual msPerStep longer
        /// dragCurve params
        @objc let useDragCurve: Bool /// If false, use only baseCurve, and ignore dragCurve
        @objc let dragExponent: Double
        @objc let dragCoefficient: Double
        @objc let stopSpeed: Int
        /// Other params
        @objc let sendGestureScrolls: Bool /// If false, send simple continuous scroll events (like MMF 2) instead of using GestureScrollSimulator
        @objc let sendMomentumScrolls: Bool /// Only works if sendGestureScrolls and useDragCurve is true. If true, make Scroll.m send momentumScroll events (what the Apple Trackpad sends after lifting your fingers off) when scrolling is controlled by the dragCurve (and in some other cases, see TouchAnimator). Only use this when the dragCurve closely mimicks the Apple Trackpads otherwise apps like Xcode will behave differently from other apps during momentum scrolling.
        
        /// Init
        init(baseCurve: Bezier?, baseMsPerStep: Int, dragExponent: Double, dragCoefficient: Double, stopSpeed: Int, sendGestureScrolls: Bool, sendMomentumScrolls: Bool) {
            
            /// Init for using hybridCurve (baseCurve + dragCurve)
            
            if sendMomentumScrolls { assert(sendGestureScrolls) }
            
            self.baseMsPerStep = baseMsPerStep
            self.baseCurve = baseCurve
            
            self.useDragCurve = true
            self.dragExponent = dragExponent
            self.dragCoefficient = dragCoefficient
            self.stopSpeed = stopSpeed
            
            self.sendGestureScrolls = sendGestureScrolls
            self.sendMomentumScrolls = sendMomentumScrolls
        }
        init(baseCurve: Bezier?, msPerStep: Int, sendGestureScrolls: Bool) {
            
            /// Init for using just baseCurve
            
            self.baseMsPerStep = msPerStep
            self.baseCurve = baseCurve
            
            self.useDragCurve = false
            self.dragExponent = -1
            self.dragCoefficient = -1
            self.stopSpeed = -1
            
            self.sendGestureScrolls = sendGestureScrolls
            self.sendMomentumScrolls = false
        }
    }
    
    /// Define function that maps preset -> params
    
    @objc func animationCurveParams(forPreset preset: MFScrollAnimationCurvePreset) -> MFScrollAnimationCurveParameters {
        
        /// For the origin behind these presets see ScrollConfigTesting.md
        /// @note I just checked the formulas on Desmos, and I don't get how this can work with 0.7 as the exponent? (But it does??) If the value is `< 1.0` that gives a completely different curve that speeds up over time, instead of slowing down.
        
        switch preset {
            
        /// --- User selected ---
            
        case kMFScrollAnimationCurvePresetNoInertia:
            
            fatalError()
            
            let baseCurve =
            Bezier(controlPoints: [_P(0, 0), _P(0, 0), _P(0.66, 1), _P(1, 1)], defaultEpsilon: 0.001)
//            Bezier(controlPoints: [_P(0, 0), _P(0.31, 0.44), _P(0.66, 1), _P(1, 1)], defaultEpsilon: 0.001)
//            ScrollConfig.linearCurve
//            Bezier(controlPoints: [_P(0, 0), _P(0.23, 0.89), _P(0.52, 1), _P(1, 1)], defaultEpsilon: 0.001)
            return MFScrollAnimationCurveParameters(baseCurve: baseCurve, msPerStep: 250, sendGestureScrolls: false)
            
        case kMFScrollAnimationCurvePresetLowInertia:            
            
            return MFScrollAnimationCurveParameters(baseCurve: ScrollConfig.linearCurve, baseMsPerStep: 140, dragExponent: 1.05, dragCoefficient: 15, stopSpeed: 30, sendGestureScrolls: false, sendMomentumScrolls: false)
            
        case kMFScrollAnimationCurvePresetMediumInertia:
            
            fatalError()
            
            return MFScrollAnimationCurveParameters(baseCurve: ScrollConfig.linearCurve, baseMsPerStep: 190, dragExponent: 1.0, dragCoefficient: 17, stopSpeed: 50, sendGestureScrolls: false, sendMomentumScrolls: false)
            
        case kMFScrollAnimationCurvePresetHighInertia:
            /// Snappiest curve that can be used to send momentumScrolls.
            ///    If you make it snappier then it will cut off the built-in momentumScroll in apps like Xcode
            return MFScrollAnimationCurveParameters(baseCurve: ScrollConfig.linearCurve, baseMsPerStep: 205, dragExponent: 0.7, dragCoefficient: 40, stopSpeed: /*50*/30, sendGestureScrolls: false, sendMomentumScrolls: false)
            
        case kMFScrollAnimationCurvePresetHighInertiaPlusTrackpadSim:
            /// Same as highInertia preset but with full trackpad simulation.
            return MFScrollAnimationCurveParameters(baseCurve: ScrollConfig.linearCurve, baseMsPerStep: 205, dragExponent: 0.7, dragCoefficient: 40, stopSpeed: /*50*/30, sendGestureScrolls: true, sendMomentumScrolls: true)
            
        /// --- Dynamically applied ---
            
        case kMFScrollAnimationCurvePresetTouchDriver:
            
            let baseCurve = Bezier(controlPoints: [_P(0, 0), _P(0, 0), _P(0.5, 1), _P(1, 1)], defaultEpsilon: 0.001)
            return MFScrollAnimationCurveParameters(baseCurve: baseCurve, msPerStep: 250, sendGestureScrolls: false)
            
        case kMFScrollAnimationCurvePresetTouchDriverLinear:
            /// "Disable" the dragCurve by setting the dragCoefficient to an absurdly high number. This creates a linear curve. This is not elegant or efficient -> Maybe refactor this (have a bool `usePureBezier` or sth to disable the dragCurve)
            return MFScrollAnimationCurveParameters(baseCurve: ScrollConfig.linearCurve, msPerStep: 180, sendGestureScrolls: false)
        
        case kMFScrollAnimationCurvePresetQuickScroll:
            /// Almost the same as `highInertia` just more inertial. Actually same feel as `trackpad` preset.
            /// Should we use trackpad sim (sendMomentumScrolls and sendGestureScrolls) here?
            return MFScrollAnimationCurveParameters(baseCurve: ScrollConfig.linearCurve, baseMsPerStep: 220, dragExponent: 0.7, dragCoefficient: 30, stopSpeed: 1, sendGestureScrolls: true, sendMomentumScrolls: true)
            
        case kMFScrollAnimationCurvePresetPreciseScroll:
            /// Similar to `lowInertia`
            return MFScrollAnimationCurveParameters(baseCurve: ScrollConfig.linearCurve, baseMsPerStep: 140, dragExponent: 1.0, dragCoefficient: 20, stopSpeed: 50, sendGestureScrolls: false, sendMomentumScrolls: false)
            
        /// --- Testing ---
            
        case kMFScrollAnimationCurvePresetTest:
            
            return MFScrollAnimationCurveParameters(baseCurve: ScrollConfig.linearCurve, msPerStep: 350, sendGestureScrolls: false)
            
        /// --- Other ---
            
        case kMFScrollAnimationCurvePresetTrackpad:
            /// The dragCurve parameters emulate the trackpad as closely as possible. Use this in GestureSimulator.m. The baseCurve parameters as well as `sendMomentumScrolls` are irrelevant, since this is not used in Scroll.m. This doesn't really belong here. We should just put these parameters into GestureScrollSimulator where they are used.
            return MFScrollAnimationCurveParameters(baseCurve: nil, baseMsPerStep: -1, dragExponent: 0.7, dragCoefficient: 30, stopSpeed: 1, sendGestureScrolls: true, sendMomentumScrolls: true)
        
        default:
            fatalError()
        }
    }
    
    // MARK: Acceleration
    
    /// User settings
    
    @objc lazy var u_speed: MFScrollSpeed = {
        switch c("speed") as! String {
        case "system": return kMFScrollSpeedSystem /// Ignore MMF acceleration algorithm and use values provided by macOS
        case "low": return kMFScrollSpeedLow
        case "medium": return kMFScrollSpeedMedium
        case "high": return kMFScrollSpeedHigh
        default: fatalError()
        }
    }()
    @objc lazy var u_precise: Bool = { c("precise") as! Bool }()
    
    /// Stored property
    ///     This is used by Scroll.m to determine how to accelerate
    
    @objc lazy var accelerationCurve: Curve = standardAccelerationCurve(withScreenSize: 1080) /// Initial value is unused I think
    
    /// Define function that maps userSettings -> accelerationCurve
    
    private func standardAccelerationCurve(forSpeed speed: MFScrollSpeed, precise: Bool, smoothness: MFScrollSmoothness, screenSize: Int) -> Curve {
        /// `screenSize` should be the width/height of the screen you're scrolling on. Depending on if you're scrolling horizontally or vertically.
        
        ///
        /// Get pxPerTickStart
        ///
        
        let pxPerTickStart: Int
        
        if precise {
            
            pxPerTickStart = 10
            
        } else {
            
            /// Get base pxPerTick
            
            let pxPerTickStartBase = SharedUtilitySwift.eval {
                switch speed {
                case kMFScrollSpeedLow: 30.0
                case kMFScrollSpeedMedium: 60.0
                case kMFScrollSpeedHigh: 90.0
                default: -1.0
                }
            }
            
            /// Get inertia factor
            
            let inertiaFactor: Double
            
            if !smoothEnabled {
                inertiaFactor = 1/2
            } else {
                
                /// Notes:
                /// - TODO: Why do we define acceleration curves for the touchDriver so weirdly? Shouldn't we just hardcode it to one curve and acceleration?
                /// - The reason why the other MFScrollAnimationCurvePreset constants will never be passed in here is because quickScroll and preciseScroll define their own accelerationCurves. See Scroll.m for more.
                
                inertiaFactor = SharedUtilitySwift.eval {
                    switch animationCurvePreset {
                    case kMFScrollAnimationCurvePresetLowInertia: 2.0/3.0
                    case kMFScrollAnimationCurvePresetNoInertia: 2.0/3.0
                    case kMFScrollAnimationCurvePresetMediumInertia: 3.0/4.0
                    case kMFScrollAnimationCurvePresetHighInertia: 1.0
                    case kMFScrollAnimationCurvePresetHighInertiaPlusTrackpadSim: 1.0
                    case kMFScrollAnimationCurvePresetTouchDriver: 2.0/3.0
                    case kMFScrollAnimationCurvePresetTouchDriverLinear: 2.0/3.0
                    default: -1.0
                    }
                }
                
                
            }
            
            /// Put it together
            pxPerTickStart = Int(pxPerTickStartBase * inertiaFactor)
        }
        
        ///
        /// Get pxPerTickEnd
        ///
        
        /// Get base pxPerTick
        
        let pxPerTickEndBase: Double
        
        switch speed {
        case kMFScrollSpeedLow:
            pxPerTickEndBase = 90
        case kMFScrollSpeedMedium:
            pxPerTickEndBase = 140
        case kMFScrollSpeedHigh:
            pxPerTickEndBase = 180
        default:
            fatalError()
        }
        
        /// Get inertia factor
        
        let inertiaFactor: Double
        
        if !smoothEnabled {
            
            inertiaFactor = 1/2
            
        } else {
            
            switch animationCurvePreset {
            case kMFScrollAnimationCurvePresetLowInertia, kMFScrollAnimationCurvePresetNoInertia:
                inertiaFactor = /*1*/ 2/3
            case kMFScrollAnimationCurvePresetMediumInertia:
                inertiaFactor = /*1*/ 3/4
            case kMFScrollAnimationCurvePresetHighInertia, kMFScrollAnimationCurvePresetHighInertiaPlusTrackpadSim:
                inertiaFactor = 1
            case kMFScrollAnimationCurvePresetTouchDriver:
                inertiaFactor = 2/3
            case kMFScrollAnimationCurvePresetTouchDriverLinear:
                inertiaFactor = 2/3
            default:
                fatalError()
            }
        }
        
        /// Get screenHeight summand
        let screenHeightSummand: Double
        
        let screenHeightFactor = Double(screenSize) / 1080.0
        
        if screenHeightFactor >= 1 {
            screenHeightSummand = 20*(screenHeightFactor - 1)
        } else {
            screenHeightSummand = -20*((1/screenHeightFactor) - 1)
        }
        
        /// Put it all together to get pxPerTickEnd
        let pxPerTickEnd = Int(pxPerTickEndBase * inertiaFactor + screenHeightSummand)
        
        /// Debug
        DDLogDebug("Dynamic pxPerTickStart: \(pxPerTickStart) end: \(pxPerTickEnd)")
        
        ///
        /// Get curvature
        ///
        
        let curvature: Double = SharedUtilitySwift.eval {
            switch animationCurvePreset {
            case kMFScrollAnimationCurvePresetLowInertia: 2.5
            case kMFScrollAnimationCurvePresetNoInertia: 2.5
            case kMFScrollAnimationCurvePresetMediumInertia: 2.5
            case kMFScrollAnimationCurvePresetHighInertia: 2.5
            case kMFScrollAnimationCurvePresetHighInertiaPlusTrackpadSim: 2.5
            case kMFScrollAnimationCurvePresetTouchDriver: 2.5
            case kMFScrollAnimationCurvePresetTouchDriverLinear: 2.5
            default: -1.0
            }
        }
        
        ///
        /// Generate curve from params
        ///
        
        let curve = ScrollConfig.accelerationCurveFromParams(pxPerTickBase: pxPerTickStart,
                                                        pxPerTickEnd: pxPerTickEnd,
                                                        consecutiveScrollTickIntervalMax: self.consecutiveScrollTickIntervalMax,
                                                        consecutiveScrollTickInterval_AccelerationEnd: self.consecutiveScrollTickInterval_AccelerationEnd,
                                                        curvature: curvature)
        
        /// DEBUG
        
        if runningPreRelease() {
            
            let xMin: Double = 1 / Double(consecutiveScrollTickIntervalMax)
//            let yMin: Double = Double(pxPerTickBase);
            let xMax: Double = 1 / consecutiveScrollTickInterval_AccelerationEnd
//            let yMax: Double = Double(pxPerTickEnd)
            
            DDLogDebug("Setting scroll acceleration curve with trace\(curve.stringTrace(startX: xMin, endX: xMax, nOfSamples: 50))")
        }
        
        /// Return
        
        return curve
        
    }
    
    /// Acceleration curve defnitions
    ///     These aren't used directly but instead they are dynamically loaded into `self.accelerationCurve` by Scroll.m on each first consecutive scroll tick.
    
    @objc func standardAccelerationCurve(withScreenSize screenSize: Int) -> Curve {
        
        return self.standardAccelerationCurve(forSpeed: self.u_speed,
                                              precise: self.u_precise,
                                              smoothness: self.u_smoothness,
                                              screenSize: screenSize)
    }
    
    @objc lazy var preciseAccelerationCurve: Curve = { () -> Curve in
        ScrollConfig.accelerationCurveFromParams(pxPerTickBase: 3, /// 2 is better than 3 but that leads to weird asswert failures in TouchAnimator that I can't be bothered to fix
                                                 pxPerTickEnd: 30,
                                                 consecutiveScrollTickIntervalMax: self.consecutiveScrollTickIntervalMax, /// We don't expect this to ever change so it's okay to just capture here
                                                 consecutiveScrollTickInterval_AccelerationEnd: self.consecutiveScrollTickInterval_AccelerationEnd,
                                                 curvature: 1.0)
    }()
    @objc lazy var quickAccelerationCurve: Curve = { () -> Curve in
        ScrollConfig.accelerationCurveFromParams(pxPerTickBase: 100,
                                                 pxPerTickEnd: 500,
                                                 consecutiveScrollTickIntervalMax: self.consecutiveScrollTickIntervalMax,
                                                 consecutiveScrollTickInterval_AccelerationEnd: self.consecutiveScrollTickInterval_AccelerationEnd,
                                                 curvature: 1.0)
    }()
    
    // MARK: Keyboard modifiers
    
    /// Event flag masks
    @objc lazy var horizontalModifiers = CGEventFlags(rawValue: c("modifiers.horizontal") as! UInt64)
    @objc lazy var zoomModifiers = CGEventFlags(rawValue: c("modifiers.zoom") as! UInt64)
    
    
    // MARK: - Helper functions
    
    fileprivate static func accelerationCurveFromParams(pxPerTickBase: Int, pxPerTickEnd: Int, consecutiveScrollTickIntervalMax: TimeInterval, consecutiveScrollTickInterval_AccelerationEnd: TimeInterval, curvature: Double) -> Curve {
        /**
         Define a curve describing the relationship between the scrollTickSpeed (in scrollTicks per second) (on the x-axis) and the pxPerTick (on the y axis).
         We'll call this function y(x).
         y(x) is composed of 3 other curves. The core of y(x) is a BezierCurve *b(x)*, which is defined on the interval (xMin, xMax).
         y(xMin) is called yMin and y(xMax) is called yMax
         There are two other components to y(x):
         - For `x < xMin`, we set y(x) to yMin
         - We do this so that the acceleration is turned off for tickSpeeds below xMin. Acceleration should only affect scrollTicks that feel 'consecutive' and not ones that feel like singular events unrelated to other scrollTicks. `self.consecutiveScrollTickIntervalMax` is (supposed to be) the maximum time between ticks where they feel consecutive. So we're using it to define xMin.
         - For `xMax < x`, we lineraly extrapolate b(x), such that the extrapolated line has the slope b'(xMax) and passes through (xMax, yMax)
         - We do this so the curve is defined and has reasonable values even when the user scrolls really fast
         (We use tick and step are interchangable here)
         
         HyperParameters:
         - `curvature` raises sensitivity for medium scrollSpeeds making scrolling feel more comfortable and accurate. This is especially nice for very low pxPerTickBase.
         */
        
        /// Define Curve
        
        let xMin: Double = 1 / Double(consecutiveScrollTickIntervalMax)
        let yMin: Double = Double(pxPerTickBase);
        
        let xMax: Double = 1 / consecutiveScrollTickInterval_AccelerationEnd
        let yMax: Double = Double(pxPerTickEnd)
        
        /// v Old accelerationHump / capHump curvature system
        
//        let x2: Double
//        let y2: Double
//        if (accelerationHump < 0) {
//            x2 = Math.scale(value: -accelerationHump, from: .unitInterval, to: Interval(xMin, xMax))
//            y2 = yMin
//        } else {
//            x2 = xMin
//            y2 = Math.scale(value: accelerationHump, from: .unitInterval, to: Interval(yMin, yMax))
//        }
//
//        /// Flatten out the end of the curve to prevent ridiculous pxPerTick outputs when input (tickSpeed) is very high. tickSpeed can be extremely high despite smoothing, because our time measurements of when ticks occur are very imprecise
//        ///     Edit: Turn off flattening by making x3 = xMax. Do this because currenlty `consecutiveScrollTickIntervalMin == consecutiveScrollTickInterval_AccelerationEnd`, and therefore the extrapolated curve after xMax will never be used anyways -> I think this feels much nicer!
//        let x3: Double /* = (xMax-xMin)*0.9 + xMin*/
//        let y3: Double
//        if capHump < 0 {
//            x3 = xMax
//            y3 = Math.scale(value: capHump, from: .unitInterval, to: Interval(yMax, yMin))
//        } else {
//            x3 = Math.scale(value: capHump, from: .unitInterval, to: Interval(xMax, xMin))
//            y3 = yMax
//        }
        
//        var curve = AccelerationBezier(controlPoints:
//                                        [_P(xMin, yMin),
//                                         _P(x2, y2),
//                                         _P(x3, y3),
//                                         _P(xMax, yMax)], defaultEpsilon: 0.08)
        
        
        /// Create curve
        ///     Not sure if 0.08 defaultEpsilon makes sense here. Is it accurate enough?
        let curve = BezierCappedAccelerationCurve(xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax, curvature: curvature, reduceToCubic: false, defaultEpsilon: 0.08)
        
        /// Return
        return curve
    }
    
    @objc func copy(with zone: NSZone? = nil) -> Any {
        
        return SharedUtilitySwift.shallowCopy(ofObject: self)
    }
    
    
    
}

