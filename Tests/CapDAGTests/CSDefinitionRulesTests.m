//
//  CSDefinitionRulesTests.m
//  The definition rules a cap is held to — named arguments, the type an
//  argument accepts, a cap's outputs — under the numbers every capdag
//  implementation tests them under.
//

#import <XCTest/XCTest.h>
#import "CapDAG.h"

@interface CSDefinitionRulesTests : XCTestCase
@end

static NSString * const CSVoidCap = @"cap:in=\"media:void\";test;out=\"media:void\"";
static NSString * const CSTextCap = @"cap:in=\"media:enc=utf-8\";test;out=\"media:void\"";

static CSCap *CSCapWithArgs(NSString *urn, NSArray<CSCapArg *> *args) {
    CSCap *cap = [CSCap capWithUrn:[CSCapUrn fromString:urn error:nil] title:@"Test" aliases:@[@"cmd"]];
    for (CSCapArg *arg in args) [cap addArg:arg];
    return cap;
}

static CSCap *CSCapWithOutputs(NSString *outSpec, NSArray<CSCapOutput *> *outputs) {
    NSString *urn = [NSString stringWithFormat:@"cap:in=\"media:enc=utf-8\";test;out=\"%@\"", outSpec];
    CSCap *cap = [CSCap capWithUrn:[CSCapUrn fromString:urn error:nil] title:@"Test" aliases:@[@"cmd"]];
    [cap setOutputs:outputs];
    return cap;
}

static CSCapArg *CSFlagArg(NSString *urn, NSString *name, NSString *flag) {
    return [CSCapArg argWithMediaUrn:urn name:name required:NO sources:@[[CSArgSource cliFlagSource:flag]]];
}

static CSCapArg *CSStdinArg(NSString *urn, NSString *name, NSString *stdinUrn) {
    return [CSCapArg argWithMediaUrn:urn name:name required:YES sources:@[[CSArgSource stdinSourceWithMediaUrn:stdinUrn]]];
}

static CSCapOutput *CSOutput(NSString *urn, NSString *name) {
    return [CSCapOutput outputWithMediaUrn:urn name:name outputDescription:@""];
}

@implementation CSDefinitionRulesTests

/// The message a refusal gives; a definition that passes fails the test.
- (NSString *)refusedArgs:(CSCap *)cap {
    NSError *error = nil;
    XCTAssertFalse([CSCapValidator validateCapArgs:cap error:&error], @"the definition must be refused");
    XCTAssertTrue([error isKindOfClass:[CSValidationError class]], @"%@", error);
    return error.localizedDescription ?: @"";
}

- (NSString *)refusedOutputs:(CSCap *)cap {
    NSError *error = nil;
    XCTAssertFalse([CSCapValidator validateCapOutputs:cap error:&error], @"the definition must be refused");
    XCTAssertTrue([error isKindOfClass:[CSValidationError class]], @"%@", error);
    return error.localizedDescription ?: @"";
}

- (void)assertArgsPass:(CSCap *)cap {
    NSError *error = nil;
    XCTAssertTrue([CSCapValidator validateCapArgs:cap error:&error], @"%@", error);
}

- (void)assertOutputsPass:(CSCap *)cap {
    NSError *error = nil;
    XCTAssertTrue([CSCapValidator validateCapOutputs:cap error:&error], @"%@", error);
}

static CSCapArg *CSPositionArg(NSString *urn, NSString *name, NSInteger position) {
    return [CSCapArg argWithMediaUrn:urn name:name required:YES sources:@[[CSArgSource positionSource:position]]];
}

static NSString * const CSVoidRecordCap = @"cap:in=\"media:void\";test;out=\"media:record\"";
static NSString * const CSTextRecordCap = @"cap:in=\"media:enc=utf-8\";test;out=\"media:record\"";

// TEST578: RULE1 - duplicate media_urns rejected
- (void)test578_rule1DuplicateMediaUrns {
    NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidRecordCap, @[CSPositionArg(CSMediaString, @"arg0", 0), CSPositionArg(CSMediaString, @"arg1", 1)])];
    XCTAssertTrue([err containsString:@"RULE1:"], @"%@", err);
}

// TEST579: RULE2 - empty sources rejected
- (void)test579_rule2EmptySources {
    NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidRecordCap, @[[CSCapArg argWithMediaUrn:CSMediaString name:@"option" required:YES sources:@[]]])];
    XCTAssertTrue([err containsString:@"RULE2"], @"%@", err);
}

