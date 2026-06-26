//
//  CSMediaDef.h
//  MediaDef parsing and handling
//
//  Parses media_def values in the canonical format:
//  `<media-type>; profile=<url>`
//
//  Examples:
//  - `application/json; profile="https://capdag.com/schema/document-outline"`
//  - `image/png; profile="https://capdag.com/schema/thumbnail-image"`
//  - `text/plain; profile=https://capdag.com/schema/str`
//
//  NOTE: The legacy "content-type:" prefix is NO LONGER SUPPORTED and will cause a hard failure.
//

#import <Foundation/Foundation.h>
#import "CSMediaUrn.h"

@class CSCapUrn;
@class CSMediaValidation;
@class CSFabricRegistry;

NS_ASSUME_NONNULL_BEGIN

/// Error domain for MediaDef errors
FOUNDATION_EXPORT NSErrorDomain const CSMediaDefErrorDomain;

/// Error codes for MediaDef operations
typedef NS_ERROR_ENUM(CSMediaDefErrorDomain, CSMediaDefError) {
    CSMediaDefErrorUnresolvableMediaUrn = 1,
};

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

/// Well-known built-in media URNs with coercion tags - these do not need to be declared in mediaDefs
FOUNDATION_EXPORT NSString * const CSMediaString;       // media:enc=utf-8
FOUNDATION_EXPORT NSString * const CSMediaInteger;      // media:integer;numeric
FOUNDATION_EXPORT NSString * const CSMediaNumber;       // media:numeric
FOUNDATION_EXPORT NSString * const CSMediaBoolean;      // media:bool;enc=utf-8
FOUNDATION_EXPORT NSString * const CSMediaObject;       // media:record
FOUNDATION_EXPORT NSString * const CSMediaList;          // media:list
FOUNDATION_EXPORT NSString * const CSMediaStringList;    // media:enc=utf-8;list
FOUNDATION_EXPORT NSString * const CSMediaIntegerList;   // media:integer;list;numeric
FOUNDATION_EXPORT NSString * const CSMediaNumberList;    // media:list;numeric
FOUNDATION_EXPORT NSString * const CSMediaBooleanList;   // media:bool;enc=utf-8;list
FOUNDATION_EXPORT NSString * const CSMediaObjectList;    // media:list;record
FOUNDATION_EXPORT NSString * const CSMediaIdentity;       // media:
FOUNDATION_EXPORT NSString * const CSMediaVoid;         // media:void
// Semantic content types
FOUNDATION_EXPORT NSString * const CSMediaPng;          // media:ext=png;image
FOUNDATION_EXPORT NSString * const CSMediaImage;        // media:ext=png;image (alias for CSMediaPng)
FOUNDATION_EXPORT NSString * const CSMediaJpeg;         // media:ext=jpeg;image
FOUNDATION_EXPORT NSString * const CSMediaGif;          // media:ext=gif;image
FOUNDATION_EXPORT NSString * const CSMediaBmp;          // media:ext=bmp;image
FOUNDATION_EXPORT NSString * const CSMediaTiff;         // media:ext=tiff;image
FOUNDATION_EXPORT NSString * const CSMediaWebp;         // media:ext=webp;image
FOUNDATION_EXPORT NSString * const CSMediaAudio;        // media:audio;ext=wav
FOUNDATION_EXPORT NSString * const CSMediaWav;          // media:audio;ext=wav (alias for CSMediaAudio)
FOUNDATION_EXPORT NSString * const CSMediaMp3;          // media:audio;ext=mp3
FOUNDATION_EXPORT NSString * const CSMediaFlac;         // media:audio;ext=flac
FOUNDATION_EXPORT NSString * const CSMediaOgg;          // media:audio;ext=ogg
FOUNDATION_EXPORT NSString * const CSMediaAac;          // media:audio;ext=aac
FOUNDATION_EXPORT NSString * const CSMediaM4a;          // media:audio;ext=m4a
FOUNDATION_EXPORT NSString * const CSMediaAiff;         // media:audio;ext=aiff
FOUNDATION_EXPORT NSString * const CSMediaOpus;         // media:audio;ext=opus
FOUNDATION_EXPORT NSString * const CSMediaVideo;        // media:video
FOUNDATION_EXPORT NSString * const CSMediaMp4;          // media:ext=mp4;video
FOUNDATION_EXPORT NSString * const CSMediaMov;          // media:ext=mov;video
FOUNDATION_EXPORT NSString * const CSMediaWebm;         // media:ext=webm;video
FOUNDATION_EXPORT NSString * const CSMediaMkv;          // media:ext=mkv;video
// Semantic AI input types
FOUNDATION_EXPORT NSString * const CSMediaAudioSpeech;           // media:audio;ext=wav;speech
FOUNDATION_EXPORT NSString * const CSMediaTextablePage;          // media:enc=utf-8;ext=txt;page;plain-text
// Document types (PRIMARY naming - type IS the format)
FOUNDATION_EXPORT NSString * const CSMediaPdf;          // media:ext=pdf
FOUNDATION_EXPORT NSString * const CSMediaEpub;         // media:ext=epub
// Text format types (PRIMARY naming - type IS the format)
FOUNDATION_EXPORT NSString * const CSMediaMd;           // media:enc=utf-8;ext=md
FOUNDATION_EXPORT NSString * const CSMediaTxt;          // media:enc=utf-8;ext=txt
FOUNDATION_EXPORT NSString * const CSMediaRst;          // media:enc=utf-8;ext=rst
FOUNDATION_EXPORT NSString * const CSMediaLog;          // media:enc=utf-8;ext=log
FOUNDATION_EXPORT NSString * const CSMediaHtml;         // media:enc=utf-8;ext=html
FOUNDATION_EXPORT NSString * const CSMediaXml;          // media:enc=utf-8;ext=xml
FOUNDATION_EXPORT NSString * const CSMediaJson;         // media:fmt=json;record
FOUNDATION_EXPORT NSString * const CSMediaJsonSchema;   // media:fmt=json;json-schema;record
FOUNDATION_EXPORT NSString * const CSMediaYaml;         // media:fmt=yaml;record
// Semantic input types
FOUNDATION_EXPORT NSString * const CSMediaModelSpec;    // media:enc=utf-8;model-spec (generic, modelcartridge)
FOUNDATION_EXPORT NSString * const CSMediaModelRepo;    // media:enc=utf-8;model-repo;record
FOUNDATION_EXPORT NSString * const CSMediaHfToken;      // media:enc=utf-8;hf-token;secret
FOUNDATION_EXPORT NSString * const CSMediaModelArchList;          // media:fmt=json;model-arch-list;record
FOUNDATION_EXPORT NSString * const CSMediaModelSearchRequest;     // media:fmt=json;model-search-request;record
FOUNDATION_EXPORT NSString * const CSMediaModelSearchResponse;    // media:fmt=json;model-search-response;record
FOUNDATION_EXPORT NSString * const CSMediaModelFilterResolution;  // media:fmt=json;model-filter-resolution;record
// Backend-narrowed model-spec supertypes (each backend's adapter
// handler returns one of these to claim a model-spec text input as
// its backend's). Narrower than CSMediaModelSpec; broader than the
// per-task variants below.
FOUNDATION_EXPORT NSString * const CSMediaModelSpecCandle;             // media:candle;enc=utf-8;model-spec
FOUNDATION_EXPORT NSString * const CSMediaModelSpecGguf;               // media:enc=utf-8;gguf;model-spec
FOUNDATION_EXPORT NSString * const CSMediaModelSpecMlx;                // media:enc=utf-8;mlx;model-spec
// Backend+use-case specific model-spec variants
FOUNDATION_EXPORT NSString * const CSMediaModelSpecGgufVision;         // media:enc=utf-8;gguf;model-spec;vision
FOUNDATION_EXPORT NSString * const CSMediaModelSpecGgufLlm;            // media:enc=utf-8;gguf;llm;model-spec
FOUNDATION_EXPORT NSString * const CSMediaModelSpecGgufEmbeddings;     // media:embeddings;enc=utf-8;gguf;model-spec
FOUNDATION_EXPORT NSString * const CSMediaModelSpecMlxVision;          // media:enc=utf-8;mlx;model-spec;vision
FOUNDATION_EXPORT NSString * const CSMediaModelSpecMlxLlm;             // media:enc=utf-8;llm;mlx;model-spec
FOUNDATION_EXPORT NSString * const CSMediaModelSpecMlxEmbeddings;      // media:embeddings;enc=utf-8;mlx;model-spec
FOUNDATION_EXPORT NSString * const CSMediaModelSpecCandleVision;       // media:candle;enc=utf-8;model-spec;vision
FOUNDATION_EXPORT NSString * const CSMediaModelSpecCandleEmbeddings;   // media:candle;embeddings;enc=utf-8;model-spec
FOUNDATION_EXPORT NSString * const CSMediaModelSpecCandleImageEmbeddings; // media:candle;enc=utf-8;image-embeddings;model-spec
FOUNDATION_EXPORT NSString * const CSMediaModelSpecCandleTranscription; // media:candle;enc=utf-8;model-spec;transcription
// File path type — single URN; cardinality lives on is_sequence.
FOUNDATION_EXPORT NSString * const CSMediaFilePath;     // media:enc=utf-8;file-path
// Semantic input types (continued)
FOUNDATION_EXPORT NSString * const CSMediaMlxModelPath;    // media:enc=utf-8;mlx-model-path
// Semantic output types
FOUNDATION_EXPORT NSString * const CSMediaImageDescription;   // media:enc=utf-8;ext=txt;image-description;plain-text
FOUNDATION_EXPORT NSString * const CSMediaModelDim;        // media:integer;model-dim;numeric
FOUNDATION_EXPORT NSString * const CSMediaDownloadOutput;  // media:download-result;enc=utf-8;record
FOUNDATION_EXPORT NSString * const CSMediaListOutput;      // media:enc=utf-8;model-list;record
FOUNDATION_EXPORT NSString * const CSMediaStatusOutput;    // media:enc=utf-8;model-status;record
FOUNDATION_EXPORT NSString * const CSMediaContentsOutput;  // media:enc=utf-8;model-contents;record
FOUNDATION_EXPORT NSString * const CSMediaAvailabilityOutput; // media:enc=utf-8;model-availability;record
FOUNDATION_EXPORT NSString * const CSMediaPathOutput;      // media:enc=utf-8;model-path;record
FOUNDATION_EXPORT NSString * const CSMediaEmbeddingVector; // media:embedding-vector;enc=utf-8;record
FOUNDATION_EXPORT NSString * const CSMediaCaptionOutput;   // media:enc=utf-8;image-caption;record
// Canonical input/output of cap:save-as-txt — finalised plain text bound to
// the `.txt` extension. See fabric/media/plain-text.toml.
FOUNDATION_EXPORT NSString * const CSMediaPlainText;       // media:enc=utf-8;ext=txt;plain-text
FOUNDATION_EXPORT NSString * const CSMediaTranscriptionOutput; // media:enc=utf-8;record;transcription
FOUNDATION_EXPORT NSString * const CSMediaDecision;        // media:decision;fmt=json;record
FOUNDATION_EXPORT NSString * const CSMediaAdapterSelection; // media:adapter-selection;fmt=json;record
// Fabric registry lookup wire types (consumed/produced by cap:lookup-cap;fabric
// and cap:lookup-media-def;fabric, both implemented by fetchcartridge).
FOUNDATION_EXPORT NSString * const CSMediaCapUrn;            // media:cap-urn;enc=utf-8
FOUNDATION_EXPORT NSString * const CSMediaMediaUrn;          // media:enc=utf-8;media-urn
FOUNDATION_EXPORT NSString * const CSMediaCapDefinition;     // media:cap-definition;fmt=json;record
FOUNDATION_EXPORT NSString * const CSMediaMediaDefinition; // media:fmt=json;media-definition;record
FOUNDATION_EXPORT NSString * const CSMediaFabricDefver; // media:defver;enc=utf-8
// Format-specific variants for JSON, YAML, CSV
FOUNDATION_EXPORT NSString * const CSMediaJsonValue;       // media:fmt=json
FOUNDATION_EXPORT NSString * const CSMediaJsonRecord;      // media:fmt=json;record
FOUNDATION_EXPORT NSString * const CSMediaJsonList;        // media:fmt=json;list
FOUNDATION_EXPORT NSString * const CSMediaJsonListRecord;  // media:fmt=json;list;record
FOUNDATION_EXPORT NSString * const CSMediaYamlValue;       // media:fmt=yaml
FOUNDATION_EXPORT NSString * const CSMediaYamlRecord;      // media:fmt=yaml;record
FOUNDATION_EXPORT NSString * const CSMediaYamlList;        // media:fmt=yaml;list
FOUNDATION_EXPORT NSString * const CSMediaYamlListRecord;  // media:fmt=yaml;list;record
FOUNDATION_EXPORT NSString * const CSMediaCsv;             // media:fmt=csv;list;record
FOUNDATION_EXPORT NSString * const CSMediaCsvList;         // media:fmt=csv;list;record

