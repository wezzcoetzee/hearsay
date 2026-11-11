#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift can't catch Objective-C exceptions. One that unwinds through Swift skips its
/// cleanup: an async job's isolation bookkeeping is left pointing at a dead stack frame,
/// and the app crashes later at the next actor check, far from the cause. Wrap calls
/// that report bad input by raising (AVAudioEngine's `installTap`) so the exception
/// becomes a thrown error where it happened.
@interface ObjCException : NSObject

+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block error:(NSError **)error NS_SWIFT_NAME(catching(_:));

@end

NS_ASSUME_NONNULL_END
