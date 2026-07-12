# CapDag-ObjC/Swift Test Catalog

**Total Tests:** 881

**Numbered Tests:** 881

**Unnumbered Tests:** 0

**Numbered Tests Missing Descriptions:** 0

**Numbering Mismatches:** 0

All numbered test numbers are unique.

This catalog lists all tests in the CapDag-ObjC/Swift codebase.

| Test # | Function Name | Description | File |
|--------|---------------|-------------|------|
| test001 | `test001_capUrnCreation` | TEST001: Test that cap URN is created with tags parsed correctly and direction specs accessible | Tests/CapDAGTests/CSCapUrnTests.m:31 |
| test002 | `test002_directionSpecsDefaultToWildcard` | TEST002: Test that missing 'in' or 'out' defaults to media: wildcard | Tests/CapDAGTests/CSCapUrnTests.m:172 |
| test003 | `test003_directionMatching` | TEST003: Test that direction specs must match exactly, different in/out types don't match, wildcard matches any | Tests/CapDAGTests/CSCapUrnTests.m:222 |
| test004 | `test004_unquotedValuesLowercased` | TEST004: Test that unquoted keys and values are normalized to lowercase | Tests/CapDAGTests/CSCapUrnTests.m:633 |
| test005 | `test005_quotedValuesPreserveCase` | TEST005: Test that quoted values preserve case while unquoted are lowercased | Tests/CapDAGTests/CSCapUrnTests.m:659 |
| test006 | `test006_quotedValueSpecialChars` | TEST006: Test that quoted values can contain special characters (semicolons, equals, spaces) | Tests/CapDAGTests/CSCapUrnTests.m:688 |
| test007 | `test007_quotedValueEscapeSequences` | TEST007: Test that escape sequences in quoted values (\" and \\) are parsed correctly | Tests/CapDAGTests/CSCapUrnTests.m:712 |
| test008 | `test008_mixedQuotedUnquoted` | TEST008: Test that mixed quoted and unquoted values in same URN parse correctly | Tests/CapDAGTests/CSCapUrnTests.m:729 |
| test009 | `test009_unterminatedQuoteError` | TEST009: Test that unterminated quote produces UnterminatedQuote error | Tests/CapDAGTests/CSCapUrnTests.m:739 |
| test010 | `test010_invalidEscapeSequenceError` | TEST010: Test that invalid escape sequences (like \n, \x) produce InvalidEscapeSequence error | Tests/CapDAGTests/CSCapUrnTests.m:748 |
| test011 | `test011_serializationSmartQuoting` | TEST011: Test that serialization uses smart quoting (no quotes for simple lowercase, quotes for special chars/uppercase) | Tests/CapDAGTests/CSCapUrnTests.m:50 |
| test012 | `test012_roundTripSimple` | TEST012: Test that simple cap URN round-trips (parse -> serialize -> parse equals original) | Tests/CapDAGTests/CSCapUrnTests.m:757 |
| test013 | `test013_roundTripQuoted` | TEST013: Test that quoted values round-trip preserving case and spaces | Tests/CapDAGTests/CSCapUrnTests.m:769 |
| test014 | `test014_roundTripEscapes` | TEST014: Test that escape sequences round-trip correctly | Tests/CapDAGTests/CSCapUrnTests.m:1296 |
| test015 | `test015_capPrefixRequired` | TEST015: Test that cap: prefix is required and case-insensitive | Tests/CapDAGTests/CSCapUrnTests.m:63 |
| test016 | `test016_trailingSemicolonEquivalence` | TEST016: Test that trailing semicolon is equivalent (same hash, same string, matches) | Tests/CapDAGTests/CSCapUrnTests.m:80 |
| test017 | `test017_tagMatching` | TEST017: Test tag matching: exact match, subset match, wildcard match, value mismatch | Tests/CapDAGTests/CSCapUrnTests.m:260 |
| test018 | `test018_matchingCaseSensitiveValues` | TEST018: Test that quoted values with different case do NOT match (case-sensitive) | Tests/CapDAGTests/CSCapUrnTests.m:1308 |
| test019 | `test019_missingTagHandling` | TEST019: Missing tag in instance causes rejection — pattern's tags are constraints | Tests/CapDAGTests/CSCapUrnTests.m:287 |
| test020 | `test020_specificity` | TEST020: Specificity is the sum of per-tag truth-table scores across in/out/y. Marker tags (bare segments and `key=*`) score 2 (must-have-any), exact `key=value` tags score 3, missing/`?` score 0, `!` scores 1. testUrn() builds "cap:in=media:void;out=media:enc=utf-8;record;<tags>" so the directional baseline is: in:  media:void              -> {void=*}              -> 2 out: media:enc=utf-8;record   -> {enc=utf-8, record=*} -> 4 Total directional baseline: 6. | Tests/CapDAGTests/CSCapUrnTests.m:315 |
| test021 | `test021_builder` | TEST021: Test builder creates cap URN with correct tags and direction specs | Tests/CapDAGTests/CSCapUrnTests.m:1323 |
| test022 | `test022_builderRequiresDirection` | TEST022: Test builder requires both in_spec and out_spec | Tests/CapDAGTests/CSCapUrnTests.m:1341 |
| test0023 | `test0023_builderPreservesCase` | TEST0023: Test builder lowercases keys but preserves value case | Tests/CapDAGTests/CSCapUrnTests.m:1369 |
| test024 | `test024_directionalAccepts` | TEST024: Directional accepts — pattern's tags are constraints, instance must satisfy | Tests/CapDAGTests/CSCapUrnTests.m:340 |
| test025 | `test025_bestMatch` | TEST025: Test find_best_match returns most specific matching cap | Tests/CapDAGTests/CSCapUrnTests.m:1398 |
| test026 | `test026_mergeAndSubset` | TEST026: Test merge combines tags from both caps, subset keeps only specified tags | Tests/CapDAGTests/CSCapUrnTests.m:484 |
| test027 | `test027_wildcardTag` | TEST027: Test with_wildcard_tag sets tag to wildcard, including in/out | Tests/CapDAGTests/CSCapUrnTests.m:456 |
| test28 | `test28_emptyCapUrnIsIllegal` | TEST28: Test empty cap URN is illegal after effect transition | Tests/CapDAGTests/CSCapUrnTests.m:194 |
| test029 | `test029_minimalCapUrn` | TEST029: Test minimal valid cap URN has just in and out, empty tags | Tests/CapDAGTests/CSCapUrnTests.m:210 |
| test030 | `test030_extendedCharacterSupport` | TEST030: Test extended characters (forward slashes, colons) in tag values | Tests/CapDAGTests/CSCapUrnTests.m:560 |
| test031 | `test031_wildcardRestrictions` | TEST031: Test wildcard rejected in keys but accepted in values | Tests/CapDAGTests/CSCapUrnTests.m:571 |
| test032 | `test032_duplicateKeyRejection` | TEST032: Test duplicate keys are rejected with DuplicateKey error | Tests/CapDAGTests/CSCapUrnTests.m:590 |
| test033 | `test033_numericKeyRestriction` | TEST033: Test pure numeric keys rejected, mixed alphanumeric allowed, numeric values allowed | Tests/CapDAGTests/CSCapUrnTests.m:600 |
| test034 | `test034_emptyValueError` | TEST034: Test empty values are rejected | Tests/CapDAGTests/CSCapUrnTests.m:1417 |
| test035 | `test035_hasTagCaseSensitive` | TEST035: Test has_tag is case-sensitive for values, case-insensitive for keys, works for in/out | Tests/CapDAGTests/CSCapUrnTests.m:782 |
| test036 | `test036_withTagPreservesValue` | TEST036: Test with_tag preserves value case | Tests/CapDAGTests/CSCapUrnTests.m:385 |
| test037 | `test037_withTagRejectsEmptyValue` | TEST037: Test with_tag rejects empty value | Tests/CapDAGTests/CSCapUrnTests.m:1428 |
| test038 | `test038_semanticEquivalence` | TEST038: Test semantic equivalence of unquoted and quoted simple lowercase values | Tests/CapDAGTests/CSCapUrnTests.m:805 |
| test039 | `test039_getTagReturnsDirectionSpecs` | TEST039: Test get_tag returns direction specs (in/out) with case-insensitive lookup | Tests/CapDAGTests/CSCapUrnTests.m:371 |
| test040 | `test040_matchingSemantics_exactMatch` | TEST040: Matching semantics - exact match succeeds | Tests/CapDAGTests/CSCapUrnTests.m:827 |
| test041 | `test041_matchingSemantics_capMissingTag` | TEST041: Matching semantics - cap missing tag matches (implicit wildcard) | Tests/CapDAGTests/CSCapUrnTests.m:840 |
| test042 | `test042_matchingSemantics_capHasExtraTag` | TEST042: Pattern rejects instance missing required tags | Tests/CapDAGTests/CSCapUrnTests.m:853 |
| test043 | `test043_matchingSemantics_requestHasWildcard` | TEST043: Matching semantics - request wildcard matches specific cap value | Tests/CapDAGTests/CSCapUrnTests.m:864 |
| test044 | `test044_matchingSemantics_capHasWildcard` | TEST044: Matching semantics - cap wildcard matches specific request value | Tests/CapDAGTests/CSCapUrnTests.m:877 |
| test045 | `test045_matchingSemantics_valueMismatch` | TEST045: Matching semantics - value mismatch does not match | Tests/CapDAGTests/CSCapUrnTests.m:890 |
| test046 | `test046_matchingSemantics_fallbackPattern` | TEST046: Matching semantics - fallback pattern (cap missing tag = implicit wildcard) | Tests/CapDAGTests/CSCapUrnTests.m:903 |
| test047 | `test047_matchingSemantics_thumbnailVoidInput` | TEST047: Matching semantics - thumbnail fallback with void input | Tests/CapDAGTests/CSCapUrnTests.m:1436 |
| test048 | `test048_matchingSemantics_wildcardDirectionMatchesAnything` | TEST048: Matching semantics - wildcard direction matches anything | Tests/CapDAGTests/CSCapUrnTests.m:916 |
| test049 | `test049_matchingSemantics_crossDimensionIndependence` | TEST049: Non-overlapping tags — neither direction accepts | Tests/CapDAGTests/CSCapUrnTests.m:928 |
| test050 | `test050_matchingSemantics_directionMismatch` | TEST050: Matching semantics - direction mismatch prevents matching | Tests/CapDAGTests/CSCapUrnTests.m:938 |
| test060 | `test060_wrong_prefix_fails` | TEST060: Test wrong prefix fails with InvalidPrefix error showing expected and actual prefix | Tests/CapDAGTests/CSMediaUrnTests.m:119 |
| test062 | `test062_is_record` | TEST062: Test is_record returns true when record marker tag is present indicating key-value structure | Tests/CapDAGTests/CSMediaUrnTests.m:135 |
| test063 | `test063_is_scalar` | TEST063: Test is_scalar returns true when list marker tag is absent (scalar is default) | Tests/CapDAGTests/CSMediaUrnTests.m:147 |
| test064 | `test064_is_list` | TEST064: Test is_list returns true when list marker tag is present indicating ordered collection | Tests/CapDAGTests/CSMediaUrnTests.m:161 |
| test065 | `test065_is_opaque` | TEST065: Test is_opaque returns true when record marker is absent (opaque is default) | Tests/CapDAGTests/CSMediaUrnTests.m:173 |
| test066 | `test066_is_json` | TEST066: Test is_json returns true only when json marker tag is present for JSON representation | Tests/CapDAGTests/CSMediaUrnTests.m:186 |
| test067 | `test067_is_text` | TEST067: Text-representability is now carried by the orthogonal `enc=` tag (the old `textable` marker and is_text() are gone). A media is "text" iff it declares an encoding. enc is orthogonal to format/numeric, so only media that actually carry enc= are text. | Tests/CapDAGTests/CSMediaUrnTests.m:196 |
| test068 | `test068_is_void` | TEST068: Test is_void returns true when void flag or type=void tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:210 |
| test071 | `test071_to_string_roundtrip` | TEST071: Test to_string roundtrip ensures serialization and deserialization preserve URN structure | Tests/CapDAGTests/CSMediaUrnTests.m:332 |
| test072 | `test072_constants_parse` | TEST072: Test all media URN constants parse successfully as valid media URNs | Tests/CapDAGTests/CSMediaUrnTests.m:343 |
| test074 | `test074_media_urn_matching` | TEST074: Test media URN conforms_to using tagged URN semantics with specific and generic requirements | Tests/CapDAGTests/CSMediaUrnTests.m:374 |
| test075 | `test075_matching` | TEST075: Test accepts with implicit wildcards where handlers with fewer tags can handle more requests | Tests/CapDAGTests/CSMediaUrnTests.m:392 |
| test076 | `test076_specificity` | TEST076: Test specificity increases with more tags for ranking conformance | Tests/CapDAGTests/CSMediaUrnTests.m:403 |
| test078 | `test078_object_does_not_conform_to_string` | TEST078: conforms_to behavior between MEDIA_OBJECT and MEDIA_STRING | Tests/CapDAGTests/CSMediaUrnTests.m:418 |
| test099 | `test099_resolved_is_binary` | TEST099: The identity media (`media:`) carries no encoding, no record marker, and no format. The old is_binary() delegate is gone (binary/text is no longer a distinction); a media is text-representable iff it declares enc=. | Tests/CapDAGTests/CSMediaDefTests.m:237 |
| test100 | `test100_resolved_is_record` | TEST100: Test ResolvedMediaDef is_record returns true when record marker is present | Tests/CapDAGTests/CSMediaDefTests.m:252 |
| test101 | `test101_resolved_is_scalar` | TEST101: Test ResolvedMediaDef is_scalar returns true when list marker is absent | Tests/CapDAGTests/CSMediaDefTests.m:267 |
| test102 | `test102_resolved_is_list` | TEST102: Test ResolvedMediaDef is_list returns true when list marker is present | Tests/CapDAGTests/CSMediaDefTests.m:282 |
| test103 | `test103_resolved_is_json` | TEST103: Test ResolvedMediaDef is_json returns true when json tag is present | Tests/CapDAGTests/CSMediaDefTests.m:297 |
| test104 | `test104_resolved_is_text` | TEST104: Text-representability is now carried by the orthogonal `enc=` tag. The old is_text()/is_binary() delegates on ResolvedMediaDef are gone; a media is text iff its URN declares an encoding. `media:enc=utf-8` is plain UTF-8 text — has enc, is not JSON. | Tests/CapDAGTests/CSMediaDefTests.m:311 |
| test106 | `test106_MetadataWithValidation` | TEST106: Metadata with validation | Tests/CapDAGTests/CSMediaDefTests.m:75 |
| test0108 | `test0108_CapCreation` | TEST0108: Cap creation | Tests/CapDAGTests/CSCapTests.m:32 |
| test0110 | `test0110_CapMatching` | TEST0110: Cap matching | Tests/CapDAGTests/CSCapTests.m:123 |
| test115 | `test115_capArgSerialization` | TEST115: Test CapArg serialization and deserialization with multiple sources | Tests/CapDAGTests/CSCapTests.m:817 |
| test116 | `test116_capArgConstructors` | TEST116: Test CapArg constructor methods basic and with_description create args correctly | Tests/CapDAGTests/CSCapTests.m:851 |
| test125 | `test125_effectNonePreservesRuntimeMedia` | TEST125: effect=none preserves runtime media identity | Tests/CapDAGTests/CSCapUrnTests.m:1579 |
| test126 | `test126_effectDeclaredUsesDeclaredOutput` | TEST126: default effect=declared uses the declared output | Tests/CapDAGTests/CSCapUrnTests.m:1596 |
| test0127 | `test0127_invalidEffectNoneFailsHard` | TEST0127: invalid effect=none declarations fail hard | Tests/CapDAGTests/CSCapUrnTests.m:1622 |
| test128 | `test128_effectDispatchRequiresExplicitWildcard` | TEST128: omitted effect means declared; unconstrained effect must be explicit | Tests/CapDAGTests/CSCapUrnTests.m:1630 |
| test129 | `test129_GcEvictsOldestEntriesByTouchedAt` | / Contract #2 — the GC drops the OLDEST entries by / `touchedAt`, not arbitrary keys. We seed a known age / distribution and recompute the expected victim set / independently of the production code, then assert that / the post-GC table contains exactly the entries the test / computed should survive. / / A regression where the GC e.g. iterates the dictionary and / drops the first N entries (dictionary iteration order is / arbitrary in Swift) would still pass contract #1 but fail / this one — so this is the assertion that catches a "wrong / victims" bug, which is the more dangerous one (silently / drops in-flight continuation frames). | Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:108 |
| test0131 | `test0131_runtimeIdentityProbeRequiredOnEmptyToNonemptyTransition` | TEST0131: empty→non-empty cap transition requires a runtime identity probe; a master that fails the probe (ERR) ends up UNHEALTHY with lastError populated, and its caps are NOT routable. | Tests/BifaciTests/RelaySwitchTests.swift:1115 |
| test132 | `test132_addMasterDynamic` | TEST132: add_master dynamically connects new host to running switch | Tests/BifaciTests/RelaySwitchTests.swift:843 |
| test133 | `test133_ReattachByIdPreservesSlotIndex` | Reattach-by-id tests for the cardinality-stable slot model. When a master dies and the host reconnects, the new socket MUST attach to the same slot index — preserving routing entries keyed by index. Accumulating zombie slots on each reconnect was the bug class these tests guard against. | Tests/BifaciTests/RelaySwitchTests.swift:901 |
| test134 | `test134_AddMasterWithDuplicateHealthyIdErrors` | TEST134: Add master with duplicate healthy id errors | Tests/BifaciTests/RelaySwitchTests.swift:953 |
| test0135 | `test0135_runtimeIdentityProbeSuccessMakesCapsRoutable` | TEST0135: the runtime identity probe SUCCESS path — a master that advertises caps AFTER connecting (empty→non-empty) and then passes the probe must flip healthy and its caps must become routable. | Tests/BifaciTests/RelaySwitchTests.swift:1158 |
| test0138 | `test0138_unhealthyMasterInventoryRetainedButNotRoutable` | TEST0138: the installed-cartridge INVENTORY is NOT health-filtered. A master held unhealthy by a failed runtime identity probe still has its cartridges visible in the aggregate inventory, even though its caps are excluded from ROUTING. Pins the deliberate asymmetry. | Tests/BifaciTests/RelaySwitchTests.swift:1198 |
| test0141 | `test0141_subscribeCapabilitiesDeliversRoutableSet` | TEST0141: the routable-capability watch (subscribeCapabilities). A subscriber must receive the CURRENT routable cap set on subscribe even though it was rebuilt during construction — BEFORE any receiver existed (the watch must persist the value, i.e. send_replace semantics). The delivered set must be the health-filtered routable cap URNs. | Tests/BifaciTests/RelaySwitchTests.swift:1249 |
| test141 | `test141_perCapURLShape` | / TEST141: URL has the right shape — protocol, host, /caps/ prefix, / 64 hex chars, no extension. | Tests/CapDAGTests/CSFabricRegistryTests.m:181 |
| test0142 | `test0142_peerReqNoHandlerSendsErrToCaller` | TEST0142 (Swift-specific, gap 3): a peer cartridge→cartridge REQ for a cap with NO handler must NOT abort the pump. The switch sends an ERR("NO_HANDLER") frame straight back to the calling master (stamped with the synthetic XID) so the caller fails fast, and handleMasterFrame returns nil — it must NOT throw. | Tests/BifaciTests/RelaySwitchTests.swift:1302 |
| test142 | `test142_normalizeHandlesDifferentTagOrders` | / TEST142: Different tag orders normalise to the same URL — the / canonicaliser strips the variation before hashing. | Tests/CapDAGTests/CSFabricRegistryTests.m:194 |
| test0143 | `test0143_addMasterIdentityFailureRegistersUnhealthy` | TEST0143 (Swift-specific, gap 5): addMaster whose identity probe FAILS must register the master UNHEALTHY (keeping its inventory visible) rather than throwing. Caps stay held back from routing. | Tests/BifaciTests/RelaySwitchTests.swift:1360 |
| test0144 | `test0144_mediaDefResolvesToVersionedObjectPathUnderManifest` | TEST0144: a media def published under a manifest (v >= 1) resolves to the VERSIONED object path `/media/<sha>/<defver>.json`, never the legacy flat path `/media/<sha>`. The flat path is the pre-manifest (v0) layout; a registry that silently runs in v0 mode fetches it and 404s every lookup against a versioned registry — the exact regression where the app's media-title resolver hit `/media/<sha>` on a staging-v1 registry and logged "Media def … not found (HTTP 404)". This pins BOTH the URL rule and the manifest-driven defver resolution. Mirrors the Rust reference's test0144_media_def_resolves_to_versioned_object_path_under_manifest. | Tests/CapDAGTests/CSFabricRegistryTests.m:66 |
| test148 | `test148_capManifestCreation` | TEST148: Cap manifest construction stores name, version, channel, description, and the cap_groups verbatim. | Tests/BifaciTests/ManifestTests.swift:28 |
| test149 | `test149_CapManifestWithAuthor` | TEST149: Cap manifest with author | Tests/CapDAGTests/CSCapTests.m:461 |
| test151 | `test151_capManifestRequiredFields` | TEST151: Manifest deserialization fails when any required field is missing — including channel, which is part of the cartridge's identity. There is no fallback default; missing means broken. | Tests/BifaciTests/ManifestTests.swift:138 |
| test152 | `test152_capManifestWithMultipleCaps` | TEST152: Multiple caps across multiple cap_groups serialize and deserialize correctly, preserving group structure. | Tests/BifaciTests/ManifestTests.swift:176 |
| test153 | `test153_capManifestEmptyCapGroups` | TEST153: An empty cap_groups list round-trips without losing the channel / version envelope. | Tests/BifaciTests/ManifestTests.swift:212 |
| test154 | `test154_capManifestOptionalAuthorField` | TEST154: Optional author field on CSCapManifest is nil by default and round-trips through `withAuthor`. | Tests/BifaciTests/ManifestTests.swift:236 |
| test163 | `test163_argumentSchemaValidationSuccess` | TEST163: Test argument schema validation succeeds with valid JSON matching schema | Tests/CapDAGTests/CSSchemaValidationTests.m:56 |
| test164 | `test164_argumentSchemaValidationFailure` | TEST164: Test argument schema validation fails with JSON missing required fields | Tests/CapDAGTests/CSSchemaValidationTests.m:97 |
| test165 | `test165_outputSchemaValidationSuccess` | TEST165: Test output schema validation succeeds with valid JSON matching schema | Tests/CapDAGTests/CSSchemaValidationTests.m:189 |
| test171 | `test171_frameTypeRoundtrip` | TEST171: Test all FrameType discriminants roundtrip through u8 conversion preserving identity | Tests/BifaciTests/FrameTests.swift:22 |
| test172 | `test172_invalidFrameType` | TEST172: Test FrameType::from_u8 returns None for values outside the valid discriminant range | Tests/BifaciTests/FrameTests.swift:32 |
| test173 | `test173_frameTypeDiscriminantValues` | TEST173: Test FrameType discriminant values match the wire protocol specification exactly | Tests/BifaciTests/FrameTests.swift:39 |
| test174 | `test174_messageIdUUID` | TEST174: Test MessageId::new_uuid generates valid UUID that roundtrips through string conversion | Tests/BifaciTests/FrameTests.swift:111 |
| test175 | `test175_messageIdUUIDUniqueness` | TEST175: Test two MessageId::new_uuid calls produce distinct IDs (no collisions) | Tests/BifaciTests/FrameTests.swift:118 |
| test176 | `test176_messageIdUintHasNoUUIDString` | TEST176: Test MessageId::Uint does not produce a UUID string, to_uuid_string returns None | Tests/BifaciTests/FrameTests.swift:125 |
| test177 | `test177_messageIdFromInvalidUUIDStr` | TEST177: Test MessageId::from_uuid_str rejects invalid UUID strings | Tests/BifaciTests/FrameTests.swift:132 |
| test178 | `test178_messageIdAsBytes` | TEST178: Test MessageId::as_bytes produces correct byte representations for Uuid and Uint variants | Tests/BifaciTests/FrameTests.swift:1303 |
| test179 | `test179_messageIdNewUUIDIsUUID` | TEST179: Test MessageId::default creates a UUID variant (not Uint) | Tests/BifaciTests/FrameTests.swift:1322 |
| test180 | `test180_helloFrame` | TEST180: Test Frame::hello without manifest produces correct HELLO frame for host side | Tests/BifaciTests/FrameTests.swift:166 |
| test181 | `test181_helloFrameWithManifest` | TEST181: Test Frame::hello_with_manifest produces HELLO with manifest bytes for cartridge side | Tests/BifaciTests/FrameTests.swift:177 |
| test182 | `test182_reqFrame` | TEST182: Test Frame::req stores cap URN, payload, and content_type correctly | Tests/BifaciTests/FrameTests.swift:193 |
| test184 | `test184_chunkFrame` | TEST184: Test Frame::chunk stores seq and payload for streaming (with stream_id) | Tests/BifaciTests/FrameTests.swift:211 |
| test185 | `test185_errFrame` | TEST185: Test Frame::err stores error code and message in metadata | Tests/BifaciTests/FrameTests.swift:225 |
| test186 | `test186_logFrame` | TEST186: Test Frame::log stores level and message in metadata | Tests/BifaciTests/FrameTests.swift:234 |
| test187 | `test187_endFrameWithPayload` | TEST187: Test Frame::end with payload sets eof and optional final payload | Tests/BifaciTests/FrameTests.swift:243 |
| test188 | `test188_endFrameWithoutPayload` | TEST188: Test Frame::end without payload still sets eof marker | Tests/BifaciTests/FrameTests.swift:252 |
| test189 | `test189_chunkWithOffset` | TEST189: Test chunk_with_offset sets offset on all chunks but len only on seq=0 (with stream_id) | Tests/BifaciTests/FrameTests.swift:261 |
| test190 | `test190_heartbeatFrame` | TEST190: Test Frame::heartbeat creates minimal frame with no payload or metadata | Tests/BifaciTests/FrameTests.swift:306 |
| test191 | `test191_errorAccessorsOnNonErrFrame` | TEST191: Test error_code and error_message return None for non-Err frame types | Tests/BifaciTests/FrameTests.swift:316 |
| test192 | `test192_logAccessorsOnNonLogFrame` | TEST192: Test log_level and log_message return None for non-Log frame types | Tests/BifaciTests/FrameTests.swift:323 |
| test193 | `test193_helloAccessorsOnNonHelloFrame` | TEST193: Test hello_max_frame and hello_max_chunk return None for non-Hello frame types | Tests/BifaciTests/FrameTests.swift:330 |
| test194 | `test194_frameNewDefaults` | TEST194: Test Frame::new sets version and defaults correctly, optional fields are None | Tests/BifaciTests/FrameTests.swift:1333 |
| test195 | `test195_frameDefaultType` | TEST195: Test Frame::default creates a Req frame (the documented default) | Tests/BifaciTests/FrameTests.swift:1358 |
| test196 | `test196_isEofWhenNil` | TEST196: Test is_eof returns false when eof field is None (unset) | Tests/BifaciTests/FrameTests.swift:338 |
| test197 | `test197_isEofWhenFalse` | TEST197: Test is_eof returns false when eof field is explicitly Some(false) | Tests/BifaciTests/FrameTests.swift:345 |
| test198 | `test198_limitsDefault` | TEST198: Test Limits::default provides the documented default values | Tests/BifaciTests/FrameTests.swift:352 |
| test199 | `test199_protocolVersionConstant` | TEST199: Test PROTOCOL_VERSION is 3 | Tests/BifaciTests/FrameTests.swift:370 |
| test200 | `test200_keyConstants` | TEST200: Test integer key constants match the protocol specification | Tests/BifaciTests/FrameTests.swift:375 |
| test201 | `test201_helloManifestBinaryData` | TEST201: Test hello_with_manifest preserves binary manifest data (not just JSON text) | Tests/BifaciTests/FrameTests.swift:392 |
| test202 | `test202_messageIdEqualityAndHash` | TEST202: Test MessageId Eq/Hash semantics: equal UUIDs are equal, different ones are not | Tests/BifaciTests/FrameTests.swift:139 |
| test203 | `test203_messageIdCrossVariantInequality` | TEST203: Test Uuid and Uint variants of MessageId are never equal even for coincidental byte values | Tests/BifaciTests/FrameTests.swift:157 |
| test204 | `test204_reqFrameEmptyPayload` | TEST204: Test Frame::req with empty payload stores Some(empty vec) not None | Tests/BifaciTests/FrameTests.swift:404 |
| test205 | `test205_encodeDecodeRoundtrip` | TEST205: Test REQ frame encode/decode roundtrip preserves all fields | Tests/BifaciTests/FrameTests.swift:413 |
| test206 | `test206_helloFrameRoundtrip` | TEST206: Test HELLO frame encode/decode roundtrip preserves max_frame, max_chunk, max_reorder_buffer | Tests/BifaciTests/FrameTests.swift:434 |
| test207 | `test207_errFrameRoundtrip` | TEST207: Test ERR frame encode/decode roundtrip preserves error code and message | Tests/BifaciTests/FrameTests.swift:447 |
| test208 | `test208_logFrameRoundtrip` | TEST208: Test LOG frame encode/decode roundtrip preserves level and message | Tests/BifaciTests/FrameTests.swift:459 |
| test210 | `test210_endFrameRoundtrip` | TEST210: Test END frame encode/decode roundtrip preserves eof marker and optional payload | Tests/BifaciTests/FrameTests.swift:473 |
| test211 | `test211_helloWithManifestRoundtrip` | TEST211: Test HELLO with manifest encode/decode roundtrip preserves manifest bytes and limits | Tests/BifaciTests/FrameTests.swift:486 |
| test212 | `test212_chunkWithOffsetRoundtrip` | TEST212: Test chunk_with_offset encode/decode roundtrip preserves offset, len, eof (with stream_id) | Tests/BifaciTests/FrameTests.swift:505 |
| test213 | `test213_heartbeatRoundtrip` | TEST213: Test heartbeat frame encode/decode roundtrip preserves ID with no extra fields | Tests/BifaciTests/FrameTests.swift:562 |
| test214 | `test214_frameIORoundtrip` | TEST214: Test write_frame/read_frame IO roundtrip through length-prefixed wire format | Tests/BifaciTests/FrameTests.swift:577 |
| test215 | `test215_multipleFrames` | TEST215: Test reading multiple sequential frames from a single buffer | Tests/BifaciTests/FrameTests.swift:596 |
| test216 | `test216_frameTooLarge` | TEST216: Test write_frame rejects frames exceeding max_frame limit | Tests/BifaciTests/FrameTests.swift:636 |
| test217 | `test217_readFrameTooLarge` | TEST217: Test read_frame rejects incoming frames exceeding the negotiated max_frame limit | Tests/BifaciTests/FrameTests.swift:655 |
| test218 | `test218_writeChunked` | TEST218: Test write_chunked splits data into chunks respecting max_chunk and reconstructs correctly Chunks from write_chunked have seq=0. SeqAssigner at the output stage assigns final seq. Chunk ordering within a stream is tracked by chunk_index (chunk_index field). | Tests/BifaciTests/FrameTests.swift:678 |
| test219 | `test219_writeChunkedEmptyData` | TEST219: Test write_chunked with empty data produces a single EOF chunk | Tests/BifaciTests/FrameTests.swift:729 |
| test220 | `test220_writeChunkedExactFit` | TEST220: Test write_chunked with data exactly equal to max_chunk produces exactly one chunk | Tests/BifaciTests/FrameTests.swift:749 |
| test221 | `test221_eofHandling` | TEST221: Test read_frame returns Ok(None) on clean EOF (empty stream) | Tests/BifaciTests/FrameTests.swift:773 |
| test222 | `test222_truncatedLengthPrefix` | TEST222: Test read_frame handles truncated length prefix (fewer than 4 bytes available) | Tests/BifaciTests/FrameTests.swift:783 |
| test223 | `test223_truncatedFrameBody` | TEST223: Test read_frame returns error on truncated frame body (length prefix says more bytes than available) | Tests/BifaciTests/FrameTests.swift:803 |
| test224 | `test224_messageIdUintRoundtrip` | TEST224: Test MessageId::Uint roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:828 |
| test225 | `test225_decodeNonMapValue` | TEST225: Test decode_frame rejects non-map CBOR values (e.g., array, integer, string) | Tests/BifaciTests/FrameTests.swift:837 |
| test226 | `test226_decodeMissingVersion` | TEST226: Test decode_frame rejects CBOR map missing required version field | Tests/BifaciTests/FrameTests.swift:852 |
| test227 | `test227_decodeInvalidFrameTypeValue` | TEST227: Test decode_frame rejects CBOR map with invalid frame_type value | Tests/BifaciTests/FrameTests.swift:870 |
| test228 | `test228_decodeMissingId` | TEST228: Test decode_frame rejects CBOR map missing required id field | Tests/BifaciTests/FrameTests.swift:888 |
| test229 | `test229_frameReaderWriterSetLimits` | TEST229: Test FrameReader/FrameWriter set_limits updates the negotiated limits | Tests/BifaciTests/FrameTests.swift:907 |
| test230 | `test230_syncHandshake` | TEST230: Test async handshake exchanges HELLO frames and negotiates minimum limits | Tests/BifaciTests/IntegrationTests.swift:450 |
| test231 | `test231_attachCartridgeFailsOnWrongFrameType` | TEST231: Test handshake fails when peer sends non-HELLO frame | Tests/BifaciTests/RuntimeTests.swift:237 |
| test232 | `test232_attachCartridgeFailsOnMissingManifest` | TEST232: Test handshake fails when cartridge HELLO is missing required manifest | Tests/BifaciTests/RuntimeTests.swift:203 |
| test233 | `test233_binaryPayloadAllByteValues` | TEST233: Test binary payload with all 256 byte values roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:923 |
| test234 | `test234_decodeGarbageBytes` | TEST234: Test decode_frame handles garbage CBOR bytes gracefully with an error | Tests/BifaciTests/FrameTests.swift:939 |
| test235 | `test235_responseChunk` | TEST235: Test ResponseChunk stores payload, seq, offset, len, and eof fields correctly | Tests/BifaciTests/FrameTests.swift:978 |
| test236 | `test236_responseChunkWithAllFields` | TEST236: Test ResponseChunk with all fields populated preserves offset, len, and eof | Tests/BifaciTests/FrameTests.swift:991 |
| test237 | `test237_cartridgeResponseSingle` | TEST237: Test CartridgeResponse::Single final_payload returns the single payload slice | Tests/BifaciTests/FrameTests.swift:1003 |
| test238 | `test238_cartridgeResponseSingleEmpty` | TEST238: Test CartridgeResponse::Single with empty payload returns empty slice and empty vec | Tests/BifaciTests/FrameTests.swift:1010 |
| test239 | `test239_cartridgeResponseStreaming` | TEST239: Test CartridgeResponse::Streaming concatenated joins all chunk payloads in order | Tests/BifaciTests/FrameTests.swift:1017 |
| test240 | `test240_cartridgeResponseStreamingFinalPayload` | TEST240: Test CartridgeResponse::Streaming final_payload returns the last chunk's payload | Tests/BifaciTests/FrameTests.swift:1028 |
| test241 | `test241_cartridgeResponseStreamingEmptyChunks` | TEST241: Test CartridgeResponse::Streaming with empty chunks vec returns empty concatenation | Tests/BifaciTests/FrameTests.swift:1038 |
| test242 | `test242_cartridgeResponseStreamingLargePayload` | TEST242: Test CartridgeResponse::Streaming concatenated capacity is pre-allocated correctly for large payloads | Tests/BifaciTests/FrameTests.swift:1045 |
| test243 | `test243_cartridgeHostErrorDisplay` | TEST243: Test AsyncHostError variants display correct error messages | Tests/BifaciTests/FrameTests.swift:1060 |
| test244 | `test244_cartridgeHostErrorFromFrameError` | TEST244: Test AsyncHostError::from converts CborError to Cbor variant | Tests/BifaciTests/RuntimeTests.swift:1307 |
| test245 | `test245_cartridgeHostErrorDetails` | TEST245: Test AsyncHostError::from converts io::Error to Io variant | Tests/BifaciTests/RuntimeTests.swift:1323 |
| test246 | `test246_cartridgeHostErrorVariants` | TEST246: Test AsyncHostError Clone implementation produces equal values | Tests/BifaciTests/RuntimeTests.swift:1331 |
| test247 | `test247_responseChunkStorage` | TEST247: Test ResponseChunk Clone produces independent copy with same data | Tests/BifaciTests/RuntimeTests.swift:1358 |
| test248 | `test248_registerAndFindHandler` | TEST248: Test register_op and find_handler by exact cap URN | Tests/BifaciTests/CartridgeRuntimeTests.swift:154 |
| test249 | `test249_rawHandler` | TEST249: Test register_op handler echoes bytes directly | Tests/BifaciTests/CartridgeRuntimeTests.swift:166 |
| test250 | `test250_typedHandlerRegistration` | TEST250: Test Op handler collects input and processes it | Tests/BifaciTests/CartridgeRuntimeTests.swift:465 |
| test251 | `test251_typedHandlerErrorPropagation` | TEST251: Test Op handler propagates errors through RuntimeError::Handler | Tests/BifaciTests/CartridgeRuntimeTests.swift:483 |
| test252 | `test252_findHandlerUnknownCap` | TEST252: Test find_handler returns None for unregistered cap URNs | Tests/BifaciTests/CartridgeRuntimeTests.swift:188 |
| test253 | `test253_handlerIsSendable` | TEST253: Test OpFactory can be cloned via Arc and sent across tasks (Send + Sync) | Tests/BifaciTests/CartridgeRuntimeTests.swift:495 |
| test254 | `test254_noPeerInvoker` | TEST254: Test NoPeerInvoker always returns PeerRequest error | Tests/BifaciTests/CartridgeRuntimeTests.swift:244 |
| test255 | `test255_noPeerInvokerWithArguments` | TEST255: Test NoPeerInvoker call_with_bytes also returns error | Tests/BifaciTests/CartridgeRuntimeTests.swift:259 |
| test256 | `test256_withManifestJson` | TEST256: Test CartridgeRuntime::with_manifest_json stores manifest data and parses when valid | Tests/BifaciTests/CartridgeRuntimeTests.swift:269 |
| test257 | `test257_newWithInvalidJson` | TEST257: Test CartridgeRuntime::new with invalid JSON still creates runtime (manifest is None) | Tests/BifaciTests/CartridgeRuntimeTests.swift:276 |
| test258 | `test258_withManifestStruct` | TEST258: Test CartridgeRuntime::with_manifest creates runtime with valid manifest data | Tests/BifaciTests/CartridgeRuntimeTests.swift:283 |
| test259 | `test259_extractEffectivePayloadNonCbor` | TEST259: Test extract_effective_payload with non-CBOR content_type returns raw payload unchanged | Tests/BifaciTests/CartridgeRuntimeTests.swift:293 |
| test260 | `test260_extractEffectivePayloadNoContentType` | TEST260: Test extract_effective_payload with None content_type returns raw payload unchanged | Tests/BifaciTests/CartridgeRuntimeTests.swift:301 |
| test261 | `test261_extractEffectivePayloadCborMatch` | TEST261: Test extract_effective_payload with CBOR content extracts matching argument value | Tests/BifaciTests/CartridgeRuntimeTests.swift:309 |
| test262 | `test262_extractEffectivePayloadCborNoMatch` | TEST262: Test extract_effective_payload with CBOR content fails when no argument matches expected input | Tests/BifaciTests/CartridgeRuntimeTests.swift:333 |
| test263 | `test263_extractEffectivePayloadInvalidCbor` | TEST263: Test extract_effective_payload with invalid CBOR bytes returns deserialization error | Tests/BifaciTests/CartridgeRuntimeTests.swift:352 |
| test264 | `test264_extractEffectivePayloadCborNotArray` | TEST264: Test extract_effective_payload with CBOR non-array (e.g. map) returns error | Tests/BifaciTests/CartridgeRuntimeTests.swift:363 |
| test266 | `test266_cliFrameSenderConstruction` | TEST266: Test CliFrameSender wraps CliStreamEmitter correctly (basic construction) | Tests/BifaciTests/CartridgeRuntimeTests.swift:511 |
| test268 | `test268_runtimeErrorDisplay` | TEST268: Test RuntimeError variants display correct messages | Tests/BifaciTests/CartridgeRuntimeTests.swift:442 |
| test270 | `test270_multipleHandlers` | TEST270: Test registering multiple Op handlers for different caps and finding each independently | Tests/BifaciTests/CartridgeRuntimeTests.swift:195 |
| test271 | `test271_handlerReplacement` | TEST271: Test Op handler replacing an existing registration for the same cap URN | Tests/BifaciTests/CartridgeRuntimeTests.swift:226 |
| test272 | `test272_extractEffectivePayloadMultipleArgs` | TEST272: Test extract_effective_payload CBOR with multiple arguments selects the correct one | Tests/BifaciTests/CartridgeRuntimeTests.swift:377 |
| test273 | `test273_extractEffectivePayloadBinaryValue` | TEST273: Test extract_effective_payload with binary data in CBOR value (not just text) | Tests/BifaciTests/CartridgeRuntimeTests.swift:413 |
| test274 | `test274_capArgumentValueNew` | TEST274: Test CapArgumentValue::new stores media_urn and raw byte value | Tests/BifaciTests/CartridgeRuntimeTests.swift:558 |
| test275 | `test275_capArgumentValueFromStr` | TEST275: Test CapArgumentValue::from_str converts string to UTF-8 bytes | Tests/BifaciTests/CartridgeRuntimeTests.swift:568 |
| test276 | `test276_capArgumentValueAsStrValid` | TEST276: Test CapArgumentValue::value_as_str succeeds for UTF-8 data | Tests/BifaciTests/CartridgeRuntimeTests.swift:575 |
| test277 | `test277_capArgumentValueAsStrInvalidUtf8` | TEST277: Test CapArgumentValue::value_as_str fails for non-UTF-8 binary data | Tests/BifaciTests/CartridgeRuntimeTests.swift:581 |
| test278 | `test278_capArgumentValueEmpty` | TEST278: Test CapArgumentValue::new with empty value stores empty vec | Tests/BifaciTests/CartridgeRuntimeTests.swift:587 |
| test282 | `test282_capArgumentValueUnicode` | TEST282: Test CapArgumentValue::from_str with Unicode string preserves all characters | Tests/BifaciTests/CartridgeRuntimeTests.swift:594 |
| test283 | `test283_capArgumentValueLargeBinary` | TEST283: Test CapArgumentValue with large binary payload preserves all bytes | Tests/BifaciTests/CartridgeRuntimeTests.swift:600 |
| test284 | `test284_handshakeHostCartridge` | TEST284: Handshake exchanges HELLO frames, negotiates limits | Tests/BifaciTests/IntegrationTests.swift:50 |
| test285 | `test285_requestResponseSimple` | TEST285: Simple request-response flow (REQ → END with payload) | Tests/BifaciTests/IntegrationTests.swift:90 |
| test286 | `test286_streamingChunks` | TEST286: Streaming response with multiple CHUNK frames | Tests/BifaciTests/IntegrationTests.swift:140 |
| test287 | `test287_heartbeatFromHost` | TEST287: Host-initiated heartbeat | Tests/BifaciTests/IntegrationTests.swift:206 |
| test290 | `test290_limitsNegotiation` | TEST290: Limit negotiation picks minimum | Tests/BifaciTests/IntegrationTests.swift:252 |
| test291 | `test291_binaryPayloadRoundtrip` | TEST291: Binary payload roundtrip (all 256 byte values) | Tests/BifaciTests/IntegrationTests.swift:287 |
| test292 | `test292_messageIdUniqueness` | TEST292: Sequential requests get distinct MessageIds | Tests/BifaciTests/IntegrationTests.swift:346 |
| test293 | `test293_cartridgeRuntimeHandlerRegistration` | TEST293: Test CartridgeRuntime Op registration and lookup by exact and non-existent cap URN | Tests/BifaciTests/RuntimeTests.swift:677 |
| test299 | `test299_emptyPayloadRoundtrip` | TEST299: Empty payload request/response roundtrip | Tests/BifaciTests/IntegrationTests.swift:399 |
| test304 | `test304_media_availability_output_constant` | TEST304: Test MEDIA_AVAILABILITY_OUTPUT constant parses as valid media URN with correct tags | Tests/CapDAGTests/CSMediaUrnTests.m:430 |
| test305 | `test305_media_path_output_constant` | TEST305: Test MEDIA_PATH_OUTPUT constant parses as valid media URN with correct tags | Tests/CapDAGTests/CSMediaUrnTests.m:441 |
| test306 | `test306_availability_and_path_output_distinct` | TEST306: Test MEDIA_AVAILABILITY_OUTPUT and MEDIA_PATH_OUTPUT are distinct URNs | Tests/CapDAGTests/CSMediaUrnTests.m:452 |
| test0314 | `test0314_CapWithDescription` | TEST0314: Cap with description | Tests/CapDAGTests/CSCapTests.m:58 |
| test0315 | `test0315_CapStdinType` | TEST0315: Cap stdin type | Tests/CapDAGTests/CSCapTests.m:80 |
| test0317 | `test0317_CapStdinSerialization` | TEST0317: Cap stdin serialization | Tests/CapDAGTests/CSCapTests.m:148 |
| test0318 | `test0318_CanonicalDictionaryDeserialization` | TEST0318: Canonical dictionary deserialization | Tests/CapDAGTests/CSCapTests.m:178 |
| test336 | `test336_file_path_reads_file_passes_bytes` | TEST336: Single file-path arg with stdin source reads file and passes bytes to handler TEST336: Single file-path arg with stdin source reads file and passes bytes to handler. Mirrors Rust test336_file_path_reads_file_passes_bytes. | Tests/BifaciTests/CartridgeRuntimeTests.swift:715 |
| test337 | `test337_file_path_without_stdin_passes_string` | TEST337: file-path arg without stdin source passes path as string (no conversion) | Tests/BifaciTests/CartridgeRuntimeTests.swift:754 |
| test338 | `test338_file_path_via_cli_flag` | TEST338: file-path arg reads file via --file CLI flag | Tests/BifaciTests/CartridgeRuntimeTests.swift:783 |
| test339 | `test339_file_path_array_glob_expansion` | TEST339: A sequence-declared file-path arg (isSequence=true) expands a glob into N files and the runtime delivers them as a CBOR Array of bytes — one item per matched file. List-ness comes from the arg declaration, NOT from any `;list` URN tag. TEST339: A sequence-declared file-path arg expands a glob to N files and the runtime delivers them as a CBOR Array of bytes — one item per matched file. List-ness comes from the arg declaration, not from any `;list` URN tag. Mirrors Rust test339_file_path_array_glob_expansion. | Tests/BifaciTests/CartridgeRuntimeTests.swift:816 |
| test340 | `test340_file_not_found_clear_error` | TEST340: File not found error provides clear message | Tests/BifaciTests/CartridgeRuntimeTests.swift:851 |
| test341 | `test341_stdin_precedence_over_file_path` | TEST341: stdin takes precedence over file-path in source order | Tests/BifaciTests/CartridgeRuntimeTests.swift:880 |
| test342 | `test342_file_path_position_zero_reads_first_arg` | TEST342: file-path with position 0 reads first positional arg as file | Tests/BifaciTests/CartridgeRuntimeTests.swift:909 |
| test343 | `test343_non_file_path_args_unaffected` | TEST343: Non-file-path args are not affected by file reading | Tests/BifaciTests/CartridgeRuntimeTests.swift:935 |
| test346 | `test346_large_file_reads_successfully` | TEST346: Large file (1MB) reads successfully | Tests/BifaciTests/CartridgeRuntimeTests.swift:1017 |
| test347 | `test347_empty_file_reads_as_empty_bytes` | TEST347: Empty file reads as empty bytes. Mirrors Rust test347_empty_file_reads_as_empty_bytes. The file is written non-atomically (`options: []`). The default `Data.write(to:)` overload uses an atomic save, which on macOS for a zero-byte Data on a fresh destination has been observed to throw NSCocoaErrorDomain Code=4 ("couldn't be removed", ENOENT) — Foundation tries to clean up a sibling temp file that was never created. The Rust reference uses `std::fs::write(...)` (non-atomic); matching that here keeps the cross-language test parity honest. Pre-removing any stale file from a prior aborted run keeps the create path clean. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1066 |
| test348 | `test348_file_path_conversion_respects_source_order` | TEST348: file-path conversion respects source order | Tests/BifaciTests/CartridgeRuntimeTests.swift:1093 |
| test349 | `test349_file_path_multiple_sources_fallback` | TEST349: file-path arg with multiple sources tries all in order | Tests/BifaciTests/CartridgeRuntimeTests.swift:1120 |
| test350 | `test350_full_cli_mode_with_file_path_integration` | TEST350: Integration test - full CLI mode invocation with file-path | Tests/BifaciTests/CartridgeRuntimeTests.swift:1152 |
| test352 | `test352_file_permission_denied_clear_error` | TEST352: file permission denied error is clear (Unix-specific) | Tests/BifaciTests/CartridgeRuntimeTests.swift:1226 |
| test353 | `test353_cbor_payload_format_consistency` | TEST353: CBOR payload format matches between CLI and CBOR mode | Tests/BifaciTests/CartridgeRuntimeTests.swift:1265 |
| test354 | `test354_glob_pattern_no_matches_fails_hard` | TEST354: Glob pattern with no matches fails hard (NO FALLBACK) | Tests/BifaciTests/CartridgeRuntimeTests.swift:1327 |
| test355 | `test355_glob_pattern_skips_directories` | TEST355: Glob pattern skips directories | Tests/BifaciTests/CartridgeRuntimeTests.swift:1356 |
| test356 | `test356_multiple_glob_patterns_combined` | TEST356: Multiple glob patterns combined as CBOR Array (CBOR mode). Mirrors Rust test356_multiple_glob_patterns_combined. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1395 |
| test357 | `test357_symlinks_followed` | TEST357: Symlinks are followed when reading files | Tests/BifaciTests/CartridgeRuntimeTests.swift:1454 |
| test358 | `test358_binary_file_non_utf8` | TEST358: Binary file with non-UTF8 data reads correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1489 |
| test359 | `test359_invalid_glob_pattern_fails` | TEST359: Invalid glob pattern fails with clear error | Tests/BifaciTests/CartridgeRuntimeTests.swift:1522 |
| test360 | `test360_extract_effective_payload_with_file_data` | TEST360: Extract effective payload handles file-path data correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1550 |
| test361 | `test361_cli_mode_file_path` | TEST361: CLI mode with file path - pass file path as command-line argument | Tests/BifaciTests/CartridgeRuntimeTests.swift:1749 |
| test362 | `test362_cli_mode_piped_binary` | TEST362: CLI mode with binary piped in - pipe binary data via stdin This test simulates real-world conditions: - Pure binary data piped to stdin (NOT CBOR) - CLI mode detected (command arg present) - Cap accepts stdin source - Binary is chunked on-the-fly and accumulated - Handler receives complete CBOR payload | Tests/BifaciTests/CartridgeRuntimeTests.swift:1787 |
| test363 | `test363_cbor_mode_chunked_content` | TEST363: CBOR mode with chunked content - send file content streaming as chunks | Tests/BifaciTests/CartridgeRuntimeTests.swift:1855 |
| test364 | `test364_cbor_mode_file_path` | TEST364: CBOR mode with file path - file-path arg in CBOR mode is auto-converted to file bytes via extract_effective_payload. Mirrors Rust test364_cbor_mode_file_path. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1926 |
| test365 | `test365_streamStartFrame` | TEST365: Frame::stream_start stores request_id, stream_id, and media_urn | Tests/BifaciTests/FrameTests.swift:1078 |
| test366 | `test366_streamEndFrame` | TEST366: Frame::stream_end stores request_id and stream_id | Tests/BifaciTests/FrameTests.swift:1091 |
| test367 | `test367_streamStartWithEmptyStreamId` | TEST367: StreamStart frame with empty stream_id still constructs (validation happens elsewhere) | Tests/BifaciTests/FrameTests.swift:1104 |
| test368 | `test368_streamStartWithEmptyMediaUrn` | TEST368: StreamStart frame with empty media_urn still constructs (validation happens elsewhere) | Tests/BifaciTests/FrameTests.swift:1116 |
| test0369 | `test0369_CapDocumentationOmittedWhenNil` | When documentation is nil, toDictionary must omit the field entirely. This matches the Rust serializer's skip-when-None semantics and the JS toJSON behaviour. A regression where nil is emitted as `documentation: NSNull` (or simply not omitted) would break the symmetric round-trip with Rust. | Tests/CapDAGTests/CSCapTests.m:960 |
| test0370 | `test0370_MediaDefDocumentationPropagatesThroughResolve` | Documentation propagates from a mediaDefs definition through CSResolveMediaUrn into the resolved CSMediaDef. Mirrors TEST924 on the Rust side and testJS_mediaDefDocumentationPropagatesThroughResolve on the JS side. | Tests/CapDAGTests/CSCapTests.m:996 |
| test0371 | `test0371_CapVersionZeroRoundTrip` | TEST0371: Cap version zero round trip | Tests/CapDAGTests/CSCapTests.m:1035 |
| test0372 | `test0372_CapVersionNonZeroRoundTrip` | TEST0372: Cap version non zero round trip | Tests/CapDAGTests/CSCapTests.m:1068 |
| test389 | `test389_streamStartRoundtrip` | TEST389: StreamStart encode/decode roundtrip preserves stream_id and media_urn | Tests/BifaciTests/FrameTests.swift:1128 |
| test390 | `test390_streamEndRoundtrip` | TEST390: StreamEnd encode/decode roundtrip preserves stream_id, no media_urn | Tests/BifaciTests/FrameTests.swift:1164 |
| test395 | `test395_build_payload_small` | TEST395: Small payload (< max_chunk) produces correct CBOR arguments | Tests/BifaciTests/CartridgeRuntimeTests.swift:1602 |
| test396 | `test396_build_payload_large` | TEST396: Large payload (> max_chunk) accumulates across chunks correctly | Tests/BifaciTests/CartridgeRuntimeTests.swift:1640 |
| test397 | `test397_build_payload_empty` | TEST397: Empty reader produces valid empty CBOR arguments | Tests/BifaciTests/CartridgeRuntimeTests.swift:1670 |
| test398 | `test398_build_payload_io_error` | TEST398: IO error from reader propagates as RuntimeError::Io | Tests/BifaciTests/CartridgeRuntimeTests.swift:1728 |
| test399 | `test399_relayNotifyDiscriminantRoundtrip` | TEST399: Verify RelayNotify frame type discriminant roundtrips through u8 (value 10) | Tests/BifaciTests/FrameTests.swift:1182 |
| test400 | `test400_relayStateDiscriminantRoundtrip` | TEST400: Verify RelayState frame type discriminant roundtrips through u8 (value 11) | Tests/BifaciTests/FrameTests.swift:1190 |
| test401 | `test401_relayNotifyFactoryAndAccessors` | TEST401: Verify relay_notify factory stores manifest and limits, and accessors extract them | Tests/BifaciTests/FrameTests.swift:1198 |
| test402 | `test402_relayStateFactoryAndPayload` | TEST402: Verify relay_state factory stores resource payload in frame payload field | Tests/BifaciTests/FrameTests.swift:1224 |
| test403 | `test403_invalidFrameTypePastCancel` | TEST403: Verify from_u8 returns None for values past the last valid frame type | Tests/BifaciTests/FrameTests.swift:1234 |
| test404 | `test404_slaveSendsRelayNotifyOnConnect` | TEST404: Slave sends RelayNotify on connect (initial_notify parameter) | Tests/BifaciTests/RelayTests.swift:19 |
| test405 | `test405_masterReadsRelayNotify` | TEST405: Master reads RelayNotify and extracts manifest + limits | Tests/BifaciTests/RelayTests.swift:50 |
| test406 | `test406_slaveStoresRelayState` | TEST406: Slave stores RelayState from master | Tests/BifaciTests/RelayTests.swift:76 |
| test407 | `test407_protocolFramesPassThrough` | TEST407: Protocol frames pass through slave transparently (both directions) | Tests/BifaciTests/RelayTests.swift:104 |
| test408 | `test408_relayFramesNotForwarded` | TEST408: RelayNotify/RelayState are NOT forwarded through relay | Tests/BifaciTests/RelayTests.swift:163 |
| test409 | `test409_slaveInjectsRelayNotifyMidstream` | TEST409: Slave can inject RelayNotify mid-stream (cap change) | Tests/BifaciTests/RelayTests.swift:197 |
| test410 | `test410_masterReceivesUpdatedRelayNotify` | TEST410: Master receives updated RelayNotify (cap change callback via read_frame) | Tests/BifaciTests/RelayTests.swift:235 |
| test411 | `test411_socketCloseDetection` | TEST411: Socket close detection (both directions) | Tests/BifaciTests/RelayTests.swift:284 |
| test412 | `test412_bidirectionalConcurrentFlow` | TEST412: Bidirectional concurrent frame flow through relay | Tests/BifaciTests/RelayTests.swift:310 |
| test413 | `test413_registerCartridgeAddsToCaptable` | TEST413: Register cartridge adds entries to cap_table | Tests/BifaciTests/RuntimeTests.swift:312 |
| test414 | `test414_relaySlaveForwardsHostRelayNotify` | TEST414: RelaySlave forwards a host-originated RelayNotify (local→socket), dropping only RelayState. The CartridgeHost publishes capability updates — the installed-cartridge inventory the engine routes by — as RelayNotify frames through the slave's local→socket path; the slave MUST forward them. Regression lock for the drift (reproduced in the go mirror) where Task 2 dropped RelayNotify alongside RelayState, stranding the host's inventory so the engine never learned the cartridge existed. Unlike test407/test408 (which hand-roll the forwarding), this drives the real RelaySlave.run() loop. | Tests/BifaciTests/RelayTests.swift:364 |
| test415 | `test415_reqTriggersSpawnError` | TEST415: REQ for known cap triggers spawn attempt (verified by expected spawn error). Mirrors Rust test415_req_for_known_cap_triggers_spawn: production install layout — versioned cartridge directory with cartridge.json (carrying the channel) plus an entry-point binary that isn't executable, so spawn fails. | Tests/BifaciTests/RuntimeTests.swift:695 |
| test416 | `test416_attachCartridgeUpdatesCaps` | TEST416: Attach cartridge performs HELLO handshake, extracts manifest, updates capabilities | Tests/BifaciTests/RuntimeTests.swift:339 |
| test417 | `test417_fullPathRequestResponse` | TEST417: Route REQ to correct cartridge by cap_urn (with two attached cartridges) | Tests/BifaciTests/RuntimeTests.swift:369 |
| test418 | `test418_routeContinuationByReqId` | TEST418: Route STREAM_START/CHUNK/STREAM_END/END by req_id (not cap_urn) Verifies that after the initial REQ→cartridge routing, all subsequent continuation frames with the same req_id are routed to the same cartridge — even though no cap_urn is present on those frames. | Tests/BifaciTests/RuntimeTests.swift:735 |
| test419 | `test419_heartbeatHandledLocally` | TEST419: Cartridge HEARTBEAT handled locally (not forwarded to relay) | Tests/BifaciTests/RuntimeTests.swift:445 |
| test420 | `test420_cartridgeFramesForwardedToRelay` | TEST420: Cartridge non-HELLO/non-HB frames forwarded to relay (pass-through) | Tests/BifaciTests/RuntimeTests.swift:821 |
| test421 | `test421_cartridgeDeathUpdatesCaps` | TEST421: Cartridge death updates capability list (caps removed) | Tests/BifaciTests/RuntimeTests.swift:895 |
| test422 | `test422_cartridgeDeathSendsErr` | TEST422: Cartridge death sends ERR for all pending requests via relay | Tests/BifaciTests/RuntimeTests.swift:947 |
| test423 | `test423_multipleCartridgesRouteIndependently` | TEST423: Multiple cartridges registered with distinct caps route independently | Tests/BifaciTests/RuntimeTests.swift:522 |
| test424 | `test424_concurrentRequestsSameCartridge` | TEST424: Concurrent requests to the same cartridge are handled independently | Tests/BifaciTests/RuntimeTests.swift:1014 |
| test425 | `test425_findCartridgeForCapUnknown` | TEST425: find_cartridge_for_cap returns None for unregistered cap | Tests/BifaciTests/RuntimeTests.swift:329 |
| test426 | `test426_single_master_req_response` | TEST426: Single master REQ/response routing | Tests/BifaciTests/RelaySwitchTests.swift:80 |
| test427 | `test427_multi_master_cap_routing` | TEST427: Multi-master cap routing | Tests/BifaciTests/RelaySwitchTests.swift:139 |
| test428 | `test428_unknown_cap_returns_error` | TEST428: Unknown cap returns error | Tests/BifaciTests/RelaySwitchTests.swift:234 |
| test429 | `test429_find_master_for_cap` | TEST429: Cap routing logic (find_master_for_cap) | Tests/BifaciTests/RelaySwitchTests.swift:275 |
| test430 | `test430_tie_breaking_same_cap_multiple_masters` | TEST430: Tie-breaking (same cap on multiple masters - first match wins, routing is consistent) | Tests/BifaciTests/RelaySwitchTests.swift:320 |
| test431 | `test431_continuation_frame_routing` | TEST431: Continuation frame routing (CHUNK, END follow REQ) | Tests/BifaciTests/RelaySwitchTests.swift:401 |
| test432 | `test432_empty_masters_allowed` | TEST432: Empty masters list creates empty switch, add_master works | Tests/BifaciTests/RelaySwitchTests.swift:466 |
| test433 | `test433_capability_aggregation_deduplicates` | TEST433: Capability aggregation deduplicates caps | Tests/BifaciTests/RelaySwitchTests.swift:483 |
| test434 | `test434_limits_negotiation_minimum` | TEST434: Limits negotiation takes minimum | Tests/BifaciTests/RelaySwitchTests.swift:538 |
| test435 | `test435_urn_matching_exact_and_accepts` | TEST435: URN matching (exact vs accepts()) Dispatch is contravariant on input (request input must conform to provider input — i.e. request can be more specific) and covariant on output (provider output must conform to request output — i.e. provider can be more specific). A request whose input is in a different type family than any registered provider has no handler. | Tests/BifaciTests/RelaySwitchTests.swift:588 |
| test436 | `test436_computeChecksum` | TEST436: Verify FNV-1a checksum function produces consistent results | Tests/BifaciTests/FrameTests.swift:1365 |
| test437 | `test437_preferredCapRoutesToExactMatch` | TEST437: find_master_for_cap with preferred_cap routes to generic handler With is_dispatchable semantics: - Generic provider (in=media:) CAN dispatch specific request (in="media:ext=pdf") because media: (wildcard) accepts any input type - Preference routes to preferred among dispatchable candidates | Tests/BifaciTests/RelaySwitchTests.swift:662 |
| test438 | `test438_preferredCapExactMatch` | TEST438: find_master_for_cap with preference falls back to closest-specificity when preferred cap is not in the comparable set | Tests/BifaciTests/RelaySwitchTests.swift:702 |
| test439 | `test439_specificRequestNoMatchingHandler` | TEST439: Generic provider CAN dispatch specific request (but only matches if no more specific provider exists) With is_dispatchable: generic provider (in=media:) CAN handle specific request (in="media:ext=pdf") because media: accepts any input type. With preference, can route to generic even when more specific exists. | Tests/BifaciTests/RelaySwitchTests.swift:742 |
| test440 | `test440_chunkIndexChecksumRoundtrip` | TEST440: CHUNK frame with chunk_index and checksum roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:1389 |
| test441 | `test441_streamEndChunkCountRoundtrip` | TEST441: STREAM_END frame with chunk_count roundtrips through encode/decode | Tests/BifaciTests/FrameTests.swift:1407 |
| test442 | `test442_seqAssignerMonotonicSameRid` | TEST442: SeqAssigner assigns seq 0,1,2,3 for consecutive frames with same RID | Tests/BifaciTests/FlowOrderingTests.swift:11 |
| test443 | `test443_seqAssignerIndependentRids` | TEST443: SeqAssigner maintains independent counters for different RIDs | Tests/BifaciTests/FlowOrderingTests.swift:32 |
| test444 | `test444_seqAssignerSkipsNonFlow` | TEST444: SeqAssigner skips non-flow frames (Heartbeat, RelayNotify, RelayState, Hello) | Tests/BifaciTests/FlowOrderingTests.swift:57 |
| test445 | `test445_seqAssignerRemoveByFlowKey` | TEST445: SeqAssigner.remove with FlowKey(rid, None) resets that flow; FlowKey(rid, Some(xid)) is unaffected | Tests/BifaciTests/FlowOrderingTests.swift:77 |
| test446 | `test446_seqAssignerMixedTypes` | TEST446: SeqAssigner handles mixed frame types (REQ, CHUNK, LOG, END) for same RID | Tests/BifaciTests/FlowOrderingTests.swift:146 |
| test447 | `test447_flowKeyWithXid` | TEST447: FlowKey::from_frame extracts (rid, Some(xid)) when routing_id present | Tests/BifaciTests/FlowOrderingTests.swift:169 |
| test448 | `test448_flowKeyWithoutXid` | TEST448: FlowKey::from_frame extracts (rid, None) when routing_id absent | Tests/BifaciTests/FlowOrderingTests.swift:181 |
| test449 | `test449_flowKeyEquality` | TEST449: FlowKey equality: same rid+xid equal, different xid different key | Tests/BifaciTests/FlowOrderingTests.swift:191 |
| test450 | `test450_flowKeyHash` | TEST450: FlowKey hash: same keys hash equal (HashMap lookup) | Tests/BifaciTests/FlowOrderingTests.swift:207 |
| test451 | `test451_reorderBufferInOrder` | TEST451: ReorderBuffer in-order delivery: seq 0,1,2 delivered immediately | Tests/BifaciTests/FlowOrderingTests.swift:226 |
| test452 | `test452_reorderBufferOutOfOrder` | TEST452: ReorderBuffer out-of-order: seq 1 then 0 delivers both in order | Tests/BifaciTests/FlowOrderingTests.swift:248 |
| test453 | `test453_reorderBufferGapFill` | TEST453: ReorderBuffer gap fill: seq 0,2,1 delivers 0, buffers 2, then delivers 1+2 | Tests/BifaciTests/FlowOrderingTests.swift:266 |
| test454 | `test454_reorderBufferStaleSeq` | TEST454: ReorderBuffer stale seq is hard error | Tests/BifaciTests/FlowOrderingTests.swift:289 |
| test455 | `test455_reorderBufferOverflow` | TEST455: ReorderBuffer overflow triggers protocol error | Tests/BifaciTests/FlowOrderingTests.swift:307 |
| test456 | `test456_reorderBufferMultipleFlows` | TEST456: Multiple concurrent flows reorder independently | Tests/BifaciTests/FlowOrderingTests.swift:328 |
| test457 | `test457_reorderBufferCleanupFlow` | TEST457: cleanup_flow removes state; new frames start at seq 0 | Tests/BifaciTests/FlowOrderingTests.swift:357 |
| test458 | `test458_reorderBufferNonFlowBypass` | TEST458: Non-flow frames bypass reorder entirely | Tests/BifaciTests/FlowOrderingTests.swift:377 |
| test459 | `test459_reorderBufferTerminalEnd` | TEST459: Terminal END frame flows through correctly | Tests/BifaciTests/FlowOrderingTests.swift:390 |
| test460 | `test460_reorderBufferTerminalErr` | TEST460: Terminal ERR frame flows through correctly | Tests/BifaciTests/FlowOrderingTests.swift:408 |
| test461 | `test461_writeChunkedSeqZero` | TEST461: write_chunked produces frames with seq=0; SeqAssigner assigns at output stage | Tests/BifaciTests/FlowOrderingTests.swift:427 |
| test462 | `test462_attachedCartridgeIdentityFromManifest` | TEST462: An attached cartridge (pre-connected over raw streams, no on-disk anchor) gets a resolvable install identity derived from its HELLO manifest — `installedCartridgeRecordFromManifest`. Identity gates advertisement (`buildInstalledCartridgeRecordsLocked` drops a cartridge whose record is nil), so a nil here means the cartridge is silently dropped from every RelayNotify and the engine can never route to it. Regression lock for the attached-cartridge identity path this mirror regressed on: `installedCartridgeRecord()` returned nil for attached cartridges, so they never reached the engine. Mirrors the reference `installed_cartridge_record_from_manifest`. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:281 |
| test472 | `test472_handshakeNegotiatesReorderBuffer` | TEST472: Handshake negotiates max_reorder_buffer (minimum of both sides) | Tests/BifaciTests/FlowOrderingTests.swift:457 |
| test473 | `test473_capDiscardParsesAsValidCapUrn` | TEST473: CAP_DISCARD parses as valid CapUrn with in=media: and out=media:void | Tests/BifaciTests/StandardCapsTests.swift:14 |
| test474 | `test474_capDiscardAcceptsVoidOutputCaps` | TEST474: CAP_DISCARD accepts specific-input/void-output caps | Tests/BifaciTests/StandardCapsTests.swift:23 |
| test478 | `test478_cartridgeRuntimeAutoRegistersIdentity` | TEST478: CartridgeRuntime auto-registers identity and discard handlers on construction | Tests/BifaciTests/StandardCapsTests.swift:135 |
| test479 | `test479_identityHandlerEchoesInput` | TEST479: Custom identity Op overrides auto-registered default | Tests/BifaciTests/StandardCapsTests.swift:150 |
| test480 | `test480_discardHandlerConsumesInput` | TEST480: parse_caps_from_manifest rejects manifest without CAP_IDENTITY | Tests/BifaciTests/StandardCapsTests.swift:218 |
| test481 | `test481_verifyIdentitySucceeds` | TEST481: verify_identity succeeds with standard identity echo handler | Tests/BifaciTests/IntegrationTests.swift:497 |
| test482 | `test482_verifyIdentityFailsOnErr` | TEST482: verify_identity fails when cartridge returns ERR on identity call | Tests/BifaciTests/IntegrationTests.swift:584 |
| test483 | `test483_verifyIdentityFailsOnClose` | TEST483: verify_identity fails when connection closes before response | Tests/BifaciTests/IntegrationTests.swift:927 |
| test485 | `test485_attachCartridgeIdentityVerificationSucceeds` | TEST485: attach_cartridge completes identity verification with working cartridge | Tests/BifaciTests/RuntimeTests.swift:1378 |
| test486 | `test486_attachCartridgeIdentityVerificationFails` | TEST486: attach_cartridge rejects cartridge that fails identity verification | Tests/BifaciTests/RuntimeTests.swift:1451 |
| test487 | `test487_relaySwitchIdentityVerificationSucceeds` | TEST487: RelaySwitch construction verifies identity through relay chain | Tests/BifaciTests/RelaySwitchTests.swift:780 |
| test488 | `test488_relaySwitchIdentityVerificationFails` | TEST488: RelaySwitch construction fails when master's identity verification fails | Tests/BifaciTests/RelaySwitchTests.swift:809 |
| test490 | `test490_identityVerificationMultipleCartridges` | TEST490: Identity verification with multiple cartridges through single relay Both cartridges must pass identity verification independently before any real requests are routed. | Tests/BifaciTests/RuntimeTests.swift:1505 |
| test491 | `test491_chunkRequiresChunkIndexAndChecksum` | TEST491: Frame::chunk constructor requires and sets chunk_index and checksum | Tests/BifaciTests/FrameTests.swift:1421 |
| test492 | `test492_streamEndRequiresChunkCount` | TEST492: Frame::stream_end constructor requires and sets chunk_count | Tests/BifaciTests/FrameTests.swift:1433 |
| test493 | `test493_computeChecksumFnv1aTestVectors` | TEST493: compute_checksum produces correct FNV-1a hash for known test vectors | Tests/BifaciTests/FrameTests.swift:1442 |
| test494 | `test494_computeChecksumDeterministic` | TEST494: compute_checksum is deterministic | Tests/BifaciTests/FrameTests.swift:1460 |
| test495 | `test495_cborRejectsChunkWithoutChunkIndex` | TEST495: CBOR decode REJECTS CHUNK frame missing chunk_index field | Tests/BifaciTests/FrameTests.swift:1472 |
| test496 | `test496_cborRejectsChunkWithoutChecksum` | TEST496: CBOR decode REJECTS CHUNK frame missing checksum field | Tests/BifaciTests/FrameTests.swift:1496 |
| test497 | `test497_chunkCorruptedPayloadRejected` | TEST497: Verify CHUNK frame with corrupted payload is rejected by checksum | Tests/BifaciTests/FrameTests.swift:1520 |
| test498 | `test498_routingIdCborRoundtrip` | TEST498: routing_id field roundtrips through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1536 |
| test499 | `test499_chunkIndexChecksumCborRoundtrip` | TEST499: chunk_index and checksum roundtrip through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1550 |
| test500 | `test500_chunkCountCborRoundtrip` | TEST500: chunk_count roundtrips through CBOR encoding | Tests/BifaciTests/FrameTests.swift:1565 |
| test501 | `test501_frameNewInitializesOptionalFieldsNone` | TEST501: Frame::new initializes new fields to None | Tests/BifaciTests/FrameTests.swift:1577 |
| test502 | `test502_keysModuleNewFieldConstants` | TEST502: Keys module has constants for new fields | Tests/BifaciTests/FrameTests.swift:1587 |
| test503 | `test503_computeChecksumEmptyData` | TEST503: compute_checksum handles empty data correctly | Tests/BifaciTests/FrameTests.swift:1595 |
| test504 | `test504_computeChecksumLargePayload` | TEST504: compute_checksum handles large payloads without overflow | Tests/BifaciTests/FrameTests.swift:1603 |
| test505 | `test505_chunkWithOffsetSetsChunkIndex` | TEST505: chunk_with_offset sets chunk_index correctly | Tests/BifaciTests/FrameTests.swift:1614 |
| test506 | `test506_computeChecksumDifferentDataDifferentHash` | TEST506: Different data produces different checksums | Tests/BifaciTests/FrameTests.swift:1637 |
| test507 | `test507_reorderBufferXidIsolation` | TEST507: ReorderBuffer isolates flows by XID (routing_id) - same RID different XIDs | Tests/BifaciTests/FlowOrderingTests.swift:496 |
| test508 | `test508_reorderBufferDuplicateBufferedSeq` | TEST508: ReorderBuffer rejects duplicate seq already in buffer | Tests/BifaciTests/FlowOrderingTests.swift:519 |
| test509 | `test509_reorderBufferLargeGapRejected` | TEST509: ReorderBuffer handles large seq gaps without DOS | Tests/BifaciTests/FlowOrderingTests.swift:540 |
| test510 | `test510_reorderBufferMultipleGaps` | TEST510: ReorderBuffer with multiple interleaved gaps fills correctly | Tests/BifaciTests/FlowOrderingTests.swift:565 |
| test511 | `test511_reorderBufferRejectsStaleSeq` | TEST511: ReorderBuffer cleanup with buffered frames discards them | Tests/BifaciTests/FlowOrderingTests.swift:591 |
| test512 | `test512_reorderBufferNonFlowFramesBypass` | TEST512: ReorderBuffer delivers burst of consecutive buffered frames | Tests/BifaciTests/FlowOrderingTests.swift:614 |
| test513 | `test513_reorderBufferCleanup` | TEST513: ReorderBuffer different frame types in same flow maintain order | Tests/BifaciTests/FlowOrderingTests.swift:635 |
| test514 | `test514_reorderBufferRespectsMaxBuffer` | TEST514: ReorderBuffer with XID cleanup doesn't affect different XID | Tests/BifaciTests/FlowOrderingTests.swift:653 |
| test515 | `test515_seqAssignerRemoveByFlowKey` | TEST515: ReorderBuffer overflow error includes diagnostic information | Tests/BifaciTests/FlowOrderingTests.swift:678 |
| test516 | `test516_seqAssignerIndependentFlowsByXid` | TEST516: ReorderBuffer stale error includes diagnostic information | Tests/BifaciTests/FlowOrderingTests.swift:701 |
| test517 | `test517_flowKeyNilXidSeparate` | TEST517: FlowKey with None XID differs from Some(xid) | Tests/BifaciTests/FlowOrderingTests.swift:733 |
| test518 | `test518_reorderBufferFlowCleanupAfterEnd` | TEST518: ReorderBuffer handles zero-length ready vec correctly | Tests/BifaciTests/FlowOrderingTests.swift:764 |
| test519 | `test519_reorderBufferMultipleRids` | TEST519: ReorderBuffer state persists across accept calls | Tests/BifaciTests/FlowOrderingTests.swift:786 |
| test520 | `test520_reorderBufferDrainsBufferedFrames` | TEST520: ReorderBuffer max_buffer_per_flow is per-flow not global | Tests/BifaciTests/FlowOrderingTests.swift:808 |
| test521 | `test521_relayNotifyCborRoundtrip` | TEST521: RelayNotify CBOR roundtrip preserves manifest and limits | Tests/BifaciTests/FrameTests.swift:1242 |
| test522 | `test522_relayStateCborRoundtrip` | TEST522: RelayState CBOR roundtrip preserves payload | Tests/BifaciTests/FrameTests.swift:1263 |
| test523 | `test523_relayNotifyNotFlowFrame` | TEST523: is_flow_frame returns false for RelayNotify | Tests/BifaciTests/FrameTests.swift:1652 |
| test524 | `test524_relayStateNotFlowFrame` | TEST524: is_flow_frame returns false for RelayState | Tests/BifaciTests/FrameTests.swift:1658 |
| test525 | `test525_relayNotifyEmptyManifest` | TEST525: RelayNotify with empty manifest is valid | Tests/BifaciTests/FrameTests.swift:1664 |
| test526 | `test526_relayStateEmptyPayload` | TEST526: RelayState with empty payload is valid | Tests/BifaciTests/FrameTests.swift:1675 |
| test527 | `test527_relayNotifyLargeManifest` | TEST527: RelayNotify with large manifest roundtrips correctly | Tests/BifaciTests/FrameTests.swift:1686 |
| test528 | `test528_relayFramesUseUintZeroId` | TEST528: RelayNotify and RelayState use MessageId::Uint(0) | Tests/BifaciTests/FrameTests.swift:1698 |
| test529 | `test529_inputStreamIteratorOrder` | TEST529: InputStream recv yields chunks in order | Tests/BifaciTests/StreamingAPITests.swift:20 |
| test530 | `test530_inputStreamCollectBytes` | TEST530: InputStream::collect_bytes concatenates byte chunks | Tests/BifaciTests/StreamingAPITests.swift:57 |
| test531 | `test531_inputStreamCollectBytesText` | TEST531: InputStream::collect_bytes handles text chunks | Tests/BifaciTests/StreamingAPITests.swift:79 |
| test532 | `test532_inputStreamEmpty` | TEST532: InputStream empty stream produces empty bytes | Tests/BifaciTests/StreamingAPITests.swift:101 |
| test533 | `test533_inputStreamErrorPropagation` | TEST533: InputStream propagates errors | Tests/BifaciTests/StreamingAPITests.swift:119 |
| test534 | `test534_inputStreamMediaUrn` | TEST534: InputStream::media_urn returns correct URN | Tests/BifaciTests/StreamingAPITests.swift:146 |
| test535 | `test535_inputPackageIteration` | TEST535: InputPackage recv yields streams | Tests/BifaciTests/StreamingAPITests.swift:156 |
| test536 | `test536_inputPackageCollectAllBytes` | TEST536: InputPackage::collect_all_bytes aggregates all streams | Tests/BifaciTests/StreamingAPITests.swift:202 |
| test537 | `test537_inputPackageEmpty` | TEST537: InputPackage empty package produces empty bytes | Tests/BifaciTests/StreamingAPITests.swift:243 |
| test538 | `test538_inputPackageErrorPropagation` | TEST538: InputPackage propagates stream errors | Tests/BifaciTests/StreamingAPITests.swift:261 |
| test539 | `test539_outputStreamSendsStreamStart` | TEST539: OutputStream sends STREAM_START on first write | Tests/BifaciTests/StreamingAPITests.swift:289 |
| test540 | `test540_outputStreamCloseSendsStreamEnd` | TEST540: OutputStream::close sends STREAM_END with correct chunk_count | Tests/BifaciTests/StreamingAPITests.swift:319 |
| test541 | `test541_outputStreamChunksLargeData` | TEST541: OutputStream chunks large data correctly | Tests/BifaciTests/StreamingAPITests.swift:350 |
| test542 | `test542_outputStreamCloseWithoutStartIsNoop` | TEST542: OutputStream empty stream sends STREAM_START and STREAM_END only | Tests/BifaciTests/StreamingAPITests.swift:385 |
| test543 | `test543_peerCallArgCreatesStream` | TEST543: PeerCall::arg creates OutputStream with correct stream_id | Tests/BifaciTests/StreamingAPITests.swift:490 |
| test544 | `test544_peerCallFinishSendsEnd` | TEST544: PeerCall::finish sends END frame | Tests/BifaciTests/StreamingAPITests.swift:519 |
| test545 | `test545_peerCallFinishReturnsPeerResponse` | TEST545: PeerCall::finish returns PeerResponse with data | Tests/BifaciTests/StreamingAPITests.swift:541 |
| test546 | `test546_is_image` | TEST546: is_image returns true only when image marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:217 |
| test547 | `test547_is_audio` | TEST547: is_audio returns true only when audio marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:229 |
| test548 | `test548_is_video` | TEST548: is_video returns true only when video marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:240 |
| test549 | `test549_is_numeric` | TEST549: is_numeric returns true only when numeric marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:250 |
| test550 | `test550_is_bool` | TEST550: is_bool returns true only when bool marker tag is present | Tests/CapDAGTests/CSMediaUrnTests.m:262 |
| test551 | `test551_is_file_path` | TEST551: is_file_path returns true for the single file-path media URN, false for everything else. There is no "array" variant — cardinality is carried by is_sequence on the wire, not by URN tags. | Tests/CapDAGTests/CSMediaUrnTests.m:274 |
| test555 | `test555_with_tag_and_without_tag` | TEST555: with_tag adds a tag and without_tag removes it | Tests/CapDAGTests/CSMediaUrnTests.m:282 |
| test558 | `test558_predicate_constant_consistency` | TEST558: predicates are consistent with constants — every constant triggers exactly the expected predicates | Tests/CapDAGTests/CSMediaUrnTests.m:300 |
| test559 | `test559_withoutTag` | TEST559: withoutTag removes a tag and returns a new URN, leaving the original unchanged (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:432 |
| test566 | `test566_withTagRejectsStructuralKeys` | TEST566: with_tag rejects structural keys | Tests/CapDAGTests/CSCapUrnTests.m:399 |
| test597 | `test597_capArgWithFullDefinition` | TEST597: CapArg::with_full_definition stores all fields including optional ones | Tests/CapDAGTests/CSCapTests.m:873 |
| test614 | `test614_RegistryCreation` | TEST614: Registry creation. Uses the network-free test constructor — the production `init` blocks on a manifest fetch (and fails hard if the registry is unreachable), so unit tests use initForTest, mirroring Rust new_for_test. | Tests/CapDAGTests/CSFabricRegistryTests.m:131 |
| test638 | `test638_noPeerRouterRejectsAll` | TEST638: Verify NoPeerRouter rejects all requests with PeerInvokeNotSupported | Tests/BifaciTests/RouterTests.swift:14 |
| test639 | `test639_Wildcard001EmptyCapIsIllegal` | TEST_WILDCARD_001: cap: (empty) is illegal | Tests/CapDAGTests/CSCapUrnTests.m:1025 |
| test640 | `test640_Wildcard002InOnlyIsIllegal` | TEST_WILDCARD_002: cap:in collapses to the same illegal bare top form | Tests/CapDAGTests/CSCapUrnTests.m:1033 |
| test641 | `test641_Wildcard003OutOnlyIsIllegal` | TEST_WILDCARD_003: cap:out collapses to the same illegal bare top form | Tests/CapDAGTests/CSCapUrnTests.m:1041 |
| test0643 | `test0643_Wildcard005ExplicitAsteriskIsIllegal` | TEST_WILDCARD_005: cap:in=*;out=* is illegal | Tests/CapDAGTests/CSCapUrnTests.m:1057 |
| test0644 | `test0644_Wildcard006SpecificInWildcardOutIsIllegal` | TEST_WILDCARD_006: cap:in=media:;out=* is illegal | Tests/CapDAGTests/CSCapUrnTests.m:1065 |
| test0645 | `test0645_Wildcard007WildcardInSpecificOut` | TEST_WILDCARD_007: cap:in=*;out=media:text has wildcard in, specific out | Tests/CapDAGTests/CSCapUrnTests.m:1073 |
| test0646 | `test0646_Wildcard008InvalidInSpecFails` | TEST_WILDCARD_008: cap:in=foo fails (invalid media URN) | Tests/CapDAGTests/CSCapUrnTests.m:1082 |
| test0647 | `test0647_Wildcard009InvalidOutSpecFails` | TEST_WILDCARD_009: cap:in=media:;out=bar fails (invalid media URN) | Tests/CapDAGTests/CSCapUrnTests.m:1091 |
| test648 | `test648_Wildcard010WildcardAcceptsSpecific` | TEST_WILDCARD_010: Wildcard in/out match specific caps | Tests/CapDAGTests/CSCapUrnTests.m:1100 |
| test649 | `test649_Wildcard011SpecificityScoring` | TEST_WILDCARD_011: Specificity - wildcard has 0, specific has tag count | Tests/CapDAGTests/CSCapUrnTests.m:1110 |
| test0650 | `test0650_Wildcard012PreserveOtherTags` | TEST_WILDCARD_012: cap:in=media:;out=media:;test preserves other tags | Tests/CapDAGTests/CSCapUrnTests.m:1120 |
| test658 | `test658_heartbeatResponse` | TEST658: InProcessCartridgeHost handles heartbeat by echoing same ID | Tests/BifaciTests/InProcessCartridgeHostTests.swift:314 |
| test659 | `test659_handlerErrorReturnsErrFrame` | TEST659: InProcessCartridgeHost handler error returns ERR frame | Tests/BifaciTests/InProcessCartridgeHostTests.swift:348 |
| test660 | `test660_closestSpecificityRouting` | TEST660: InProcessCartridgeHost closest-specificity routing prefers specific over identity | Tests/BifaciTests/InProcessCartridgeHostTests.swift:394 |
| test662 | `test662_rebuildCapabilitiesIncludesNonRunningCartridges` | TEST662: rebuild_capabilities includes non-running cartridges' caps (each cartridge's `cap_groups` is the source of truth, regardless of whether its process has been spawned yet). | Tests/BifaciTests/RuntimeTests.swift:1150 |
| test663 | `test663_helloFailedCartridgeRemovedFromCapabilities` | TEST663: Cartridge with hello_failed is permanently removed from capabilities | Tests/BifaciTests/RuntimeTests.swift:1175 |
| test664 | `test664_runningCartridgeUsesManifestCaps` | TEST664: Running cartridge uses manifest caps, not known_caps | Tests/BifaciTests/RuntimeTests.swift:1214 |
| test665 | `test665_capTableMixedRunningAndNonRunning` | TEST665: Cap table aggregates caps from every healthy cartridge — attached/running cartridges contribute their post-HELLO cap_groups, registered-but-not-yet-spawned cartridges contribute their probe-time cap_groups. Both flow through the same `cap_urns()` view. | Tests/BifaciTests/RuntimeTests.swift:1253 |
| test667 | `test667_verifyChunkChecksumDetectsCorruption` | TEST667: verify_chunk_checksum detects corrupted payload | Tests/BifaciTests/FrameTests.swift:1275 |
| test678 | `test678_findStreamEquivalentUrnDifferentTagOrder` | TEST678: find_stream with exact equivalent URN (same tags, different order) succeeds | Tests/BifaciTests/StreamingAPITests.swift:578 |
| test679 | `test679_findStreamBaseUrnDoesNotMatchFullUrn` | TEST679: find_stream with base URN vs full URN fails — is_equivalent is strict This is the root cause of the cartridge_client.rs bug. Sender sent "media:llm-generation-request" but receiver looked for "media:fmt=json;llm-generation-request;record". | Tests/BifaciTests/StreamingAPITests.swift:591 |
| test680 | `test680_requireStreamMissingUrnReturnsError` | TEST680: require_stream with missing URN returns hard StreamError | Tests/BifaciTests/StreamingAPITests.swift:602 |
| test681 | `test681_findStreamMultipleStreamsReturnsCorrect` | TEST681: find_stream with multiple streams returns the correct one | Tests/BifaciTests/StreamingAPITests.swift:617 |
| test682 | `test682_requireStreamStrReturnsUtf8` | TEST682: require_stream_str returns UTF-8 string for text data | Tests/BifaciTests/StreamingAPITests.swift:635 |
| test683 | `test683_findStreamInvalidUrnReturnsNone` | TEST683: find_stream returns None for invalid media URN string (not a parse error — just None) | Tests/BifaciTests/StreamingAPITests.swift:645 |
| test688 | `test688_is_multiple` | TEST688: Tests is_multiple method correctly identifies multi-value cardinalities Verifies Single returns false while Sequence and AtLeastOne return true | Tests/CapDAGTests/CSCardinalityTests.m:21 |
| test689 | `test689_accepts_single` | TEST689: Tests accepts_single method identifies cardinalities that accept single values Verifies Single and AtLeastOne accept singles while Sequence does not | Tests/CapDAGTests/CSCardinalityTests.m:28 |
| test690 | `test690_compatibility_single_to_single` | TEST690: Tests cardinality compatibility for single-to-single data flow Verifies Direct compatibility when both input and output are Single | Tests/CapDAGTests/CSCardinalityTests.m:37 |
| test691 | `test691_compatibility_single_to_vector` | TEST691: Tests cardinality compatibility when wrapping single value into array Verifies WrapInArray compatibility when Sequence expects Single input | Tests/CapDAGTests/CSCardinalityTests.m:43 |
| test692 | `test692_compatibility_vector_to_single` | TEST692: Tests cardinality compatibility when unwrapping array to singles Verifies RequiresFanOut compatibility when Single expects Sequence input | Tests/CapDAGTests/CSCardinalityTests.m:49 |
| test693 | `test693_compatibility_vector_to_vector` | TEST693: Tests cardinality compatibility for sequence-to-sequence data flow Verifies Direct compatibility when both input and output are Sequence | Tests/CapDAGTests/CSCardinalityTests.m:55 |
| test697 | `test697_cap_shape_info_one_to_one` | TEST697: Tests CapShapeInfo correctly identifies one-to-one pattern Verifies Single input and Single output result in OneToOne pattern | Tests/CapDAGTests/CSCardinalityTests.m:63 |
| test698 | `test698_cap_shape_info_cardinality_always_single_from_urn` | TEST698: CapShapeInfo cardinality is always Single when derived from URN Cardinality comes from context (is_sequence), not from URN tags. The list tag is a semantic type property, not a cardinality indicator. | Tests/CapDAGTests/CSCardinalityTests.m:71 |
| test699 | `test699_cap_shape_info_list_urn_still_single_cardinality` | TEST699: CapShapeInfo cardinality from URN is always Single; ManyToOne requires is_sequence | Tests/CapDAGTests/CSCardinalityTests.m:79 |
| test709 | `test709_pattern_produces_vector` | TEST709: Tests CardinalityPattern correctly identifies patterns that produce vectors Verifies OneToMany and ManyToMany return true, others return false | Tests/CapDAGTests/CSCardinalityTests.m:100 |
| test710 | `test710_pattern_requires_vector` | TEST710: Tests CardinalityPattern correctly identifies patterns that require vectors Verifies ManyToOne and ManyToMany return true, others return false | Tests/CapDAGTests/CSCardinalityTests.m:108 |
| test711 | `test711_strand_shape_analysis_simple_linear` | TEST711: Tests shape chain analysis for simple linear one-to-one capability chains Verifies chains with no fan-out are valid and require no transformation | Tests/CapDAGTests/CSCardinalityTests.m:118 |
| test712 | `test712_strand_shape_analysis_with_fan_out` | TEST712: Tests shape chain analysis detects fan-out points in capability chains Fan-out requires is_sequence=true on the cap's output, not a "list" URN tag | Tests/CapDAGTests/CSCardinalityTests.m:130 |
| test713 | `test713_strand_shape_analysis_empty` | TEST713: Tests shape chain analysis handles empty capability chains correctly Verifies empty chains are valid and require no transformation | Tests/CapDAGTests/CSCardinalityTests.m:146 |
| test714 | `test714_cardinality_serialization` | TEST714: Tests InputCardinality enum values are distinct (parity for Rust serde round-trip) | Tests/CapDAGTests/CSCardinalityTests.m:158 |
| test715 | `test715_pattern_serialization` | TEST715: Tests CardinalityPattern enum values are distinct (parity for Rust serde round-trip) | Tests/CapDAGTests/CSCardinalityTests.m:165 |
| test720 | `test720_from_media_urn_opaque` | TEST720: Tests InputStructure correctly identifies opaque media URNs Verifies that URNs without record marker are parsed as Opaque | Tests/CapDAGTests/CSCardinalityTests.m:177 |
| test721 | `test721_from_media_urn_record` | TEST721: Tests InputStructure correctly identifies record media URNs Verifies that URNs with record marker tag are parsed as Record | Tests/CapDAGTests/CSCardinalityTests.m:186 |
| test722 | `test722_structure_compatibility_opaque_to_opaque` | TEST722: Tests structure compatibility for opaque-to-opaque data flow | Tests/CapDAGTests/CSCardinalityTests.m:195 |
| test723 | `test723_structure_compatibility_record_to_record` | TEST723: Tests structure compatibility for record-to-record data flow | Tests/CapDAGTests/CSCardinalityTests.m:201 |
| test724 | `test724_structure_incompatibility_opaque_to_record` | TEST724: Tests structure incompatibility for opaque-to-record flow | Tests/CapDAGTests/CSCardinalityTests.m:207 |
| test725 | `test725_structure_incompatibility_record_to_opaque` | TEST725: Tests structure incompatibility for record-to-opaque flow | Tests/CapDAGTests/CSCardinalityTests.m:213 |
| test726 | `test726_apply_structure_add_record` | TEST726: Tests applying Record structure adds record marker to URN | Tests/CapDAGTests/CSCardinalityTests.m:219 |
| test727 | `test727_apply_structure_remove_record` | TEST727: Tests applying Opaque structure removes record marker from URN | Tests/CapDAGTests/CSCardinalityTests.m:225 |
| test730 | `test730_media_shape_from_urn_all_combinations` | TEST730: Tests MediaShape correctly parses all four combinations | Tests/CapDAGTests/CSCardinalityTests.m:233 |
| test731 | `test731_media_shape_compatible_direct` | TEST731: Tests MediaShape compatibility for matching shapes | Tests/CapDAGTests/CSCardinalityTests.m:256 |
| test732 | `test732_media_shape_cardinality_changes` | TEST732: Tests MediaShape compatibility for cardinality changes with matching structure | Tests/CapDAGTests/CSCardinalityTests.m:270 |
| test733 | `test733_media_shape_structure_mismatch` | TEST733: Tests MediaShape incompatibility when structures don't match | Tests/CapDAGTests/CSCardinalityTests.m:286 |
| test740 | `test740_cap_shape_info_from_specs` | TEST740: Tests CapShapeInfo correctly parses cap specs | Tests/CapDAGTests/CSCardinalityTests.m:306 |
| test741 | `test741_cap_shape_info_pattern` | TEST741: Tests CapShapeInfo pattern detection — OneToMany requires output is_sequence=true | Tests/CapDAGTests/CSCardinalityTests.m:317 |
| test750 | `test750_strand_shape_valid` | TEST750: Tests shape chain analysis for valid chain with matching structures | Tests/CapDAGTests/CSCardinalityTests.m:329 |
| test751 | `test751_strand_shape_structure_mismatch` | TEST751: Tests shape chain analysis detects structure mismatch | Tests/CapDAGTests/CSCardinalityTests.m:340 |
| test752 | `test752_strand_shape_with_fanout` | TEST752: Tests shape chain analysis with fan-out (matching structures) Fan-out requires output is_sequence=true on the disbind cap | Tests/CapDAGTests/CSCardinalityTests.m:353 |
| test753 | `test753_strand_shape_list_record_to_list_record` | TEST753: Tests shape chain analysis correctly handles list-to-list record flow | Tests/CapDAGTests/CSCardinalityTests.m:369 |
| test754 | `test754_extractPrefixNonexistent` | TEST754: extract_prefix_to with nonexistent node returns error | Tests/CapDAGTests/CSPlanDecompositionTests.m:136 |
| test755 | `test755_extractForeachBody` | TEST755: extract_foreach_body extracts body as standalone plan | Tests/CapDAGTests/CSPlanDecompositionTests.m:145 |
| test756 | `test756_extractForeachBodyUnclosed` | TEST756: extract_foreach_body for unclosed ForEach (single body cap) | Tests/CapDAGTests/CSPlanDecompositionTests.m:177 |
| test757 | `test757_extractForeachBodyWrongType` | TEST757: extract_foreach_body fails for non-ForEach node | Tests/CapDAGTests/CSPlanDecompositionTests.m:194 |
| test758 | `test758_extractSuffixFrom` | TEST758: extract_suffix_from extracts collect → cap_post → output | Tests/CapDAGTests/CSPlanDecompositionTests.m:205 |
| test759 | `test759_extractSuffixNonexistent` | TEST759: extract_suffix_from fails for nonexistent node | Tests/CapDAGTests/CSPlanDecompositionTests.m:226 |
| test760 | `test760_decompositionCoversAllCaps` | TEST760: Full decomposition roundtrip — prefix + body + suffix cover all cap nodes | Tests/CapDAGTests/CSPlanDecompositionTests.m:235 |
| test761 | `test761_prefixIsDag` | TEST761: Prefix is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:274 |
| test762 | `test762_bodyIsDag` | TEST762: Body is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:283 |
| test763 | `test763_suffixIsDag` | TEST763: Suffix is valid DAG | Tests/CapDAGTests/CSPlanDecompositionTests.m:292 |
| test764 | `test764_prefixToInputSlot` | TEST764: extract_prefix_to with InputSlot as target (trivial prefix) | Tests/CapDAGTests/CSPlanDecompositionTests.m:301 |
| test780 | `test780_splitIntegerArray` | TEST780: split_cbor_array splits a simple array of integers | Tests/BifaciTests/CborSequenceTests.swift:236 |
| test782 | `test782_splitNonArray` | TEST782: split_cbor_array rejects non-array input | Tests/BifaciTests/CborSequenceTests.swift:266 |
| test783 | `test783_splitEmptyArray` | TEST783: split_cbor_array rejects empty array | Tests/BifaciTests/CborSequenceTests.swift:284 |
| test784 | `test784_splitInvalidCbor` | TEST784: split_cbor_array rejects invalid CBOR bytes | Tests/BifaciTests/CborSequenceTests.swift:302 |
| test785 | `test785_assembleIntegerArray` | TEST785: assemble_cbor_array creates array from individual items | Tests/BifaciTests/CborSequenceTests.swift:321 |
| test786 | `test786_roundtripSplitAssemble` | TEST786: split then assemble roundtrip preserves data | Tests/BifaciTests/CborSequenceTests.swift:342 |
| test790 | `test790_identityUrnSpecific` | TEST790: Tests identity_urn is specific and doesn't match everything | Tests/CapDAGTests/CSLiveCapFabTests.m:353 |
| test810 | `test810_splitSequenceBytes` | TEST810: Tests EdgeType::JsonPath extracts values using nested path expressions Verifies that JsonPath edge type correctly navigates through multiple levels like "data.nested.value" | Tests/BifaciTests/CborSequenceTests.swift:26 |
| test811 | `test811_splitSequenceText` | TEST811: Tests EdgeType::Iteration preserves array values for iterative processing Verifies that Iteration edge type passes through arrays unchanged to enable ForEach patterns | Tests/BifaciTests/CborSequenceTests.swift:50 |
| test812 | `test812_splitSequenceMixed` | TEST812: Tests EdgeType::Collection preserves collected values without transformation Verifies that Collection edge type maintains structure for aggregation patterns | Tests/BifaciTests/CborSequenceTests.swift:66 |
| test813 | `test813_splitSequenceSingle` | TEST813: Tests JSON path extraction through deeply nested object hierarchies (4+ levels) Verifies that paths can traverse multiple nested levels like "level1.level2.level3.level4.value" | Tests/BifaciTests/CborSequenceTests.swift:84 |
| test814 | `test814_roundtripAssembleSplitSequence` | TEST814: Tests error handling when array index exceeds available elements Verifies that out-of-bounds array access returns a descriptive error message | Tests/BifaciTests/CborSequenceTests.swift:96 |
| test815 | `test815_roundtripSplitAssembleSequence` | TEST815: Tests JSON path extraction with single-level paths (no nesting) Verifies that simple field names without dots correctly extract top-level values | Tests/BifaciTests/CborSequenceTests.swift:114 |
| test816 | `test816_splitSequenceEmpty` | TEST816: Tests JSON path extraction preserves special characters in string values Verifies that quotes, backslashes, and other special characters are correctly maintained | Tests/BifaciTests/CborSequenceTests.swift:127 |
| test817 | `test817_splitSequenceTruncated` | TEST817: Tests JSON path extraction correctly handles explicit null values Verifies that null is returned as serde_json::Value::Null rather than an error | Tests/BifaciTests/CborSequenceTests.swift:142 |
| test818 | `test818_assembleSequenceInvalidItem` | TEST818: Tests JSON path extraction correctly returns empty arrays Verifies that zero-length arrays are extracted as valid empty array values | Tests/BifaciTests/CborSequenceTests.swift:165 |
| test819 | `test819_assembleSequenceEmpty` | TEST819: Tests JSON path extraction handles various numeric types correctly Verifies extraction of integers, floats, negative numbers, and zero | Tests/BifaciTests/CborSequenceTests.swift:186 |
| test820 | `test820_singleValueSequence` | TEST820: Tests JSON path extraction correctly handles boolean values Verifies that true and false are extracted as proper boolean JSON values | Tests/BifaciTests/CborSequenceTests.swift:192 |
| test821 | `test821_inputStreamCollectCborSequence` | TEST821: Tests JSON path extraction with multi-dimensional arrays (matrix access) Verifies that nested array structures like "matrix[1]" correctly extract inner arrays | Tests/BifaciTests/CborSequenceTests.swift:202 |
| test822 | `test822_collectBytesVsSequence` | TEST822: Tests error handling for non-numeric array indices Verifies that invalid indices like "items[abc]" return a descriptive parse error | Tests/BifaciTests/CborSequenceTests.swift:589 |
| test823 | `test823_isDispatchable_exactMatch` | TEST823: is_dispatchable — exact match provider dispatches request | Tests/CapDAGTests/CSCapUrnTests.m:1132 |
| test824 | `test824_isDispatchable_broaderInputHandlesSpecific` | TEST824: is_dispatchable — provider with broader input handles specific request (contravariance) | Tests/CapDAGTests/CSCapUrnTests.m:1142 |
| test825 | `test825_isDispatchable_unconstrainedInput` | TEST825: is_dispatchable — request with unconstrained input dispatches to specific provider media: on the request input axis means "unconstrained" — vacuously true | Tests/CapDAGTests/CSCapUrnTests.m:1152 |
| test826 | `test826_isDispatchable_providerOutputSatisfiesRequest` | TEST826: is_dispatchable — provider output must satisfy request output (covariance) | Tests/CapDAGTests/CSCapUrnTests.m:1162 |
| test827 | `test827_isDispatchable_genericOutputCannotSatisfySpecific` | TEST827: is_dispatchable — provider with generic output cannot satisfy specific request | Tests/CapDAGTests/CSCapUrnTests.m:1172 |
| test828 | `test828_isDispatchable_wildcardRequestProviderMissingTag` | TEST828: is_dispatchable — wildcard * tag in request, provider missing tag → reject | Tests/CapDAGTests/CSCapUrnTests.m:1182 |
| test829 | `test829_isDispatchable_wildcardRequestProviderHasTag` | TEST829: is_dispatchable — wildcard * tag in request, provider has tag → accept | Tests/CapDAGTests/CSCapUrnTests.m:1192 |
| test830 | `test830_isDispatchable_providerExtraTags` | TEST830: is_dispatchable — provider extra tags are refinement, always OK | Tests/CapDAGTests/CSCapUrnTests.m:1202 |
| test831 | `test831_isDispatchable_crossBackendMismatch` | TEST831: is_dispatchable — cross-backend mismatch prevented | Tests/CapDAGTests/CSCapUrnTests.m:1212 |
| test832 | `test832_isDispatchable_asymmetric` | TEST832: is_dispatchable is NOT symmetric | Tests/CapDAGTests/CSCapUrnTests.m:1222 |
| test833 | `test833_isComparable_symmetric` | TEST833: is_comparable — both directions checked | Tests/CapDAGTests/CSCapUrnTests.m:1233 |
| test834 | `test834_isComparable_unrelated` | TEST834: is_comparable — unrelated caps are NOT comparable | Tests/CapDAGTests/CSCapUrnTests.m:1244 |
| test835 | `test835_isEquivalent_identical` | TEST835: is_equivalent — identical caps | Tests/CapDAGTests/CSCapUrnTests.m:1255 |
| test836 | `test836_isEquivalent_nonEquivalent` | TEST836: is_equivalent — non-equivalent comparable caps | Tests/CapDAGTests/CSCapUrnTests.m:1265 |
| test837 | `test837_isDispatchable_opTagMismatch` | TEST837: is_dispatchable — op tag mismatch rejects | Tests/CapDAGTests/CSCapUrnTests.m:1276 |
| test838 | `test838_isDispatchable_requestWildcardOutput` | TEST838: is_dispatchable — request with wildcard output accepts any provider output | Tests/CapDAGTests/CSCapUrnTests.m:1286 |
| test839 | `test839_peerResponseDeliversLogsBeforeStreamStart` | TEST839: LOG frames arriving BEFORE StreamStart are delivered immediately This tests the critical fix: during a peer call, the peer (e.g., modelcartridge) sends LOG frames for minutes during model download BEFORE sending any data (StreamStart + Chunk). The handler must receive these LOGs in real-time so it can re-emit progress and keep the engine's activity timer alive. Previously, demux_single_stream blocked on awaiting StreamStart before returning PeerResponse, which meant the handler couldn't call recv() until data arrived — causing 120s activity timeouts during long downloads. | Tests/BifaciTests/StreamingAPITests.swift:662 |
| test840 | `test840_peerResponseCollectBytesDiscardsLogs` | TEST840: PeerResponse::collect_bytes discards LOG frames | Tests/BifaciTests/StreamingAPITests.swift:733 |
| test841 | `test841_peerResponseCollectValueDiscardsLogs` | TEST841: PeerResponse::collect_value discards LOG frames | Tests/BifaciTests/StreamingAPITests.swift:763 |
| test842 | `test842_runWithKeepaliveReturnsResult` | TEST842: run_with_keepalive returns closure result (fast operation, no keepalive frames) | Tests/BifaciTests/StreamingAPITests.swift:794 |
| test843 | `test843_runWithKeepaliveReturnsResultType` | TEST843: run_with_keepalive returns Ok/Err from closure | Tests/BifaciTests/StreamingAPITests.swift:817 |
| test844 | `test844_runWithKeepalivePropagatesError` | TEST844: run_with_keepalive propagates errors from closure | Tests/BifaciTests/StreamingAPITests.swift:835 |
| test845 | `test845_progressSenderEmitsFrames` | TEST845: ProgressSender emits progress and log frames independently of OutputStream | Tests/BifaciTests/StreamingAPITests.swift:863 |
| test846 | `test846_progressFrameRoundtrip` | TEST846: Test progress LOG frame encode/decode roundtrip preserves progress float | Tests/BifaciTests/FrameTests.swift:1753 |
| test847 | `test847_progressDoubleRoundtrip` | TEST847: Double roundtrip (modelcartridge → relay → candlecartridge) | Tests/BifaciTests/FrameTests.swift:1790 |
| test852 | `test852_lub_identical` | TEST852: LUB of identical URNs returns the same URN | Tests/CapDAGTests/CSMediaUrnTests.m:18 |
| test853 | `test853_lub_no_common_tags` | TEST853: LUB of URNs with no common tags returns media: (universal) | Tests/CapDAGTests/CSMediaUrnTests.m:27 |
| test854 | `test854_lub_partial_overlap` | TEST854: LUB keeps common tags, drops differing ones | Tests/CapDAGTests/CSMediaUrnTests.m:41 |
| test855 | `test855_lub_list_vs_scalar` | TEST855: LUB of list and non-list drops list tag | Tests/CapDAGTests/CSMediaUrnTests.m:55 |
| test856 | `test856_lub_empty` | TEST856: LUB of empty input returns universal type | Tests/CapDAGTests/CSMediaUrnTests.m:69 |
| test857 | `test857_lub_single` | TEST857: LUB of single input returns that input | Tests/CapDAGTests/CSMediaUrnTests.m:78 |
| test858 | `test858_lub_three_inputs` | TEST858: LUB with three+ inputs narrows correctly | Tests/CapDAGTests/CSMediaUrnTests.m:87 |
| test859 | `test859_lub_valued_tags` | TEST859: LUB with valued tags (non-marker) that differ | Tests/CapDAGTests/CSMediaUrnTests.m:103 |
| test860 | `test860_seqAssignerSameRidDifferentXidsIndependent` | TEST860: Same RID with different XIDs get independent seq counters | Tests/BifaciTests/FlowOrderingTests.swift:115 |
| test890 | `test890_directionSemanticMatching` | TEST890: Semantic direction matching - generic provider matches specific request | Tests/CapDAGTests/CSCapUrnTests.m:951 |
| test891 | `test891_directionSemanticSpecificity` | TEST891: Semantic direction specificity - more media URN tags = higher specificity (mirror-local variant of TEST052) | Tests/CapDAGTests/CSCapUrnTests.m:998 |
| test893 | `test893_ExtensionsWithMetadataAndValidation` | TEST893: Test extensions can coexist with metadata and validation | Tests/CapDAGTests/CSMediaDefTests.m:168 |
| test894 | `test894_MultipleExtensions` | TEST894: Test multiple extensions in a media def | Tests/CapDAGTests/CSMediaDefTests.m:201 |
| test898 | `test898_binaryIntegrityThroughRelay` | TEST898: Binary data integrity through full relay path (256 byte values) | Tests/BifaciTests/IntegrationTests.swift:745 |
| test899 | `test899_streamingChunksThroughRelay` | TEST899: Streaming chunks flow through relay without accumulation | Tests/BifaciTests/IntegrationTests.swift:803 |
| test900 | `test900_twoCartridgesRoutedIndependently` | TEST900: Two cartridges routed independently by cap_urn | Tests/BifaciTests/IntegrationTests.swift:860 |
| test901 | `test901_reqForUnknownCapReturnsErr` | TEST901: REQ for unknown cap returns ERR frame (not fatal) | Tests/BifaciTests/RuntimeTests.swift:624 |
| test902 | `test902_computeChecksumEmpty` | TEST902: Verify FNV-1a checksum handles empty data | Tests/BifaciTests/FrameTests.swift:1707 |
| test903 | `test903_chunkWithChunkIndexAndChecksum` | TEST903: Verify CHUNK frame can store chunk_index and checksum fields | Tests/BifaciTests/FrameTests.swift:1714 |
| test904 | `test904_streamEndWithChunkCount` | TEST904: Verify STREAM_END frame can store chunk_count field | Tests/BifaciTests/FrameTests.swift:1727 |
| test908 | `test908_map_progress_basic_mapping` | TEST908: cached caps remain accessible while offline. | Tests/CapDAGTests/CSProgressMapperTests.m:17 |
| test910 | `test910_map_progress_monotonic` | TEST910: map_progress output is monotonic for monotonically increasing input | Tests/CapDAGTests/CSProgressMapperTests.m:44 |
| test911 | `test911_map_progress_bounded` | TEST911: map_progress output is bounded within [base, base+weight] | Tests/CapDAGTests/CSProgressMapperTests.m:56 |
| test912 | `test912_progress_mapper_reports_through_parent` | TEST912: ProgressMapper correctly maps through a CapProgressFn | Tests/CapDAGTests/CSProgressMapperTests.m:70 |
| test913 | `test913_progress_mapper_as_cap_progress_fn` | TEST913: ProgressMapper.as_cap_progress_fn produces same mapping | Tests/CapDAGTests/CSProgressMapperTests.m:89 |
| test914 | `test914_progress_mapper_sub_mapper` | TEST914: ProgressMapper.sub_mapper chains correctly | Tests/CapDAGTests/CSProgressMapperTests.m:110 |
| test915 | `test915_per_group_subdivision_monotonic_bounded` | TEST915: Per-group subdivision produces monotonic, bounded progress for N groups Uses pre-computed boundaries (same pattern as production code) to guarantee monotonicity regardless of f32 rounding. | Tests/CapDAGTests/CSProgressMapperTests.m:132 |
| test917 | `test917_high_frequency_progress_bounded` | TEST917: High-frequency progress emission does not violate bounds (Regression test for the deadlock scenario — verifies computation stays bounded) | Tests/CapDAGTests/CSProgressMapperTests.m:170 |
| test919 | `test919_parseSimpleTestcartridgeGraph` | TEST919: Parse simple machine notation graph with test-edge1 | Tests/BifaciTests/OrchestratorTests.swift:82 |
| test934 | `test934_findFirstForeach` | MARK: - TEST934: findFirstForeach detects ForEach | Tests/CapDAGTests/CSPlanDecompositionTests.m:85 |
| test935 | `test935_findFirstForeachLinear` | TEST935: find_first_foreach returns None for linear plans | Tests/CapDAGTests/CSPlanDecompositionTests.m:92 |
| test936 | `test936_hasForeach` | TEST936: hasForeach | Tests/CapDAGTests/CSPlanDecompositionTests.m:101 |
| test937 | `test937_extractPrefixTo` | TEST937: extract_prefix_to extracts input_slot -> cap_0 as a standalone plan | Tests/CapDAGTests/CSPlanDecompositionTests.m:113 |
| test939 | `test939_capUrnCanonicalFormDropsWildcardInOut` | TEST939: The canonical form drops `in=media:` and `out=media:` segments. Every spelling of "the same cap with wildcard in/out" collapses to one byte-identical canonical string. This is the contract that makes registry lookups work: the cap-publisher hashes `<canonical-urn>` to compute the cache key, and every language port (Rust, Go, Python, JS, ObjC) must agree on the canonical form for cross-language lookups to land on the same key. A regression that emitted the wildcard segments would silently move the published cap to a different SHA-256 bucket, 404'ing every reader that hashes the canonical form. | Tests/CapDAGTests/CSCapUrnTests.m:104 |
| test944 | `test944_sixMachine` | TEST944: 6-machine: edge1 -> edge2 -> edge7 -> edge8 -> edge9 -> edge10 Full cycle: node1 -> node2 -> node3 -> node6 -> node7 -> node8 -> node1 Completes the round trip: unwrap markers + lowercase | Tests/BifaciTests/OrchestratorTests.swift:300 |
| test945 | `test945_fiveMachine` | TEST945: 5-machine: edge1 -> edge2 -> edge7 -> edge8 -> edge9 node1 -> node2 -> node3 -> node6 -> node7 -> node8 adds <<...>> wrapping around the reversed string | Tests/BifaciTests/OrchestratorTests.swift:274 |
| test946 | `test946_fourMachine` | TEST946: 4-machine: edge1 -> edge2 -> edge7 -> edge8 node1 -> node2 -> node3 -> node6 -> node7 "hello" -> "[PREPEND]hello" -> "[PREPEND]hello[APPEND]" -> "[PREPEND]HELLO[APPEND]" -> "]DNEPPA[OLLEH]DNEPERP[" | Tests/BifaciTests/OrchestratorTests.swift:250 |
| test947 | `test947_capNotFound` | TEST947: Cap not found in registry | Tests/BifaciTests/OrchestratorTests.swift:224 |
| test948 | `test948_invalidCapUrn` | TEST948: Invalid cap URN in machine notation | Tests/BifaciTests/OrchestratorTests.swift:206 |
| test949 | `test949_emptyGraph` | TEST949: Empty machine notation (no edges) | Tests/BifaciTests/OrchestratorTests.swift:188 |
| test950 | `test950_rejectCycles` | Mirror-specific coverage: Validate that cycles are rejected | Tests/BifaciTests/OrchestratorTests.swift:163 |
| test955 | `test955_splitMapArray` | TEST955: split_cbor_array with nested maps | Tests/BifaciTests/CborSequenceTests.swift:250 |
| test956 | `test956_roundtripAssembleSplit` | TEST956: assemble then split roundtrip preserves data | Tests/BifaciTests/CborSequenceTests.swift:360 |
| test961 | `test961_assembleEmpty` | TEST961: assemble empty list produces empty CBOR array | Tests/BifaciTests/CborSequenceTests.swift:377 |
| test962 | `test962_assembleInvalidItem` | TEST962: assemble rejects invalid CBOR item | Tests/BifaciTests/CborSequenceTests.swift:387 |
| test963 | `test963_splitBinaryItems` | TEST963: split preserves CBOR byte strings (binary data — the common case in bifaci) | Tests/BifaciTests/CborSequenceTests.swift:403 |
| test964 | `test964_splitSequenceBytes` | TEST964: split_cbor_sequence splits concatenated CBOR Bytes values | Tests/BifaciTests/CborSequenceTests.swift:421 |
| test965 | `test965_splitSequenceText` | TEST965: split_cbor_sequence splits concatenated CBOR Text values | Tests/BifaciTests/CborSequenceTests.swift:436 |
| test966 | `test966_splitSequenceMixed` | TEST966: split_cbor_sequence handles mixed types | Tests/BifaciTests/CborSequenceTests.swift:451 |
| test967 | `test967_splitSequenceSingle` | TEST967: split_cbor_sequence single-item sequence | Tests/BifaciTests/CborSequenceTests.swift:470 |
| test968 | `test968_roundtripAssembleSplitSequence` | TEST968: roundtrip — assemble then split preserves items | Tests/BifaciTests/CborSequenceTests.swift:481 |
| test969 | `test969_roundtripSplitAssembleSequence` | TEST969: roundtrip — split then assemble preserves byte-for-byte | Tests/BifaciTests/CborSequenceTests.swift:498 |
| test970 | `test970_splitSequenceEmpty` | TEST970: split_cbor_sequence rejects empty data | Tests/BifaciTests/CborSequenceTests.swift:512 |
| test971 | `test971_splitSequenceTruncated` | TEST971: split_cbor_sequence rejects truncated CBOR | Tests/BifaciTests/CborSequenceTests.swift:526 |
| test972 | `test972_assembleSequenceInvalidItem` | TEST972: assemble_cbor_sequence rejects invalid CBOR item | Tests/BifaciTests/CborSequenceTests.swift:537 |
| test973 | `test973_assembleSequenceEmpty` | TEST973: assemble_cbor_sequence with empty items list produces empty bytes | Tests/BifaciTests/CborSequenceTests.swift:548 |
| test974 | `test974_sequenceIsNotArray` | TEST974: CBOR sequence is NOT a CBOR array — split_cbor_array rejects a sequence | Tests/BifaciTests/CborSequenceTests.swift:554 |
| test975 | `test975_singleValueSequence` | TEST975: split_cbor_sequence works on data that is also a valid CBOR array (single top-level value) | Tests/BifaciTests/CborSequenceTests.swift:571 |
| test987 | `test987_GcSecondaryPassEnforcesHardCap` | / Contract #3 — the secondary "hard cap" pass kicks in if / the table somehow exceeds `hardCap` (e.g. a seed that goes / over, simulating an extreme runaway). Without the / secondary pass, a single GC at the soft watermark would / not be enough to recover headroom and the table could / grow without bound between bursts. | Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:172 |
| test988 | `test988_GcReducesTableBelowSoftWatermarkInOnePass` | / Contract #1 — the GC keeps the table strictly below the / hard cap. We seed the table well above the soft watermark / (matching what a runaway producer would do mid-frame-burst) / and call the production GC entry point. The post-state / must be at most `softWatermark` entries because the GC / drops at least `evictionFraction × pre-state` entries in / one pass and the pre-state is below `hardCap` (i.e. one / pass is enough; the secondary "hard cap" pass would only / kick in if pre-state crossed the hard cap before insertion / completed, which production prevents by gc-ing on every / insert). | Tests/BifaciTests/CartridgeHostRoutingTableGCTests.swift:45 |
| test1000 | `test1000_single_existing_file` | TEST1000: Single existing file | Tests/CapDAGTests/CSInputResolverTests.m:80 |
| test1001 | `test1001_nonexistent_file` | TEST1001: Single non-existent file | Tests/CapDAGTests/CSInputResolverTests.m:93 |
| test1002 | `test1002_empty_directory` | TEST1002: Empty directory | Tests/CapDAGTests/CSInputResolverTests.m:105 |
| test1003 | `test1003_directory_with_files` | TEST1003: Directory with files | Tests/CapDAGTests/CSInputResolverTests.m:117 |
| test1004 | `test1004_directory_with_subdirs` | TEST1004: Directory with subdirs (recursive) | Tests/CapDAGTests/CSInputResolverTests.m:132 |
| test1005 | `test1005_glob_matching_files` | TEST1005: Glob matching files | Tests/CapDAGTests/CSInputResolverTests.m:147 |
| test1006 | `test1006_glob_matching_nothing` | TEST1006: Glob matching nothing | Tests/CapDAGTests/CSInputResolverTests.m:162 |
| test1007 | `test1007_recursive_glob` | TEST1007: Recursive glob | Tests/CapDAGTests/CSInputResolverTests.m:174 |
| test1008 | `test1008_mixed_file_dir` | TEST1008: Mixed file + dir | Tests/CapDAGTests/CSInputResolverTests.m:193 |
| test1010 | `test1010_duplicate_paths` | TEST1010: Duplicate paths are deduplicated | Tests/CapDAGTests/CSInputResolverTests.m:207 |
| test1011 | `test1011_invalid_glob` | TEST1011: Invalid glob syntax | Tests/CapDAGTests/CSInputResolverTests.m:219 |
| test1013 | `test1013_empty_input` | TEST1013: Empty input array | Tests/CapDAGTests/CSInputResolverTests.m:230 |
| test1014 | `test1014_symlink_to_file` | TEST1014: Symlink to file | Tests/CapDAGTests/CSInputResolverTests.m:241 |
| test1016 | `test1016_path_with_spaces` | TEST1016: Path with spaces | Tests/CapDAGTests/CSInputResolverTests.m:259 |
| test1017 | `test1017_path_with_unicode` | TEST1017: Path with unicode | Tests/CapDAGTests/CSInputResolverTests.m:271 |
| test1018 | `test1018_relative_path` | TEST1018: Relative path | Tests/CapDAGTests/CSInputResolverTests.m:283 |
| test1020 | `test1020_ds_store_excluded` | TEST1020: macOS .DS_Store is excluded | Tests/CapDAGTests/CSInputResolverTests.m:301 |
| test1021 | `test1021_thumbs_db_excluded` | TEST1021: Windows Thumbs.db is excluded | Tests/CapDAGTests/CSInputResolverTests.m:307 |
| test1022 | `test1022_resource_fork_excluded` | TEST1022: macOS resource fork files are excluded | Tests/CapDAGTests/CSInputResolverTests.m:313 |
| test1023 | `test1023_office_lock_excluded` | TEST1023: Office lock files are excluded | Tests/CapDAGTests/CSInputResolverTests.m:319 |
| test1024 | `test1024_git_dir_excluded` | TEST1024: .git directory is excluded | Tests/CapDAGTests/CSInputResolverTests.m:325 |
| test1025 | `test1025_macosx_dir_excluded` | TEST1025: __MACOSX archive artifact is excluded | Tests/CapDAGTests/CSInputResolverTests.m:331 |
| test1026 | `test1026_temp_files_excluded` | TEST1026: Temp files are excluded | Tests/CapDAGTests/CSInputResolverTests.m:337 |
| test1027 | `test1027_localized_excluded` | TEST1027: .localized is excluded | Tests/CapDAGTests/CSInputResolverTests.m:343 |
| test1028 | `test1028_desktop_ini_excluded` | TEST1028: desktop.ini is excluded | Tests/CapDAGTests/CSInputResolverTests.m:348 |
| test1029 | `test1029_normal_files_not_excluded` | TEST1029: Normal files are NOT excluded | Tests/CapDAGTests/CSInputResolverTests.m:353 |
| test1090 | `test1090_single_file_scalar` | TEST1090: 1 file → is_sequence=false | Tests/CapDAGTests/CSInputResolverTests.m:364 |
| test1092 | `test1092_two_files` | TEST1092: 2 files → is_sequence=true | Tests/CapDAGTests/CSInputResolverTests.m:376 |
| test1093 | `test1093_dir_single_file` | TEST1093: 1 dir with 1 file → is_sequence=false | Tests/CapDAGTests/CSInputResolverTests.m:390 |
| test1094 | `test1094_dir_multiple_files` | TEST1094: 1 dir with 3 files → is_sequence=true | Tests/CapDAGTests/CSInputResolverTests.m:404 |
| test1098 | `test1098_extension_based_pdf` | TEST1098: Extension-based detection picks up pdf tag for .pdf files | Tests/CapDAGTests/CSInputResolverTests.m:420 |
| test1122 | `test1122_fullPathEngineReqToCartridgeResponse` | TEST1122: All cap input media defs that represent user files must have extensions. These are the entry points — the file types users can right-click on. | Tests/BifaciTests/IntegrationTests.swift:636 |
| test1123 | `test1123_cartridgeErrorFlowsToEngine` | TEST1123: Verify that specific cap output URNs resolve to the correct extension. This catches misconfigurations where a spec exists but has the wrong extension. | Tests/BifaciTests/IntegrationTests.swift:703 |
| test1126 | `test1126_map_progress_deterministic` | TEST1126: set_offline(false) restores fetch ability (would fail with HTTP error, not NetworkBlocked) | Tests/CapDAGTests/CSProgressMapperTests.m:34 |
| test1144 | `test1144_content_structure_helpers` | TEST1144: ContentStructure is_list/is_record helpers and Display implementation are correct | Tests/CapDAGTests/CSInputResolverTests.m:440 |
| test1145 | `test1145_resolved_input_set_uses_equivalent_media_and_file_count_cardinality` | TEST1145: ResolvedInputSet uses URN equivalence for common_media and file count for is_sequence | Tests/CapDAGTests/CSInputResolverTests.m:471 |
| test1150 | `test1150_AddCapAndBasicTraversal` | MARK: - Basic Tests (unnumbered, match Rust unnumbered tests) | Tests/CapDAGTests/CSLiveCapFabTests.m:32 |
| test1151 | `test1151_ExactVsConformanceMatching` | TEST1151: Exact vs conformance matching | Tests/CapDAGTests/CSLiveCapFabTests.m:51 |
| test1152 | `test1152_MultiStepPath` | TEST1152: Multi step path | Tests/CapDAGTests/CSLiveCapFabTests.m:82 |
| test1153 | `test1153_DeterministicOrdering` | TEST1153: Deterministic ordering | Tests/CapDAGTests/CSLiveCapFabTests.m:103 |
| test1154 | `test1154_SyncFromCaps` | TEST1154: Sync from caps | Tests/CapDAGTests/CSLiveCapFabTests.m:128 |
| test1270 | `test1270_getOwnMemoryMbReturnsValues` | TEST1270: Runtime memory inspection returns non-negative resident and virtual memory values. `getOwnMemoryMb` calls `proc_pid_rusage(getpid())` which must always work — even in a sandbox (the sandbox only blocks querying OTHER processes). If it returns nil on macOS, the self-reporting mechanism is broken and cartridges will report 0 footprint. | Tests/BifaciTests/CartridgeRuntimeTests.swift:534 |
| test1271 | `test1271_mediaAdapterSelectionConstant` | TEST1271: MEDIA_ADAPTER_SELECTION constant parses and has expected tags | Tests/BifaciTests/StandardCapsTests.swift:41 |
| test1272 | `test1272_adapterCapConstantParses` | TEST1272: CAP_ADAPTER_SELECTION constant parses as a valid CapUrn | Tests/BifaciTests/StandardCapsTests.swift:55 |
| test1273 | `test1273_adapterSelectionUrnBuilder` | TEST1273: the adapter-selection cap URN has correct in/out specs — in is the bare wildcard `media:` (accepts any) and out conforms to the adapter-selection media URN. (The reference exposes this as the `adapter_selection_urn()` builder; here the parsed constant IS the canonical form the runtime registers.) | Tests/BifaciTests/StandardCapsTests.swift:67 |
| test1300 | `test1300_sequenceItemFragmentsReassembleIntoOneItem` | TEST1300: A sequence item CBOR-encoded once and split across multiple CHUNK frames (the emitListItem framing) reassembles into exactly one delivered item. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:198 |
| test1301 | `test1301_sequenceStreamTruncatedMidItemFailsHard` | TEST1301: A sequence stream that ENDs mid-item (trailing fragment bytes that never complete a CBOR item) surfaces a hard decode error instead of silently dropping the partial item. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:253 |
| test1302 | `test1302_sequenceFragmentFramesAreCreditedOnArrival` | TEST1302: Continuation fragments of a multi-frame sequence item are credited back by the demux on arrival — the handler grants one frame per consumed item, so without fragment grants an item spanning more frames than the credit window could never finish arriving. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:277 |
| test1400 | `test1400_missingOutSpecDefaultsToWildcard` | TEST1400: Missing 'out' defaults to media: wildcard (mirror-local variant of TEST002 covering the out-side case) | Tests/CapDAGTests/CSCapUrnTests.m:183 |
| test1401 | `test1401_directionWildcardMatches` | TEST1401: Wildcard in/out specs accept any concrete value (mirror-local variant of TEST003's wildcard branch) | Tests/CapDAGTests/CSCapUrnTests.m:240 |
| test1402 | `test1402_invalidCharacters` | TEST1402: Invalid characters (e.g. '@') in tag keys are rejected by the parser (mirror-local variant of TEST003) | Tests/CapDAGTests/CSCapUrnTests.m:160 |
| test1403 | `test1403_equality` | TEST1403: Equality and hash of CSCapUrn identify identical URNs and distinguish direction/tag differences (mirror-local variant of TEST016) | Tests/CapDAGTests/CSCapUrnTests.m:510 |
| test1404 | `test1404_merge` | TEST1404: merge() combines tags from two cap URNs; direction comes from the other cap (mirror-local variant of TEST026's merge branch) | Tests/CapDAGTests/CSCapUrnTests.m:494 |
| test1405 | `test1405_wildcardTagDirection` | TEST1405: withWildcardTag resolves to withInSpec/withOutSpec for "in"/"out" tags, setting them to the wildcard "media:" (mirror-local variant of TEST027) | Tests/CapDAGTests/CSCapUrnTests.m:470 |
| test1406 | `test1406_valuelessTagParsing` | TEST1406: Value-less tags (bare keys like ";flag") parse as wildcards (mirror-local variant of TEST031) | Tests/CapDAGTests/CSCapUrnTests.m:140 |
| test1408 | `test1408_withInSpec` | TEST1408: withInSpec returns a new URN with the in= spec replaced, leaving the original unchanged (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:409 |
| test1409 | `test1409_withOutSpec` | TEST1409: withOutSpec returns a new URN with the out= spec replaced, leaving the original unchanged (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:419 |
| test1411 | `test1411_withoutTagRejectsStructuralKeys` | TEST1411: withoutTag rejects reserved structural keys (mirror-local) | Tests/CapDAGTests/CSCapUrnTests.m:446 |
| test1414 | `test1414_parseSingleEdgeDag` | TEST1414: Parse DAG with a single edge using different node names (mirror-local) | Tests/BifaciTests/OrchestratorTests.swift:100 |
| test1415 | `test1415_parseEdge1ToEdge2Chain` | TEST1415: Parse DAG chaining test_edge1 → test_edge2 (mirror-local) | Tests/BifaciTests/OrchestratorTests.swift:118 |
| test1600 | `test1600_hashesFileLargerThanOneChunk` | TEST1600: Hashing a directory containing a file LARGER than the streaming chunk size produces the same hash as an independent reference implementation. Exercises the multi-iteration read loop in `computeCartridgeDirectoryHash` — if a future refactor reverted to slurping whole files, the hash would still match (slurp gives the right answer too), so this is the necessary correctness pin even though it is not the tightest possible regression. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:92 |
| test1601 | `test1601_streamChunkSizeIsBounded` | TEST1601: The streaming chunk size is bounded so no single allocation scales with file size. This is the structural guard that prevents a future revert to FileManager.contents(atPath:) on a 200+ MB cartridge binary — that revert silently corrupted state in the sandboxed XPC service. Anything above 16 MiB is in the "you're slurping" zone and must not land. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:114 |
| test1602 | `test1602_cartridgeJsonExcluded` | TEST1602: cartridge.json is excluded from the hash — adding it (or changing its contents) must not change the directory hash, because cartridge.json carries install-time metadata that varies between installs of the same logical content. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:122 |
| test1603 | `test1603_missingDirectoryThrowsTypedError` | TEST1603: Hashing a directory that does not exist throws CartridgeDirectoryHashError.directoryUnreadable carrying the offending path. Replaces the original silent `return nil` that the caller turned into a generic "must be hashable" fatalError — the new error names the actual path so operators see what to fix. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:142 |
| test1604 | `test1604_emptyDirectoryHashes` | TEST1604: An empty directory hashes successfully (just the SHA256 of nothing — empty input). Ensures the function does not insist on at least one file. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:161 |
| test1605 | `test1605_fileSHA256MatchesKnownVector` | TEST1605: computeFileSHA256 streams a single file (used for quarantine identity tracking) and produces the standard SHA256 of the file's bytes. Verifies multi-chunk read correctness against a known SHA256 of `"abc"` from the FIPS-180-2 test vectors. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:172 |
| test1606 | `test1606_fileSHA256StreamsAcrossChunks` | TEST1606: computeFileSHA256 streams arbitrarily large files without loading the whole file into memory. Hashes a file roughly 3.5 chunks long and verifies the result against a single-shot CC_SHA256 over the same buffer — proving the chunk loop is correct across multiple read iterations. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:184 |
| test1607 | `test1607_fileSHA256ThrowsOnMissingPath` | TEST1607: computeFileSHA256 throws openFailed on a missing path with the offending path attached. Replaces the previous silent `return nil` so callers can surface the actual cause to the operator. | Tests/BifaciTests/CartridgeDirectoryHashTests.swift:204 |
| test1700 | `test1700_healthyAnchorHashesAndCarriesNoError` | / TEST1700: A healthy cartridge whose directory exists hashes / successfully and the resulting identity has the same name / / version / channel as the cartridge.json, a non-empty sha256, / and NO attachment error. Pins the happy path so a future / refactor that breaks healthy-case hashing surfaces here. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:94 |
| test1701 | `test1701_missingManifestReturnsNil` | / TEST1701: A cartridge whose `cartridge.json` has been / deleted (e.g. the operator uninstalled, or the directory / got swept up by a `dx clear --cartridges`) returns nil from / `buildInstalledCartridgeRecord`. There is no layout / fallback — cartridge.json IS the identity, and a cartridge / without a manifest is considered gone for this RelayNotify / pass. The host stays alive; the discovery scanner picks up / the change on its next scan. / / Regression test for the field crash: /   Bifaci/CartridgeHost.swift:617: Fatal error: /   BUG: healthy installed cartridge directory must be /   hashable at .../pdfcartridge/0.182.450 / Before the fix this code path aborted the whole XPC service. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:131 |
| test1702 | `test1702_malformedManifestReturnsNil` | / TEST1702: Cartridge.json that's present-but-malformed (e.g. / the file got truncated mid-write) also returns nil. There / is no salvage path — a cartridge whose manifest can't be / parsed is not a cartridge. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:154 |
| test1703 | `test1703_oldSchemaManifestMissingRegistryUrlReturnsNil` | / TEST1703: A cartridge.json that omits the required / `registry_url` key (old-schema file) returns nil. / `registry_url` is required-but-nullable in the manifest / schema; absent-key surfaces here as nil identity, surfaces / downstream as the cartridge being filtered out of / RelayNotify, and forces the operator to reinstall on the / new schema. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:179 |
| test1704 | `test1704_existingAttachmentErrorRoundTrips` | / TEST1704: A cartridge that already carries an attachment / error from upstream (e.g. failed HELLO) round-trips that / error verbatim — the identity-build path does NOT mint a / fresh error or override it. The sha256 is the real hash / because the directory is still healthy; the error / describes a different problem (the failed HELLO) than the / hash function could surface. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:215 |
| test1705 | `test1705_missingManifestWinsOverExistingError` | / TEST1705: An attached cartridge whose manifest has gone / missing returns nil regardless of any prior attachment / error. The contract is "manifest is identity"; a cartridge / without a manifest is gone for this RelayNotify pass — / even if it had a previously-recorded HELLO failure, the / disappeared anchor wins. The discovery scanner removes the / stale tree on its next pass. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:254 |
| test1710 | `test1710_kindRawValuesMatchProtoSnakeCase` | / TEST1710: Every variant's `rawValue` must be its / snake_case proto name. New variants must be added here AND / to `cartridge.proto`'s `CartridgeAttachmentErrorKind`. This / test fails with a clear "expected X for Y" message rather / than a "unknown enum case" runtime crash if the two sides / drift. | Tests/BifaciTests/CartridgeAttachmentErrorKindWireTests.swift:31 |
| test1711 | `test1711_attachmentErrorJSONRoundTripsForEveryKind` | / TEST1711: A `CartridgeAttachmentError` round-trips through / `JSONEncoder` → bytes → `JSONDecoder` unchanged for every / kind. RelayNotify's wire payload is JSON; if any variant / fails to deserialize, the engine's aggregate parse fails / and ALL cartridges from that host disappear from the / inventory — including the healthy ones. This test / covers each variant individually so a single-variant / regression doesn't hide behind a passing healthy-case. | Tests/BifaciTests/CartridgeAttachmentErrorKindWireTests.swift:60 |
| test1712 | `test1712_decodesWireFormatJSONIntoExpectedVariants` | / TEST1712: An on-the-wire JSON payload using the snake_case / raw values decodes into the right Swift variant. This is / the engine → Swift path: the engine emits / `{"kind":"bad_installation",...}` and the Swift side must / resolve it to `.badInstallation`. Asserts the lookup table / the decoder synthesises for `String`-backed enums actually / covers the new variants. | Tests/BifaciTests/CartridgeAttachmentErrorKindWireTests.swift:92 |
| test1713 | `test1713_unknownWireKindFailsToDecode` | / TEST1713: An unknown wire kind FAILS to decode. The two / new variants are wire-additive — older Swift binaries that / don't know `bad_installation` or `disabled` will see those / strings and reject them, which is correct: silently / coercing an unknown variant to a fallback would hide the / version-skew bug. The fatalError sites in / CartridgeGRPCAdapter and InstalledCartridgesStore rely on / this — they expect decode to throw / produce a known / variant, never silently pick a default. | Tests/BifaciTests/CartridgeAttachmentErrorKindWireTests.swift:130 |
| test1800 | `test1800_kind_identity_only_for_bare_cap` | TEST1800: Identity classifier — only explicit effect=none qualifies. Adding any tag (even one that doesn't constrain in/out) demotes the cap to Transform because the operation/metadata axis is no longer fully generic. | Tests/CapDAGTests/CSCapUrnTests.m:1460 |
| test1801 | `test1801_kind_source_when_input_is_void` | TEST1801: Source classifier — in=media:void, out non-void. | Tests/CapDAGTests/CSCapUrnTests.m:1492 |
| test1802 | `test1802_kind_sink_when_output_is_void` | TEST1802: Sink classifier — out=media:void, in non-void. | Tests/CapDAGTests/CSCapUrnTests.m:1505 |
| test1803 | `test1803_kind_effect_when_both_sides_void` | TEST1803: Effect classifier — both sides void. Reads as `() → ()`. | Tests/CapDAGTests/CSCapUrnTests.m:1518 |
| test1804 | `test1804_kind_transform_for_normal_data_processors` | TEST1804: Transform classifier — at least one side non-void, and the cap is not the bare identity. The default kind for ordinary data-processing caps. | Tests/CapDAGTests/CSCapUrnTests.m:1531 |
| test1805 | `test1805_kind_invariant_under_canonical_spellings` | TEST1805: Kind is invariant under canonicalization. The same morphism written in many surface forms must classify the same way once parsed. This pins the rule that kind is a property of the cap as a structured object, not of any particular spelling. | Tests/CapDAGTests/CSCapUrnTests.m:1544 |
| test1810 | `test1810_media_void_is_atomic` | TEST1810: media:void is atomic — refinements are parse errors. Mirrored across every language port (Rust, Go, Python, Swift/ObjC, JS) under the SAME number. Any divergence is a wire-level inconsistency — the unit type's atomicity is part of the protocol's deepest layer, not a per-port detail. The bare `media:void` parses successfully; any combination with another tag (marker or key=value) MUST fail with VoidNotAtomic. This forecloses a fake taxonomy of unit values; reasons or labels for *why* void is used belong on the cap URN's non-directional tags or in cap args. | Tests/CapDAGTests/CSMediaUrnTests.m:463 |
| test1820 | `test1820_specificity_question_is_zero` | TEST1820: A `?`-valued cap-tag scores 0. Same as missing. | Tests/CapDAGTests/CSCapUrnTests.m:1661 |
| test1821 | `test1821_specificity_must_not_have_is_five` | TEST1821: A `!`-valued cap-tag scores 5 (top of negative chain). | Tests/CapDAGTests/CSCapUrnTests.m:1675 |
| test1822 | `test1822_specificity_must_have_any_is_two` | TEST1822: A `*`-valued cap-tag (including bare markers) scores 2. | Tests/CapDAGTests/CSCapUrnTests.m:1684 |
| test1823 | `test1823_specificity_exact_value_is_four` | TEST1823: An exact-valued cap-tag scores 4. | Tests/CapDAGTests/CSCapUrnTests.m:1702 |
| test1824 | `test1824_specificity_combined_y_axis` | TEST1824: All six forms compose additively on a single cap. This pins the truth-table sum across the y axis as a whole. | Tests/CapDAGTests/CSCapUrnTests.m:1711 |
| test1830 | `test1830_canonicalize_no_constraint` | TEST1830: ?x ≡ x? ≡ x=? all canonicalize to ?x. | Tests/CapDAGTests/CSCapUrnTests.m:1722 |
| test1831 | `test1831_canonicalize_absent_or_not_value` | TEST1831: ?x=v and x?=v both canonicalize to x?=v. The third hypothetical form `x=?v` is NOT recognized as a qualifier — a value starting with `?` is just an exact value beginning with a `?` character. | Tests/CapDAGTests/CSCapUrnTests.m:1734 |
| test1832 | `test1832_canonicalize_must_have_any` | TEST1832: x ≡ x=* both canonicalize to bare x. | Tests/CapDAGTests/CSCapUrnTests.m:1753 |
| test1833 | `test1833_canonicalize_present_not_value` | TEST1833: !x=v and x!=v both canonicalize to x!=v. The third hypothetical form `x=!v` is NOT recognized as a qualifier — a value starting with `!` is just an exact value beginning with a `!` character. | Tests/CapDAGTests/CSCapUrnTests.m:1765 |
| test1834 | `test1834_canonicalize_exact_value` | TEST1834: Canonicalize exact value | Tests/CapDAGTests/CSCapUrnTests.m:1784 |
| test1835 | `test1835_canonicalize_must_not_have` | TEST1835: !x ≡ x! ≡ x=! all canonicalize to !x. | Tests/CapDAGTests/CSCapUrnTests.m:1792 |
| test1842 | `test1842_truth_table_full_cross_product` | TEST1842: Full 6×6 truth table. | Tests/CapDAGTests/CSCapUrnTests.m:1804 |
| test1845 | `test1845_axis_weighting_in_dominates_y` | TEST1845: With equal out-axis, in-axis dominates over y-axis. | Tests/CapDAGTests/CSCapUrnTests.m:1865 |
| test1847 | `test1847_cartridgeBuildLegacyPackageFallback` | TEST1847: A build from a registry manifest published BEFORE `packages[]` existed carries only the legacy singular `package` (no `format`). It must still deserialize (a missing `packages` must not fail the whole parse) and `primary_package()` must fall back to that legacy package, so a registry not yet republished with the dual-write keeps installing. When `packages[]` is present it is preferred over the legacy field. | Tests/BifaciTests/CartridgeRepoTests.swift:69 |
| test1849 | `test1849_resolveForHostCompatibleLatest` | TEST1849: latest version has a host build → Compatible, resolving to the latest version and that platform's native-format package. | Tests/BifaciTests/CartridgeRepoTests.swift:111 |
| test1850 | `test1850_resolveForHostCompatibleOutdated` | TEST1850: the latest version lacks a host build but an older version has one → CompatibleOutdated, resolving to the older version with a reason naming both the latest and the resolved version. | Tests/BifaciTests/CartridgeRepoTests.swift:130 |
| test1851 | `test1851_resolveForHostIncompatible` | TEST1851: no version ships a host build → Incompatible, no resolved version/package, reason states the host platform. | Tests/BifaciTests/CartridgeRepoTests.swift:153 |
| test1852 | `test1852_resolveForHostSkipsBuildWithNoInstaller` | TEST1852: a host build whose packages[] is empty AND has no legacy `package` ships no installer; resolution must SKIP it (not resolve to an un-downloadable version) and fall through to an older usable version. | Tests/BifaciTests/CartridgeRepoTests.swift:167 |
| test1853 | `test1853_hostPlatformNormalizedForm` | TEST1853: host_platform() returns a normalized {os}-{arch} string with arch aarch64 mapped to arm64 — the exact form the registry uses. | Tests/BifaciTests/CartridgeRepoTests.swift:189 |
| test1872 | `test1872_registryUrlFromBuildEnvPassesThroughNonempty` | TEST1872: `registry_url_from_build_env` passes a non-empty registry URL through unchanged. This is the function that decides the engine's baked PRIMARY registry (surfaced over SystemService.HealthStatus); a published build must report exactly the URL it was compiled with. | Tests/BifaciTests/ManifestTests.swift:308 |
| test1873 | `test1873_registryUrlFromBuildEnvNoneForDev` | TEST1873: an unset env (None) yields None — a dev build has no baked registry, so the engine reports an empty primary-registry URL and loads only `dev/` cartridges. This is the dev-engine contract the registry sheets rely on to omit the read-only "Primary · built-in" row. | Tests/BifaciTests/ManifestTests.swift:314 |
| test1874 | `test1874_registryUrlFromBuildEnvRejectsEmptyString` | TEST1874: an exported-but-empty env (the empty string) is neither a dev build nor a valid identity and MUST fail hard, so the build can never silently hash the empty string into a fake registry slug. We assert the failure AND its exact message — the catchable Swift analog of Rust's compile-time panic — so a regression that dropped the check (or replaced it with a silent fallback) is caught rather than passing on a bogus empty primary registry. | Tests/BifaciTests/ManifestTests.swift:325 |
| test1875 | `test1875_scanAllReachesBothDevAndRegistrySlugs` | TEST1875: scan-all — a registry slug folder AND the dev slot present on disk are BOTH scanned, regardless of the host's own baked registry. The dev cartridge (null registry under dev/) and the registry cartridge (its url hashing to its slug folder) each reach their probe. Both fixtures lack a real bifaci binary, so both end at HandshakeFailed — proving discovery REACHED them (was not filtered out by a registry pin), which is the behavior under test. A registry-pin rejection would instead surface BadInstallation and never probe. | Tests/BifaciTests/CartridgeDiscoveryTests.swift:89 |
| test1876 | `test1876_otherChannelSubtreeIsSkipped` | TEST1876: only the host's channel subtree is scanned. A cartridge under a slug's `release/` folder is invisible to a nightly host even though the slug folder is present (its `nightly/` subtree is absent). | Tests/BifaciTests/CartridgeDiscoveryTests.swift:117 |
| test1877 | `test1877_registryCartridgeUnderWrongSlugIsBadInstall` | TEST1877: a registry cartridge hand-copied under the WRONG registry slug folder fails the three-place rule (BadInstallation) — scan-all does not mean "accept anywhere", placement must still be self-consistent. | Tests/BifaciTests/CartridgeDiscoveryTests.swift:131 |
| test1878 | `test1878_bundledProviderWithoutBakedHashIsRejected` | TEST1878: a cartridge marked `installed_from: bundle` with no baked hash is rejected as BadInstallation — the bundled-integrity gate fires before the probe. Non-macOS only: on macOS the baked-hash path is intentionally absent (OS code-signature is the guard), so a bundled provider is accepted there and would instead end at the probe. | Tests/BifaciTests/CartridgeDiscoveryTests.swift:151 |
| test1879 | `test1879_syncRosterAddsAndRemovesRegisteredDirLive` | TEST1879: SyncRoster updates the LIVE host inventory in place — the engine sees an added registered-dir cartridge via a fresh RelayNotify without reconnecting, and a subsequent empty sync removes it. This is the macOS-XPC `syncDiscoveryOutcomes` parity path the daemon uses after a registry verdict flips a held cartridge to Listed. | Tests/BifaciTests/SyncRosterTests.swift:36 |
| test1880 | `test1880_AliasNameNormalizationRules` | TEST1880: alias name normalization lowercases and accepts the allowed character class; rejects colon, whitespace, and out-of-class chars with the right error. A broken validator would let a URN-shaped or whitespace name through, or mangle a valid name. | Tests/CapDAGTests/CSFabricAliasTests.m:37 |
| test1881 | `test1881_TokenURNvsAliasDetection` | TEST1881: URN-vs-alias detection keys purely on the presence of ':'. The whole design rests on this discriminator being exact. | Tests/CapDAGTests/CSFabricAliasTests.m:49 |
| test1882 | `test1882_ClassifyAliasTargetByPrefix` | TEST1882: alias target classification distinguishes cap from media by prefix and rejects a non-URN target. The typed-boundary enforcement in the registry depends on this. | Tests/CapDAGTests/CSFabricAliasTests.m:58 |
| test1887 | `test1887_ManifestRoundTripsAliases` | TEST1887: the Manifest type round-trips an `aliases` map. | Tests/CapDAGTests/CSFabricAliasTests.m:70 |
| test1888 | `test1888_ResolveAliasReturnsTarget` | TEST1888: resolve_alias returns the alias target untyped. Seeding a media alias and resolving it yields the media URN; a malformed alias name is rejected before any lookup. | Tests/CapDAGTests/CSFabricAliasTests.m:81 |
| test1889 | `test1889_ResolveAliasTypedEnforcesKind` | TEST1889: resolve alias typed enforces the expected kind. | Tests/CapDAGTests/CSFabricAliasTests.m:106 |
| test1890 | `test1890_GetCapViaAliasAndTypeMismatch` | TEST1890: get_cap accepts a cap alias and returns the aliased cap; a media alias passed to get_cap fails hard (typed boundary). This proves alias substitution AND type enforcement at the registry's cap surface. | Tests/CapDAGTests/CSFabricAliasTests.m:129 |
| test1891 | `test1891_GetMediaDefViaAliasAndTypeMismatch` | TEST1891: get_media_def accepts a media alias and returns the aliased spec; a cap alias passed to get_media_def fails hard. | Tests/CapDAGTests/CSFabricAliasTests.m:153 |
| test1892 | `test1892_UnknownAliasIsNotFound` | TEST1892: an unknown alias name is a hard not-found, never a silent empty; unknown and malformed names are treated the same. This is the "expose issues, no fallback" contract. | Tests/CapDAGTests/CSFabricAliasTests.m:177 |
| test1893 | `test1893_cacheRootIsNamespacedPerRegistryOrigin` | TEST1893: cache root namespaced per registry origin — prod and staging serve different bytes for the same URN/version, so they must never share a cache root; the same origin must map to a stable (deterministic) root or caching never hits; and the final path component is exactly slugFor(url) under the shared "capdag" cache directory — one slug scheme across the codebase. The old origin-blind code rooted every origin at the same "capdag" directory, which makes the prod≠staging assertion below fail. | Tests/CapDAGTests/CSFabricRegistryTests.m:207 |
| test6200 | `test6200_csCapManifestWithPageUrl` | MARK: - CSCapManifest With PageUrl Test | Tests/BifaciTests/ManifestTests.swift:277 |
| test6205 | `test6205_csCapManifestRejectsUnknownChannel` | Channel is part of the cartridge's identity; the deserializer accepts the closed enum {release, nightly} only. Anything else is a publish-pipeline bug we want to surface. | Tests/BifaciTests/ManifestTests.swift:293 |
| test6207 | `test6207_concatenatedVsFinalPayloadDivergence` | Mirror-specific coverage: concatenated() returns full payload while finalPayload returns only last chunk | Tests/BifaciTests/RuntimeTests.swift:1105 |
| test6209 | `test6209_RunExitKillsAllManagedCartridges` | / Contract #1: when `run()` exits because the relay closed, / every running cartridge is torn down and the observer is / fired with a death notification for each. The Rust reference / enforces this by calling `kill_all_cartridges().await` at / the very end of `run()`. The Swift mirror's previous / behavior was to leak cartridges across reconnects, which is / what allowed the XPC-service NSConcreteData accumulator bug. | Tests/BifaciTests/CartridgeHostSessionLifecycleTests.swift:66 |
| test6213 | `test6213_NewHostInstancePerRelaySession` | / Contract #2 (well-behaved path): one host → one run() → / drop. The misuse path (calling run() twice) is enforced via / `precondition` and is not death-tested here — the well- / behaved path is sufficient because if the precondition were / silently disabled, the prior test (`testRunExitKills…`) / would still pass on the first invocation but the second / call would race with itself and fail intermittently. This / test documents the contract by demonstrating that a fresh / `CartridgeHost` instance is the only correct way to start / a new relay session. | Tests/BifaciTests/CartridgeHostSessionLifecycleTests.swift:141 |
| test6217 | `test6217_HostConstructsAndClosesWithoutAnObserver` | TEST6217: Host constructs and closes without an observer | Tests/BifaciTests/CartridgeHostObserverTests.swift:54 |
| test6221 | `test6221_SetObserverNilClearsThePreviouslyRegisteredObserver` | TEST6221: Set observer nil clears the previously registered observer | Tests/BifaciTests/CartridgeHostObserverTests.swift:64 |
| test6229 | `test6229_b_limitsNegotiation` | TEST198 (continued): Limits negotiation picks minimum of both sides | Tests/BifaciTests/FrameTests.swift:360 |
| test6237 | `test6237_b_allFrameTypesRoundtrip` | Covers all frame types in a single loop for comprehensive roundtrip verification | Tests/BifaciTests/FrameTests.swift:947 |
| test6243 | `test6243_b_streamStartIsSequenceRoundtrip` | TEST389b: STREAM_START with isSequence roundtrips correctly | Tests/BifaciTests/FrameTests.swift:1144 |
| test6244 | `test6244_manifestEnsureIdentityIdempotent` | Mirror-specific coverage: Manifest.ensureIdentity() adds if missing, idempotent if present | Tests/BifaciTests/StandardCapsTests.swift:111 |
| test6247 | `test6247_parseFanInPattern` | Mirror-specific coverage: Parse fan-in pattern | Tests/BifaciTests/OrchestratorTests.swift:138 |
| test6254 | `test6254_DotParserSimpleDigraph` | TEST: Parse simple digraph | Tests/BifaciTests/OrchestratorTests.swift:330 |
| test6258 | `test6258_DotParserEdgeWithLabel` | TEST: Parse edge with label attribute | Tests/BifaciTests/OrchestratorTests.swift:350 |
| test6262 | `test6262_DotParserNodeWithAttributes` | TEST: Parse node with attributes | Tests/BifaciTests/OrchestratorTests.swift:364 |
| test6266 | `test6266_DotParserQuotedIdentifiers` | TEST: Parse quoted identifiers | Tests/BifaciTests/OrchestratorTests.swift:381 |
| test6270 | `test6270_DotParserComments` | TEST: Parse graph with comments | Tests/BifaciTests/OrchestratorTests.swift:397 |
| test6273 | `test6273_DotParserCapUrnLabel` | TEST: Parse cap URN label with escaped quotes | Tests/BifaciTests/OrchestratorTests.swift:413 |
| test6282 | `test6282_resolve_custom_media_def` | TEST6282: Test resolving a custom media URN from a registry-seeded media def | Tests/CapDAGTests/CSMediaDefTests.m:327 |
| test6283 | `test6283_resolve_custom_with_schema` | TEST6283: Test resolving a custom record media def carrying a schema from a registry-seeded media def | Tests/CapDAGTests/CSMediaDefTests.m:345 |
| test6285 | `test6285_b_outputStreamStartThenCloseEmpty` | TEST542b: OutputStream start + close sends STREAM_START + STREAM_END (empty stream) | Tests/BifaciTests/StreamingAPITests.swift:407 |
| test6287 | `test6287_local_overrides_registry` | TEST6287: Test local media_defs definition overrides registry definition for same URN | Tests/CapDAGTests/CSMediaDefTests.m:370 |
| test6289 | `test6289_c_outputStreamWriteWithoutStartThrows` | TEST542c: OutputStream write without start() throws | Tests/BifaciTests/StreamingAPITests.swift:437 |
| test6291 | `test6291_d_outputStreamDoubleStartThrows` | TEST542d: OutputStream start() twice throws | Tests/BifaciTests/StreamingAPITests.swift:453 |
| test6293 | `test6293_e_outputStreamModeConflictThrows` | TEST542e: OutputStream mode conflict throws (start write, call emitListItem) | Tests/BifaciTests/StreamingAPITests.swift:470 |
| test6307 | `test6307_PressureAndKill` | / Single test: allocate 90% of RAM with incompressible CSPRNG data, monitor / memory, detect pressure (kernel or threshold), kill cartridge, verify death. / The goal is to overload the system — force the kernel into real pressure. | testcartridge-host/Sources/TestcartridgeHost/main.swift:288 |
| test6309 | `test6309_BuilderBasicConstruction` | TEST6309: Builder basic construction | Tests/CapDAGTests/CSCapUrnBuilderTests.m:17 |
| test6311 | `test6311_BuilderFluentAPI` | TEST6311: Builder fluent a p i | Tests/CapDAGTests/CSCapUrnBuilderTests.m:34 |
| test6313 | `test6313_BuilderDirectionAccess` | TEST6313: Builder direction access | Tests/CapDAGTests/CSCapUrnBuilderTests.m:56 |
| test6314 | `test6314_ComplexNestedSchema` | TEST6314: Complex nested schema validation | Tests/CapDAGTests/CSSchemaValidationTests.m:416 |
| test6316 | `test6316_BuilderCustomTags` | TEST6316: Builder custom tags | Tests/CapDAGTests/CSCapUrnBuilderTests.m:74 |
| test6317 | `test6317_MediaUrnResolutionThroughRegistry` | TEST6317: Media urn resolution with registry | Tests/CapDAGTests/CSCapTests.m:371 |
| test6319 | `test6319_BuilderTagOverrides` | TEST6319: Builder tag overrides | Tests/CapDAGTests/CSCapUrnBuilderTests.m:93 |
| test6322 | `test6322_BuilderMissingInSpecFails` | TEST6322: Builder missing in spec fails | Tests/CapDAGTests/CSCapUrnBuilderTests.m:111 |
| test6324 | `test6324_BuilderMissingOutSpecFails` | TEST6324: Builder missing out spec fails | Tests/CapDAGTests/CSCapUrnBuilderTests.m:125 |
| test6328 | `test6328_BuilderEmptyBuildFailsWithMissingInSpec` | TEST6328: Builder empty build fails with missing in spec | Tests/CapDAGTests/CSCapUrnBuilderTests.m:139 |
| test6332 | `test6332_BuilderTagIgnoresInOut` | TEST6332: Builder tag ignores in out | Tests/CapDAGTests/CSCapUrnBuilderTests.m:149 |
| test6335 | `test6335_BuilderMinimalValid` | TEST6335: Builder minimal valid | Tests/CapDAGTests/CSCapUrnBuilderTests.m:159 |
| test6338 | `test6338_BuilderComplex` | TEST6338: Builder complex | Tests/CapDAGTests/CSCapUrnBuilderTests.m:179 |
| test6342 | `test6342_BuilderWildcards` | TEST6342: Builder wildcards | Tests/CapDAGTests/CSCapUrnBuilderTests.m:221 |
| test6346 | `test6346_BuilderStaticFactory` | TEST6346: Builder static factory | Tests/CapDAGTests/CSCapUrnBuilderTests.m:247 |
| test6350 | `test6350_BuilderMatchingWithBuiltCap` | TEST6350: Builder matching with built cap | Tests/CapDAGTests/CSCapUrnBuilderTests.m:257 |
| test6354 | `test6354_BuilderDirectionMismatchNoMatch` | TEST6354: Builder direction mismatch no match | Tests/CapDAGTests/CSCapUrnBuilderTests.m:308 |
| test6358 | `test6358_ArgumentValidationWithUnknownSpecFails` | Obj-C specific: unresolved spec ID fails hard during schema validation | Tests/CapDAGTests/CSSchemaValidationTests.m:141 |
| test6362 | `test6362_NonStructuredArgumentSkipsSchemaValidation` | Obj-C specific: Non-structured argument skips schema validation | Tests/CapDAGTests/CSSchemaValidationTests.m:160 |
| test6363 | `test6363_CapManifestWithPageUrl` | TEST6363: Cap manifest with page url | Tests/CapDAGTests/CSCapTests.m:491 |
| test6366 | `test6366_OutputWithEmbeddedSchemaValidationFailure` | TEST6366: Output with embedded schema validation failure | Tests/CapDAGTests/CSSchemaValidationTests.m:233 |
| test6370 | `test6370_IntegrationWithInputValidation` | TEST6370: Integration with input validation | Tests/CapDAGTests/CSSchemaValidationTests.m:275 |
| test6371 | `test6371_CapManifestCompatibility` | TEST6371: Cap manifest compatibility | Tests/CapDAGTests/CSCapTests.m:724 |
| test6373 | `test6373_IntegrationWithOutputValidation` | TEST6373: Integration with output validation | Tests/CapDAGTests/CSSchemaValidationTests.m:346 |
| test6378 | `test6378_SchemaValidationErrorDetails` | TEST6378: Schema validation error details | Tests/CapDAGTests/CSSchemaValidationTests.m:508 |
| test6381 | `test6381_BuiltinSpecIdsResolve` | TEST6381: Builtin spec ids resolve | Tests/CapDAGTests/CSSchemaValidationTests.m:555 |
| test6384 | `test6384_MediaDefsWithoutSchemaSkipsValidation` | TEST6384: Media defs without schema skips validation | Tests/CapDAGTests/CSSchemaValidationTests.m:610 |
| test6387 | `test6387_SchemaValidationPerformance` | TEST6387: Schema validation performance | Tests/CapDAGTests/CSSchemaValidationTests.m:637 |
| test6388 | `test6388_PerCapURLUsesSHA256` | / Per-cap URLs use /caps/<sha256-hex> — no URN-grammar characters / in the path, so no percent-encoding gymnastics. | Tests/CapDAGTests/CSFabricRegistryTests.m:154 |
| test6390 | `test6390_FullCapValidationWithMediaDefs` | TEST6390: Full cap validation with media defs | Tests/CapDAGTests/CSSchemaValidationTests.m:696 |
| test6391 | `test6391_sameCapDifferentSpellingsSameURL` | / TEST6391: Equivalent URNs (different tag order, etc.) hash to the / same key. This is the property that makes cross-language lookups / land at the same registry object regardless of which capdag / implementation issued the request. Inputs MUST quote any / multi-tag media URN value — the previous unquoted spelling / `out=media:task;id` was actually a different URN (the bare / `media:task` plus a separate `id` op tag), and treating those / two URNs as equivalent here masked a real spec violation. | Tests/CapDAGTests/CSFabricRegistryTests.m:173 |
| test6396 | `test6396_malformedCapUrnFailsHard` | TEST6396: A malformed cap URN must FAIL HARD — surfaced as an NSError, not passed through raw (the old fallback) to surface later as a misleading not-found. The `out` value below contains an unquoted `=`, which the cap grammar rejects. Against the old `parsed ? [parsed toString] : urn` fallback, normalizeCapUrn: returned the raw string and the cache lookup reported a (misleading) miss; this test asserts the truthful error and that the process never crashes. Mirrors Rust test6396_malformed_cap_urn_fails_hard. | Tests/CapDAGTests/CSFabricRegistryTests.m:238 |
| test6399 | `test6399_glob_pattern_detection` | Mirror-specific: glob pattern detection is an objc-only helper used by the resolver internals. Rust uses globwalk; these checks exercise the BSD glob detection logic. | Tests/CapDAGTests/CSInputResolverTests.m:506 |
| test6401 | `test6401_resolved_input_set_total_size` | Mirror-specific: CSResolvedInputSet aggregates totalSize across files | Tests/CapDAGTests/CSInputResolverTests.m:515 |
| test6403 | `test6403_MetadataPropagationFromObjectDef` | TEST6403: Metadata propagation from object def | Tests/CapDAGTests/CSMediaDefTests.m:25 |
| test6405 | `test6405_MetadataNilByDefault` | TEST6405: Metadata nil by default | Tests/CapDAGTests/CSMediaDefTests.m:56 |
| test6411 | `test6411_capManifestWithAuthor` | TEST6411: Author field round-trips through CSCapManifest.withAuthor. | Tests/BifaciTests/ManifestTests.swift:49 |
| test6412 | `test6412_capManifestJsonRoundtrip` | TEST6412: JSON roundtrip preserves channel and cap_groups. | Tests/BifaciTests/ManifestTests.swift:63 |
| test6422 | `test6422_componentMetadataAccessors` | TEST6422: CSCapManifest exposes name / version / channel / description / cap_groups via its accessors. The Obj-C bridge is schema-equivalent to the Swift `Manifest` struct. | Tests/BifaciTests/ManifestTests.swift:254 |
| test6424 | `test6424_ResolveMediaUrnNotFound` | TEST6424: Resolve media urn not found | Tests/CapDAGTests/CSMediaDefTests.m:112 |
| test6425 | `test6425_ExtensionsPropagationFromObjectDef` | Extensions field tests | Tests/CapDAGTests/CSMediaDefTests.m:124 |
| test6426 | `test6426_ExtensionsEmptyWhenNotSet` | TEST6426: Extensions empty when not set | Tests/CapDAGTests/CSMediaDefTests.m:148 |
| test6435 | `test6435_RegistryValidCapCheck` | Registry validator tests removed - not part of current API | Tests/CapDAGTests/CSFabricRegistryTests.m:138 |
| test6441 | `test6441_GetCapDefinitionReal` | TEST6441: Get cap definition real | Tests/CapDAGTests/CSFabricRegistryTests.m:269 |
| test6443 | `test6443_ValidateCapCanonical` | TEST6443: Validate cap canonical | Tests/CapDAGTests/CSFabricRegistryTests.m:290 |
| test6445 | `test6445_SourceWithData` | TEST6445: Source with data | Tests/CapDAGTests/CSStdinSourceTests.m:15 |
| test6447 | `test6447_SourceWithFileReference` | TEST6447: Source with file reference | Tests/CapDAGTests/CSStdinSourceTests.m:31 |
| test6461 | `test6461_DataSourceWithEmptyData` | TEST6461: Data source with empty data | Tests/CapDAGTests/CSStdinSourceTests.m:54 |
| test6477 | `test6477_DataSourceWithBinaryContent` | TEST6477: Data source with binary content | Tests/CapDAGTests/CSStdinSourceTests.m:65 |
| test6485 | `test6485_FileReferenceWithAllFields` | TEST6485: File reference with all fields | Tests/CapDAGTests/CSStdinSourceTests.m:79 |
| test6490 | `test6490_StandaloneCollectNode` | MARK: - Standalone Collect Node Tests | Tests/CapDAGTests/CSPlanDecompositionTests.m:63 |
| test6523 | `test6523_CapAndForEachAreNotStandaloneCollect` | TEST6523: Cap and for each are not standalone collect | Tests/CapDAGTests/CSPlanDecompositionTests.m:76 |
| test6525 | `test6525_InvalidCapUrn` | TEST001 variant: Test empty URN fails | Tests/CapDAGTests/CSCapUrnTests.m:130 |
| test6527 | `test6527_Coding` | Obj-C specific: NSCoding support | Tests/CapDAGTests/CSCapUrnTests.m:524 |
| test6534 | `test6534_Copying` | Obj-C specific: NSCopying support | Tests/CapDAGTests/CSCapUrnTests.m:546 |
| test6541 | `test6541_Wildcard004InOutNoValuesAreIllegal` | TEST_WILDCARD_004: cap:in;out collapses to the same illegal bare top form | Tests/CapDAGTests/CSCapUrnTests.m:1049 |
| test6544 | `test6544_b_builderRejectsStructuralKeys` | TEST023B: Builder rejects reserved structural keys on tag/marker helpers | Tests/CapDAGTests/CSCapUrnTests.m:1383 |
| test6547 | `test6547_effectPatchAppliesMediaDelta` | TEST655 variant: patch effect applies the declared media delta to runtime input | Tests/CapDAGTests/CSCapUrnTests.m:1609 |
| test6549 | `test6549_CanonicalArgumentsDeserialization` | TEST6549: Canonical arguments deserialization | Tests/CapDAGTests/CSCapTests.m:226 |
| test6551 | `test6551_CanonicalOutputDeserialization` | TEST6551: Canonical output deserialization | Tests/CapDAGTests/CSCapTests.m:251 |
| test6553 | `test6553_CanonicalValidationDeserialization` | TEST6553: Canonical validation deserialization | Tests/CapDAGTests/CSCapTests.m:268 |
| test6555 | `test6555_CompleteCapDeserialization` | TEST6555: Complete cap deserialization | Tests/CapDAGTests/CSCapTests.m:289 |
| test6558 | `test6558_CapManifestCreation` | MARK: - Cap Manifest Tests | Tests/CapDAGTests/CSCapTests.m:428 |
| test6564 | `test6564_CapManifestDictionaryDeserialization` | TEST6564: Cap manifest dictionary deserialization | Tests/CapDAGTests/CSCapTests.m:523 |
| test6566 | `test6566_CapManifestRequiredFields` | TEST6566: Cap manifest required fields | Tests/CapDAGTests/CSCapTests.m:577 |
| test6569 | `test6569_CapManifestWithMultipleCaps` | TEST6569: Cap manifest with multiple caps | Tests/CapDAGTests/CSCapTests.m:591 |
| test6571 | `test6571_CapManifestEmptyCaps` | TEST6571: Cap manifest empty caps | Tests/CapDAGTests/CSCapTests.m:637 |
| test6573 | `test6573_CapManifestOptionalAuthorField` | TEST6573: Cap manifest optional author field | Tests/CapDAGTests/CSCapTests.m:666 |
| test6578 | `test6578_ArgumentCreationWithNewAPI` | TEST6578: Argument creation with new a p i | Tests/CapDAGTests/CSCapTests.m:779 |
| test6580 | `test6580_OutputCreationWithNewAPI` | TEST6580: Output creation with new a p i | Tests/CapDAGTests/CSCapTests.m:900 |
| test6583 | `test6583_CapDocumentationRoundTrip` | Mirrors TEST920 in capdag/src/cap/definition.rs and the JS testJS_capDocumentationRoundTrip test. The body is non-trivial — multi-line, embedded backticks and double quotes, Unicode dingbat (\u2605) — so any escaping mismatch between dictionary serialization here and the Rust / JS counterparts surfaces as a failed round-trip. | Tests/CapDAGTests/CSCapTests.m:922 |
| test6586 | `test6586_file_path_array_invalid_json_fails` | TEST6586: A scalar file-path arg receiving a nonexistent path fails hard with a clear error that names the path. The runtime refuses to silently swallow user mistakes like typos or wrong directories. | Tests/BifaciTests/CartridgeRuntimeTests.swift:959 |
| test6587 | `test6587_file_path_array_one_file_missing_fails_hard` | TEST6587: file-path-array with literal nonexistent path fails hard | Tests/BifaciTests/CartridgeRuntimeTests.swift:988 |
| test6588 | `test6588_file_path_array_empty_array` | TEST6588: file-path arg in CBOR mode with empty Array value returns empty. CBOR Array (not JSON) is the multi-input wire form for sequence args. Mirrors Rust test6588_file_path_array_empty_array. | Tests/BifaciTests/CartridgeRuntimeTests.swift:1194 |
| test6594 | `test6594_capabilitiesEmptyInitially` | TEST6594: capabilities() returns empty JSON initially (no running cartridges) | Tests/BifaciTests/RuntimeTests.swift:320 |
| test6598 | `test6598_manifestValidatePassesWithIdentity` | TEST6598: CapManifest::validate() passes when CAP_IDENTITY is present | Tests/BifaciTests/StandardCapsTests.swift:81 |
| test6599 | `test6599_manifestValidateFailsWithoutIdentity` | TEST6599: CapManifest::validate() fails when CAP_IDENTITY is missing | Tests/BifaciTests/StandardCapsTests.swift:96 |
| test6623 | `test6623_cartridgeDeathKeepsKnownCapsAdvertised` | TEST6623: Cartridge death keeps caps advertised for on-demand respawn. Identity is the gating filter for advertisement; we provision a real cartridge directory with a valid `cartridge.json` so the cartridge has a resolvable identity. cap_table routes regardless of identity (in-process / attached cartridges still need to be dispatchable), but the relay payload only advertises cartridges with identity records. | Tests/BifaciTests/RuntimeTests.swift:1128 |
| test6650 | `test6650_findPathsMultiStep` | TEST6650: Multi-step path through intermediate node | Tests/CapDAGTests/CSLiveCapFabTests.m:153 |
| test6651 | `test6651_findPathsEmptyWhenNoPath` | TEST6651: Empty when target unreachable | Tests/CapDAGTests/CSLiveCapFabTests.m:175 |
| test6652 | `test6652_getReachableTargetsAll` | TEST6652: BFS finds multiple direct targets | Tests/CapDAGTests/CSLiveCapFabTests.m:191 |
| test6653 | `test6653_typeMismatchPdfPng` | TEST6653: PDF cap does not match PNG input | Tests/CapDAGTests/CSLiveCapFabTests.m:214 |
| test6654 | `test6654_typeMismatchPngPdf` | TEST6654: PNG cap does not match PDF input | Tests/CapDAGTests/CSLiveCapFabTests.m:229 |
| test6655 | `test6655_reachableTargetsTypeMatching` | TEST6655: BFS respects type matching | Tests/CapDAGTests/CSLiveCapFabTests.m:244 |
| test6656 | `test6656_findPathsTypeChain` | TEST6656: Multi-step type chain enforcement | Tests/CapDAGTests/CSLiveCapFabTests.m:267 |
| test6657 | `test6657_sortingShorterFirst` | TEST6657: Sorting prefers shorter paths | Tests/CapDAGTests/CSLiveCapFabTests.m:290 |
| test6658 | `test6658_forEachWithSequenceInput` | TEST6658: ForEach synthesized when input is a sequence | Tests/CapDAGTests/CSLiveCapFabTests.m:312 |
| test6672 | `test6672_cborAcceptsStreamEndWithoutChunkCount` | TEST6672: CBOR decode ACCEPTS STREAM_END without chunk_count — unbounded streams make no length promise (v3, L16) | Tests/BifaciTests/FrameTests.swift:1737 |
| test6720 | `test6720_writeAfterCloseThrowsCleanly` | TEST6720: Writing to a closed FrameWriter must throw FrameError.ioError("writer closed"), never raise an Objective-C NSException that aborts the process. | Tests/BifaciTests/FrameTests.swift:1837 |
| test6721 | `test6721_doubleCloseIsIdempotent` | TEST6721: Calling close() twice on a FrameWriter is a no-op — the second call must not throw, must not double-close the underlying fd, and must leave the writer in the closed state. | Tests/BifaciTests/FrameTests.swift:1862 |
| test6722 | `test6722_flushAfterCloseThrowsCleanly` | TEST6722: flush() on a closed FrameWriter — even with an empty buffer — must throw FrameError.ioError, not silently succeed. A flush call after close() is a programmer error and must surface, not be papered over. | Tests/BifaciTests/FrameTests.swift:1885 |
| test6723 | `test6723_concurrentCloseAndWriteDoesNotCrash` | TEST6723: Concurrent close() + write() must not raise an Objective-C NSException. This is the regression test for the CartridgeXPCService crash on cartridge OOM: the old writer accessed `handle.fileDescriptor` on every write, so a close() racing a write() called the accessor on a closed handle and aborted the process. The cached-fd writer keeps the descriptor in the writer's own state, so the worst outcome of the race is a clean FrameError thrown from write(). | Tests/BifaciTests/FrameTests.swift:1899 |
| test6724 | `test6724_closeShutsTheUnderlyingPipe` | TEST6724: After FrameWriter.close(), the underlying FileHandle is closed. A subsequent read on the paired read end must observe EOF — proving that close() actually closes the pipe (not just marks the writer dead in software). This guards against the regression where close() flips the writer flag but leaves the pipe open, which would let buffered data still drain into a peer that's been told the writer is gone. | Tests/BifaciTests/FrameTests.swift:1966 |
| test6725 | `test6725_deinitDoesNotAccessClosedHandle` | TEST6725: A FrameWriter going through deinit must NOT touch the underlying handle's `fileDescriptor` accessor. The original bug used to deinit-flush by reading `handle.fileDescriptor`, which raises NSFileHandleOperationException on a closed handle and aborts the process. The new contract: deinit does no I/O. This test deinits a writer whose handle was closed externally, then asserts the test process is still alive (i.e. did not crash via NSException). | Tests/BifaciTests/FrameTests.swift:1978 |
| test6734 | `test6734_reject_invalid_combinations` | TEST6734: Invalid qualifier combinations must be rejected. | Tests/CapDAGTests/CSCapUrnTests.m:1836 |
| test6735 | `test6735_axis_weighting_out_dominates` | TEST6735: out-axis difference dominates combined in+y differences. | Tests/CapDAGTests/CSCapUrnTests.m:1852 |
| test6736 | `test6736_axis_weighting_decoded_layout` | TEST6736: Decoded layout — 10000*out + 100*in + y. | Tests/CapDAGTests/CSCapUrnTests.m:1878 |
| test6745 | `test6745_RelaySwitchInitRejectsDuplicateIds` | TEST6745: RelaySwitch::new rejects duplicate ids in its cardinality list. | Tests/BifaciTests/RelaySwitchTests.swift:992 |
| test6748 | `test6748_routesReqToHandler` | TEST6748: InProcessCartridgeHost routes REQ to matching handler and returns response | Tests/BifaciTests/InProcessCartridgeHostTests.swift:104 |
| test6749 | `test6749_identityVerification` | TEST6749: InProcessCartridgeHost handles identity verification (echo nonce) | Tests/BifaciTests/InProcessCartridgeHostTests.swift:188 |
| test6750 | `test6750_noHandlerReturnsErr` | TEST6750: InProcessCartridgeHost returns NO_HANDLER for unregistered cap | Tests/BifaciTests/InProcessCartridgeHostTests.swift:249 |
| test6751 | `test6751_manifestIncludesAllCaps` | TEST6751: InProcessCartridgeHost manifest includes identity cap and handler caps | Tests/BifaciTests/InProcessCartridgeHostTests.swift:291 |
| test7000 | `test7000_v3HandshakeNegotiatesAllFourLimits` | TEST7000: v3 handshake succeeds and negotiates the element-wise minimum of all four limits including initial_credit | Tests/BifaciTests/ProtocolV3Tests.swift:127 |
| test7001 | `test7001_handshakeRejectsVersion2` | TEST7001: HELLO carrying protocol version 2 is rejected at handshake with a version-mismatch error | Tests/BifaciTests/ProtocolV3Tests.swift:147 |
| test7002 | `test7002_initialCreditNegotiatedMinimum` | TEST7002: initial_credit negotiation picks the element-wise minimum of the two proposals | Tests/BifaciTests/ProtocolV3Tests.swift:180 |
| test7003 | `test7003_decodeRejectsMalformedIdWrongLength` | TEST7003: decodeFrame rejects a present-but-malformed id (wrong byte length) as a hard error instead of fabricating .uint(0), which would forge a routing key from corruption and misroute the frame. | Tests/BifaciTests/FrameTests.swift:61 |
| test7004 | `test7004_decodeRejectsMalformedIdWrongType` | TEST7004: decodeFrame rejects an id of the wrong CBOR type as a hard error. | Tests/BifaciTests/FrameTests.swift:72 |
| test7005 | `test7005_decodeRejectsMalformedRoutingId` | TEST7005: decodeFrame rejects a present-but-malformed routing_id (wrong length or wrong type) rather than silently dropping it — a dropped relay hint would let the switch treat a routed response as a fresh top-level request. A well-formed routing_id still decodes. | Tests/BifaciTests/FrameTests.swift:85 |
| test7010 | `test7010_creditFrameRoundtrip` | TEST7010: CREDIT frame round-trips encode/decode with rid, stream_id, and credit count | Tests/BifaciTests/ProtocolV3Tests.swift:197 |
| test7011 | `test7011_creditIsNonFlow` | TEST7011: CREDIT is a non-flow frame — no seq assigned, passes the reorder buffer untouched regardless of flow state | Tests/BifaciTests/ProtocolV3Tests.swift:231 |
| test7012 | `test7012_streamStartUnboundedRoundtrip` | TEST7012: STREAM_START unbounded flag round-trips through CBOR; absent flag means bounded | Tests/BifaciTests/ProtocolV3Tests.swift:258 |
| test7013 | `test7013_cborRejectsCreditWithoutCount` | TEST7013: CBOR decode REJECTS a CREDIT frame missing its credit count | Tests/BifaciTests/ProtocolV3Tests.swift:275 |
| test7014 | `test7014_endTerminalMetaRoundtrip` | TEST7014: END terminal meta (progress, message) round-trips; successful END without progress reads as 1.0; failed END without progress reads as None | Tests/BifaciTests/ProtocolV3Tests.swift:291 |
| test7015 | `test7015_creditGateAcquireAndGrant` | TEST7015: CreditGate acquire succeeds immediately within the initial window and waits when exhausted until a grant arrives. | Tests/BifaciTests/ProtocolV3Tests.swift:353 |
| test7016 | `test7016_creditGateCloseReleasesWaiters` | TEST7016: CreditGate close releases blocked waiters with CreditClosed and fails all future acquires. | Tests/BifaciTests/ProtocolV3Tests.swift:374 |
| test7017 | `test7017_creditRouterRouting` | TEST7017: CreditRouter routes grants by (rid, stream_id), falls back to a request's sole gate for stream-less grants, and reports unmatched grants. | Tests/BifaciTests/ProtocolV3Tests.swift:408 |
| test7018 | `test7018_creditRouterCloseRequest` | TEST7018: CreditRouter close_request closes and removes every gate of the request, releasing their waiters. | Tests/BifaciTests/ProtocolV3Tests.swift:432 |
| test7019 | `test7019_dropCountersRecordAndSnapshot` | TEST7019: Drop counters record per-reason exactly once per drop, and the snapshot omits zero-count reasons while totalling all of them. | Tests/BifaciTests/ProtocolV3Tests.swift:466 |
| test7020 | `test7020_writerGateDropsPostTerminalFlowFrames` | TEST7020: A flow frame reaching the writer after the flow's END has been written is dropped with a counted post_terminal drop — END is the last flow frame on the wire. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:87 |
| test7021 | `test7021_writerGatePrecision` | TEST7021: The writer gate is precise — flow frames before END are written, non-flow frames (heartbeat, credit) still pass after a flow's terminal, and only that flow is gated. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:116 |
| test7025 | `test7025_unroutableFlowFrameIsCountedDrop` | TEST7025: A flow frame for a request with no routing state is a counted no_route drop — not a protocol error and not a silent loss — observable in the protocol stats snapshot. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:988 |
| test7026 | `test7026_reorderFlushesPreTerminalBeforeCleanup` | TEST7026: An out-of-order terminal is buffered until the gap fills; buffered pre-terminal frames flush ahead of it in seq order, and only then may the flow be cleaned up | Tests/BifaciTests/ProtocolV3Tests.swift:317 |
| test7027 | `test7027_channelClosedSendsAreCounted` | TEST7027: A frame sent through a ChannelFrameSender whose receiver is gone is a counted channel_closed drop, never a silent loss. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:145 |
| test7029 | `test7029_terminatedFlowsCapacityAndEviction` | TEST7029: TerminatedFlows membership is exact up to capacity and evicts strictly oldest-first beyond it. | Tests/BifaciTests/ProtocolV3Tests.swift:488 |
| test7030 | `test7030_registerOnceTerminateOnce` | TEST7030: A request registers exactly once and terminates exactly once — duplicate registration and double termination are rejected, and after terminate zero state remains for the key. | Tests/BifaciTests/RequestStateTests.swift:152 |
| test7031 | `test7031_ridIndexConsistency` | TEST7031: The rid index and the entry table never disagree across register/terminate cycles, and a terminated rid is immediately reusable. | Tests/BifaciTests/RequestStateTests.swift:178 |
| test7032 | `test7032_recordFrameStatsAndPhase` | TEST7032: record_frame accumulates per-stream frame/byte/chunk counters by direction, flips phase Created→Streaming on the first flow frame, and tracks unbounded/ended/credit stream markers. | Tests/BifaciTests/RequestStateTests.swift:199 |
| test7033 | `test7033_terminatedSummariesRing` | TEST7033: Terminated requests leave a bounded ring of summaries carrying kind, lifetime, and flow totals, and the ring evicts oldest-first at capacity. | Tests/BifaciTests/RequestStateTests.swift:237 |
| test7035 | `test7035_endTerminatesAndReleasesAllState` | TEST7035: After END, the switch holds zero state for the request — entry, rid index, and response channel all released atomically, with the terminal delivered and a terminated summary recorded. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:1016 |
| test7036 | `test7036_errTerminatesAndReleasesAllState` | TEST7036: After ERR, the same total-cleanup invariant holds as after END, with kind err. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:1053 |
| test7037 | `test7037_cancelCascadesToChildrenAndCleansAllState` | TEST7037: Cancelling a request terminates it AND its recursively-linked peer children — Cancel frames reach the destination, waiting channels get ERR CANCELLED, and zero state remains for parent or child. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:1076 |
| test7038 | `test7038_masterDeathTerminatesPendingRequests` | TEST7038: Master death terminates every request routed to it with kind master_died, delivering synthetic MASTER_DIED ERRs to waiting channels and leaving zero state. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:1160 |
| test7050 | `test7050_senderStallsAtWindowAndResumesOnGrant` | TEST7050: A credited sender emits exactly its window of chunks then stalls until a CREDIT grant arrives — observed on the frame channel. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:325 |
| test7052 | `test7052_inputGrantsAreBatched` | TEST7052: Input consumption emits batched CREDIT grants — roughly one grant per half-window consumed, not one per chunk. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:410 |
| test7053 | `test7053_overWindowChunkIsCreditViolation` | TEST7053: A chunk received beyond the granted window is a fatal CREDIT_VIOLATION surfaced to the consumer (L12). | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:546 |
| test7059 | `test7059_terminalEndReleasesCreditAndLeaksNoState` | TEST7059: Terminal frames release ALL request state and every registration is accounted exactly once (L7/L13) — across a mixed workload of END-, ERR-, and cancel-terminated requests the active table drains to empty and the terminated-by-kind counts sum to the total registrations. A leaked entry keeps `active` non-empty; a double- or un-counted termination breaks the conservation equation. (The reference runs this over a real cartridge execution; the law under test lives in the switch's request table, which is the layer this mirror implements.) | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:726 |
| test7061 | `test7061_negotiatedInitialCreditIsMinOfProposals` | TEST7061: The negotiated initial_credit is the element-wise min of all masters' proposals, wire-visible at the switch. A master's RelayNotify carries its limits; renegotiation must include initialCredit — the regression this pins is `rebuildLimits()` dropping the credit field and silently resetting it to the default (which would let switch-side senders overrun a smaller window with CREDIT_VIOLATIONs at the master). | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:795 |
| test7062 | `test7062_logFlowsWhileWindowExhausted` | TEST7062: LOG/progress frames flow while the data window is exhausted — control frames are never credited. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:372 |
| test7063 | `test7063_pendingGrantsFlushBeforeBlocking` | TEST7063: A receiver flushes pending sub-batch grants before blocking on an empty input — progress is guaranteed even when the sender's window is smaller than the receiver's grant batch threshold. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:485 |
| test7070 | `test7070_unboundedInputConsumedLive` | TEST7070: An unbounded input stream is consumed live — the handler observes early items while the producer is still emitting, and the stream reports itself unbounded. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:586 |
| test7073 | `test7073_collectRefusesUnboundedStreams` | TEST7073: Buffering collectors refuse unbounded streams with a hard error instead of buffering without bound. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:617 |
| test7085 | `test7085_relayNotifyCarriesHostProtocolStats` | TEST7085: The RelayNotify capabilities payload carries the host's protocol stats snapshot, surviving the wire round-trip. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:955 |
| test7086 | `test7086_dropSnapshotMatchesInducedDrops` | TEST7086: One runtime's drop counters aggregate every drop source — post-terminal writer drops and closed-channel sends — each counted exactly once, and the snapshot totals match the induced drops. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:164 |
| test7087 | `test7087_snapshotFieldNamesAreStable` | TEST7087: Protocol stats snapshots serialize with stable field names — the snapshot shape is the mirror contract. | Tests/BifaciTests/RequestStateTests.swift:61 |
| test7088 | `test7088_lastActivityMonotonic` | TEST7088: last_activity is monotonic non-decreasing across a long-lived streaming request — idle time resets on every recorded frame and never runs backwards. | Tests/BifaciTests/RequestStateTests.swift:110 |
| test7089 | `test7089_helloFailedStaysInInventoryWithError` | TEST7089: A cartridge whose HELLO permanently failed stays IN the inventory advertisement carrying a handshake_failed attachment error and no cap groups — failure is named, never silently absent; a roster-retired cartridge disappears entirely. (The reference drives hello_failed directly and merges daemon-provided static inventory records; on this host both flow through `syncDiscoveryOutcomes` — the macOS discovery authority.) | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:369 |
| test7090 | `test7090_heartbeatDropsTotalReachesInventoryStats` | TEST7090: The cartridge's cumulative protocol drop counter (`drops_total` heartbeat meta, L8) is ingested by the host and surfaces on the cartridge's inventory runtime stats as `protocol_drops_total` — absent until the first reading, then tracking the running total as-is. | Tests/BifaciTests/CartridgeHostInstalledRecordTests.swift:312 |
| test7091 | `test7091_switchRetainsHostProtocolStatsFromRelayNotify` | TEST7091: Host protocol stats carried by a master's RelayNotify are RETAINED by the switch (not parsed-and-discarded) and surface in `protocolStats().hosts` keyed by master id; a master that has not yet advertised stats is absent from the map — never a zeroed placeholder. | Tests/BifaciTests/RelaySwitchTests.swift:1412 |
| test7092 | `test7092_capUrnAttributionSurvivesLifecycle` | TEST7092: A request registered with its originating REQ's cap URN carries that identity through the ACTIVE snapshot and into the terminated ring — observability surfaces can always NAME a request (background chatter vs run traffic), never just show a bare rid. A request registered without one snapshots with cap_urn absent — never invented. | Tests/BifaciTests/RequestStateTests.swift:31 |
| test7093 | `test7093_deadConsumerCancelsUpstream` | TEST7093: A response frame for a LIVE request whose external consumer is gone (dropped/timed-out caller) is a counted channel_closed drop AND cancels the request upstream — the destination master receives Cancel, the entry terminates as cancelled, and zero state remains: the cartridge stops producing for a dead channel instead of running to completion against it. | Tests/BifaciTests/ProtocolV3RuntimeTests.swift:863 |
---

*Generated from CapDag-ObjC/Swift source tree*
*Total tests: 881*
*Total numbered tests: 881*
*Total unnumbered tests: 0*
*Total numbered tests missing descriptions: 0*
*Total numbering mismatches: 0*
