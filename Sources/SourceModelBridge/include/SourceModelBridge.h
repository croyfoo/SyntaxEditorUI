#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SourceModelBridge : NSObject

+ (nullable NSDictionary<NSString *, id> *)snapshotForFileAtPath:(NSString *)filePath
                                                        language:(nullable NSString *)languageInput
                                                    toolchainApp:(NSString *)toolchainAppPath
                                                     includeText:(BOOL)includeText
                                                           error:(NSError **)error
    NS_SWIFT_NAME(snapshot(filePath:language:toolchainAppPath:includeText:));

+ (nullable NSDictionary<NSString *, id> *)renderedSnapshotForFileAtPath:(NSString *)filePath
                                                                language:(nullable NSString *)languageInput
                                                            toolchainApp:(NSString *)toolchainAppPath
                                                               themeName:(nullable NSString *)themeName
                                                              includeText:(BOOL)includeText
                                                                    error:(NSError **)error
    NS_SWIFT_NAME(renderedSnapshot(filePath:language:toolchainAppPath:themeName:includeText:));

+ (nullable NSDictionary<NSString *, id> *)languageDiagnosticsForFileAtPath:(NSString *)filePath
                                                                   language:(nullable NSString *)languageInput
                                                               toolchainApp:(NSString *)toolchainAppPath
                                                                      error:(NSError **)error
    NS_SWIFT_NAME(languageDiagnostics(filePath:language:toolchainAppPath:));

+ (nullable NSDictionary<NSString *, id> *)sourceEditorViewDiagnosticsForFileAtPath:(NSString *)filePath
                                                                            language:(nullable NSString *)languageInput
                                                                        toolchainApp:(NSString *)toolchainAppPath
                                                                               error:(NSError **)error
    NS_SWIFT_NAME(sourceEditorViewDiagnostics(filePath:language:toolchainAppPath:));

@end

NS_ASSUME_NONNULL_END
