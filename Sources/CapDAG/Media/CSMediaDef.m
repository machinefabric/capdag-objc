//
//  CSMediaDef.m
//  MediaDef parsing and handling
//

#import "CSMediaDef.h"
#import "CSCapUrn.h"
#import "CSCap.h"
#import "CSMediaUrn.h"
#import "CSFabricRegistry.h"
@import TaggedUrn;

NSErrorDomain const CSMediaDefErrorDomain = @"CSMediaDefErrorDomain";

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

NSString * const CSMediaString = @"media:enc=utf-8";
NSString * const CSMediaInteger = @"media:integer;numeric";
NSString * const CSMediaNumber = @"media:numeric";
NSString * const CSMediaBoolean = @"media:bool;enc=utf-8";
NSString * const CSMediaObject = @"media:record";
NSString * const CSMediaList = @"media:list";
NSString * const CSMediaStringList = @"media:enc=utf-8;list";
NSString * const CSMediaIntegerList = @"media:integer;list;numeric";
NSString * const CSMediaNumberList = @"media:list;numeric";
NSString * const CSMediaBooleanList = @"media:bool;enc=utf-8;list";
NSString * const CSMediaObjectList = @"media:list;record";
NSString * const CSMediaIdentity = @"media:";
NSString * const CSMediaVoid = @"media:void";
// Semantic content types
NSString * const CSMediaPng = @"media:ext=png;image";
NSString * const CSMediaImage = @"media:ext=png;image"; // alias for CSMediaPng
NSString * const CSMediaJpeg = @"media:ext=jpeg;image";
NSString * const CSMediaGif = @"media:ext=gif;image";
NSString * const CSMediaBmp = @"media:ext=bmp;image";
NSString * const CSMediaTiff = @"media:ext=tiff;image";
NSString * const CSMediaWebp = @"media:ext=webp;image";
NSString * const CSMediaAudio = @"media:audio;ext=wav";
NSString * const CSMediaWav = @"media:audio;ext=wav"; // alias for CSMediaAudio
NSString * const CSMediaMp3 = @"media:audio;ext=mp3";
NSString * const CSMediaFlac = @"media:audio;ext=flac";
NSString * const CSMediaOgg = @"media:audio;ext=ogg";
NSString * const CSMediaAac = @"media:audio;ext=aac";
NSString * const CSMediaM4a = @"media:audio;ext=m4a";
NSString * const CSMediaAiff = @"media:audio;ext=aiff";
NSString * const CSMediaOpus = @"media:audio;ext=opus";
NSString * const CSMediaVideo = @"media:video";
NSString * const CSMediaMp4 = @"media:ext=mp4;video";
NSString * const CSMediaMov = @"media:ext=mov;video";
NSString * const CSMediaWebm = @"media:ext=webm;video";
NSString * const CSMediaMkv = @"media:ext=mkv;video";
// Semantic AI input types
NSString * const CSMediaAudioSpeech = @"media:audio;ext=wav;speech";
NSString * const CSMediaTextablePage = @"media:enc=utf-8;ext=txt;page;plain-text";
// Document types (PRIMARY naming - type IS the format)
NSString * const CSMediaPdf = @"media:ext=pdf";
NSString * const CSMediaEpub = @"media:ext=epub";
// Text format types (PRIMARY naming - type IS the format)
NSString * const CSMediaMd = @"media:enc=utf-8;ext=md";
NSString * const CSMediaTxt = @"media:enc=utf-8;ext=txt";
NSString * const CSMediaRst = @"media:enc=utf-8;ext=rst";
NSString * const CSMediaLog = @"media:enc=utf-8;ext=log";
NSString * const CSMediaHtml = @"media:enc=utf-8;ext=html";
NSString * const CSMediaXml = @"media:enc=utf-8;ext=xml";
NSString * const CSMediaJson = @"media:fmt=json;record";
NSString * const CSMediaJsonSchema = @"media:fmt=json;json-schema;record";
NSString * const CSMediaYaml = @"media:fmt=yaml;record";
// Semantic input types
NSString * const CSMediaModelSpec = @"media:enc=utf-8;model-spec";
NSString * const CSMediaModelRepo = @"media:enc=utf-8;model-repo;record";
NSString * const CSMediaHfToken = @"media:enc=utf-8;hf-token;secret";
NSString * const CSMediaModelArchList = @"media:fmt=json;model-arch-list;record";
NSString * const CSMediaModelSearchRequest = @"media:fmt=json;model-search-request;record";
NSString * const CSMediaModelSearchResponse = @"media:fmt=json;model-search-response;record";
NSString * const CSMediaModelFilterResolution = @"media:fmt=json;model-filter-resolution;record";
// Backend-narrowed model-spec supertypes
NSString * const CSMediaModelSpecCandle = @"media:candle;enc=utf-8;model-spec";
NSString * const CSMediaModelSpecGguf = @"media:enc=utf-8;gguf;model-spec";
NSString * const CSMediaModelSpecMlx = @"media:enc=utf-8;mlx;model-spec";
// Backend+use-case specific model-spec variants
NSString * const CSMediaModelSpecGgufVision = @"media:enc=utf-8;gguf;model-spec;vision";
NSString * const CSMediaModelSpecGgufLlm = @"media:enc=utf-8;gguf;llm;model-spec";
NSString * const CSMediaModelSpecGgufEmbeddings = @"media:embeddings;enc=utf-8;gguf;model-spec";
NSString * const CSMediaModelSpecMlxVision = @"media:enc=utf-8;mlx;model-spec;vision";
NSString * const CSMediaModelSpecMlxLlm = @"media:enc=utf-8;llm;mlx;model-spec";
NSString * const CSMediaModelSpecMlxEmbeddings = @"media:embeddings;enc=utf-8;mlx;model-spec";
NSString * const CSMediaModelSpecCandleVision = @"media:candle;enc=utf-8;model-spec;vision";
NSString * const CSMediaModelSpecCandleEmbeddings = @"media:candle;embeddings;enc=utf-8;model-spec";
NSString * const CSMediaModelSpecCandleImageEmbeddings = @"media:candle;enc=utf-8;image-embeddings;model-spec";
NSString * const CSMediaModelSpecCandleTranscription = @"media:candle;enc=utf-8;model-spec;transcription";
// File path type — single URN; cardinality lives on is_sequence.
NSString * const CSMediaFilePath = @"media:enc=utf-8;file-path";
// Semantic input types (continued)
NSString * const CSMediaMlxModelPath = @"media:enc=utf-8;mlx-model-path";
// Semantic output types
NSString * const CSMediaImageDescription = @"media:enc=utf-8;ext=txt;image-description;plain-text";
NSString * const CSMediaModelDim = @"media:integer;model-dim;numeric";
NSString * const CSMediaDownloadOutput = @"media:download-result;enc=utf-8;record";
NSString * const CSMediaListOutput = @"media:enc=utf-8;model-list;record";
NSString * const CSMediaStatusOutput = @"media:enc=utf-8;model-status;record";
NSString * const CSMediaContentsOutput = @"media:enc=utf-8;model-contents;record";
NSString * const CSMediaAvailabilityOutput = @"media:enc=utf-8;model-availability;record";
NSString * const CSMediaPathOutput = @"media:enc=utf-8;model-path;record";
NSString * const CSMediaEmbeddingVector = @"media:embedding-vector;enc=utf-8;record";
NSString * const CSMediaCaptionOutput = @"media:enc=utf-8;image-caption;record";
NSString * const CSMediaPlainText = @"media:enc=utf-8;ext=txt;plain-text";
NSString * const CSMediaTranscriptionOutput = @"media:enc=utf-8;record;transcription";
NSString * const CSMediaDecision = @"media:decision;fmt=json;record";
NSString * const CSMediaAdapterSelection = @"media:adapter-selection;fmt=json;record";
// Fabric registry lookup wire types
NSString * const CSMediaCapUrn = @"media:cap-urn;enc=utf-8";
NSString * const CSMediaMediaUrn = @"media:enc=utf-8;media-urn";
NSString * const CSMediaCapDefinition = @"media:cap-definition;fmt=json;record";
NSString * const CSMediaMediaDefinition = @"media:fmt=json;media-definition;record";
// Fabric registry per-definition version (defver). Carried as data alongside a
// URN when a cap looks up a definition pinned to a specific manifest snapshot.
// Absent ⇒ defver 0 (legacy v0 flat-path lookup).
NSString * const CSMediaFabricDefver = @"media:defver;enc=utf-8";
// Fabric lookup caps (implemented by fetchcartridge)
NSString * const CSCapLookupCapFabric =
    @"cap:in=\"media:cap-urn;enc=utf-8\";fabric;lookup-cap;out=\"media:cap-definition;fmt=json;record\"";