// TEST582: RULE4 - duplicate source type in single arg rejected
- (void)test582_rule4DuplicateSourceType {
    CSCapArg *twice = [CSCapArg argWithMediaUrn:CSMediaString name:@"arg0" required:YES
                                        sources:@[[CSArgSource positionSource:0], [CSArgSource positionSource:1]]];
    NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidRecordCap, @[twice])];
    XCTAssertTrue([err containsString:@"RULE4"], @"%@", err);
}

// TEST583: RULE5 - duplicate position across args rejected
- (void)test583_rule5DuplicatePosition {
    NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidRecordCap, @[CSPositionArg(CSMediaString, @"arg0", 0), CSPositionArg(CSMediaInteger, @"arg0-2", 0)])];
    XCTAssertTrue([err containsString:@"RULE5"], @"%@", err);
}

// TEST584: RULE6 - position gap rejected (0, 2 without 1)
- (void)test584_rule6PositionGap {
    NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidRecordCap, @[CSPositionArg(CSMediaString, @"arg0", 0), CSPositionArg(CSMediaInteger, @"arg2", 2)])];
    XCTAssertTrue([err containsString:@"RULE6"], @"%@", err);
}

// TEST585: RULE6 - sequential positions (0, 1) pass
- (void)test585_rule6SequentialOk {
    [self assertArgsPass:CSCapWithArgs(CSVoidRecordCap, @[CSPositionArg(CSMediaString, @"arg0", 0), CSPositionArg(CSMediaInteger, @"arg1", 1)])];
}

// TEST586: RULE7 - arg with both position and cli_flag rejected
- (void)test586_rule7PositionAndCliFlag {
    CSCapArg *both = [CSCapArg argWithMediaUrn:CSMediaString name:@"file" required:YES
                                       sources:@[[CSArgSource positionSource:0], [CSArgSource cliFlagSource:@"--file"]]];
    NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidRecordCap, @[both])];
    XCTAssertTrue([err containsString:@"RULE7"], @"%@", err);
}

// TEST587: RULE9 - duplicate cli_flag across args rejected
- (void)test587_rule9DuplicateCliFlag {
    NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidRecordCap, @[CSFlagArg(CSMediaString, @"file", @"--file"), CSFlagArg(CSMediaInteger, @"file-2", @"--file")])];
    XCTAssertTrue([err containsString:@"RULE9"], @"%@", err);
}

// TEST588: RULE10 - reserved cli_flags rejected
- (void)test588_rule10ReservedCliFlags {
    for (NSString *reserved in @[@"manifest", @"--help", @"--version", @"-v", @"-h"]) {
        NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidRecordCap, @[CSFlagArg(CSMediaString, @"option", reserved)])];
        XCTAssertTrue([err containsString:@"RULE10"], @"%@: %@", reserved, err);
    }
}

// TEST589: valid cap args with mixed sources pass all rules
- (void)test589_allRulesPass {
    CSCapArg *input = [CSCapArg argWithMediaUrn:CSMediaString name:@"input" required:YES
                                        sources:@[[CSArgSource positionSource:0], [CSArgSource stdinSourceWithMediaUrn:@"media:enc=utf-8"]]];
    CSCapArg *second = [CSCapArg argWithMediaUrn:CSMediaInteger name:@"arg1" required:NO sources:@[[CSArgSource positionSource:1]]];
    [self assertArgsPass:CSCapWithArgs(CSTextRecordCap, @[input, second])];
}

// TEST1294: RULE15 - void-input cap with stdin source rejected
- (void)test1294_rule15VoidInputWithStdinRejected {
    CSCap *cap = CSCapWithArgs(@"cap:in=\"media:void\";test;out=\"media:string\"",
                               @[CSStdinArg(@"media:string", @"string", @"media:string")]);
    XCTAssertTrue([[self refusedArgs:cap] containsString:@"RULE15"]);
}

// TEST1295: RULE15 - non-void-input cap without stdin source rejected
- (void)test1295_rule15NonVoidInputWithoutStdinRejected {
    CSCap *cap = CSCapWithArgs(@"cap:in=\"media:string\";test;out=\"media:string\"",
                               @[CSFlagArg(@"media:string", @"string", @"--name")]);
    XCTAssertTrue([[self refusedArgs:cap] containsString:@"RULE15"]);
}

