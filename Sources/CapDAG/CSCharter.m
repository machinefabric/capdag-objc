//
//  CSCharter.m
//  CapDAG
//
//  Registry charters. Mirrors Rust `bifaci/charter.rs` without its signature
//  verification (see CSCharter.h).
//

#import "CSCharter.h"

NSErrorDomain const CSCharterErrorDomain = @"CSCharterError";

NSString * const CSCharterFormat = @"machinefabric-registry-charter/1";
NSString * const CSCharterSigFormat = @"machinefabric-charter-sig/1";
NSString * const CSCharterFile = @"charter.json";
NSString * const CSCharterSigFile = @"charter.json.sig";
NSString * const CSCharterDevSlug = @"dev";

static NSError *CSCharterError(CSCharterErrorCode code, NSString *message) {
    return [NSError errorWithDomain:CSCharterErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL CSCharterFail(NSError **error, CSCharterErrorCode code, NSString *message) {
    if (error) *error = CSCharterError(code, message);
    return NO;
}

NSString *CSRegistryKindName(CSRegistryKind kind) {
    switch (kind) {
        case CSRegistryKindCartridges: return @"cartridges";
        case CSRegistryKindFabric: return @"fabric";
        case CSRegistryKindReleases: return @"releases";
    }
    [NSException raise:NSInternalInconsistencyException format:@"unknown registry kind %ld", (long)kind];
    return nil;
}

static BOOL CSRegistryKindFromName(NSString *name, CSRegistryKind *outKind) {
    for (NSNumber *each in @[@(CSRegistryKindCartridges), @(CSRegistryKindFabric), @(CSRegistryKindReleases)]) {
        CSRegistryKind kind = (CSRegistryKind)each.integerValue;
        if ([CSRegistryKindName(kind) isEqualToString:name]) {
            *outKind = kind;
            return YES;
        }
    }
    return NO;
}

/// Per kind, the locations a charter must declare, each with the placeholders
/// its template must use — all of them and no others.
static NSDictionary<NSString *, NSArray<NSString *> *> *CSRegistryLocations(CSRegistryKind kind) {
    switch (kind) {
        case CSRegistryKindCartridges:
            return @{@"manifest": @[@"registry_version"]};
        case CSRegistryKindFabric:
            return @{@"manifest": @[@"manifest_version"],
                     @"latest": @[],
                     @"definition": @[@"kind", @"urn_hash", @"version"]};
        case CSRegistryKindReleases:
            return @{@"manifest": @[@"app_id"]};
    }
    return @{};
}

static BOOL CSMatchesWhole(NSString *pattern, NSString *s) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSRange whole = NSMakeRange(0, s.length);
    NSTextCheckingResult *match = [re firstMatchInString:s options:NSMatchingAnchored range:whole];
    return match != nil && NSEqualRanges(match.range, whole);
}

static BOOL CSCheckHTTPS(NSString *what, NSString *url, NSError **error) {
    NSRange sep = [url rangeOfString:@"://"];
    NSString *rest = sep.location == NSNotFound ? @"" : [url substringFromIndex:NSMaxRange(sep)];
    if (sep.location == NSNotFound || ![[url substringToIndex:sep.location] isEqualToString:@"https"]
        || rest.length == 0 || [rest hasPrefix:@"/"]) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"%@ '%@' is not an https URL", what, url]);
    }
    if ([url rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]].location != NSNotFound) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"%@ '%@' carries a query or fragment", what, url]);
    }
    return YES;
}

/// The {name} placeholders a template uses, in order of first use. A stray
/// brace is an error rather than literal text.
static NSArray<NSString *> *_Nullable CSPlaceholdersIn(NSString *template, NSError **error) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSString *rest = template;
    NSCharacterSet *braces = [NSCharacterSet characterSetWithCharactersInString:@"{}"];
    while (YES) {
        NSRange at = [rest rangeOfCharacterFromSet:braces];
        if (at.location == NSNotFound) return out;
        if ([rest characterAtIndex:at.location] == '}') {
            CSCharterFail(error, CSCharterErrorMalformed,
                          [NSString stringWithFormat:@"'%@' has an unmatched '}'", template]);
            return nil;
        }
        NSString *after = [rest substringFromIndex:at.location + 1];
        NSRange end = [after rangeOfString:@"}"];
        if (end.location == NSNotFound) {
            CSCharterFail(error, CSCharterErrorMalformed,
                          [NSString stringWithFormat:@"'%@' has an unclosed '{'", template]);
            return nil;
        }
        NSString *name = [after substringToIndex:end.location];
        if (!CSMatchesWhole(@"[a-z_]+", name)) {
            CSCharterFail(error, CSCharterErrorMalformed,
                          [NSString stringWithFormat:@"'%@' has a placeholder '{%@}' that is not a name", template, name]);
            return nil;
        }
        if (![out containsObject:name]) [out addObject:name];
        rest = [after substringFromIndex:end.location + 1];
    }
}