NSString * const CSCapLookupMediaDefFabric =
    @"cap:in=\"media:enc=utf-8;media-urn\";fabric;lookup-media-def;out=\"media:fmt=json;media-definition;record\"";
// Format-specific variants for JSON, YAML, CSV
NSString * const CSMediaJsonValue = @"media:fmt=json";
NSString * const CSMediaJsonRecord = @"media:fmt=json;record";
NSString * const CSMediaJsonList = @"media:fmt=json;list";
NSString * const CSMediaJsonListRecord = @"media:fmt=json;list;record";
NSString * const CSMediaYamlValue = @"media:fmt=yaml";
NSString * const CSMediaYamlRecord = @"media:fmt=yaml;record";
NSString * const CSMediaYamlList = @"media:fmt=yaml;list";
NSString * const CSMediaYamlListRecord = @"media:fmt=yaml;list;record";
NSString * const CSMediaCsv = @"media:fmt=csv;list;record";
NSString * const CSMediaCsvList = @"media:fmt=csv;list;record";

// ============================================================================
// SCHEMA URL CONFIGURATION
// ============================================================================

static NSString * const CSDefaultSchemaBase = @"https://capdag.com/schema";

/**
 * Get the schema base URL from environment variables or default
 *
 * Checks in order:
 * 1. CDG_SCHEMA_BASE_URL environment variable
 * 2. CDG_FABRIC_REGISTRY_URL environment variable + "/schema"
 * 3. Default: "https://capdag.com/schema"
 */
