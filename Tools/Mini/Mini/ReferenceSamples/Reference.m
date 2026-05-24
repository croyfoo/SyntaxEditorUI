#import "Reference.h"
#import <objc/message.h>

#define ReferenceLog(format, ...) NSLog((@"[Reference] " format), ##__VA_ARGS__)

static NSDictionary<NSString *, NSString *> *ReferenceLanguageAliases(void)
{
    return @{
        @"objc": @"xcode.lang.objc",
        @"objective-c": @"xcode.lang.objc",
        @"swift": @"xcode.lang.swift",
    };
}

static id ReferenceCallObject(id object, NSString *selectorName)
{
    return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selectorName));
}

static BOOL ReferenceCallBoolError(id object, NSString *selectorName, NSError **error)
{
    return ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(object, NSSelectorFromString(selectorName), error);
}

static NSRange ReferenceCallRange(id object, NSString *selectorName)
{
    return ((NSRange (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selectorName));
}

@implementation ReferenceItem
- (NSString *)displayTitle {
    ReferenceLog(@"display %@", self.title);
    return self.isEnabled ? self.title ?: @"Untitled" : @"Disabled";
}
@end

@implementation ReferenceCache {
    NSMutableDictionary<NSString *, ReferenceItem *> *_itemsByIdentifier;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _itemsByIdentifier = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSDictionary<NSString *, ReferenceItem *> *)itemsByIdentifier
{
    return [_itemsByIdentifier copy];
}

- (ReferenceItem *)itemForIdentifier:(NSString *)identifier effectiveRange:(NSRange *)effectiveRange
{
    if (effectiveRange != NULL) {
        *effectiveRange = NSMakeRange(0, identifier.length);
    }
    NSString *normalized = ReferenceLanguageAliases()[identifier] ?: identifier;
    return _itemsByIdentifier[normalized];
}

- (void)loadItemForIdentifier:(NSString *)identifier completion:(REReferenceCompletion)completion
{
    NSRange range = ReferenceCallRange(identifier, @"rangeOfComposedCharacterSequencesForRange:");
    (void)range;
    NSError *error = nil;
    ReferenceItem *item = [self itemForIdentifier:identifier effectiveRange:NULL];
    if (item == nil && !ReferenceCallBoolError(self, @"validateWithError:", &error)) {
        completion(nil, error);
        return;
    }
    completion(item ?: ReferenceCallObject(self, @"defaultItem"), nil);
}

- (NSString *)renderItem:(ReferenceItem *)item error:(NSError **)error
{
    if (item.title.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"ReferenceCache"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing title"}];
        }
        return nil;
    }
    return item.displayTitle;
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