// ============================================================================
// STANDARD CAP URN CONSTANTS
// ============================================================================

/// Standard echo capability URN
/// Accepts any media type as input and outputs any media type
FOUNDATION_EXPORT NSString * const CSCapIdentity;           // cap:effect=none

/// Fabric registry lookup caps. Implemented by fetchcartridge.
/// `CSCapLookupCapFabric` resolves a canonical cap URN to its full
/// flattened cap definition; `CSCapLookupMediaDefFabric` does the same
/// for media defs. Both fetch from the public fabric registry with a
/// two-level cache (memory + disk + 1-week TTL).
FOUNDATION_EXPORT NSString * const CSCapLookupCapFabric;
FOUNDATION_EXPORT NSString * const CSCapLookupMediaDefFabric;

// ============================================================================
// SCHEMA URL CONFIGURATION
// ============================================================================

/**
 * Get the schema base URL from environment variables or default
 *
 * Checks in order:
 * 1. CDG_SCHEMA_BASE_URL environment variable
 * 2. CDG_FABRIC_REGISTRY_URL environment variable + "/schema"
 * 3. Default: "https://capdag.com/schema"
 */
FOUNDATION_EXPORT NSString *CSGetSchemaBaseURL(void);

/**
 * Get a profile URL for the given profile name
 *
 * @param profileName The profile name (e.g., "string", "integer")
 * @return The full profile URL
 */
