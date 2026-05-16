#import "SourceModelBridge.h"
#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const SourceModelBridgeErrorDomain = @"SourceModelBridge";
static NSUInteger const SourceModelTokenBase = 0x20000;

@interface SourceModelBufferProvider : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) id language;
@end

@implementation SourceModelBufferProvider

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

static id CallObjectShort(id object, NSString *selectorName, short argument)
{
    return ((id (*)(id, SEL, short))objc_msgSend)(object, NSSelectorFromString(selectorName), argument);
}

static void CallVoid(id object, NSString *selectorName)
{
    ((void (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selectorName));
}

static void CallVoid1(id object, NSString *selectorName, id argument)
{
    ((void (*)(id, SEL, id))objc_msgSend)(object, NSSelectorFromString(selectorName), argument);
}

static void CallVoidBool(id object, NSString *selectorName, BOOL argument)
{
    ((void (*)(id, SEL, BOOL))objc_msgSend)(object, NSSelectorFromString(selectorName), argument);
}

static void CallVoidRange(id object, NSString *selectorName, NSRange argument)
{
    ((void (*)(id, SEL, NSRange))objc_msgSend)(object, NSSelectorFromString(selectorName), argument);
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

static BOOL CallBoolError(id object, NSString *selectorName, NSError **error)
{
    return ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(object, NSSelectorFromString(selectorName), error);
}

static id CallObjectAtIndex(id object, NSString *selectorName, NSUInteger index, NSRange *effectiveRange, id context)
{
    return ((id (*)(id, SEL, NSUInteger, NSRange *, id))objc_msgSend)(
        object,
        NSSelectorFromString(selectorName),
        index,
        effectiveRange,
        context
    );
}

static NSInteger CallIntegerAtIndex(id object, NSString *selectorName, NSUInteger index, NSRange *effectiveRange, id context)
{
    return ((NSInteger (*)(id, SEL, NSUInteger, NSRange *, id))objc_msgSend)(
        object,
        NSSelectorFromString(selectorName),
        index,
        effectiveRange,
        context
    );
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
    NSString *alias = LanguageAliases()[languageInput.lowercaseString];
    return alias ?: languageInput;
}

static NSDictionary *ErrorUserInfo(NSString *message)
{
    return @{NSLocalizedDescriptionKey: message};
}

static BOOL SetError(NSError **error, NSInteger code, NSString *message)
{
    if (error != nil) {
        *error = [NSError errorWithDomain:SourceModelBridgeErrorDomain
                                     code:code
                                 userInfo:ErrorUserInfo(message)];
    }
    return NO;
}

static BOOL LoadFramework(NSString *toolchainAppPath, NSString *relativePath, NSError **error, NSInteger code)
{
    NSString *frameworkPath = [toolchainAppPath stringByAppendingPathComponent:relativePath];
    NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];
    if (frameworkBundle == nil || ![frameworkBundle load]) {
        return SetError(error, code, [NSString stringWithFormat:@"Could not load framework at %@", frameworkPath]);
    }
    return YES;
}

static void InitializeDVTApplicationDirectoryName(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class developerPathsClass = NSClassFromString(@"DVTDeveloperPaths");
        SEL selector = NSSelectorFromString(@"initializeApplicationDirectoryName:");
        if (developerPathsClass != Nil && [developerPathsClass respondsToSelector:selector]) {
            CallVoid1(developerPathsClass, @"initializeApplicationDirectoryName:", @"Xcode");
        }
    });
}

static BOOL InitializeDVTPlugIns(NSError **error)
{
    static dispatch_once_t onceToken;
    static BOOL didScan = NO;
    static NSError *scanError = nil;
    dispatch_once(&onceToken, ^{
        Class managerClass = NSClassFromString(@"DVTPlugInManager");
        id manager = managerClass == Nil ? nil : CallObject(managerClass, @"defaultPlugInManager");
        if (manager != nil && [manager respondsToSelector:NSSelectorFromString(@"scanForPlugIns:")]) {
            NSError *localError = nil;
            didScan = CallBoolError(manager, @"scanForPlugIns:", &localError);
            scanError = localError;
        }
    });
    if (!didScan && error != nil) {
        *error = scanError ?: [NSError errorWithDomain:SourceModelBridgeErrorDomain
                                                  code:9
                                              userInfo:ErrorUserInfo(@"Could not scan Xcode DVT plug-ins.")];
    }
    return didScan;
}

