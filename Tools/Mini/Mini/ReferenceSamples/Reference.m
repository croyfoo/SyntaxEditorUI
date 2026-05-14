#import "Reference.h"

#define ReferenceLog(format, ...) NSLog((@"[Reference] " format), ##__VA_ARGS__)

@implementation ReferenceItem
- (NSString *)displayTitle {
    ReferenceLog(@"display %@", self.title);
    return self.isEnabled ? self.title ?: @"Untitled" : @"Disabled";
}
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