FOUNDATION_EXPORT NSString *CSGetProfileURL(NSString *profileName);

// ============================================================================
// MEDIA DEFINITION PARSING
// ============================================================================

/**
 * A resolved MediaDef value
 */
@interface CSMediaDef : NSObject

/// The media URN identifier (e.g., "media:pdf")
@property (nonatomic, readonly, nullable) NSString *mediaUrn;

/// The MIME content type (e.g., "application/json", "image/png")
@property (nonatomic, readonly) NSString *contentType;

/// Optional profile URL
@property (nonatomic, readonly, nullable) NSString *profile;

/// Optional JSON Schema for local validation
@property (nonatomic, readonly, nullable) NSDictionary *schema;

/// Optional display-friendly title
@property (nonatomic, readonly, nullable) NSString *title;

/// Optional description
@property (nonatomic, readonly, nullable) NSString *descriptionText;

/// Optional long-form markdown documentation.
///
/// Rendered in media info panels, the cap navigator, capdag-dot-com,
/// and anywhere else a rich-text explanation of the media def is
/// useful. Authored as a triple-quoted literal string in the source
/// TOML so newlines and markdown punctuation pass through unchanged.
@property (nonatomic, readonly, nullable) NSString *documentation;

/// Optional validation rules (inherent to the semantic type)
@property (nonatomic, readonly, nullable) CSMediaValidation *validation;

