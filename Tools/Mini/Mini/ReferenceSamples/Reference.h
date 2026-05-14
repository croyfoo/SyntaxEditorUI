#import <Foundation/Foundation.h>

NS_SWIFT_NAME(ReferenceState)
typedef NS_ENUM(NSInteger, REReferenceState) {
    REReferenceStateIdle,
    REReferenceStateLoading,
    REReferenceStateReady,
};

NS_SWIFT_NAME(ReferenceItem)
@interface ReferenceItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
- (NSString *)displayTitle;
@end

@interface ReferenceItem (Formatting)
- (NSString *)formattedTitleForState:(REReferenceState)state;
@end
