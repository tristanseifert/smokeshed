//
//  Logging.h
//  Smokeshed
//
//  Created by Tristan Seifert on 20200617.
//

#ifndef Logging_h
#define Logging_h

// Logging
#import <CocoaLumberjack/CocoaLumberjack.h>

#if DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif

#endif /* Logging_h */
