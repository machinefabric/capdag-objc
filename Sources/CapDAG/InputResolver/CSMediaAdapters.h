//
//  CSMediaAdapters.h
//  CapDAG
//
//  This file previously contained forward declarations for all media adapter classes.
//  Media adapters have been moved to cartridges. The CSMediaAdapterRegistry now
//  tracks cartridge-provided adapters via cap group registration.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// All adapter classes have been removed. Content inspection is now
// performed by cartridges via the adapter-selection cap protocol.
// See CSMediaAdapterRegistry in CSInputResolver.h.

NS_ASSUME_NONNULL_END