NSString *CSGetSchemaBaseURL(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSString *schemaURL = env[@"CDG_SCHEMA_BASE_URL"];
    if (schemaURL.length > 0) {
        return schemaURL;
    }

    NSString *registryURL = env[@"CDG_FABRIC_REGISTRY_URL"];
    if (registryURL.length > 0) {
        return [registryURL stringByAppendingString:@"/schema"];
    }

    return CSDefaultSchemaBase;
}

/**
 * Get a profile URL for the given profile name
 *
 * @param profileName The profile name (e.g., "string", "integer")
 * @return The full profile URL
 */
NSString *CSGetProfileURL(NSString *profileName) {
    return [NSString stringWithFormat:@"%@/%@", CSGetSchemaBaseURL(), profileName];
}

// ============================================================================
// BUILTIN MEDIA URN DEFINITIONS
// ============================================================================

// ============================================================================
// MEDIA DEFINITION IMPLEMENTATION
// ============================================================================

@interface CSMediaDef ()
@property (nonatomic, readwrite) NSString *contentType;
@property (nonatomic, readwrite, nullable) NSString *profile;
@property (nonatomic, readwrite, nullable) NSDictionary *schema;
@property (nonatomic, readwrite, nullable) NSString *title;
@property (nonatomic, readwrite, nullable) NSString *descriptionText;
@property (nonatomic, readwrite, nullable) NSString *documentation;
@property (nonatomic, readwrite, nullable) NSString *mediaUrn;
@property (nonatomic, readwrite, nullable) CSMediaValidation *validation;
@property (nonatomic, readwrite, nullable) NSDictionary *metadata;
@property (nonatomic, readwrite) NSArray<NSString *> *extensions;
@end

/// Helper to check if a media URN has a marker tag using CSTaggedUrn.
/// Requires a valid, non-empty media URN - fails hard otherwise.
/// Nil/empty/whitespace validation is handled by CSTaggedUrn.
static BOOL CSMediaUrnHasTag(NSString *mediaUrn, NSString *tagName) {
    NSError *error = nil;
    CSTaggedUrn *parsed = [CSTaggedUrn fromString:mediaUrn error:&error];
    if (parsed == nil || error != nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Failed to parse media URN '%@': %@ - this indicates the CSMediaDef was not resolved via CSResolveMediaUrn", mediaUrn, error.localizedDescription];
    }
    return [parsed getTag:tagName] != nil;
}

/// Helper to check if a media URN has a marker tag (tag value is "*").
/// Requires a valid, non-empty media URN - fails hard otherwise.
/// Nil/empty/whitespace validation is handled by CSTaggedUrn.
static BOOL CSMediaUrnHasMarkerTag(NSString *mediaUrn, NSString *tagName) {
    NSError *error = nil;
    CSTaggedUrn *parsed = [CSTaggedUrn fromString:mediaUrn error:&error];
    if (parsed == nil || error != nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Failed to parse media URN '%@': %@ - this indicates the CSMediaDef was not resolved via CSResolveMediaUrn", mediaUrn, error.localizedDescription];
    }
    NSString *value = [parsed getTag:tagName];
    return value != nil && [value isEqualToString:@"*"];
}

