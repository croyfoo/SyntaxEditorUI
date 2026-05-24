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

typedef void (^REReferenceCompletion)(ReferenceItem *item, NSError * _Nullable error);

@protocol ReferenceRendering <NSObject>
- (nullable NSString *)renderItem:(ReferenceItem *)item error:(NSError **)error;
@end

NS_SWIFT_NAME(ReferenceCache)
@interface ReferenceCache : NSObject <ReferenceRendering>
@property (nonatomic, copy, readonly) NSDictionary<NSString *, ReferenceItem *> *itemsByIdentifier;
- (nullable ReferenceItem *)itemForIdentifier:(NSString *)identifier effectiveRange:(NSRange *)effectiveRange;
- (void)loadItemForIdentifier:(NSString *)identifier completion:(REReferenceCompletion)completion;
@end

@interface ReferenceItem (Formatting)
- (NSString *)formattedTitleForState:(REReferenceState)state;
@end