/// Optional metadata (arbitrary key-value pairs for display/categorization)
@property (nonatomic, readonly, nullable) NSDictionary *metadata;

/// File extensions for storing this media type (e.g., @[@"pdf"], @[@"jpg", @"jpeg"])
@property (nonatomic, readonly) NSArray<NSString *> *extensions;

/**
 * Create a MediaDef with all properties
 * @param contentType The MIME content type
 * @param profile Optional profile URL
 * @param schema Optional JSON Schema for local validation
 * @param title Optional display-friendly title
 * @param descriptionText Optional description
 * @param documentation Optional long-form markdown documentation
 * @param validation Optional validation rules
 * @param metadata Optional metadata dictionary
 * @param extensions File extensions for storing this media type (can be empty array)
 * @return A new CSMediaDef instance
 */
+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText
                  documentation:(nullable NSString *)documentation
                     validation:(nullable CSMediaValidation *)validation
                       metadata:(nullable NSDictionary *)metadata
                     extensions:(NSArray<NSString *> *)extensions;

/**
 * Create a MediaDef from content type, optional profile, and optional schema
 * @param contentType The MIME content type
 * @param profile Optional profile URL
 * @param schema Optional JSON Schema for local validation
 * @return A new CSMediaDef instance
 */
+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema;

/**
 * Create a MediaDef from content type and optional profile (no schema)
 * @param contentType The MIME content type
 * @param profile Optional profile URL
 * @return A new CSMediaDef instance
 */
+ (instancetype)withContentType:(NSString *)contentType profile:(nullable NSString *)profile;

/**
 * Check if this media def represents a record (has record marker tag)
 * A record has internal key-value structure (e.g., JSON object).
 * @return YES if record marker tag is present
 */
- (BOOL)isRecord;

/**
 * Check if this media def is opaque (no record marker tag)
 * Opaque is the default structure - no internal fields recognized.
 * @return YES if opaque (no record marker)
 */
- (BOOL)isOpaque;

/**
 * Check if this media def represents a scalar value (no list marker tag)
 * Scalar is the default cardinality.
 * @return YES if scalar (no list marker)
 */
- (BOOL)isScalar;

/**
 * Check if this media def represents a list/array structure (has list marker tag)
 * @return YES if list marker tag is present
 */
- (BOOL)isList;