static BOOL CSWriteAtomic(NSString *path, NSData *data, NSError **error) {
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

@interface CSCharter ()
@property (nonatomic, readwrite, copy) NSString *format;
@property (nonatomic, readwrite, copy) NSString *anchor;
@property (nonatomic, readwrite) CSRegistryKind kind;
@property (nonatomic, readwrite, copy) NSString *slug;
@property (nonatomic, readwrite, copy) NSString *environment;
@property (nonatomic, readwrite, copy, nullable) NSString *experiment;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *locations;
@property (nonatomic, readwrite, copy, nullable) NSString *fabric;
@property (nonatomic, readwrite) uint64_t issuedAt;
@property (nonatomic, readwrite, nullable) NSNumber *notAfter;
@end

@implementation CSCharter

+ (nullable instancetype)charterWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    static NSArray<NSString *> *fields, *required;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fields = @[@"format", @"anchor", @"kind", @"slug", @"environment", @"experiment",
                   @"locations", @"fabric", @"issued_at", @"not_after"];
        required = @[@"format", @"anchor", @"kind", @"slug", @"environment", @"locations",
                     @"issued_at", @"not_after"];
    });
    NSString *(^notACharter)(NSString *) = ^NSString *(NSString *why) {
        return [@"the charter is not a charter document: " stringByAppendingString:why];
    };
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        CSCharterFail(error, CSCharterErrorMalformed, notACharter(@"not a JSON object"));
        return nil;
    }
    for (NSString *key in [dictionary.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![fields containsObject:key]) {
            CSCharterFail(error, CSCharterErrorMalformed,
                          notACharter([NSString stringWithFormat:@"unknown field '%@'", key]));
            return nil;
        }
    }
    for (NSString *key in required) {
        if (dictionary[key] == nil) {
            CSCharterFail(error, CSCharterErrorMalformed, notACharter([NSString stringWithFormat:@"no '%@'", key]));
            return nil;
        }
    }
    for (NSString *key in @[@"format", @"anchor", @"kind", @"slug", @"environment"]) {
        if (![dictionary[key] isKindOfClass:[NSString class]]) {
            CSCharterFail(error, CSCharterErrorMalformed,
                          notACharter([NSString stringWithFormat:@"'%@' is not a string", key]));
            return nil;
        }
    }
    for (NSString *key in @[@"experiment", @"fabric"]) {
        id value = dictionary[key];
        if (value != nil && value != [NSNull null] && ![value isKindOfClass:[NSString class]]) {
            CSCharterFail(error, CSCharterErrorMalformed,
                          notACharter([NSString stringWithFormat:@"'%@' is not a string", key]));
            return nil;
        }
    }
    CSRegistryKind kind;
    if (!CSRegistryKindFromName(dictionary[@"kind"], &kind)) {
        CSCharterFail(error, CSCharterErrorMalformed,
                      notACharter([NSString stringWithFormat:@"kind '%@' is not a kind of registry", dictionary[@"kind"]]));
        return nil;
    }
    NSDictionary *locations = dictionary[@"locations"];
    BOOL templatesByName = [locations isKindOfClass:[NSDictionary class]];
    for (id key in templatesByName ? locations : @{}) {
        if (![key isKindOfClass:[NSString class]] || ![locations[key] isKindOfClass:[NSString class]]) {
            templatesByName = NO;
        }
    }
    if (!templatesByName) {
        CSCharterFail(error, CSCharterErrorMalformed, notACharter(@"locations are not templates by name"));
        return nil;
    }
    // A time is a non-negative whole number; JSON booleans decode as NSNumber
    // too, and are not one.
    BOOL (^isTime)(id) = ^BOOL(id value) {
        if (![value isKindOfClass:[NSNumber class]] || value == (id)kCFBooleanTrue || value == (id)kCFBooleanFalse) {
            return NO;
        }
        NSNumber *n = value;
        return n.doubleValue >= 0 && n.doubleValue == floor(n.doubleValue);
    };
    if (!isTime(dictionary[@"issued_at"])) {
        CSCharterFail(error, CSCharterErrorMalformed, notACharter(@"'issued_at' is not a time"));
        return nil;
    }
    id notAfter = dictionary[@"not_after"];
    if (notAfter != [NSNull null] && !isTime(notAfter)) {
        CSCharterFail(error, CSCharterErrorMalformed, notACharter(@"'not_after' is not a time"));
        return nil;
    }
    CSCharter *charter = [[CSCharter alloc] init];
    charter.format = dictionary[@"format"];
    charter.anchor = dictionary[@"anchor"];
    charter.kind = kind;
    charter.slug = dictionary[@"slug"];
    charter.environment = dictionary[@"environment"];
    charter.experiment = dictionary[@"experiment"] == [NSNull null] ? nil : dictionary[@"experiment"];
    charter.locations = locations;
    charter.fabric = dictionary[@"fabric"] == [NSNull null] ? nil : dictionary[@"fabric"];
    charter.issuedAt = [dictionary[@"issued_at"] unsignedLongLongValue];
    charter.notAfter = notAfter == [NSNull null] ? nil : notAfter;
    return charter;
}

