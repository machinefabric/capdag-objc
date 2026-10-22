//
//  CSDim.m
//  CapDAG
//
//  Fabric dims. Mirrors capdag-rs `fabric/dim.rs`.
//

#import "CSDim.h"

NSErrorDomain const CSDimErrorDomain = @"CSDimError";

static NSError *CSDimError(CSDimErrorCode code, NSString *message) {
    return [NSError errorWithDomain:CSDimErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// A key `dictionary` carries that `known` does not list is a fabric newer
/// than this capdag; it is refused, named. (Rust `deny_unknown_fields`.)
static BOOL CSDimRefuseUnknownKeys(NSDictionary *dictionary, NSArray<NSString *> *known, NSString *what,
                                   NSError **error) {
    NSMutableArray<NSString *> *unknown = [NSMutableArray array];
    for (id key in dictionary) {
        if (![key isKindOfClass:[NSString class]] || ![known containsObject:key]) {
            [unknown addObject:[key description]];
        }
    }
    if (unknown.count == 0) return YES;
    [unknown sortUsingSelector:@selector(compare:)];
    if (error) {
        *error = CSDimError(CSDimErrorUnknownField, [NSString stringWithFormat:
            @"%@ carries field(s) this capdag does not know: %@ — the definition comes from a fabric newer than this capdag; the contract is %@",
            what, [unknown componentsJoinedByString:@", "],
            [[known sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]]);
    }
    return NO;
}

/// A required string field, present and a string.
static NSString *_Nullable CSDimRequireString(NSDictionary *dictionary, NSString *key, NSString *what, NSError **error) {
    id field = dictionary[key];
    if (![field isKindOfClass:[NSString class]]) {
        if (error) {
            *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:
                @"%@: '%@' is %@", what, key, field ? @"not a string" : @"missing"]);
        }
        return nil;
    }
    return field;
}

/// An optional string field: absent is nil, present must be a string.
static BOOL CSDimOptionalString(NSDictionary *dictionary, NSString *key, NSString *what,
                                NSString *_Nullable *_Nonnull out, NSError **error) {
    id field = dictionary[key];
    if (field == nil) { *out = nil; return YES; }
    if (![field isKindOfClass:[NSString class]]) {
        if (error) {
            *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:@"%@: '%@' is not a string", what, key]);
        }
        return NO;
    }
    *out = field;
    return YES;
}

static BOOL CSDimIsBoolean(id value) {
    return [value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

BOOL CSIsDimName(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return NO;
    unichar first = [name characterAtIndex:0];
    if (!(first >= 'a' && first <= 'z')) return NO;
    for (NSUInteger i = 1; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')) return NO;
    }
    return YES;
}

// MARK: - CSDimRef

@implementation CSDimRef

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)refWithDim:(NSString *)dim value:(NSString *)value {
    CSDimRef *ref = [[CSDimRef alloc] init];
    ref->_dim = [dim copy];
    ref->_value = [value copy];
    return ref;
}

+ (nullable instancetype)refWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CSDimError(CSDimErrorMalformed, @"a dims entry is an object {\"dim\", \"value\"}");
        return nil;
    }
    if (!CSDimRefuseUnknownKeys(dictionary, @[@"dim", @"value"], @"dims entry", error)) return nil;
    NSString *dim = CSDimRequireString(dictionary, @"dim", @"dims entry", error);
    if (!dim) return nil;
    NSString *value = CSDimRequireString(dictionary, @"value", @"dims entry", error);
    if (!value) return nil;
    return [self refWithDim:dim value:value];
}