static void InitializeDVTSourceSpecifications(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class specificationClass = NSClassFromString(@"DVTSourceSpecification");
        SEL selector = NSSelectorFromString(@"searchForAndRegisterAllAvailableSpecifications");
        if (specificationClass != Nil && [specificationClass respondsToSelector:selector]) {
            CallVoid(specificationClass, @"searchForAndRegisterAllAvailableSpecifications");
        }
    });
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
        return CallObject1(languageClass, @"sourceCodeLanguageForLanguageSpecificationIdentifier:", normalized);
    }

    NSString *extension = filePath.pathExtension;
    if (extension.length == 0) {
        return nil;
    }
    return CallObject1(languageClass, @"sourceCodeLanguageForFileExtension:", extension);
}

static id DVTSourceCodeLanguageForInput(NSString *languageInput, NSString *filePath)
{
    Class languageClass = NSClassFromString(@"DVTSourceCodeLanguage");
    if (languageClass == Nil) {
        return nil;
    }

    if (languageInput.length > 0) {
        NSString *normalized = NormalizedLanguageInput(languageInput);
        if ([normalized isEqualToString:@"xcode.lang.swift"]) {
            return CallObject(languageClass, @"swiftSourceCodeLanguage");
        }
        if ([normalized isEqualToString:@"xcode.lang.c"]) {
            return CallObject(languageClass, @"cSourceCodeLanguage");
        }
        if ([normalized isEqualToString:@"xcode.lang.cpp"]) {
            return CallObject(languageClass, @"cPlusPlusSourceCodeLanguage");
        }
        if ([normalized isEqualToString:@"xcode.lang.objc"]) {
            return CallObject(languageClass, @"objectiveCSourceCodeLanguage");
        }
        if ([normalized hasPrefix:@"Xcode.SourceCodeLanguage."]) {
            return CallObject1(languageClass, @"sourceCodeLanguageWithIdentifier:", normalized);
        }
        return CallObject1(languageClass, @"sourceCodeLanguageForLanguageSpecificationIdentifier:", normalized);
    }

    NSString *extension = filePath.pathExtension;
    if (extension.length == 0) {
        return nil;
    }
    return CallObject1(languageClass, @"_sourceCodeLanguageForExtension:", extension);
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

static NSString *DVTNodeTypeNameForNodeType(NSInteger nodeType)
{
    Class nodeTypesClass = NSClassFromString(@"DVTSourceNodeTypes");
    if (nodeTypesClass == Nil) {
        return nil;
    }
    return CallObjectShort(nodeTypesClass, @"nodeTypeNameForId:", (short)nodeType);
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

static id DVTThemeForName(NSString *themeName)
{
    Class themeClass = NSClassFromString(@"DVTFontAndColorTheme");
    if (themeClass == Nil) {
        return nil;
    }

    NSString *normalized = themeName.lowercaseString ?: @"";
    if ([normalized isEqualToString:@"current"]) {
        return CallObject(themeClass, @"currentTheme");
    }
    if ([normalized isEqualToString:@"current-light"]) {
        return CallObject(themeClass, @"currentLightTheme");
    }
    if ([normalized isEqualToString:@"current-dark"]) {
        return CallObject(themeClass, @"currentDarkTheme");
    }
    if ([normalized isEqualToString:@"default-light"]) {
        return CallObject(themeClass, @"ideDefaultLightTheme");
    }
    return CallObject(themeClass, @"ideDefaultDarkTheme");
}

static NSDictionary *ColorDictionary(NSColor *color)
{
    if (![color isKindOfClass:NSColor.class]) {
        return @{};
    }

    NSColor *rgbColor = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (rgbColor == nil) {
        return @{@"description": color.description ?: @""};
    }

    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    [rgbColor getRed:&red green:&green blue:&blue alpha:&alpha];

    NSInteger redByte = lround(red * 255.0);
    NSInteger greenByte = lround(green * 255.0);
    NSInteger blueByte = lround(blue * 255.0);
    NSInteger alphaByte = lround(alpha * 255.0);

    return @{
        @"red": @(red),
        @"green": @(green),
        @"blue": @(blue),
        @"alpha": @(alpha),
        @"hex": [NSString stringWithFormat:@"#%02lX%02lX%02lX", (long)redByte, (long)greenByte, (long)blueByte],
        @"rgbaHex": [NSString stringWithFormat:@"#%02lX%02lX%02lX%02lX", (long)redByte, (long)greenByte, (long)blueByte, (long)alphaByte],
        @"colorSpace": rgbColor.colorSpace.localizedName ?: @"",
    };
}

@implementation SourceModelBridge

+ (nullable NSDictionary<NSString *, id> *)snapshotForFileAtPath:(NSString *)filePath
                                                        language:(nullable NSString *)languageInput
                                                    toolchainApp:(NSString *)toolchainAppPath
                                                     includeText:(BOOL)includeText
                                                           error:(NSError **)error
{
    NSError *readError = nil;
    NSString *text = [NSString stringWithContentsOfFile:filePath
                                               encoding:NSUTF8StringEncoding
                                                  error:&readError];
    if (text == nil) {
        if (error != nil) {
            *error = readError;
        }
        return nil;
    }

    NSString *frameworkPath = [toolchainAppPath stringByAppendingPathComponent:
        @"Contents/SharedFrameworks/SourceModel.framework"];
    NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];
    if (frameworkBundle == nil || ![frameworkBundle load]) {
        SetError(error, 1, [NSString stringWithFormat:@"Could not load SourceModel framework at %@", frameworkPath]);
        return nil;
    }

    id language = SourceCodeLanguageForInput(languageInput ?: @"", filePath);
    if (language == nil) {
        SetError(error, 2, @"Could not resolve source language for input.");
        return nil;
    }

    SourceModelBufferProvider *provider = [SourceModelBufferProvider new];
    provider.text = text;
    provider.language = language;

    Class sourceModelClass = NSClassFromString(@"SMSourceModel");
    id sourceModel = CallObject1([sourceModelClass alloc], @"initWithSourceBufferProvider:", provider);
    if (sourceModel == nil) {
        SetError(error, 3, @"Could not create SourceModel instance.");
        return nil;
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
            @"isIdentifier": @(CallBool(item, @"isIdentifier")),
            @"isKeyword": @(CallBool(item, @"isKeyword")),
            @"isSimpleToken": @(CallBool(item, @"isSimpleToken")),
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

    return @{
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
}

+ (nullable NSDictionary<NSString *, id> *)renderedSnapshotForFileAtPath:(NSString *)filePath
                                                                language:(nullable NSString *)languageInput
                                                            toolchainApp:(NSString *)toolchainAppPath
                                                               themeName:(nullable NSString *)themeName
                                                              includeText:(BOOL)includeText
                                                                    error:(NSError **)error
{
    NSError *readError = nil;
    NSString *text = [NSString stringWithContentsOfFile:filePath
                                               encoding:NSUTF8StringEncoding
                                                  error:&readError];
    if (text == nil) {
        if (error != nil) {
            *error = readError;
        }
        return nil;
    }

    if (!LoadFramework(toolchainAppPath, @"Contents/SharedFrameworks/DVTFoundation.framework", error, 4)) {
        return nil;
    }
    InitializeDVTApplicationDirectoryName();
    if (!LoadFramework(toolchainAppPath, @"Contents/SharedFrameworks/SourceModel.framework", error, 5)) {
        return nil;
    }
    if (!LoadFramework(toolchainAppPath, @"Contents/SharedFrameworks/DVTKit.framework", error, 6)) {
        return nil;
    }
    if (!InitializeDVTPlugIns(error)) {
        return nil;
    }
    InitializeDVTSourceSpecifications();

    id language = DVTSourceCodeLanguageForInput(languageInput ?: @"", filePath);
    if (language == nil) {
        SetError(error, 7, @"Could not resolve DVT source language for input.");
        return nil;
    }

    Class textStorageClass = NSClassFromString(@"DVTTextStorage");
    id textStorage = CallObject1([textStorageClass alloc], @"initWithString:", text);
    if (textStorage == nil) {
        SetError(error, 8, @"Could not create DVTTextStorage instance.");
        return nil;
    }

    id theme = DVTThemeForName(themeName ?: @"default-dark");
    if (theme != nil && [textStorage respondsToSelector:NSSelectorFromString(@"setFontAndColorTheme:")]) {
        CallVoid1(textStorage, @"setFontAndColorTheme:", theme);
    }
    if ([textStorage respondsToSelector:NSSelectorFromString(@"setLanguage:")]) {
        CallVoid1(textStorage, @"setLanguage:", language);
    }
    if ([textStorage respondsToSelector:NSSelectorFromString(@"setSyntaxColoringEnabled:")]) {
        CallVoidBool(textStorage, @"setSyntaxColoringEnabled:", YES);
    }
    if ([textStorage respondsToSelector:NSSelectorFromString(@"fixSyntaxColoringInRange:")]) {
        CallVoidRange(textStorage, @"fixSyntaxColoringInRange:", NSMakeRange(0, text.length));
    }

    id context = [textStorage respondsToSelector:NSSelectorFromString(@"sourceLanguageServiceContext")]
        ? CallObject(textStorage, @"sourceLanguageServiceContext")
        : nil;

    NSMutableArray *items = [NSMutableArray array];
    NSUInteger index = 0;
    while (index < text.length) {
        NSRange colorRange = NSMakeRange(index, 1);
        id color = CallObjectAtIndex(textStorage, @"colorAtCharacterIndex:effectiveRange:context:", index, &colorRange, context);

        NSRange nodeRange = NSMakeRange(index, 1);
        NSInteger nodeType = CallIntegerAtIndex(textStorage, @"nodeTypeAtCharacterIndex:effectiveRange:context:", index, &nodeRange, context);
        NSString *syntaxType = DVTNodeTypeNameForNodeType(nodeType) ?: @"";

        NSRange range = colorRange;
        if (range.location == NSNotFound || range.length == 0 || NSMaxRange(range) > text.length) {
            range = nodeRange;
        }
        if (range.location == NSNotFound || range.length == 0 || NSMaxRange(range) > text.length) {
            range = NSMakeRange(index, 1);
        }

        NSMutableDictionary *dictionary = [@{
            @"range": RangeDictionary(range),
            @"nodeType": @(nodeType),
            @"syntaxType": syntaxType,
            @"color": ColorDictionary(color),
        } mutableCopy];
        if (includeText) {
            dictionary[@"text"] = SubstringForRange(text, range);
        }
        [items addObject:dictionary];

        index = NSMaxRange(range);
    }

    id languageIdentifier = [language respondsToSelector:NSSelectorFromString(@"identifier")]
        ? CallObject(language, @"identifier")
        : nil;
    id languageName = [language respondsToSelector:NSSelectorFromString(@"languageName")]
        ? CallObject(language, @"languageName")
        : nil;
    id themeDisplayName = [theme respondsToSelector:NSSelectorFromString(@"name")]
        ? CallObject(theme, @"name")
        : nil;
    if (themeDisplayName == nil && [theme respondsToSelector:NSSelectorFromString(@"localizedName")]) {
        themeDisplayName = CallObject(theme, @"localizedName");
    }

    return @{
        @"source": @{
            @"framework": [toolchainAppPath stringByAppendingPathComponent:@"Contents/SharedFrameworks/DVTKit.framework"],
            @"file": filePath,
            @"languageInput": languageInput ?: @"",
            @"languageIdentifier": languageIdentifier ?: @"",
            @"languageName": languageName ?: @"",
            @"themeInput": themeName ?: @"default-dark",
            @"themeName": themeDisplayName ?: @"",
        },
        @"items": items,
    };
}

@end
