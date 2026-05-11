#import <Foundation/Foundation.h>

#define ReferenceLog(format, ...) NSLog((@"[Reference] " format), ##__VA_ARGS__)

NS_SWIFT_NAME(ReferenceState)
typedef NS_ENUM(NSInteger, REReferenceState) {
    REReferenceStateIdle,
    REReferenceStateLoading,
    REReferenceStateReady,
};

@interface ReferenceItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
- (NSString *)displayTitle;
@end

@implementation ReferenceItem
- (NSString *)displayTitle {
    ReferenceLog(@"display %@", self.title);
    return self.isEnabled ? self.title ?: @"Untitled" : @"Disabled";
}
@end

@interface ReferenceItem (Formatting)
- (NSString *)formattedTitleForState:(REReferenceState)state;
@end

@implementation ReferenceItem (Formatting)
- (NSString *)formattedTitleForState:(REReferenceState)state {
    switch (state) {
        case REReferenceStateIdle:
            return [NSString stringWithFormat:@"Idle: %@", self.displayTitle];
        case REReferenceStateLoading:
            return @"Loading";
        case REReferenceStateReady:
            return self.displayTitle;
    }
}
@end
