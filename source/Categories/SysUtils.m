/*
    SysUtils.m

    This file is in the public domain.
*/

#import <Cocoa/Cocoa.h>
#import <Foundation/NSCharacterSet.h>

#import "SystemIncludes.h"  // for UTF8STRING()
#import "SysUtils.h"

@implementation NSObject(SysUtils)

//  checkOtool:
// ----------------------------------------------------------------------------
- (BOOL) _checkOtool:(NSString*)otoolPath{
    
    NSLog (@"Checking otool at path:%@",otoolPath);
    if (!otoolPath) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:otoolPath]) return NO;
    
    NSTask* otoolTask = [[[NSTask alloc] init] autorelease];
    NSPipe* silence = [NSPipe pipe];
    
    [otoolTask setLaunchPath: otoolPath];
    [otoolTask setStandardInput: [NSPipe pipe]];
    [otoolTask setStandardOutput: silence];
    [otoolTask setStandardError: silence];
    [otoolTask launch];
    [otoolTask waitUntilExit];
    
    return ([otoolTask terminationStatus] == 1);

}
- (BOOL)checkOtool: (NSString*)filePath
{
    NSString * internalOtoolPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"otool" ofType:@""];
    
    if (!internalOtoolPath) {
        NSString * mypath = [[[NSProcessInfo processInfo] arguments] objectAtIndex:0];
        internalOtoolPath  = [[mypath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"otool"];
    }
    
    NSString * otoolDefaultPath = @"/usr/bin/otool";
    
    BOOL found = [self _checkOtool:internalOtoolPath];
    if (!found) found = [self _checkOtool:otoolDefaultPath];
    if (!found){
        NSString* otoolPath = [self _pathForTool: @"otool"];
        found = [self _checkOtool:otoolPath];

    }
    return found;
}

//  pathForTool:
// ----------------------------------------------------------------------------
- (NSString*) pathForTool: (NSString*)toolName{
    if ([toolName isEqualToString:@"otool"]){
        NSString * internalOtoolPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"otool" ofType:@""];
        if ([self _checkOtool:internalOtoolPath]){
            NSLog (@"otool found at %@",internalOtoolPath);
            return internalOtoolPath;
        }
        NSString * otoolDefaultPath = @"/usr/bin/otool";
        if ([self _checkOtool:otoolDefaultPath]){
            NSLog (@"otool found at %@",otoolDefaultPath);
            return otoolDefaultPath;
        }
        NSString * xcodePath =  [self _pathForTool: @"otool"];
       
        if ([self _checkOtool:xcodePath]){
            NSLog (@"otool found at %@",xcodePath);
            return xcodePath;
        }
    }
    return nil;
    
}
- (NSString*)_pathForTool: (NSString*)toolName
{
    NSString* relToolBase = [NSString pathWithComponents:
        [NSArray arrayWithObjects: @"/", @"usr", @"bin", nil]];
    NSString* relToolPath = [relToolBase stringByAppendingPathComponent: toolName];
    NSString* xcrunToolPath = [relToolBase stringByAppendingPathComponent: @"xcrun"];
    NSTask* xcrunTask = [[[NSTask alloc] init] autorelease];
    NSPipe* selectPipe = [NSPipe pipe];
    NSArray* args = [NSArray arrayWithObjects: @"--find", toolName, nil];

    [xcrunTask setLaunchPath: xcrunToolPath];
    [xcrunTask setArguments: args];
    [xcrunTask setStandardInput: [NSPipe pipe]];
    [xcrunTask setStandardOutput: selectPipe];
    [xcrunTask launch];
    [xcrunTask waitUntilExit];

    int xcrunStatus = [xcrunTask terminationStatus];

    if (xcrunStatus == -1)
        return relToolPath;

    NSData* xcrunData = [[selectPipe fileHandleForReading] availableData];
    NSString* absToolPath = [[[NSString alloc] initWithBytes: [xcrunData bytes]
                                                      length: [xcrunData length]
                                                    encoding: NSUTF8StringEncoding] autorelease];

    return [absToolPath stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