// TEST1296: RULE15 - void-input cap with only cli_flag sources passes
- (void)test1296_rule15VoidInputCliFlagOnly {
    [self assertArgsPass:CSCapWithArgs(@"cap:in=\"media:void\";test;out=\"media:string\"",
                                       @[CSFlagArg(@"media:string", @"string", @"--name")])];
}

// TEST1297: RULE15 - non-void-input cap with stdin source passes
- (void)test1297_rule15NonVoidInputWithStdin {
    [self assertArgsPass:CSCapWithArgs(@"cap:in=\"media:string\";test;out=\"media:string\"",
                                       @[CSStdinArg(@"media:string", @"string", @"media:string")])];
}

// TEST580: RULE3 - two args that declare a stdin source are rejected
- (void)test580_rule3TwoStdinArgsRejected {
    NSString *err = [self refusedArgs:CSCapWithArgs(CSTextCap, @[
        CSStdinArg(CSMediaString, @"input", @"media:enc=utf-8"),
        CSStdinArg(CSMediaInteger, @"other", @"media:"),
    ])];
    XCTAssertTrue([err containsString:@"RULE3"], @"%@", err);
    // Both arguments are named, by the URNs that identify them.
    XCTAssertTrue([err containsString:CSMediaString] && [err containsString:CSMediaInteger], @"%@", err);
}

// TEST581: RULE3 - two stdin args are rejected even when their stdin URNs are
// identical: a cap has one main input, and two args that both claim it leave
// nothing to say which of them a piped value is.
- (void)test581_rule3IdenticalStdinUrnsAreStillTwoMainInputs {
    NSString *err = [self refusedArgs:CSCapWithArgs(CSTextCap, @[
        CSStdinArg(CSMediaString, @"input", @"media:enc=utf-8"),
        CSStdinArg(CSMediaInteger, @"other", @"media:enc=utf-8"),
    ])];
    XCTAssertTrue([err containsString:@"RULE3"], @"%@", err);
    // One is the main input; a cap of one is fine.
    [self assertArgsPass:CSCapWithArgs(CSTextCap, @[CSStdinArg(CSMediaString, @"input", @"media:enc=utf-8")])];
}

// TEST12705: RULE15 - the stdin argument's URN is the cap's `in=`, as a tagged
// URN: the same tags in another order pass, another type does not.
- (void)test12705_rule15TheStdinArgumentIsTheCapsInput {
    CSCap *(^capOf)(NSString *) = ^CSCap *(NSString *stdinUrn) {
        return CSCapWithArgs(@"cap:in=\"media:document;ext=pdf\";test;out=\"media:record\"",
                             @[CSStdinArg(@"media:enc=utf-8;file-path", @"document", stdinUrn)]);
    };
    [self assertArgsPass:capOf(@"media:document;ext=pdf")];
    [self assertArgsPass:capOf(@"media:ext=pdf;document")];  // tag order is not identity
    NSString *err = [self refusedArgs:capOf(@"media:document")];
    XCTAssertTrue([err containsString:@"RULE15"] && [err containsString:@"media:document;ext=pdf"], @"%@", err);
}

// TEST12706: RULE17 - every argument has a well-formed name, unique in its cap.
- (void)test12706_rule17ArgumentNames {
    // Two args, two names: fine. A name says nothing of the URN it labels.
    [self assertArgsPass:CSCapWithArgs(CSVoidCap, @[CSFlagArg(CSMediaString, @"window", @"--a"),
                                                    CSFlagArg(CSMediaInteger, @"benchmark", @"--b")])];
    NSString *err = [self refusedArgs:CSCapWithArgs(CSVoidCap, @[CSFlagArg(CSMediaString, @"", @"--a")])];
    XCTAssertTrue([err containsString:@"RULE17"] && [err containsString:@"has no name"], @"%@", err);
    for (NSString *bad in @[@"9lives", @"has space", @"dotted.name", @"a=b", @"true", @"false", @"null", @"-lead"]) {
        err = [self refusedArgs:CSCapWithArgs(CSVoidCap, @[CSFlagArg(CSMediaString, bad, @"--a")])];
        XCTAssertTrue([err containsString:@"RULE17"] && [err containsString:@"not a valid name"], @"%@: %@", bad, err);
        XCTAssertFalse(CSIsValidDefinitionName(bad), @"%@", bad);
    }
    for (NSString *good in @[@"x", @"_x", @"model-spec", @"top_k", @"A1"]) {
        [self assertArgsPass:CSCapWithArgs(CSVoidCap, @[CSFlagArg(CSMediaString, good, @"--a")])];
        XCTAssertTrue(CSIsValidDefinitionName(good), @"%@", good);
    }
    err = [self refusedArgs:CSCapWithArgs(CSVoidCap, @[CSFlagArg(CSMediaString, @"same", @"--a"),
                                                       CSFlagArg(CSMediaInteger, @"same", @"--b")])];
    XCTAssertTrue([err containsString:@"RULE17"] && [err containsString:@"share the name 'same'"], @"%@", err);
    XCTAssertTrue([err containsString:CSMediaString] && [err containsString:CSMediaInteger], @"both args are named by URN: %@", err);
}

