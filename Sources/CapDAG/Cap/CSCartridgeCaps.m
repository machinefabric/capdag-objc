//
//  CSCartridgeCaps.m
//

#import "CSCartridgeCaps.h"

@interface CSCartridgeCaps ()
@property (nonatomic, strong) NSMutableArray<CSCap *> *mutableCaps;
@end

@implementation CSCartridgeCaps

+ (instancetype)new {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableCaps = [NSMutableArray array];
    }
    return self;
}

- (NSArray<CSCap *> *)caps {
    return [self.mutableCaps copy];
}

- (void)addCap:(CSCap *)cap {
    if (cap) {
        [self.mutableCaps addObject:cap];
    }
}

- (NSArray<NSString *> *)capUrns {
    NSMutableArray<NSString *> *urns = [NSMutableArray arrayWithCapacity:self.mutableCaps.count];
    for (CSCap *cap in self.mutableCaps) {
        [urns addObject:[cap urnString]];
    }
    return urns;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"CSCartridgeCaps(count: %lu, caps: %@)",
            (unsigned long)self.mutableCaps.count, self.caps];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCartridgeCaps class]]) return NO;
    CSCartridgeCaps *other = (CSCartridgeCaps *)object;
    return [self.caps isEqualToArray:other.caps];
}

- (NSUInteger)hash {
    return [self.caps hash];
}

- (id)copyWithZone:(NSZone *)zone {
    CSCartridgeCaps *copy = [[CSCartridgeCaps allocWithZone:zone] init];
    copy.mutableCaps = [self.mutableCaps mutableCopy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.caps forKey:@"caps"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (!self) return nil;
    NSArray<CSCap *> *caps = [coder decodeObjectOfClass:[NSArray class] forKey:@"caps"];
    _mutableCaps = caps ? [caps mutableCopy] : [NSMutableArray array];
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end