/**
 * Check if this media def represents JSON content (carries `fmt=json`).
 * Note: This only checks for the explicit JSON content-format tag.
 * For checking if data is structured (map/list), use isStructured.
 * @return YES if the fmt=json content-format tag is present
 */
- (BOOL)isJSON;

/**
 * Get the primary type (e.g., "image" from "image/png")
 * @return The primary type
 */
- (NSString *)primaryType;

/**
 * Get the subtype (e.g., "png" from "image/png")
 * @return The subtype or nil if not present
 */
- (nullable NSString *)subtype;

/**
 * Get the canonical string representation
 * Format: <media-type>; profile="<url>" (no content-type: prefix)
 * @return The media_def as a string
 */
- (NSString *)toString;

@end

// ============================================================================
// MEDIA URN RESOLUTION
// ============================================================================

/**
 * Resolve a media URN to a MediaDef
 *
 * Resolution algorithm:
 * 1. Iterate mediaDefs array and find by URN
 * 2. If not found: FAIL HARD
 *
 * @param mediaUrn The media URN (e.g., "media:enc=utf-8")
 * @param registry The unified `CSFabricRegistry` to resolve through.
 *   The registry's in-memory media-def cache is the only source —
 *   there is no inline-spec fallback.
 * @param error Error if media URN cannot be resolved
 * @return The resolved MediaDef or nil on error
 */
CSMediaDef * _Nullable CSResolveMediaUrn(NSString *mediaUrn,
                                          CSFabricRegistry *registry,
                                          NSError * _Nullable * _Nullable error);

/**
 * Check if a media URN is text-representable by checking for the `enc=`
 * encoding tag. Replaces the old textable-based text/binary distinction:
 * everything is bytes at the wire level, and text is the orthogonal `enc=`
 * axis. This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN carries an enc= tag
 */
BOOL CSMediaUrnHasEncoding(NSString *mediaUrn);

/**
 * Check if a media URN represents JSON content by checking for the `fmt=json`
 * content-format tag. This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN carries fmt=json
 */
BOOL CSMediaUrnIsJson(NSString *mediaUrn);

/**
 * Check if a media URN represents a list/array (has list marker tag).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has list marker tag
 */
BOOL CSMediaUrnIsList(NSString *mediaUrn);

/**
 * Check if a media URN represents a record (has record marker tag).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has record marker tag
 */
BOOL CSMediaUrnIsRecord(NSString *mediaUrn);

/**
 * Check if a media URN is opaque (no record marker tag).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has no record marker (opaque is default)
 */
BOOL CSMediaUrnIsOpaque(NSString *mediaUrn);

/**
 * Check if a media URN represents a scalar value (no list marker tag).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has no list marker (scalar is default)
 */
BOOL CSMediaUrnIsScalar(NSString *mediaUrn);

/**
 * Check if a media URN represents image data by checking for 'image' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'image' marker tag
 */
BOOL CSMediaUrnIsImage(NSString *mediaUrn);

/**
 * Check if a media URN represents audio data by checking for 'audio' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'audio' marker tag
 */
BOOL CSMediaUrnIsAudio(NSString *mediaUrn);

/**
 * Check if a media URN represents video data by checking for 'video' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'video' marker tag
 */
BOOL CSMediaUrnIsVideo(NSString *mediaUrn);

/**
 * Check if a media URN represents numeric data by checking for 'numeric' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'numeric' marker tag
 */
BOOL CSMediaUrnIsNumeric(NSString *mediaUrn);

/**
 * Check if a media URN represents boolean data by checking for 'bool' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'bool' marker tag
 */
BOOL CSMediaUrnIsBool(NSString *mediaUrn);

/**
 * Check if a media URN represents a file path (has file-path marker tag).
 * This is a pure syntax check - no resolution required.
 * Cardinality (single file vs many) is carried by is_sequence, not URN tags.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'file-path' marker tag
 */
BOOL CSMediaUrnIsFilePath(NSString *mediaUrn);

/**
 * Check if a media URN represents a model specification (has model-spec marker).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'model-spec' marker tag
 */
BOOL CSMediaUrnIsModelSpec(NSString *mediaUrn);

/**
 * Helper functions for working with MediaDef in CapUrn
 */
@interface CSMediaDef (CapUrn)

/**
 * Extract MediaDef from a CapUrn's 'out' tag (a media URN), resolved
 * through the unified `CSFabricRegistry`.
 * @param capUrn The cap URN to extract from
 * @param registry The unified `CSFabricRegistry`
 * @param error Error if media URN not found or resolution fails
 * @return The resolved MediaDef or nil if not found
 */
+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn
                           registry:(CSFabricRegistry *)registry
                              error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
