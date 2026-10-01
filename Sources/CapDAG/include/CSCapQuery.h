//
//  CSCapQuery.h
//  Asking the fabric for a cap
//
//  A request is not a cap. A cap takes this and gives that; a request is a
//  QUESTION about caps, and may leave a side unasked: "what gives me this file,
//  whatever it takes?", "what can this input become?". Those are not cap URNs
//  with `media:` on a side — `media:` is the type "anything", a claim about every
//  input — they are queries with that side unknown.
//
//  CSCapQuery is such a question, and CSMatchGrade is how a registered cap
//  answers it. A cap URN read as a request or as a pattern is one — which is what
//  -[CSCapUrn isDispatchable:] and -[CSCapUrn accepts:] ask — and so are the
//  questions no cap URN can spell (producing, consuming, between).
//
//  Every answer is decided by the proved model (formal/CapDAG/Query.lean).
//

#import <Foundation/Foundation.h>

@class CSCapUrn;
@class CSMediaUrn;

NS_ASSUME_NONNULL_BEGIN

/// How a registered cap answers a CSCapQuery.
typedef NS_ENUM(NSInteger, CSMatchGrade) {
    /// Guaranteed, and exactly what was asked on every side that was asked.
    CSMatchGradeExact,
    /// Guaranteed: whatever the cap takes and gives, it is what was asked.
    CSMatchGradeGuaranteed,
    /// Not guaranteed and not excluded: only running it tells. For exploring; a
    /// call is never routed on it.
    CSMatchGradePossible,
    /// Excluded.
    CSMatchGradeNone,
};

/// The model's name for a grade: "exact", "guaranteed", "possible" or "none".
FOUNDATION_EXPORT NSString *CSMatchGradeName(CSMatchGrade grade);

/// A question about caps.
@interface CSCapQuery : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// The cap URN `request`, read as a request: an input it leaves open is not
/// established. What -[CSCapUrn isDispatchable:] asks.
+ (instancetype)fromRequest:(CSCapUrn *)request;

/// The cap URN `pattern`, read as a pattern over caps: an output it leaves open
/// is not established. What -[CSCapUrn accepts:] asks.
+ (instancetype)fromPattern:(CSCapUrn *)pattern;

/// Caps that GIVE `output`, whatever they take, with the cap-tags `tags` asks
/// for (nil or empty asks for none).
+ (instancetype)producing:(CSMediaUrn *)output tags:(nullable NSDictionary<NSString *, NSString *> *)tags;

/// Caps that TAKE `input`, whatever they give: what this input can become in
/// one step.
+ (instancetype)consuming:(CSMediaUrn *)input tags:(nullable NSDictionary<NSString *, NSString *> *)tags;

/// Caps that take `input` and give `output`: nothing unknown.
+ (instancetype)betweenInput:(CSMediaUrn *)input
                      output:(CSMediaUrn *)output
                        tags:(nullable NSDictionary<NSString *, NSString *> *)tags;

/// Whether `cap` is guaranteed to be what is asked.
- (BOOL)admits:(CSCapUrn *)cap;

/// Whether `cap` could be what is asked.
- (BOOL)mayAdmit:(CSCapUrn *)cap;

/// How `cap` answers.
- (CSMatchGrade)grade:(CSCapUrn *)cap;

@end

NS_ASSUME_NONNULL_END
