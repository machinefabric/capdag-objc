//
//  CSDim.h
//  CapDAG
//
//  Fabric dims — the axes definitions are built along.
//
//  A dim (a language, a file type, a quantisation, …) is a fabric definition
//  like a cap, a media def or an alias: published on its own at
//  `dims/<sha256-of-name>/<defver>.json` and pinned by a manifest's `dims`
//  map. Its body says what the dim is and which values it may take, each with
//  its own documentation.
//
//  A cap or media definition names the dims it was built from, and the value
//  chosen from each, in its `dims` (`CSDimRef`). Its own `documentation` is
//  only what is specific to it; what a dim and a value mean is read from the
//  dim. A reader shows both.
//
//  Mirrors capdag-rs `fabric/dim.rs`.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for dim bodies and dim references this library cannot hold.
extern NSErrorDomain const CSDimErrorDomain;

typedef NS_ERROR_ENUM(CSDimErrorDomain, CSDimErrorCode) {
    /// A dim body, value, tag or reference is not the shape the schema says
    /// (a missing or mistyped field).
    CSDimErrorMalformed = 1,
    /// A dim body, value, tag or reference carries a field this capdag does
    /// not know (`deny_unknown_fields` in the reference).
    CSDimErrorUnknownField = 2,
    /// A dim name is not `^[a-z][a-z0-9-]*$`.
    CSDimErrorInvalidName = 3,
    /// A dim declares no values.
    CSDimErrorNoValues = 4,
    /// A dim declares one value name more than once.
    CSDimErrorDuplicateValue = 5,
    /// A dim value contributes no tag.
    CSDimErrorValueWithoutTags = 6,
    /// A definition's `dims` names a dim twice, names a non-dim, or names a
    /// dim without a value.
    CSDimErrorInvalidRefs = 7,
};

/// Whether `name` is a dim name: `^[a-z][a-z0-9-]*$`.
BOOL CSIsDimName(NSString *name);

/// One dim a definition was built from, and the value chosen from it. The
/// entries of a definition's `dims`, in the order its source references them.
///
/// Unknown fields are refused, as for arguments and outputs: a key this
/// library does not know would be dropped when the definition is written back
/// out, and the copy would no longer say what the registry said.
@interface CSDimRef : NSObject <NSCopying, NSSecureCoding>

/// The dim's name.
@property (nonatomic, readonly) NSString *dim;
/// The name of the value chosen from that dim.
@property (nonatomic, readonly) NSString *value;

+ (instancetype)refWithDim:(NSString *)dim value:(NSString *)value;

/// Parse one `{"dim","value"}` entry. Refuses a key this capdag does not know,
/// naming it, and a missing or non-string field.
+ (nullable instancetype)refWithDictionary:(NSDictionary *)dictionary
                                     error:(NSError *_Nullable *_Nullable)error;

/// Parse a definition's `dims` field: absent (`nil`) is no dims; otherwise an
/// array of entries, each parsed by `refWithDictionary:error:`, and the whole
/// held to `CSCheckDimRefs`. `owner` names the definition in errors.
+ (nullable NSArray<CSDimRef *> *)refsFromField:(nullable id)field
                                          owner:(NSString *)owner
                                          error:(NSError *_Nullable *_Nullable)error;

/// The wire form: `{"dim": …, "value": …}`.
- (NSDictionary<NSString *, NSString *> *)toDictionary;

/// The wire form of a list of references, in order.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)dictionariesFromRefs:(NSArray<CSDimRef *> *)refs;

@end

/// A definition's `dims` names each dim at most once, and only by dim and
/// value names. Returns NO and writes why not (naming the offending entry,
/// code `CSDimErrorInvalidRefs`) otherwise.
BOOL CSCheckDimRefs(NSArray<CSDimRef *> *refs, NSError *_Nullable *_Nullable error);

/// A tag a dim value contributes to the URN of every definition built with
/// it. `value` is `*` for a marker tag.
@interface CSDimTag : NSObject <NSCopying>
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) NSString *value;
+ (instancetype)tagWithKey:(NSString *)key value:(NSString *)value;
- (NSDictionary<NSString *, NSString *> *)toDictionary;
@end

/// One value a dim may take.
@interface CSStoredDimValue : NSObject <NSCopying>
/// The value's name, unique within the dim.
@property (nonatomic, readonly) NSString *name;
/// Display-friendly title of the value.
@property (nonatomic, readonly) NSString *title;
/// The tags the value contributes. At least one.
@property (nonatomic, readonly) NSArray<CSDimTag *> *tags;
/// Markdown documentation of what choosing this value means.
@property (nonatomic, readonly, nullable) NSString *documentation;
/// The MIME media type the value gives the media defs built with it.
@property (nonatomic, readonly, nullable) NSString *mediaType;
/// The file extensions the value gives the media defs built with it.
@property (nonatomic, readonly) NSArray<NSString *> *extensions;

+ (instancetype)valueWithName:(NSString *)name
                        title:(NSString *)title
                         tags:(NSArray<CSDimTag *> *)tags
                documentation:(nullable NSString *)documentation
                    mediaType:(nullable NSString *)mediaType
                   extensions:(NSArray<NSString *> *)extensions;
- (NSDictionary<NSString *, id> *)toDictionary;
@end

/// Stored dim definition. Mirrors `fabric/dim.schema.json` on the wire and is
/// the body cached at `dims/<sha256-of-name>/<defver>.json`.
@interface CSStoredDim : NSObject <NSCopying>
/// The dim's name, unique across the snapshot.
@property (nonatomic, readonly) NSString *name;
/// Per-definition version. Always >= 1 — dims exist only in the versioned
/// regime.
@property (nonatomic, readonly) uint32_t version;
/// Display-friendly title of the dim.
@property (nonatomic, readonly) NSString *title;
/// Markdown documentation of what the dim is.
@property (nonatomic, readonly) NSString *documentation;
/// The values the dim may take, in the order the dim declares them.
@property (nonatomic, readonly) NSArray<CSStoredDimValue *> *values;

+ (instancetype)dimWithName:(NSString *)name
                    version:(uint32_t)version
                      title:(NSString *)title
              documentation:(NSString *)documentation
                     values:(NSArray<CSStoredDimValue *> *)values;

/// Parse a dim body. Refuses a field this capdag does not know at any level,
/// naming it (`CSDimErrorUnknownField`), and a missing or mistyped field
/// (`CSDimErrorMalformed`). Does not `validate:` — see that method.
+ (nullable instancetype)dimWithDictionary:(NSDictionary *)dictionary
                                     error:(NSError *_Nullable *_Nullable)error;

/// The wire form, exactly as `dim.schema.json` has it (optional fields omitted
/// when absent or empty).
- (NSDictionary<NSString *, id> *)toDictionary;

/// The value named `name`, if the dim declares it.
- (nullable CSStoredDimValue *)valueNamed:(NSString *)name;

/// Hold the body to what `dim.schema.json` says beyond its field types: a dim
/// name, at least one value, value names unique, every value with a tag.
- (BOOL)validate:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