// TEST12707: RULE18 - an argument says what it accepts in one place; and what
// it accepts is not what it is delivered under.
- (void)test12707_rule18AcceptsAndTheTwoUrnsOfAnArgument {
    NSString *series = @"media:fmt=json;list;record;time-series";
    NSString *own = @"media:benchmark;fmt=json;list;record;time-series";
    CSCapArg *declared = CSFlagArg(own, @"benchmark", @"--benchmark");
    CSCapArg *benchmark = [declared argAccepting:series];
    // It accepts a plain series, and is delivered under its own URN: two args
    // accepting one type stay distinct on the wire.
    XCTAssertEqualObjects([benchmark acceptedUrn], series, @"what it accepts");
    XCTAssertEqualObjects([benchmark streamUrn], own, @"what it is delivered under");
    XCTAssertNil(declared.accepts, @"the arg it was made from is not changed");
    XCTAssertEqualObjects(benchmark.name, @"benchmark", @"and keeps its name");
    // It survives the dictionary round trip, and is not written when not declared.
    NSError *error = nil;
    CSCapArg *back = [CSCapArg argWithDictionary:[benchmark toDictionary] error:&error];
    XCTAssertEqualObjects(back.accepts, series, @"accepts round-trips: %@", error);
    XCTAssertNil([declared toDictionary][@"accepts"], @"accepts is written only when declared");
    XCTAssertEqualObjects([benchmark toDictionary][@"name"], @"benchmark", @"the name is written");

    // The main input accepts, and is delivered under, its stdin URN.
    CSCapArg *main = CSStdinArg(@"media:enc=utf-8;file-path", @"path", series);
    XCTAssertEqualObjects([main acceptedUrn], series, @"the main input accepts its stdin URN");
    XCTAssertEqualObjects([main streamUrn], series, @"and is delivered under it");
    // What it is piped is what it accepts, whatever else it says (and saying
    // both is refused, below).
    XCTAssertEqualObjects([[main argAccepting:@"media:other"] acceptedUrn], series, @"a stdin source is what the arg accepts");

    // An arg with neither accepts its own URN.
    CSCapArg *plain = CSFlagArg(CSMediaInteger, @"window", @"--window");
    XCTAssertEqualObjects([plain acceptedUrn], CSMediaInteger);
    XCTAssertEqualObjects([plain streamUrn], CSMediaInteger);

    NSString *urn = [NSString stringWithFormat:@"cap:in=\"%@\";compare;out=\"media:record\"", series];
    [self assertArgsPass:CSCapWithArgs(urn, @[main, benchmark])];

    // `accepts` beside a stdin source says it twice.
    NSString *err = [self refusedArgs:CSCapWithArgs(urn, @[[main argAccepting:series]])];
    XCTAssertTrue([err containsString:@"RULE18"] && [err containsString:@"media:enc=utf-8;file-path"], @"%@", err);
}

