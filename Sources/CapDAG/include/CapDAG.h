//
//  CapDAG.h
//  Cap SDK - Core cap URN and definition system
//
//  This library provides the fundamental cap URN system used across
//  all MachineFabric cartridges and providers. It defines the formal structure for cap
//  identifiers with flat tag-based naming, wildcard support, and specificity comparison.
//
//  ## Cartridge Communication
//
//  The library also provides unified cartridge communication infrastructure:
//
//  - **Binary Packet Framing** (`CSPacket`): Length-prefixed binary packets for stdin/stdout
//  - **Message Envelope** (`CSMessage`): JSON message types for requests/responses
//

#import <Foundation/Foundation.h>

//! Project version number for CapDAG.
FOUNDATION_EXPORT double CapDAGVersionNumber;

//! Project version string for CapDAG.
FOUNDATION_EXPORT const unsigned char CapDAGVersionString[];

// Core cap URN system
#import "CSCapUrn.h"
#import "CSCap.h"
#import "CSMediaSpec.h"
#import "CSStandardCaps.h"
#import "CSStdinSource.h"
#import "CSResponseWrapper.h"
#import "CSCapManifest.h"
#import "CSCapMatcher.h"
#import "CSCapValidator.h"
#import "CSSchemaValidator.h"
#import "CSFabricRegistry.h"

// Cartridge communication infrastructure
#import "CSPacket.h"
#import "CSMessage.h"

// Planner module - execution planning and cardinality analysis
#import "CSCardinality.h"
#import "CSArgumentBinding.h"
#import "CSCollectionInput.h"
#import "CSPlan.h"
#import "CSPlanBuilder.h"
#import "CSExecutor.h"
#import "CSLiveCapFab.h"

// Progress mapping for DAG execution
#import "CSProgressMapper.h"

// InputResolver module - unified input resolution with media detection
#import "CSInputResolver.h"

