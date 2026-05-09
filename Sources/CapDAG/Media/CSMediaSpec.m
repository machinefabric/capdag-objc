//
//  CSMediaSpec.m
//  MediaSpec parsing and handling
//

#import "CSMediaSpec.h"
#import "CSCapUrn.h"
#import "CSCap.h"
#import "CSMediaUrn.h"
#import "CSFabricRegistry.h"
@import TaggedUrn;

NSErrorDomain const CSMediaSpecErrorDomain = @"CSMediaSpecErrorDomain";

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

NSString * const CSMediaString = @"media:textable";
NSString * const CSMediaInteger = @"media:integer;textable;numeric";
NSString * const CSMediaNumber = @"media:textable;numeric";
NSString * const CSMediaBoolean = @"media:bool;textable";
NSString * const CSMediaObject = @"media:record";
NSString * const CSMediaList = @"media:list";
NSString * const CSMediaTextableList = @"media:list;textable";
NSString * const CSMediaStringList = @"media:list;textable";
NSString * const CSMediaIntegerList = @"media:integer;list;textable;numeric";
NSString * const CSMediaNumberList = @"media:list;numeric;textable";
NSString * const CSMediaBooleanList = @"media:bool;list;textable";
NSString * const CSMediaObjectList = @"media:list;record";
NSString * const CSMediaIdentity = @"media:";
NSString * const CSMediaVoid = @"media:void";
// Semantic content types
NSString * const CSMediaPng = @"media:image;png";
NSString * const CSMediaImage = @"media:image;png"; // alias for CSMediaPng
NSString * const CSMediaJpeg = @"media:jpeg;image";
NSString * const CSMediaGif = @"media:gif;image";
NSString * const CSMediaBmp = @"media:bmp;image";
NSString * const CSMediaTiff = @"media:tiff;image";
NSString * const CSMediaWebp = @"media:webp;image";
NSString * const CSMediaAudio = @"media:wav;audio";
NSString * const CSMediaWav = @"media:wav;audio"; // alias for CSMediaAudio
NSString * const CSMediaMp3 = @"media:mp3;audio";
NSString * const CSMediaFlac = @"media:flac;audio";
NSString * const CSMediaOgg = @"media:ogg;audio";
NSString * const CSMediaAac = @"media:aac;audio";
NSString * const CSMediaM4a = @"media:m4a;audio";
NSString * const CSMediaAiff = @"media:aiff;audio";
NSString * const CSMediaOpus = @"media:opus;audio";
NSString * const CSMediaVideo = @"media:video";
NSString * const CSMediaMp4 = @"media:mp4;video";
NSString * const CSMediaMov = @"media:mov;video";
NSString * const CSMediaWebm = @"media:webm;video";
NSString * const CSMediaMkv = @"media:mkv;video";
// Semantic AI input types
NSString * const CSMediaAudioSpeech = @"media:audio;wav;speech";
NSString * const CSMediaTextablePage = @"media:textable;page";
// Document types (PRIMARY naming - type IS the format)
NSString * const CSMediaPdf = @"media:pdf";
NSString * const CSMediaEpub = @"media:epub";
// Text format types (PRIMARY naming - type IS the format)
NSString * const CSMediaMd = @"media:md;textable";
NSString * const CSMediaTxt = @"media:txt;textable";
NSString * const CSMediaRst = @"media:rst;textable";
NSString * const CSMediaLog = @"media:log;textable";
NSString * const CSMediaHtml = @"media:html;textable";
NSString * const CSMediaXml = @"media:xml;textable";
NSString * const CSMediaJson = @"media:json;record;textable";
NSString * const CSMediaJsonSchema = @"media:json;json-schema;record;textable";
NSString * const CSMediaYaml = @"media:record;textable;yaml";
// Semantic input types
NSString * const CSMediaModelSpec = @"media:model-spec;textable";
NSString * const CSMediaModelRepo = @"media:model-repo;record;textable";
NSString * const CSMediaHfToken = @"media:hf-token;secret;textable";
NSString * const CSMediaModelArchList = @"media:model-arch-list;json;record;textable";
NSString * const CSMediaModelSearchRequest = @"media:model-search-request;json;record;textable";
NSString * const CSMediaModelSearchResponse = @"media:model-search-response;json;record;textable";
NSString * const CSMediaModelFilterResolution = @"media:model-filter-resolution;json;record;textable";
// Backend-narrowed model-spec supertypes
NSString * const CSMediaModelSpecCandle = @"media:candle;model-spec;textable";
NSString * const CSMediaModelSpecGguf = @"media:gguf;model-spec;textable";
NSString * const CSMediaModelSpecMlx = @"media:mlx;model-spec;textable";
// Backend+use-case specific model-spec variants
NSString * const CSMediaModelSpecGgufVision = @"media:model-spec;gguf;textable;vision";
NSString * const CSMediaModelSpecGgufLlm = @"media:model-spec;gguf;textable;llm";
NSString * const CSMediaModelSpecGgufEmbeddings = @"media:model-spec;gguf;textable;embeddings";
NSString * const CSMediaModelSpecMlxVision = @"media:model-spec;mlx;textable;vision";
NSString * const CSMediaModelSpecMlxLlm = @"media:model-spec;mlx;textable;llm";
NSString * const CSMediaModelSpecMlxEmbeddings = @"media:model-spec;mlx;textable;embeddings";
NSString * const CSMediaModelSpecCandleVision = @"media:model-spec;candle;textable;vision";
NSString * const CSMediaModelSpecCandleEmbeddings = @"media:model-spec;candle;textable;embeddings";
NSString * const CSMediaModelSpecCandleImageEmbeddings = @"media:model-spec;candle;image-embeddings;textable";
NSString * const CSMediaModelSpecCandleTranscription = @"media:model-spec;candle;textable;transcription";
// File path type — single URN; cardinality lives on is_sequence.
NSString * const CSMediaFilePath = @"media:file-path;textable";
// Semantic input types (continued)
NSString * const CSMediaMlxModelPath = @"media:mlx-model-path;textable";
// Semantic output types
NSString * const CSMediaImageDescription = @"media:image-description;textable";
NSString * const CSMediaModelDim = @"media:integer;model-dim;numeric;textable";
NSString * const CSMediaDownloadOutput = @"media:download-result;record;textable";
NSString * const CSMediaListOutput = @"media:model-list;record;textable";
NSString * const CSMediaStatusOutput = @"media:model-status;record;textable";
NSString * const CSMediaContentsOutput = @"media:model-contents;record;textable";
NSString * const CSMediaAvailabilityOutput = @"media:model-availability;record;textable";
NSString * const CSMediaPathOutput = @"media:model-path;record;textable";
NSString * const CSMediaEmbeddingVector = @"media:embedding-vector;record;textable";
NSString * const CSMediaLlmInferenceOutput = @"media:generated-text;record;textable";
NSString * const CSMediaCaptionOutput = @"media:image-caption;record;textable";
NSString * const CSMediaTranscriptionOutput = @"media:record;textable;transcription";
NSString * const CSMediaDecision = @"media:decision;json;record;textable";
NSString * const CSMediaAdapterSelection = @"media:adapter-selection;json;record";
// Fabric registry lookup wire types
NSString * const CSMediaCapUrn = @"media:cap-urn;textable";
NSString * const CSMediaMediaUrn = @"media:media-urn;textable";
NSString * const CSMediaCapDefinition = @"media:cap-definition;json;record;textable";
NSString * const CSMediaMediaSpecDefinition = @"media:media-spec-definition;json;record;textable";
// Fabric lookup caps (implemented by netaccesscartridge)
NSString * const CSCapLookupCapFabric =
    @"cap:in=\"media:cap-urn;textable\";fabric;lookup-cap;out=\"media:cap-definition;json;record;textable\"";
