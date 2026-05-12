#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const DefaultToolchainAppPath = @"/Applications/Xcode.app";
static NSUInteger const SourceModelTokenBase = 0x20000;

@interface EditorSpecSourceBufferProvider : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) id language;
@end

@implementation EditorSpecSourceBufferProvider

- (NSUInteger)length
{
    return self.text.length;
}

- (unichar)characterAtIndex:(NSUInteger)index
{
    return [self.text characterAtIndex:index];
}

- (NSString *)string
{
    return self.text;
}

- (id)stringAsId
{
    return self.text;
}

- (NSString *)stringWithRange:(NSRange)range
{
    return [self.text substringWithRange:range];
}

- (void)scheduleLazyInvalidationForRange:(NSRange)range
{
    (void)range;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    if (signature != nil) {
        return signature;
    }

    const char *selectorName = sel_getName(selector);
    if (strstr(selectorName, "Range") != NULL) {
        return [NSMethodSignature signatureWithObjCTypes:"v@:{_NSRange=QQ}"];
    }
    if (strstr(selectorName, "length") != NULL || strstr(selectorName, "Length") != NULL) {
        return [NSMethodSignature signatureWithObjCTypes:"Q@:"];
    }
    if (strstr(selectorName, "is") == selectorName || strstr(selectorName, "uses") == selectorName) {
        return [NSMethodSignature signatureWithObjCTypes:"B@:"];
    }
    return [NSMethodSignature signatureWithObjCTypes:"@@:"];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    const char *returnType = invocation.methodSignature.methodReturnType;
    if (strcmp(returnType, @encode(void)) == 0) {
        return;
    }
    if (returnType[0] == '@' || returnType[0] == '#') {
        id value = nil;
        [invocation setReturnValue:&value];
        return;
    }
    NSUInteger length = invocation.methodSignature.methodReturnLength;
    void *zero = calloc(1, length);
    [invocation setReturnValue:zero];
    free(zero);
}

@end

static id CallObject(id object, NSString *selectorName)
{
    return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selectorName));
}

static id CallObject1(id object, NSString *selectorName, id argument)
{
    return ((id (*)(id, SEL, id))objc_msgSend)(object, NSSelectorFromString(selectorName), argument);
}

