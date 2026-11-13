//
//  CSFileMediaDetection.h
//  CapDAG
//
//  What a file is: the one detection every host runs.
//
//  A file's extension names the file media types the fabric declares for it
//  (its candidates: every definition of the pinned manifest that carries the
//  `ext=` file-type tag and lists the extension,
//  -[CSFabricRegistry fileMediaForExtension:completion:]). Its content decides
//  between them, by the proved model (capdag/formal/CapDAG/Detect.lean,
//  generated into the CapDAGFormalProgram target):
//
//  - a candidate whose definition declares validation rules the content fails
//    never stands;
//  - a candidate under a cartridge's content-inspection adapter stands only if
//    a consulted cartridge claims the file as it or as something more specific
//    (the adapter speaks for its whole domain);
//  - any other candidate stands if the content met rules it declares, or if it
//    is a base type of the extension: no other candidate is more general. A
//    refinement (digitized text of a `.txt`, a JSON record of a `.json`) is a
//    claim about the content, and an unproven claim is never made.
//
//  Of what stands, each line of refinement keeps only its most specific
//  member. A `list` tag stays: it says what the content is (a CSV file is a
//  list of records), never how many values are in transit. What is left is
//  what the file is; more than one is a genuine alternative a host may offer.
//  CSPrimaryMedia picks the one a host that cannot ask uses.
//
//  What this module does itself is the I/O the model is handed: reading the
//  content, evaluating each definition's rules against it, and asking the
//  cartridges.
//
//  Mirrors Rust: capdag/src/input_resolver/detection.rs
//

#import <Foundation/Foundation.h>

@class CSFabricRegistry;
@class CSMediaUrn;

NS_ASSUME_NONNULL_BEGIN

/// The most of a file's content that is read to tell what it is (100 KiB).
/// Mirrors Rust MAX_CONTENT_INSPECTION_BYTES.
FOUNDATION_EXPORT const NSUInteger CSMaxContentInspectionBytes;

#pragma mark - Cartridges

/// Asks one cartridge what a file is, through its adapter-selection cap. The
/// host implements it: it is the side that can reach the cartridges.
/// Mirrors Rust: trait CartridgeAdapterInvoker
@protocol CSCartridgeAdapterInvoker <NSObject>

/// Ask cartridge `cartridgeId` what the file at `filePath` is. The completion
/// gets the media URNs the cartridge claims the file as; nil claims and nil
/// error when the cartridge declines the file; an error when it cannot be
/// asked.
- (void)invokeAdapterSelectionForCartridge:(NSString *)cartridgeId
                                  filePath:(NSString *)filePath
                                completion:(void (^)(NSArray<NSString *> *_Nullable claims,
                                                     NSError *_Nullable error))completion;

@end

/// One cartridge's content-inspection adapter: the cartridge, and the media
/// URN its adapter speaks for.
@interface CSCartridgeAdapter : NSObject

@property (nonatomic, copy, readonly) NSString *cartridgeId;
@property (nonatomic, strong, readonly) CSMediaUrn *adapterUrn;

+ (instancetype)adapterWithCartridgeId:(NSString *)cartridgeId adapterUrn:(CSMediaUrn *)adapterUrn;

@end

/// Where a host's content-inspection adapters come from: which cartridges to
/// consult for a file whose candidates these are.
/// Mirrors Rust: trait AdapterSource
@protocol CSAdapterSource <NSObject>

- (NSArray<CSCartridgeAdapter *> *)adaptersForCandidates:(NSArray<CSMediaUrn *> *)candidates;

@end

/// A host with no content-inspection adapters. Mirrors Rust: NoAdapters
@interface CSNoAdapters : NSObject <CSAdapterSource>
@end

/// A host that asks no cartridge: it has none to ask. Being asked is a broken
/// invariant (a host with no adapters was asked to consult a cartridge), and
/// raises NSInternalInconsistencyException. Mirrors Rust: NoInvoker
@interface CSNoInvoker : NSObject <CSCartridgeAdapterInvoker>
@end

#pragma mark - What a file is

/// What a file is. Mirrors Rust: FileMedia
@interface CSFileMedia : NSObject

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, readonly) uint64_t sizeBytes;
/// The file's extension, lowercased.
@property (nonatomic, copy, readonly) NSString *extension;
/// Every file media type the fabric declares for the extension.
@property (nonatomic, copy, readonly) NSArray<NSString *> *candidates;
/// What the file is: one entry, or several genuine alternatives, in the
/// candidates' order. Never empty.
@property (nonatomic, copy, readonly) NSArray<NSString *> *media;

+ (instancetype)fileMediaWithPath:(NSString *)path
                        sizeBytes:(uint64_t)sizeBytes
                        extension:(NSString *)extension
                       candidates:(NSArray<NSString *> *)candidates
                            media:(NSArray<NSString *> *)media;

/// The one media a host that cannot ask uses (CSPrimaryMedia).
- (NSString *)primary;

@end

/// The one media a host that cannot ask uses: the most specific, the first of
/// them on a tie (the model's `primary`). nil with no error only for an empty
/// list; nil with `error` set when a member is no media URN, naming it.
/// Mirrors Rust: primary_media
NSString *_Nullable CSPrimaryMedia(NSArray<NSString *> *media, NSError *_Nullable *_Nullable error);

/// What a file is, by its extension and its content: the one detection every
/// host runs (see the top of this header). A host with no cartridges passes
/// CSNoAdapters and CSNoInvoker. The completion gets what the file is, or an
/// error in CSInputResolverErrorDomain: NoExtension, UnknownExtension (the
/// fabric declares no file type for the extension), FabricUnavailable (the
/// fabric's file types could not be loaded; the reason says why), NotFound,
/// PermissionDenied, IOError, or InspectionFailed (its content is none of the
/// candidates, a definition declares an invalid validation pattern, or a
/// definition has no valid URN).
///
/// This library has no value adapters (Rust's ValueAdapterRegistry): what
/// stands is kept as the fabric declares it, as the reference does with an
/// empty value adapter registry.
/// Mirrors Rust: detect_file_media
void CSDetectFileMedia(NSString *path,
                       CSFabricRegistry *registry,
                       id<CSAdapterSource> adapters,
                       id<CSCartridgeAdapterInvoker> invoker,
                       void (^completion)(CSFileMedia *_Nullable found, NSError *_Nullable error));

/// What a file with this extension is before its content is read: the
/// extension's base types (no candidate is more general), in the candidates'
/// order — the model's rule with no rules read and no cartridge asked. Hosts
/// that name a file's media from its name alone use this, and CSPrimaryMedia
/// when they need one. Errors as CSDetectFileMedia's, before any content is
/// read. Mirrors Rust: extension_media
void CSExtensionMedia(NSString *extension,
                      CSFabricRegistry *registry,
                      void (^completion)(NSArray<NSString *> *_Nullable media, NSError *_Nullable error));

NS_ASSUME_NONNULL_END