NSString * const CSCapLookupMediaSpecFabric =
    @"cap:in=\"media:media-urn;textable\";fabric;lookup-media-spec;out=\"media:media-spec-definition;json;record;textable\"";
// Format-specific variants for JSON, YAML, CSV
NSString * const CSMediaJsonValue = @"media:json;textable";
NSString * const CSMediaJsonRecord = @"media:json;record;textable";
NSString * const CSMediaJsonList = @"media:json;list;textable";
NSString * const CSMediaJsonListRecord = @"media:json;list;record;textable";
NSString * const CSMediaYamlValue = @"media:textable;yaml";
NSString * const CSMediaYamlRecord = @"media:record;textable;yaml";
NSString * const CSMediaYamlList = @"media:list;textable;yaml";
NSString * const CSMediaYamlListRecord = @"media:list;record;textable;yaml";
NSString * const CSMediaCsv = @"media:csv;list;record;textable";
NSString * const CSMediaCsvList = @"media:csv;list;record;textable";

// ============================================================================
// SCHEMA URL CONFIGURATION
// ============================================================================

static NSString * const CSDefaultSchemaBase = @"https://capdag.com/schema";

/**
 * Get the schema base URL from environment variables or default
 *
 * Checks in order:
 * 1. CAPDAG_SCHEMA_BASE_URL environment variable
 * 2. CAPDAG_REGISTRY_URL environment variable + "/schema"
 * 3. Default: "https://capdag.com/schema"
 */