+ (nullable instancetype)charterWithData:(NSData *)data error:(NSError **)error {
    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![json isKindOfClass:[NSDictionary class]] || json[@"format"] == nil) {
        CSCharterFail(error, CSCharterErrorMalformed,
                      [NSString stringWithFormat:@"the charter is not a charter document: %@",
                       jsonError.localizedDescription ?: @"no format"]);
        return nil;
    }
    if (![json[@"format"] isEqual:CSCharterFormat]) {
        CSCharterFail(error, CSCharterErrorMalformed,
                      [NSString stringWithFormat:@"the charter declares format '%@' (this build reads '%@')",
                       json[@"format"], CSCharterFormat]);
        return nil;
    }
    CSCharter *charter = [self charterWithDictionary:json error:error];
    if (!charter) return nil;
    NSError *shapeError = nil;
    if (![charter validate:&shapeError]) {
        CSCharterFail(error, CSCharterErrorMalformed,
                      [@"the charter is not a charter document: " stringByAppendingString:shapeError.localizedDescription]);
        return nil;
    }
    return charter;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *out = [@{
        @"format": self.format,
        @"anchor": self.anchor,
        @"kind": CSRegistryKindName(self.kind),
        @"slug": self.slug,
        @"environment": self.environment,
        @"locations": self.locations,
        @"issued_at": @(self.issuedAt),
        @"not_after": self.notAfter ?: [NSNull null],
    } mutableCopy];
    if (self.experiment) out[@"experiment"] = self.experiment;
    if (self.fabric) out[@"fabric"] = self.fabric;
    return out;
}

- (BOOL)validate:(NSError **)error {
    if (![self.format isEqualToString:CSCharterFormat]) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"format '%@' is not '%@'", self.format, CSCharterFormat]);
    }
    if (!CSCheckHTTPS(@"anchor", self.anchor, error)) return NO;
    if ([self.anchor hasSuffix:@"/"]) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"anchor '%@' ends with '/'", self.anchor]);
    }
    if (![CSCharter isSlug:self.slug]) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"slug '%@' is not a registry slug ([a-z0-9][a-z0-9.-]{0,62}, not '%@')",
                              self.slug, CSCharterDevSlug]);
    }
    if (!CSMatchesWhole(@"[a-z0-9-]+", self.environment)) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"environment '%@' is not a label ([a-z0-9-]+)", self.environment]);
    }
    if (self.experiment && ![CSCharter isExperimentID:self.experiment]) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"experiment '%@' is not an experiment id ([a-z0-9][a-z0-9-]{0,39})",
                              self.experiment]);
    }
    NSString *kindName = CSRegistryKindName(self.kind);
    NSDictionary<NSString *, NSArray<NSString *> *> *required = CSRegistryLocations(self.kind);
    for (NSString *name in self.locations) {
        if (required[name] == nil) {
            return CSCharterFail(error, CSCharterErrorMalformed,
                                 [NSString stringWithFormat:@"location '%@' is not one a %@ registry has", name, kindName]);
        }
    }
    for (NSString *name in [required.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *template = self.locations[name];
        if (template == nil) {
            return CSCharterFail(error, CSCharterErrorMalformed,
                                 [NSString stringWithFormat:@"a %@ registry must declare location '%@'", kindName, name]);
        }
        if (!CSCheckHTTPS([NSString stringWithFormat:@"location '%@'", name], template, error)) return NO;
        NSArray<NSString *> *used = CSPlaceholdersIn(template, error);
        if (!used) return NO;
        for (NSString *placeholder in used) {
            if (![required[name] containsObject:placeholder]) {
                return CSCharterFail(error, CSCharterErrorMalformed,
                                     [NSString stringWithFormat:@"location '%@' uses '{%@}', which it does not take", name, placeholder]);
            }
        }
        for (NSString *placeholder in required[name]) {
            if (![used containsObject:placeholder]) {
                return CSCharterFail(error, CSCharterErrorMalformed,
                                     [NSString stringWithFormat:@"location '%@' must use '{%@}'", name, placeholder]);
            }
        }
    }
    if (self.kind == CSRegistryKindCartridges) {
        if (self.fabric == nil) {
            return CSCharterFail(error, CSCharterErrorMalformed, @"a cartridges registry must name its fabric");
        }
        if (!CSCheckHTTPS(@"fabric", self.fabric, error)) return NO;
        if ([self.fabric hasSuffix:@"/"]) {
            return CSCharterFail(error, CSCharterErrorMalformed,
                                 [NSString stringWithFormat:@"fabric '%@' ends with '/'", self.fabric]);
        }
    } else if (self.fabric != nil) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"only a cartridges registry names a fabric, and this is a %@ registry", kindName]);
    }
    if (self.notAfter && self.notAfter.unsignedLongLongValue <= self.issuedAt) {
        return CSCharterFail(error, CSCharterErrorMalformed,
                             [NSString stringWithFormat:@"not_after %@ is not after issued_at %llu", self.notAfter, self.issuedAt]);
    }
    return YES;
}

