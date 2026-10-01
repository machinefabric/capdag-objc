//
//  CSCapQuery.m
//  Asking the fabric for a cap — see CSCapQuery.h.
//

#import "CSCapQuery.h"
#import "CSCapUrn.h"
#import "CSMediaUrn.h"
@import TaggedUrn;

#import "capdagFormal.h"

NSString *CSMatchGradeName(CSMatchGrade grade) {
    switch (grade) {
        case CSMatchGradeExact: return @"exact";
        case CSMatchGradeGuaranteed: return @"guaranteed";
        case CSMatchGradePossible: return @"possible";
        case CSMatchGradeNone: return @"none";
    }
}

/// A call into the generated program fails only when the runtime does, never on a value this
/// library built.
static void CSCapQueryFailed(NSString *what, lungo_error *error) {
    NSString *message = error ? [NSString stringWithUTF8String:lungo_error_message(error)] : @"no diagnostic";
    if (error) lungo_error_free(error);
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"capdag: the model could not %@: %@", what, message]
                                 userInfo:nil];
}

/// The cap-tag pattern a query asks for — `cap:` with these tags — as the model's value; owned.
static lungo_value *CSCapQueryTagPattern(NSDictionary<NSString *, NSString *> *tags) {
    NSError *error = nil;
    CSTaggedUrn *pattern = [CSTaggedUrn fromPrefix:@"cap" tags:(tags ?: @{}) error:&error];
    if (!pattern) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:[NSString stringWithFormat:@"capdag: a query's cap-tags are not valid tags: %@", error.localizedDescription]
                                     userInfo:nil];
    }
    return lungo_value_clone(pattern.formalValue);
}

@interface CSCapQuery () {
    // The question on the proved model's side (a CapDAG.Exec.WfQuery, owned).
    lungo_value *_formal;
    NSString *_asked;
}
@end

@implementation CSCapQuery

- (instancetype)initWithFormal:(lungo_value *)formal asked:(NSString *)asked {
    self = [super init];
    if (self) {
        _formal = formal;
        _asked = [asked copy];
    }
    return self;
}

- (void)dealloc {
    lungo_value_free(_formal);
}

- (NSString *)description {
    return _asked;
}

+ (instancetype)fromRequest:(CSCapUrn *)request {
    lungo_value *query = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_query_of_request(request.formalValue, &query, &error) != LUNGO_OK) CSCapQueryFailed(@"read a request", error);
    return [[self alloc] initWithFormal:query asked:[NSString stringWithFormat:@"request %@", [request toString]]];
}

+ (instancetype)fromPattern:(CSCapUrn *)pattern {
    lungo_value *query = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_query_of_pattern(pattern.formalValue, &query, &error) != LUNGO_OK) CSCapQueryFailed(@"read a pattern", error);
    return [[self alloc] initWithFormal:query asked:[NSString stringWithFormat:@"pattern %@", [pattern toString]]];
}

+ (instancetype)producing:(CSMediaUrn *)output tags:(NSDictionary<NSString *, NSString *> *)tags {
    lungo_value *pattern = CSCapQueryTagPattern(tags);
    lungo_value *query = NULL;
    lungo_error *error = NULL;
    int32_t status = capdagFormal_query_producing(output.inner.formalValue, pattern, &query, &error);
    lungo_value_free(pattern);
    if (status != LUNGO_OK) CSCapQueryFailed(@"ask what gives a type", error);
    return [[self alloc] initWithFormal:query asked:[NSString stringWithFormat:@"anything giving %@", [output toString]]];
}

+ (instancetype)consuming:(CSMediaUrn *)input tags:(NSDictionary<NSString *, NSString *> *)tags {
    lungo_value *pattern = CSCapQueryTagPattern(tags);
    lungo_value *query = NULL;
    lungo_error *error = NULL;
    int32_t status = capdagFormal_query_consuming(input.inner.formalValue, pattern, &query, &error);
    lungo_value_free(pattern);
    if (status != LUNGO_OK) CSCapQueryFailed(@"ask what takes a type", error);
    return [[self alloc] initWithFormal:query asked:[NSString stringWithFormat:@"anything taking %@", [input toString]]];
}

+ (instancetype)betweenInput:(CSMediaUrn *)input
                      output:(CSMediaUrn *)output
                        tags:(NSDictionary<NSString *, NSString *> *)tags {
    lungo_value *pattern = CSCapQueryTagPattern(tags);
    lungo_value *query = NULL;
    lungo_error *error = NULL;
    int32_t status = capdagFormal_query_between(input.inner.formalValue, output.inner.formalValue, pattern, &query, &error);
    lungo_value_free(pattern);
    if (status != LUNGO_OK) CSCapQueryFailed(@"ask what takes one type and gives another", error);
    return [[self alloc] initWithFormal:query
                                  asked:[NSString stringWithFormat:@"anything taking %@ and giving %@", [input toString], [output toString]]];
}

- (BOOL)admits:(CSCapUrn *)cap {
    lungo_value *result = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_query_admits(_formal, cap.formalValue, &result, &error) != LUNGO_OK) CSCapQueryFailed(@"decide a query", error);
    BOOL answer = lungo_value_get_bool(result);
    lungo_value_free(result);
    return answer;
}

- (BOOL)mayAdmit:(CSCapUrn *)cap {
    lungo_value *result = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_query_may_admit(_formal, cap.formalValue, &result, &error) != LUNGO_OK) CSCapQueryFailed(@"decide a possible answer", error);
    BOOL answer = lungo_value_get_bool(result);
    lungo_value_free(result);
    return answer;
}

- (CSMatchGrade)grade:(CSCapUrn *)cap {
    lungo_value *result = NULL;
    lungo_error *error = NULL;
    if (capdagFormal_query_grade(_formal, cap.formalValue, &result, &error) != LUNGO_OK) CSCapQueryFailed(@"grade an answer", error);
    uint32_t which = lungo_value_ctor_index(result);
    lungo_value_free(result);
    switch (which) {
        case CAPDAGFORMAL_GRADE_EXACT: return CSMatchGradeExact;
        case CAPDAGFORMAL_GRADE_GUARANTEED: return CSMatchGradeGuaranteed;
        case CAPDAGFORMAL_GRADE_POSSIBLE: return CSMatchGradePossible;
        case CAPDAGFORMAL_GRADE_NONE: return CSMatchGradeNone;
        default:
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"capdag: the model answered with a grade this mirror does not know: %u", which]
                                         userInfo:nil];
    }
}

@end