NSString *CSGetSchemaBaseURL(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSString *schemaURL = env[@"CAPDAG_SCHEMA_BASE_URL"];
    if (schemaURL.length > 0) {
        return schemaURL;
    }

    NSString *registryURL = env[@"CAPDAG_REGISTRY_URL"];
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
// MEDIA SPEC IMPLEMENTATION
// ============================================================================

@interface CSMediaSpec ()
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
                    format:@"Failed to parse media URN '%@': %@ - this indicates the CSMediaSpec was not resolved via CSResolveMediaUrn", mediaUrn, error.localizedDescription];
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
                    format:@"Failed to parse media URN '%@': %@ - this indicates the CSMediaSpec was not resolved via CSResolveMediaUrn", mediaUrn, error.localizedDescription];
    }
    NSString *value = [parsed getTag:tagName];
    return value != nil && [value isEqualToString:@"*"];
}

/// Public function to check if a media URN represents binary data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsBinary(NSString *mediaUrn) {
    return !CSMediaUrnHasTag(mediaUrn, @"textable");
}

/// Public function to check if a media URN represents text data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsText(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"textable");
}

/// Public function to check if a media URN represents JSON data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsJson(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"json");
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

@implementation CSMediaSpec

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
    CSMediaSpec *spec = [[CSMediaSpec alloc] init];
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

- (BOOL)isBinary {
    return !CSMediaUrnHasTag(self.mediaUrn, @"textable");
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
    return CSMediaUrnHasTag(self.mediaUrn, @"json");
}

- (BOOL)isText {
    return CSMediaUrnHasTag(self.mediaUrn, @"textable");
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

CSMediaSpec * _Nullable CSResolveMediaUrn(NSString *mediaUrn,
                                          CSFabricRegistry *registry,
                                          NSError * _Nullable * _Nullable error) {
    if (!registry) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorUnresolvableMediaUrn
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Cannot resolve media URN '%@': no registry provided", mediaUrn]}];
        }
        return nil;
    }

    NSDictionary *def = [registry getCachedMediaSpec:mediaUrn];
    if (!def) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorUnresolvableMediaUrn
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
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorUnresolvableMediaUrn
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Media URN '%@' has invalid spec: missing media_type", mediaUrn]}];
        }
        return nil;
    }

    CSMediaSpec *spec = [CSMediaSpec withContentType:mediaType
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

@implementation CSMediaSpec (CapUrn)

+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn
                           registry:(CSFabricRegistry *)registry
                              error:(NSError * _Nullable * _Nullable)error {
    NSString *mediaUrn = [capUrn getOutSpec];

    if (!mediaUrn) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorUnresolvableMediaUrn
                                     userInfo:@{NSLocalizedDescriptionKey: @"no 'out' media URN found in cap URN"}];
        }
        return nil;
    }

    return CSResolveMediaUrn(mediaUrn, registry, error);
}

@end