- (nullable NSString *)locationNamed:(NSString *)name
                              values:(NSDictionary<NSString *, NSString *> *)values
                               error:(NSError **)error {
    NSString *template = self.locations[name];
    if (template == nil) {
        CSCharterFail(error, CSCharterErrorMalformed,
                      [NSString stringWithFormat:@"the %@ registry at %@ has no location '%@'",
                       CSRegistryKindName(self.kind), self.anchor, name]);
        return nil;
    }
    NSArray<NSString *> *used = CSPlaceholdersIn(template, error);
    if (!used) return nil;
    for (NSString *key in values) {
        if (![used containsObject:key]) {
            CSCharterFail(error, CSCharterErrorMalformed,
                          [NSString stringWithFormat:@"location '%@' does not take '%@'", name, key]);
            return nil;
        }
    }
    NSString *out = template;
    for (NSString *placeholder in used) {
        NSString *value = values[placeholder];
        if (value == nil) {
            CSCharterFail(error, CSCharterErrorMalformed,
                          [NSString stringWithFormat:@"location '%@' needs '%@'", name, placeholder]);
            return nil;
        }
        out = [out stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"{%@}", placeholder] withString:value];
    }
    return out;
}

+ (BOOL)isSlug:(NSString *)s {
    return ![s isEqualToString:CSCharterDevSlug] && CSMatchesWhole(@"[a-z0-9][a-z0-9.-]{0,62}", s);
}

+ (BOOL)isExperimentID:(NSString *)s {
    return CSMatchesWhole(@"[a-z0-9][a-z0-9-]{0,39}", s);
}

+ (nullable instancetype)storedInFolder:(NSString *)folder kind:(CSRegistryKind)kind error:(NSError **)error {
    NSString *path = [folder stringByAppendingPathComponent:CSCharterFile];
    NSError *readError = nil;
    NSData *body = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    if (!body) {
        CSCharterFail(error, CSCharterErrorUnreadable,
                      [NSString stringWithFormat:@"cannot read %@: %@", path, readError.localizedDescription]);
        return nil;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:CSCharterSigFile]]) {
        CSCharterFail(error, CSCharterErrorUnreadable,
                      [NSString stringWithFormat:@"the charter in %@ has no signature beside it", folder]);
        return nil;
    }
    CSCharter *charter = [self charterWithData:body error:error];
    if (!charter) return nil;
    if (charter.kind != kind) {
        CSCharterFail(error, CSCharterErrorRefused,
                      [NSString stringWithFormat:@"the charter is for a %@ registry, not a %@ one",
                       CSRegistryKindName(charter.kind), CSRegistryKindName(kind)]);
        return nil;
    }
    if (![folder.lastPathComponent isEqualToString:charter.slug]) {
        CSCharterFail(error, CSCharterErrorRefused,
                      [NSString stringWithFormat:@"the charter for '%@' names slug '%@', but it is stored in a folder named '%@'",
                       charter.anchor, charter.slug, folder.lastPathComponent]);
        return nil;
    }
    return charter;
}

