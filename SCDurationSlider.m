//
//  SCTimeSlider.m
//  SelfControl
//
//  Created by Charlie Stigler on 4/17/21.
//

#import "SCDurationSlider.h"
#import "SCTimeIntervalFormatter.h"

// The slider doesn't map linearly to minutes: with a 30-day max, a linear slider would jump
// ~2 hours per pixel and make short blocks impossible to pick. Instead the slider's value is
// an index into a list of "stops" that get coarser as durations grow (1 min steps at the low
// end, 1 day steps at the high end).
static NSArray<NSNumber*>* SCDurationStopsUpTo(NSInteger maxMinutes) {
    // { step size, last value covered by that step size } in minutes
    static const NSInteger segments[][2] = {
        { 1,        15 },        // 1-15 min, every minute
        { 5,        60 },        // 20 min - 1 hr, every 5 min
        { 15,       4 * 60 },    // 1-4 hr, every 15 min
        { 30,       12 * 60 },   // 4-12 hr, every 30 min
        { 60,       24 * 60 },   // 12-24 hr, every hour
        { 6 * 60,   3 * 1440 },  // 1-3 days, every 6 hr
        { 12 * 60,  7 * 1440 },  // 3-7 days, every 12 hr
        { 1440,     NSIntegerMax } // beyond a week, every day
    };

    NSMutableArray<NSNumber*>* stops = [NSMutableArray array];
    NSInteger minutes = 0;
    for (size_t i = 0; i < sizeof(segments) / sizeof(segments[0]); i++) {
        while (minutes + segments[i][0] <= MIN(segments[i][1], maxMinutes)) {
            minutes += segments[i][0];
            [stops addObject: @(minutes)];
        }
    }
    // always let the user pick exactly the max, even if it doesn't land on a stop
    if (maxMinutes >= 1 && stops.lastObject.integerValue != maxMinutes) {
        [stops addObject: @(maxMinutes)];
    }
    if (stops.count == 0) [stops addObject: @1];
    return stops;
}

@interface SCDurationSlider ()
@property (nonatomic, copy) NSArray<NSNumber*>* durationStops;
- (NSInteger)stopIndexForMinutes:(NSInteger)minutes;
@end

// Converts between minutes (what the bound model stores) and stop index (the slider's value).
@interface SCDurationSliderValueTransformer : NSValueTransformer
@property (nonatomic, weak) SCDurationSlider* slider;
@end

@implementation SCDurationSliderValueTransformer
+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
// model (minutes) -> slider (stop index)
- (id)transformedValue:(id)value {
    if (![value respondsToSelector: @selector(integerValue)]) return @0;
    return @([self.slider stopIndexForMinutes: [value integerValue]]);
}
// slider (stop index) -> model (minutes)
- (id)reverseTransformedValue:(id)value {
    if (![value respondsToSelector: @selector(doubleValue)]) return @1;
    NSArray<NSNumber*>* stops = self.slider.durationStops;
    long idx = MAX(0, MIN((long)stops.count - 1, lround([value doubleValue])));
    return stops[idx];
}
@end

@implementation SCDurationSlider

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder: coder]) {
        [self initializeDurationProperties];
    }
    return self;
}
- (instancetype)init {
    if (self = [super init]) {
        [self initializeDurationProperties];
    }
    return self;
}

- (void)initializeDurationProperties {
    // default: 30 days max
    [self setMaxDuration: 43200];
}

- (void)setMaxDuration:(NSInteger)maxDuration {
    // keep whatever duration is currently selected (clamped to the new max) across the change
    NSInteger currentMinutes = (self.durationStops != nil) ? self.durationValueMinutes : 1;

    _maxDuration = MAX(1, maxDuration); // never start a block shorter than 1 minute
    self.durationStops = SCDurationStopsUpTo(_maxDuration);
    [self setMinValue: 0];
    [self setMaxValue: (double)(self.durationStops.count - 1)];
    [self setDurationValueMinutes: MIN(currentMinutes, _maxDuration)];
}

// index of the stop closest to the given number of minutes
- (NSInteger)stopIndexForMinutes:(NSInteger)minutes {
    NSArray<NSNumber*>* stops = self.durationStops;
    NSInteger bestIdx = 0;
    for (NSInteger i = 0; i < (NSInteger)stops.count; i++) {
        if (labs(stops[i].integerValue - minutes) < labs(stops[bestIdx].integerValue - minutes)) {
            bestIdx = i;
        }
    }
    return bestIdx;
}

- (NSInteger)durationValueMinutes {
    long idx = MAX(0, MIN((long)self.durationStops.count - 1, lround(self.doubleValue)));
    return self.durationStops[idx].integerValue;
}

- (void)setDurationValueMinutes:(NSInteger)minutes {
    self.doubleValue = (double)[self stopIndexForMinutes: minutes];
}

- (void)bindDurationToObject:(id)obj keyPath:(NSString*)keyPath {
    SCDurationSliderValueTransformer* transformer = [SCDurationSliderValueTransformer new];
    transformer.slider = self;
    [self bind: @"value"
      toObject: obj
   withKeyPath: keyPath
       options: @{
                  NSContinuouslyUpdatesValueBindingOption: @YES,
                  NSValueTransformerBindingOption: transformer
                  }];
}

- (NSString*)durationDescription {
    return [SCDurationSlider timeSliderDisplayStringFromNumberOfMinutes: self.durationValueMinutes];
}

// String conversion utility methods

+ (NSString *)timeSliderDisplayStringFromTimeInterval:(NSTimeInterval)numberOfSeconds {
    static SCTimeIntervalFormatter* formatter = nil;
    if (formatter == nil) {
        formatter = [[SCTimeIntervalFormatter alloc] init];
    }

    NSString* formatted = [formatter stringForObjectValue:@(numberOfSeconds)];
    return formatted;
}

+ (NSString *)timeSliderDisplayStringFromNumberOfMinutes:(NSInteger)numberOfMinutes {
    if (numberOfMinutes < 0) return @"Invalid duration";

    static NSCalendar* gregorian = nil;
    if (gregorian == nil) {
        gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    }

    NSRange secondsRangePerMinute = [gregorian
                                     rangeOfUnit:NSCalendarUnitSecond
                                     inUnit:NSCalendarUnitMinute
                                     forDate:[NSDate date]];
    NSInteger numberOfSecondsPerMinute = (NSInteger)NSMaxRange(secondsRangePerMinute);

    NSTimeInterval numberOfSecondsSelected = (NSTimeInterval)(numberOfSecondsPerMinute * numberOfMinutes);

    NSString* displayString = [SCDurationSlider timeSliderDisplayStringFromTimeInterval:numberOfSecondsSelected];
    return displayString;
}


@end