/// Helper to read a tag's value (nil if absent) from a media URN string.
/// Requires a valid, non-empty media URN - fails hard otherwise.
static NSString * _Nullable CSMediaUrnTagValue(NSString *mediaUrn, NSString *tagName) {
    NSError *error = nil;
    CSTaggedUrn *parsed = [CSTaggedUrn fromString:mediaUrn error:&error];
    if (parsed == nil || error != nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Failed to parse media URN '%@': %@ - this indicates the CSMediaDef was not resolved via CSResolveMediaUrn", mediaUrn, error.localizedDescription];
    }
    return [parsed getTag:tagName];
}

/// Public function to check if a media URN is text-representable, i.e. it
/// declares a character encoding via the `enc=` tag. Replaces the old
/// textable-based text/binary distinction (everything is bytes at the wire
/// level; text is the orthogonal `enc=` axis).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnHasEncoding(NSString *mediaUrn) {
    return CSMediaUrnTagValue(mediaUrn, @"enc") != nil;
}

/// Public function to check if a media URN represents JSON content
/// (carries the `fmt=json` content-format tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsJson(NSString *mediaUrn) {
    return [CSMediaUrnTagValue(mediaUrn, @"fmt") isEqualToString:@"json"];
}

/// Public function to check if a media URN represents a list (has list marker tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsList(NSString *mediaUrn) {
    return CSMediaUrnHasMarkerTag(mediaUrn, @"list");
}

/// Public function to check if a media URN represents a record (has record marker tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsRecord(NSString *mediaUrn) {
    return CSMediaUrnHasMarkerTag(mediaUrn, @"record");
}

/// Public function to check if a media URN is opaque (no record marker tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsOpaque(NSString *mediaUrn) {
    return !CSMediaUrnHasMarkerTag(mediaUrn, @"record");
}

/// Public function to check if a media URN represents a scalar (no list marker tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsScalar(NSString *mediaUrn) {
    return !CSMediaUrnHasMarkerTag(mediaUrn, @"list");
}

/// Public function to check if a media URN represents image data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsImage(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"image");
}

/// Public function to check if a media URN represents audio data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsAudio(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"audio");
}

/// Public function to check if a media URN represents video data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsVideo(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"video");
}

/// Public function to check if a media URN represents numeric data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsNumeric(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"numeric");
}

/// Public function to check if a media URN represents boolean data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsBool(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"bool");
}

/// Public function to check if a media URN represents a file path.
/// Cardinality (single file vs many) is carried by is_sequence, not URN tags.
BOOL CSMediaUrnIsFilePath(NSString *mediaUrn) {
    return CSMediaUrnHasMarkerTag(mediaUrn, @"file-path");
}

/// Public function to check if a media URN represents a model specification.
BOOL CSMediaUrnIsModelSpec(NSString *mediaUrn) {
    return CSMediaUrnHasMarkerTag(mediaUrn, @"model-spec");
}

@implementation CSMediaDef

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema {
    return [self withContentType:contentType profile:profile schema:schema title:nil descriptionText:nil];
}

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText {
    return [self withContentType:contentType profile:profile schema:schema title:title descriptionText:descriptionText validation:nil];
}

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText
                     validation:(nullable CSMediaValidation *)validation {
    return [self withContentType:contentType profile:profile schema:schema title:title descriptionText:descriptionText documentation:nil validation:validation metadata:nil extensions:@[]];
}

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText
                  documentation:(nullable NSString *)documentation
                     validation:(nullable CSMediaValidation *)validation
                       metadata:(nullable NSDictionary *)metadata
                     extensions:(NSArray<NSString *> *)extensions {
    CSMediaDef *spec = [[CSMediaDef alloc] init];
    spec.contentType = contentType;
    spec.profile = profile;
    spec.schema = schema;
    spec.title = title;
    spec.descriptionText = descriptionText;
    spec.documentation = documentation;
    spec.validation = validation;
    spec.metadata = metadata;
    spec.extensions = extensions ?: @[];
    return spec;
}

+ (instancetype)withContentType:(NSString *)contentType profile:(nullable NSString *)profile {
    return [self withContentType:contentType profile:profile schema:nil];
}

- (BOOL)isRecord {
    return CSMediaUrnHasMarkerTag(self.mediaUrn, @"record");
}

- (BOOL)isOpaque {
    return !CSMediaUrnHasMarkerTag(self.mediaUrn, @"record");
}