+ (nullable NSArray<CSDimRef *> *)refsFromField:(nullable id)field owner:(NSString *)owner error:(NSError **)error {
    if (field == nil) return @[];
    if (![field isKindOfClass:[NSArray class]]) {
        if (error) *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:@"%@ dims: 'dims' is a list of entries", owner]);
        return nil;
    }
    NSMutableArray<CSDimRef *> *refs = [NSMutableArray array];
    for (id entry in (NSArray *)field) {
        NSError *entryError = nil;
        CSDimRef *ref = [self refWithDictionary:entry error:&entryError];
        if (!ref) {
            if (error) *error = CSDimError((CSDimErrorCode)entryError.code, [NSString stringWithFormat:
                @"%@ dims: %@", owner, entryError.localizedDescription]);
            return nil;
        }
        [refs addObject:ref];
    }
    NSError *checkError = nil;
    if (!CSCheckDimRefs(refs, &checkError)) {
        if (error) *error = CSDimError(CSDimErrorInvalidRefs, [NSString stringWithFormat:
            @"%@ dims: %@", owner, checkError.localizedDescription]);
        return nil;
    }
    return [refs copy];
}

- (NSDictionary<NSString *, NSString *> *)toDictionary {
    return @{@"dim": self.dim, @"value": self.value};
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)dictionariesFromRefs:(NSArray<CSDimRef *> *)refs {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:refs.count];
    for (CSDimRef *ref in refs) {
        [out addObject:[ref toDictionary]];
    }
    return [out copy];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSDimRef class]]) return NO;
    CSDimRef *other = object;
    return [self.dim isEqualToString:other.dim] && [self.value isEqualToString:other.value];
}

- (NSUInteger)hash {
    return self.dim.hash ^ (self.value.hash << 1);
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@=%@", self.dim, self.value];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.dim forKey:@"dim"];
    [coder encodeObject:self.value forKey:@"value"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *dim = [coder decodeObjectOfClass:[NSString class] forKey:@"dim"];
    NSString *value = [coder decodeObjectOfClass:[NSString class] forKey:@"value"];
    if (!dim || !value) return nil;
    self = [super init];
    if (self) {
        _dim = [dim copy];
        _value = [value copy];
    }
    return self;
}

@end

BOOL CSCheckDimRefs(NSArray<CSDimRef *> *refs, NSError **error) {
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (CSDimRef *ref in refs) {
        NSString *message = nil;
        if (!CSIsDimName(ref.dim)) {
            message = [NSString stringWithFormat:@"'%@' is not a dim name", ref.dim];
        } else if (ref.value.length == 0) {
            message = [NSString stringWithFormat:@"dim '%@' is named without a value", ref.dim];
        } else if ([seen containsObject:ref.dim]) {
            message = [NSString stringWithFormat:@"dim '%@' is named more than once", ref.dim];
        }
        if (message) {
            if (error) *error = CSDimError(CSDimErrorInvalidRefs, message);
            return NO;
        }
        [seen addObject:ref.dim];
    }
    return YES;
}

// MARK: - CSDimTag

@implementation CSDimTag

+ (instancetype)tagWithKey:(NSString *)key value:(NSString *)value {
    CSDimTag *tag = [[CSDimTag alloc] init];
    tag->_key = [key copy];
    tag->_value = [value copy];
    return tag;
}

+ (nullable instancetype)tagWithDictionary:(id)dictionary what:(NSString *)what error:(NSError **)error {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:@"%@: a tag is an object {\"key\", \"value\"}", what]);
        return nil;
    }
    if (!CSDimRefuseUnknownKeys(dictionary, @[@"key", @"value"], [what stringByAppendingString:@" tag"], error)) return nil;
    NSString *key = CSDimRequireString(dictionary, @"key", [what stringByAppendingString:@" tag"], error);
    if (!key) return nil;
    NSString *value = CSDimRequireString(dictionary, @"value", [what stringByAppendingString:@" tag"], error);
    if (!value) return nil;
    return [self tagWithKey:key value:value];
}

- (NSDictionary<NSString *, NSString *> *)toDictionary {
    return @{@"key": self.key, @"value": self.value};
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSDimTag class]]) return NO;
    CSDimTag *other = object;
    return [self.key isEqualToString:other.key] && [self.value isEqualToString:other.value];
}