// TEST12708: RULE19, RULE20 - outputs have well-formed, distinct names and
// distinct media URNs, compared as URNs.
- (void)test12708_rule19Rule20OutputNamesAndIdentities {
    NSString *fitUrn = @"media:fmt=json;record;regression";
    NSString *residuals = @"media:fmt=json;list;record;residual";
    CSCapOutput *fit = CSOutput(fitUrn, @"fit");
    [self assertOutputsPass:CSCapWithOutputs(fitUrn, @[fit, CSOutput(residuals, @"residuals")])];

    NSString *err = [self refusedOutputs:CSCapWithOutputs(fitUrn, @[fit, CSOutput(residuals, @"")])];
    XCTAssertTrue([err containsString:@"RULE19"] && [err containsString:@"has no name"], @"%@", err);
    err = [self refusedOutputs:CSCapWithOutputs(fitUrn, @[fit, CSOutput(residuals, @"null")])];
    XCTAssertTrue([err containsString:@"RULE19"] && [err containsString:@"not a valid name"], @"%@", err);
    err = [self refusedOutputs:CSCapWithOutputs(fitUrn, @[fit, CSOutput(residuals, @"fit")])];
    XCTAssertTrue([err containsString:@"RULE19"] && [err containsString:@"share the name 'fit'"], @"%@", err);
    // The same URN with its tags in another order is the same output.
    err = [self refusedOutputs:CSCapWithOutputs(fitUrn, @[fit, CSOutput(@"media:regression;record;fmt=json", @"again")])];
    XCTAssertTrue([err containsString:@"RULE20"], @"%@", err);
    err = [self refusedOutputs:CSCapWithOutputs(fitUrn, @[fit, CSOutput(@"not a urn", @"broken")])];
    XCTAssertTrue([err containsString:@"RULE20"] && [err containsString:@"not a media URN"], @"%@", err);
}

// TEST12709: RULE21 - exactly one output is the main one, the cap's `out=`; a
// cap whose `out=` is void declares none.
- (void)test12709_rule21ExactlyOneMainOutput {
    NSString *fitUrn = @"media:fmt=json;record;regression";
    NSString *err = [self refusedOutputs:CSCapWithOutputs(fitUrn, @[CSOutput(@"media:fmt=json;list;record;residual", @"residuals")])];
    XCTAssertTrue([err containsString:@"RULE21"] && [err containsString:@"0 outputs"], @"%@", err);
    XCTAssertTrue([[self refusedOutputs:CSCapWithOutputs(fitUrn, @[])] containsString:@"RULE21"], @"no output at all");

    CSCap *one = CSCapWithOutputs(fitUrn, @[CSOutput(@"media:regression;fmt=json;record", @"fit")]);
    [self assertOutputsPass:one];  // the main output is found by URN equivalence
    XCTAssertEqualObjects([one mainOutput].name, @"fit", @"the main output");
    XCTAssertEqualObjects([one outputNamed:@"fit"], [one mainOutput], @"and it is the one of that name");
    XCTAssertNil([one outputNamed:@"other"], @"no output of another name");
    XCTAssertNil([one outputByUrn:@"not a urn"], @"what is no URN identifies no output");
    // The main output is the one `out=` names, wherever it is declared.
    CSCap *second = CSCapWithOutputs(fitUrn, @[CSOutput(@"media:fmt=json;list;record;residual", @"residuals"), CSOutput(fitUrn, @"fit")]);
    [self assertOutputsPass:second];
    XCTAssertEqualObjects([second mainOutput].name, @"fit", @"the main output is found by its URN, not its place");

    CSCap *empty = CSCapWithOutputs(@"media:void", @[]);
    [self assertOutputsPass:empty];
    XCTAssertNil([empty mainOutput], @"a void cap has no main output");
    err = [self refusedOutputs:CSCapWithOutputs(@"media:void", @[CSOutput(@"media:enc=utf-8", @"text")])];
    XCTAssertTrue([err containsString:@"RULE21"] && [err containsString:@"media:void"], @"%@", err);
}