static void CallVoid(id object, NSString *selectorName)
{
    ((void (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selectorName));
}

static NSRange CallRange(id object, NSString *selectorName)
{
    return ((NSRange (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selectorName));
}

static NSInteger CallInteger(id object, NSString *selectorName)
{
    return ((NSInteger (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selectorName));
}

static BOOL CallBool(id object, NSString *selectorName)
{
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selectorName));
}

static NSString *SourceModelFrameworkPath(NSString *toolchainAppPath)
{
    return [toolchainAppPath stringByAppendingPathComponent:
        @"Contents/SharedFrameworks/SourceModel.framework"];
}

static NSDictionary<NSString *, NSString *> *LanguageAliases(void)
{
    return @{
        @"c": @"xcode.lang.c",
        @"cpp": @"xcode.lang.cpp",
        @"c++": @"xcode.lang.cpp",
        @"css": @"xcode.lang.css",
        @"html": @"xcode.lang.html",
        @"javascript": @"xcode.lang.javascript",
        @"js": @"xcode.lang.javascript",
        @"json": @"xcode.lang.json",
        @"objc": @"xcode.lang.objc",
        @"objective-c": @"xcode.lang.objc",
        @"swift": @"xcode.lang.swift",
        @"ini": @"xcode.lang.toml",
        @"toml": @"xcode.lang.toml",
        @"xml": @"Xcode.SourceCodeLanguage.XML",
    };
}

static NSString *NormalizedLanguageInput(NSString *languageInput)
{
    NSString *lowercase = languageInput.lowercaseString;
    NSString *alias = LanguageAliases()[lowercase];
    return alias ?: languageInput;
}

static id SourceCodeLanguageForInput(NSString *languageInput, NSString *filePath)
{
    Class languageClass = NSClassFromString(@"SMSourceCodeLanguage");
    if (languageClass == Nil) {
        return nil;
    }

    CallVoid(languageClass, @"loadAndCacheDefaultSourceCodeLanguages");

    if (languageInput.length > 0) {
        NSString *normalized = NormalizedLanguageInput(languageInput);
        if ([normalized hasPrefix:@"Xcode.SourceCodeLanguage."]) {
            return CallObject1(languageClass, @"sourceCodeLanguageWithIdentifier:", normalized);
        }
        return CallObject1(
            languageClass,
            @"sourceCodeLanguageForLanguageSpecificationIdentifier:",
            normalized
        );
    }

    NSString *extension = filePath.pathExtension;
    if (extension.length == 0) {
        return nil;
    }
    return CallObject1(languageClass, @"sourceCodeLanguageForFileExtension:", extension);
}

static NSString *TokenNameForToken(NSInteger token)
{
    if (token < (NSInteger)SourceModelTokenBase) {
        return nil;
    }
    Class tokenClass = NSClassFromString(@"SMSourceTokens");
    NSArray *names = CallObject(tokenClass, @"globalTokenNames");
    NSInteger index = token - (NSInteger)SourceModelTokenBase;
    if (index < 0 || index >= (NSInteger)names.count) {
        return nil;
    }
    id name = names[(NSUInteger)index];
    return [name isKindOfClass:NSString.class] ? name : nil;
}

static NSString *NodeTypeNameForNodeType(NSInteger nodeType)
{
    Class nodeTypesClass = NSClassFromString(@"SMSourceNodeTypes");
    if (nodeTypesClass == Nil) {
        return nil;
    }
    return ((id (*)(id, SEL, short))objc_msgSend)(
        nodeTypesClass,
        NSSelectorFromString(@"nodeTypeNameForId:"),
        (short)nodeType
    );
}

static NSDictionary *RangeDictionary(NSRange range)
{
    return @{
        @"location": @(range.location),
        @"length": @(range.length),
    };
}

static NSString *SubstringForRange(NSString *text, NSRange range)
{
    if (range.location == NSNotFound || NSMaxRange(range) > text.length) {
        return @"";
    }
    return [text substringWithRange:range];
}

static void PrintUsage(void)
{
    fprintf(stderr,
        "Usage: source_model_snapshot --file <path> [--language <identifier>] [--xcode <path>] [--pretty] [--no-text]\n"
        "\n"
        "Language may be a SourceModel language specification identifier, a source language identifier,\n"
        "or a common alias such as swift, html, css, javascript, json, objc, xml, or toml.\n"
    );
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSString *toolchainAppPath = DefaultToolchainAppPath;
        NSString *filePath = nil;
        NSString *languageInput = nil;
        BOOL pretty = NO;
        BOOL includeText = YES;

        for (int index = 1; index < argc; index += 1) {
            NSString *argument = [NSString stringWithUTF8String:argv[index]];
            if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
                PrintUsage();
                return 0;
            } else if ([argument isEqualToString:@"--xcode"] && index + 1 < argc) {
                toolchainAppPath = [NSString stringWithUTF8String:argv[++index]];
            } else if ([argument isEqualToString:@"--file"] && index + 1 < argc) {
                filePath = [NSString stringWithUTF8String:argv[++index]];
            } else if ([argument isEqualToString:@"--language"] && index + 1 < argc) {
                languageInput = [NSString stringWithUTF8String:argv[++index]];
            } else if ([argument isEqualToString:@"--pretty"]) {
                pretty = YES;
            } else if ([argument isEqualToString:@"--no-text"]) {
                includeText = NO;
            } else {
                fprintf(stderr, "Unknown or incomplete argument: %s\n", argv[index]);
                PrintUsage();
                return 2;
            }
        }

        if (filePath.length == 0) {
            PrintUsage();
            return 2;
        }

        NSError *error = nil;
        NSString *text = [NSString stringWithContentsOfFile:filePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
        if (text == nil) {
            fprintf(stderr, "Could not read input file: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        NSString *frameworkPath = SourceModelFrameworkPath(toolchainAppPath);
        NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];
        if (frameworkBundle == nil || ![frameworkBundle load]) {
            fprintf(stderr, "Could not load SourceModel framework at %s\n", frameworkPath.UTF8String);
            return 1;
        }

        id language = SourceCodeLanguageForInput(languageInput, filePath);
        if (language == nil) {
            fprintf(stderr, "Could not resolve source language for input.\n");
            return 1;
        }

        EditorSpecSourceBufferProvider *provider = [EditorSpecSourceBufferProvider new];
        provider.text = text;
        provider.language = language;

        Class sourceModelClass = NSClassFromString(@"SMSourceModel");
        id sourceModel = CallObject1([sourceModelClass alloc], @"initWithSourceBufferProvider:", provider);
        if (sourceModel == nil) {
            fprintf(stderr, "Could not create SourceModel instance.\n");
            return 1;
        }
        CallVoid(sourceModel, @"parse");

        NSMutableArray *items = [NSMutableArray array];
        void (^block)(id) = ^(id item) {
            NSRange range = CallRange(item, @"range");
            NSInteger token = CallInteger(item, @"token");
            NSInteger nodeType = CallInteger(item, @"nodeType");

            NSMutableDictionary *dictionary = [@{
                @"range": RangeDictionary(range),
                @"token": @(token),
                @"nodeType": @(nodeType),
            } mutableCopy];

            NSString *tokenName = TokenNameForToken(token);
            if (tokenName != nil) {
                dictionary[@"tokenName"] = tokenName;
            }

            NSString *nodeTypeName = NodeTypeNameForNodeType(nodeType);
            if (nodeTypeName != nil) {
                dictionary[@"syntaxType"] = nodeTypeName;
            }

            if ([item respondsToSelector:NSSelectorFromString(@"specificationIdentifier")]) {
                id specificationIdentifier = CallObject(item, @"specificationIdentifier");
                if ([specificationIdentifier isKindOfClass:NSString.class]) {
                    dictionary[@"specificationIdentifier"] = specificationIdentifier;
                }
            }

            dictionary[@"isIdentifier"] = @(CallBool(item, @"isIdentifier"));
            dictionary[@"isKeyword"] = @(CallBool(item, @"isKeyword"));
            dictionary[@"isSimpleToken"] = @(CallBool(item, @"isSimpleToken"));

            if (includeText) {
                dictionary[@"text"] = SubstringForRange(text, range);
            }

            [items addObject:dictionary];
        };
        ((void (*)(id, SEL, id))objc_msgSend)(
            sourceModel,
            NSSelectorFromString(@"enumerateItemsUsingBlock:"),
            block
        );

        id languageIdentifier = [language respondsToSelector:NSSelectorFromString(@"identifier")]
            ? CallObject(language, @"identifier")
            : nil;
        id languageName = [language respondsToSelector:NSSelectorFromString(@"languageName")]
            ? CallObject(language, @"languageName")
            : nil;
        id languageSpecification = [language respondsToSelector:NSSelectorFromString(@"languageSpecification")]
            ? CallObject(language, @"languageSpecification")
            : nil;
        id languageSpecificationIdentifier = [languageSpecification respondsToSelector:NSSelectorFromString(@"identifier")]
            ? CallObject(languageSpecification, @"identifier")
            : nil;
        id languageSpecificationName = [languageSpecification respondsToSelector:NSSelectorFromString(@"name")]
            ? CallObject(languageSpecification, @"name")
            : nil;

        NSDictionary *output = @{
            @"source": @{
                @"framework": frameworkPath,
                @"file": filePath,
                @"languageInput": languageInput ?: @"",
                @"languageIdentifier": languageIdentifier ?: @"",
                @"languageName": languageName ?: @"",
                @"languageSpecificationIdentifier": languageSpecificationIdentifier ?: @"",
                @"languageSpecificationName": languageSpecificationName ?: @"",
            },
            @"items": items,
        };

        NSJSONWritingOptions options = pretty ? NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys : 0;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:output options:options error:&error];
        if (jsonData == nil) {
            fprintf(stderr, "Could not serialize JSON: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        fwrite(jsonData.bytes, 1, jsonData.length, stdout);
        fputc('\n', stdout);
    }
    return 0;
}