+ (nullable instancetype)storedUnder:(NSString *)root
                           forAnchor:(NSString *)anchor
                                kind:(CSRegistryKind)kind
                              folder:(NSString **)outFolder {
    NSArray<NSString *> *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]
                                  sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        NSString *folder = [root stringByAppendingPathComponent:name];
        if (![[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:CSCharterFile]]) {
            continue;
        }
        NSError *readError = nil;
        CSCharter *charter = [self storedInFolder:folder kind:kind error:&readError];
        if (!charter) {
            NSLog(@"[CSCharter] the charter stored in %@ is not used: %@", folder, readError.localizedDescription);
            continue;
        }
        if ([charter.anchor isEqualToString:anchor]) {
            if (outFolder) *outFolder = folder;
            return charter;
        }
    }
    return nil;
}

@end

@implementation CSFetchedCharter

- (instancetype)initWithCharter:(CSCharter *)charter body:(NSData *)body signature:(NSData *)signature {
    self = [super init];
    if (self) {
        _charter = charter;
        _body = [body copy];
        _signature = [signature copy];
    }
    return self;
}

/// One file under the anchor, fetched synchronously.
+ (nullable NSData *)fetch:(NSString *)url
                    anchor:(NSString *)anchor
                 cacheBust:(long long)cacheBust
                   session:(NSURLSession *)session
                     error:(NSError **)error {
    NSURL *requestURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?cb=%lld", url, cacheBust]];
    if (!requestURL) {
        CSCharterFail(error, CSCharterErrorUnreachable, [NSString stringWithFormat:@"cannot reach %@: not a URL", url]);
        return nil;
    }
    __block NSData *data = nil;
    __block NSURLResponse *response = nil;
    __block NSError *netError = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session dataTaskWithURL:requestURL completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d;
        response = r;
        netError = e;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (netError || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
        CSCharterFail(error, CSCharterErrorUnreachable,
                      [NSString stringWithFormat:@"cannot reach %@: %@", url, netError.localizedDescription ?: @"no HTTP response"]);
        return nil;
    }
    NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
    if (status == 404) {
        CSCharterFail(error, CSCharterErrorUnchartered,
                      [NSString stringWithFormat:@"%@ has no charter (%@ answered 404) — it is not a MachineFabric registry", anchor, url]);
        return nil;
    }
    if (status < 200 || status > 299) {
        CSCharterFail(error, CSCharterErrorHTTP, [NSString stringWithFormat:@"%@ answered HTTP %ld", url, (long)status]);
        return nil;
    }
    return data ?: [NSData data];
}

+ (nullable instancetype)fetchFromAnchor:(NSString *)anchor
                                    kind:(CSRegistryKind)kind
                                 session:(NSURLSession *)session
                                   error:(NSError **)error {
    long long cacheBust = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    NSData *body = [self fetch:[anchor stringByAppendingFormat:@"/%@", CSCharterFile]
                        anchor:anchor cacheBust:cacheBust session:session error:error];
    if (!body) return nil;
    NSData *signature = [self fetch:[anchor stringByAppendingFormat:@"/%@", CSCharterSigFile]
                             anchor:anchor cacheBust:cacheBust session:session error:error];
    if (!signature) return nil;
    NSError *readError = nil;
    CSCharter *charter = [CSCharter charterWithData:body error:&readError];
    NSString *refusal = nil;
    if (!charter) {
        refusal = readError.localizedDescription;
    } else if (![charter.anchor isEqualToString:anchor]) {
        refusal = [NSString stringWithFormat:@"it is the charter of %@", charter.anchor];
    } else if (charter.kind != kind) {
        refusal = [NSString stringWithFormat:@"it charters a %@ registry, not a %@ one",
                   CSRegistryKindName(charter.kind), CSRegistryKindName(kind)];
    }
    if (refusal) {
        CSCharterFail(error, CSCharterErrorRefused,
                      [NSString stringWithFormat:@"the charter of %@ was refused: %@", anchor, refusal]);
        return nil;
    }
    return [[CSFetchedCharter alloc] initWithCharter:charter body:body signature:signature];
}

- (BOOL)storeInFolder:(NSString *)folder error:(NSError **)error {
    if (![folder.lastPathComponent isEqualToString:self.charter.slug]) {
        return CSCharterFail(error, CSCharterErrorRefused,
                             [NSString stringWithFormat:@"the charter of %@ names slug '%@' and cannot be stored in a folder named '%@'",
                              self.charter.anchor, self.charter.slug, folder.lastPathComponent]);
    }
    if (![[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    return CSWriteAtomic([folder stringByAppendingPathComponent:CSCharterFile], self.body, error)
        && CSWriteAtomic([folder stringByAppendingPathComponent:CSCharterSigFile], self.signature, error);
}

@end