- (NSUInteger)hash {
    return self.key.hash ^ (self.value.hash << 1);
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

// MARK: - CSStoredDimValue

@implementation CSStoredDimValue

+ (instancetype)valueWithName:(NSString *)name
                        title:(NSString *)title
                         tags:(NSArray<CSDimTag *> *)tags
                documentation:(nullable NSString *)documentation
                    mediaType:(nullable NSString *)mediaType
                   extensions:(NSArray<NSString *> *)extensions {
    CSStoredDimValue *v = [[CSStoredDimValue alloc] init];
    v->_name = [name copy];
    v->_title = [title copy];
    v->_tags = [tags copy];
    v->_documentation = [documentation copy];
    v->_mediaType = [mediaType copy];
    v->_extensions = [extensions copy] ?: @[];
    return v;
}

+ (nullable instancetype)valueWithDictionary:(id)dictionary dim:(NSString *)dimName error:(NSError **)error {
    NSString *what = [NSString stringWithFormat:@"dim '%@' value", dimName];
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:@"%@: a value is an object", what]);
        return nil;
    }
    if (!CSDimRefuseUnknownKeys(dictionary, @[@"name", @"title", @"tags", @"documentation", @"media_type", @"extensions"],
                                what, error)) return nil;
    NSString *name = CSDimRequireString(dictionary, @"name", what, error);
    if (!name) return nil;
    what = [NSString stringWithFormat:@"dim '%@' value '%@'", dimName, name];
    NSString *title = CSDimRequireString(dictionary, @"title", what, error);
    if (!title) return nil;
    id tagsField = dictionary[@"tags"];
    if (![tagsField isKindOfClass:[NSArray class]]) {
        if (error) *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:
            @"%@: 'tags' is %@", what, tagsField ? @"not a list" : @"missing"]);
        return nil;
    }
    NSMutableArray<CSDimTag *> *tags = [NSMutableArray array];
    for (id tagDict in (NSArray *)tagsField) {
        CSDimTag *tag = [CSDimTag tagWithDictionary:tagDict what:what error:error];
        if (!tag) return nil;
        [tags addObject:tag];
    }
    NSString *documentation = nil;
    if (!CSDimOptionalString(dictionary, @"documentation", what, &documentation, error)) return nil;
    NSString *mediaType = nil;
    if (!CSDimOptionalString(dictionary, @"media_type", what, &mediaType, error)) return nil;
    NSArray<NSString *> *extensions = @[];
    id extensionsField = dictionary[@"extensions"];
    if (extensionsField != nil) {
        if (![extensionsField isKindOfClass:[NSArray class]]) {
            if (error) *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:@"%@: 'extensions' is not a list", what]);
            return nil;
        }
        for (id ext in (NSArray *)extensionsField) {
            if (![ext isKindOfClass:[NSString class]]) {
                if (error) *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:@"%@: an extension is a string", what]);
                return nil;
            }
        }
        extensions = extensionsField;
    }
    return [self valueWithName:name title:title tags:tags documentation:documentation mediaType:mediaType extensions:extensions];
}

- (NSDictionary<NSString *, id> *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"name"] = self.name;
    dict[@"title"] = self.title;
    NSMutableArray *tags = [NSMutableArray arrayWithCapacity:self.tags.count];
    for (CSDimTag *tag in self.tags) {
        [tags addObject:[tag toDictionary]];
    }
    dict[@"tags"] = tags;
    if (self.documentation) dict[@"documentation"] = self.documentation;
    if (self.mediaType) dict[@"media_type"] = self.mediaType;
    if (self.extensions.count > 0) dict[@"extensions"] = self.extensions;
    return [dict copy];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSStoredDimValue class]]) return NO;
    return [[self toDictionary] isEqualToDictionary:[object toDictionary]];
}