// TEST12710: RULE22 - only a non-main output of a cap that takes an input may
// carry that input's type.
- (void)test12710_rule22WhatAnOutputCarries {
    NSString *kept = @"media:enc=utf-8;kept";
    CSCapOutput *dropped = [[CSOutput(@"media:enc=utf-8;dropped", @"no") outputAsOptional:YES] outputCarryingInput];
    XCTAssertEqualObjects(dropped.carries, CSOutputCarriesInput, @"it carries the input");
    XCTAssertTrue(dropped.optional, @"and stays optional");
    // In the other order too: each keeps what the other declared.
    CSCapOutput *reversed = [[CSOutput(@"media:enc=utf-8;dropped", @"no") outputCarryingInput] outputAsOptional:YES];
    XCTAssertEqualObjects(reversed.carries, CSOutputCarriesInput);
    XCTAssertTrue(reversed.optional);
    [self assertOutputsPass:CSCapWithOutputs(kept, @[[CSOutput(kept, @"yes") outputAsOptional:YES], dropped])];
    // What an output carries and whether it is optional are part of its dictionary.
    NSDictionary *written = [dropped toDictionary];
    XCTAssertEqualObjects(written[@"carries"], @"input", @"carries is written");
    XCTAssertEqualObjects(written[@"optional"], @YES, @"optional is written");
    XCTAssertEqualObjects([CSOutput(kept, @"yes") toDictionary][@"optional"], @NO, @"optional is written when false too");
    XCTAssertNil([CSOutput(kept, @"yes") toDictionary][@"carries"], @"carries is written only when declared");
    NSError *error = nil;
    CSCapOutput *back = [CSCapOutput outputWithDictionary:written error:&error];
    XCTAssertEqualObjects(back.carries, @"input", @"carries round-trips: %@", error);
    XCTAssertTrue(back.optional, @"optional round-trips");
    error = nil;
    NSDictionary *carriesOutput = @{@"media_urn": kept, @"name": @"yes", @"output_description": @"", @"carries": @"output"};
    XCTAssertNil([CSCapOutput outputWithDictionary:carriesOutput error:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"carries"], @"an output carries its own type or the input: %@", error);

    NSString *err = [self refusedOutputs:CSCapWithOutputs(kept, @[[CSOutput(kept, @"yes") outputCarryingInput]])];
    XCTAssertTrue([err containsString:@"RULE22"] && [err containsString:@"main output"], @"%@", err);

    CSCap *source = [CSCap capWithUrn:[CSCapUrn fromString:@"cap:in=\"media:void\";now;out=\"media:enc=utf-8;stamp\"" error:nil]
                                title:@"Now" aliases:@[@"now"]];
    [source setOutputs:@[CSOutput(@"media:enc=utf-8;stamp", @"stamp"), [CSOutput(@"media:enc=utf-8;echo", @"echo") outputCarryingInput]]];
    err = [self refusedOutputs:source];
    XCTAssertTrue([err containsString:@"RULE22"] && [err containsString:@"takes none"], @"%@", err);
}

/// A cap that converts, complete with its output or without it.
- (CSCap *)convertCap:(BOOL)complete {
    CSCap *cap = [CSCap capWithUrn:[CSCapUrn fromString:@"cap:in=\"media:void\";convert;out=\"media:record;textable\"" error:nil]
                             title:@"Convert" aliases:@[@"convert"]];
    if (complete) [cap addOutput:CSOutput(@"media:record;textable", @"record")];
    return cap;
}

- (CSCapManifest *)manifestWithGroups:(NSArray<CSCapGroup *> *)groups {
    return [CSCapManifest manifestWithName:@"TestCartridge" version:@"1.0.0" channel:CSCartridgeChannelRelease
                               registryURL:nil description:@"Test" capGroups:groups];
}

// TEST12711: validate holds every definition in the manifest to the definition
// rules: a cap in any group that breaks one is refused, naming the cap and the
// rule. Identity alone being present is not enough.
- (void)test12711_validateRefusesAnInvalidDefinition {
    CSCapManifest *(^withCap)(CSCap *) = ^CSCapManifest *(CSCap *cap) {
        return [self manifestWithGroups:@[[[CSCapGroup alloc] initWithName:@"default" caps:@[[CSCap identityCap]] adapterUrns:@[]],
                                          [[CSCapGroup alloc] initWithName:@"second" caps:@[cap] adapterUrns:@[]]]];
    };
    NSError *error = nil;
    XCTAssertTrue([withCap([self convertCap:YES]) validate:&error], @"%@", error);

    // No output although `out=` is not void.
    error = nil;
    XCTAssertFalse([withCap([self convertCap:NO]) validate:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"RULE21"] && [error.localizedDescription containsString:@"convert"], @"%@", error);

    // Two arguments under one name.
    CSCap *twins = [self convertCap:YES];
    [twins addArg:CSFlagArg(@"media:enc=utf-8", @"same", @"--a")];
    [twins addArg:CSFlagArg(@"media:integer", @"same", @"--b")];
    error = nil;
    XCTAssertFalse([withCap(twins) validate:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"RULE17"], @"%@", error);

    // A manifest of valid definitions that lacks identity is refused too.
    error = nil;
    XCTAssertFalse([[self manifestWithGroups:@[[[CSCapGroup alloc] initWithName:@"default" caps:@[[self convertCap:YES]] adapterUrns:@[]]]] validate:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"CAP_IDENTITY"], @"%@", error);
}

