#import <Foundation/Foundation.h>

NSData *CUPatchJSONData(NSData *data);
NSData *CUPatchConnectFrames(NSData *framePayload);
NSData *CUPatchSSELine(NSData *line);

@interface CUStreamPatcher : NSObject
- (instancetype)initWithMode:(NSInteger)mode;
- (NSData *)consume:(NSData *)chunk;
- (NSData *)flush;
@end