- (BOOL)isScalar {
    return !CSMediaUrnHasMarkerTag(self.mediaUrn, @"list");
}

- (BOOL)isList {
    return CSMediaUrnHasMarkerTag(self.mediaUrn, @"list");
}

- (BOOL)isJSON {
    return [CSMediaUrnTagValue(self.mediaUrn, @"fmt") isEqualToString:@"json"];
}

- (NSString *)primaryType {
    NSArray<NSString *> *parts = [self.contentType componentsSeparatedByString:@"/"];
    return [parts firstObject] ?: self.contentType;
}

- (nullable NSString *)subtype {
    NSArray<NSString *> *parts = [self.contentType componentsSeparatedByString:@"/"];
    if (parts.count > 1) {
        return parts[1];
    }
    return nil;
}

- (NSString *)toString {
    // Canonical format: <media-type>; profile="<url>" (no content-type: prefix)
    if (self.profile) {
        return [NSString stringWithFormat:@"%@; profile=\"%@\"", self.contentType, self.profile];
    }
    return self.contentType;
}

- (NSString *)description {
    return [self toString];
}

@end

// ============================================================================
// MEDIA URN RESOLUTION
// ============================================================================

CSMediaDef * _Nullable CSResolveMediaUrn(NSString *mediaUrn,
                                          CSFabricRegistry *registry,
                                          NSError * _Nullable * _Nullable error) {
    if (!registry) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaDefErrorDomain
                                         code:CSMediaDefErrorUnresolvableMediaUrn
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Cannot resolve media URN '%@': no registry provided", mediaUrn]}];
        }
        return nil;
    }

    NSDictionary *def = [registry getCachedMediaDef:mediaUrn];
    if (!def) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaDefErrorDomain
                                         code:CSMediaDefErrorUnresolvableMediaUrn
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Cannot resolve media URN '%@': not in registry cache", mediaUrn]}];
        }
        return nil;
    }

    NSString *mediaType = def[@"media_type"] ?: def[@"mediaType"];
    NSString *profileUri = def[@"profile_uri"] ?: def[@"profileUri"];
    NSDictionary *schema = def[@"schema"];
    NSString *title = def[@"title"];
    NSString *descriptionText = def[@"description"];

    NSString *documentation = nil;
    id documentationField = def[@"documentation"];
    if ([documentationField isKindOfClass:[NSString class]] && [(NSString *)documentationField length] > 0) {
        documentation = (NSString *)documentationField;
    }

    CSMediaValidation *validation = nil;
    NSDictionary *validationDict = def[@"validation"];
    if (validationDict && [validationDict isKindOfClass:[NSDictionary class]]) {
        NSError *validationError = nil;
        validation = [CSMediaValidation validationWithDictionary:validationDict error:&validationError];
    }

    NSDictionary *metadata = nil;
    id metadataValue = def[@"metadata"];
    if (metadataValue && [metadataValue isKindOfClass:[NSDictionary class]]) {
        metadata = (NSDictionary *)metadataValue;
    }

    NSArray<NSString *> *extensions = @[];
    id extensionsValue = def[@"extensions"];
    if (extensionsValue && [extensionsValue isKindOfClass:[NSArray class]]) {
        extensions = (NSArray<NSString *> *)extensionsValue;
    }

    if (!mediaType) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaDefErrorDomain
                                         code:CSMediaDefErrorUnresolvableMediaUrn
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Media URN '%@' has invalid spec: missing media_type", mediaUrn]}];
        }
        return nil;
    }

    CSMediaDef *spec = [CSMediaDef withContentType:mediaType
                                              profile:profileUri
                                               schema:schema
                                                title:title
                                      descriptionText:descriptionText
                                        documentation:documentation
                                           validation:validation
                                             metadata:metadata
                                           extensions:extensions];
    spec.mediaUrn = mediaUrn;
    return spec;
}

// ============================================================================
// CAP URN EXTENSION
// ============================================================================

@implementation CSMediaDef (CapUrn)

+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn
                           registry:(CSFabricRegistry *)registry
                              error:(NSError * _Nullable * _Nullable)error {
    NSString *mediaUrn = [capUrn getOutSpec];

    if (!mediaUrn) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaDefErrorDomain
                                         code:CSMediaDefErrorUnresolvableMediaUrn
                                     userInfo:@{NSLocalizedDescriptionKey: @"no 'out' media URN found in cap URN"}];
        }
        return nil;
    }

    return CSResolveMediaUrn(mediaUrn, registry, error);
}

@end