// TEST12713: every definition this library builds in passes the rules it holds
// everyone else's definitions to.
- (void)test12713_builtInDefinitionsPassTheDefinitionRules {
    CSCap *identity = [CSCap identityCap];
    NSError *error = nil;
    XCTAssertTrue([CSCapValidator validateCapDefinition:identity error:&error], @"%@", error);
    // Identity's `out=` is not void, so it declares its one output.
    XCTAssertEqualObjects([identity mainOutput].name, @"output", @"identity declares its output");
    XCTAssertEqualObjects([identity argNamed:@"input"].name, @"input", @"and its input");
    XCTAssertNil([identity argNamed:@"output"], @"an output is no argument");
    XCTAssertEqualObjects(identity.aliases, @[@"identity"], @"under the alias every implementation gives it");
    XCTAssertTrue([identity.capUrn isEquivalent:[CSCapUrn fromString:CSCapIdentity error:nil]], @"it is the identity cap");
    // A manifest without identity is given this one.
    CSCapManifest *bare = [self manifestWithGroups:@[[[CSCapGroup alloc] initWithName:@"default" caps:@[[self convertCap:YES]] adapterUrns:@[]]]];
    error = nil;
    XCTAssertTrue([[bare ensureIdentity] validate:&error], @"%@", error);
}

// TEST12717: a manifest read from another program's bytes is parsed and held
// to the definition rules in one step, and the two refusals are told apart:
// bytes that are no manifest, and a manifest with a definition that breaks a
// rule.
- (void)test12717_anAdvertisedManifestIsParsedAndChecked {
    NSData *(^bytesOf)(CSCap *) = ^NSData *(CSCap *cap) {
        CSCapManifest *manifest = [self manifestWithGroups:@[[[CSCapGroup alloc] initWithName:@"default" caps:@[[CSCap identityCap], cap] adapterUrns:@[]]]];
        return [NSJSONSerialization dataWithJSONObject:[manifest toDictionary] options:0 error:nil];
    };
    NSError *error = nil;
    CSCapManifest *taken = [CSCapManifest manifestFromAdvertisedData:bytesOf([self convertCap:YES]) error:&error];
    XCTAssertNotNil(taken, @"%@", error);
    XCTAssertEqual([taken allCaps].count, 2, @"both caps are taken");
    XCTAssertEqualObjects([[taken allCaps][1] outputNamed:@"record"].mediaUrn, @"media:record;textable", @"the output is read as an output");

    error = nil;
    XCTAssertNil([CSCapManifest manifestFromAdvertisedData:bytesOf([self convertCap:NO]) error:&error]);
    XCTAssertEqualObjects(error.domain, CSManifestLoadErrorDomain);
    XCTAssertEqual(error.code, CSManifestLoadInvalidDefinition, @"it parsed: what it carries is invalid");
    XCTAssertTrue([error.localizedDescription containsString:@"invalid cap definition"] &&
                  [error.localizedDescription containsString:@"RULE21"] &&
                  [error.localizedDescription containsString:@"convert"], @"%@", error);

    for (NSString *notAManifest in @[@"{not json", @"[]", @"{\"name\":\"x\"}", @"null", @"7", @"\"manifest\""]) {
        error = nil;
        XCTAssertNil([CSCapManifest manifestFromAdvertisedData:[notAManifest dataUsingEncoding:NSUTF8StringEncoding] error:&error], @"%@", notAManifest);
        XCTAssertEqual(error.code, CSManifestLoadUnparseable, @"%@: bytes that are no manifest", notAManifest);
        XCTAssertTrue([error.localizedDescription containsString:@"not a manifest"], @"%@", error);
    }
    const unsigned char invalidUtf8[] = {0xff, 0xfe};
    error = nil;
    XCTAssertNil([CSCapManifest manifestFromAdvertisedData:[NSData dataWithBytes:invalidUtf8 length:2] error:&error]);
    XCTAssertEqual(error.code, CSManifestLoadUnparseable);
}

@end