- (NSUInteger)hash {
    return self.name.hash;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

// MARK: - CSStoredDim

@implementation CSStoredDim

+ (instancetype)dimWithName:(NSString *)name
                    version:(uint32_t)version
                      title:(NSString *)title
              documentation:(NSString *)documentation
                     values:(NSArray<CSStoredDimValue *> *)values {
    CSStoredDim *dim = [[CSStoredDim alloc] init];
    dim->_name = [name copy];
    dim->_version = version;
    dim->_title = [title copy];
    dim->_documentation = [documentation copy];
    dim->_values = [values copy];
    return dim;
}

+ (nullable instancetype)dimWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CSDimError(CSDimErrorMalformed, @"a dim body is an object");
        return nil;
    }
    if (!CSDimRefuseUnknownKeys(dictionary, @[@"name", @"version", @"title", @"documentation", @"values"],
                                @"dim", error)) return nil;
    NSString *name = CSDimRequireString(dictionary, @"name", @"dim", error);
    if (!name) return nil;
    NSString *what = [NSString stringWithFormat:@"dim '%@'", name];
    id versionField = dictionary[@"version"];
    if (![versionField isKindOfClass:[NSNumber class]] || CSDimIsBoolean(versionField)
        || [versionField doubleValue] != floor([versionField doubleValue])
        || [versionField doubleValue] < 0 || [versionField doubleValue] > UINT32_MAX) {
        if (error) *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:
            @"%@: 'version' is %@", what, versionField ? @"not a non-negative integer" : @"missing"]);
        return nil;
    }
    NSString *title = CSDimRequireString(dictionary, @"title", what, error);
    if (!title) return nil;
    NSString *documentation = CSDimRequireString(dictionary, @"documentation", what, error);
    if (!documentation) return nil;
    id valuesField = dictionary[@"values"];
    if (![valuesField isKindOfClass:[NSArray class]]) {
        if (error) *error = CSDimError(CSDimErrorMalformed, [NSString stringWithFormat:
            @"%@: 'values' is %@", what, valuesField ? @"not a list" : @"missing"]);
        return nil;
    }
    NSMutableArray<CSStoredDimValue *> *values = [NSMutableArray array];
    for (id valueDict in (NSArray *)valuesField) {
        CSStoredDimValue *value = [CSStoredDimValue valueWithDictionary:valueDict dim:name error:error];
        if (!value) return nil;
        [values addObject:value];
    }
    return [self dimWithName:name
                     version:(uint32_t)[versionField unsignedLongLongValue]
                       title:title
               documentation:documentation
                      values:values];
}

- (NSDictionary<NSString *, id> *)toDictionary {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:self.values.count];
    for (CSStoredDimValue *value in self.values) {
        [values addObject:[value toDictionary]];
    }
    return @{
        @"name": self.name,
        @"version": @(self.version),
        @"title": self.title,
        @"documentation": self.documentation,
        @"values": values,
    };
}

- (nullable CSStoredDimValue *)valueNamed:(NSString *)name {
    for (CSStoredDimValue *value in self.values) {
        if ([value.name isEqualToString:name]) return value;
    }
    return nil;
}

- (BOOL)validate:(NSError **)error {
    if (!CSIsDimName(self.name)) {
        if (error) *error = CSDimError(CSDimErrorInvalidName, [NSString stringWithFormat:
            @"dim name '%@' is not a dim name (lowercase letters, digits and '-', starting with a letter)", self.name]);
        return NO;
    }
    if (self.values.count == 0) {
        if (error) *error = CSDimError(CSDimErrorNoValues, [NSString stringWithFormat:@"dim '%@' declares no values", self.name]);
        return NO;
    }
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (CSStoredDimValue *value in self.values) {
        if ([seen containsObject:value.name]) {
            if (error) *error = CSDimError(CSDimErrorDuplicateValue, [NSString stringWithFormat:
                @"dim '%@' declares value '%@' more than once", self.name, value.name]);
            return NO;
        }
        [seen addObject:value.name];
        if (value.tags.count == 0) {
            if (error) *error = CSDimError(CSDimErrorValueWithoutTags, [NSString stringWithFormat:
                @"dim '%@' value '%@' contributes no tag", self.name, value.name]);
            return NO;
        }
    }
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSStoredDim class]]) return NO;
    return [[self toDictionary] isEqualToDictionary:[object toDictionary]];
}

- (NSUInteger)hash {
    return self.name.hash ^ self.version;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end
