#import "CUPatch.h"

#define CU_MODEL_ID      @"claude-opus-5-5"
#define CU_MODEL_LABEL   @"Claude Opus 5.5"
#define CU_BIG_COUNT     @999999
#define CU_RESET_DAYS    30

static NSArray<NSString *> *CUProCaps(void) {
    return @[@"chat", @"claude_pro", @"claude_max", @"raven", @"api",
             @"create_api_keys", @"attachments", @"files", @"vision",
             @"artifacts", @"extended_thinking", @"opus"];
}

static NSSet<NSString *> *CUTrueKeys(void) {
    static NSSet *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        s = [NSSet setWithArray:@[
            @"is_pro", @"is_max", @"is_paid", @"is_paid_user", @"is_subscriber",
            @"is_subscribed", @"is_premium", @"is_entitled", @"has_subscription",
            @"has_active_subscription", @"has_pro", @"has_max", @"premium", @"pro",
            @"paid", @"subscribed", @"has_access", @"is_unlimited", @"unlimited",
            @"can_use_opus", @"can_use_models", @"opus_enabled", @"is_power_user",
            @"has_paid_plan", @"is_plus"]];
    });
    return s;
}

static NSSet<NSString *> *CUFalseKeys(void) {
    static NSSet *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        s = [NSSet setWithArray:@[
            @"requires_upgrade", @"needs_upgrade", @"show_upgrade", @"is_locked",
            @"locked", @"is_gated", @"exceeded_limit", @"is_exceeded", @"exceeded",
            @"is_at_limit", @"has_hit_limit", @"limit_reached", @"quota_exceeded",
            @"out_of_credits", @"is_trial_expired"]];
    });
    return s;
}

static NSSet<NSString *> *CUPlanKeys(void) {
    static NSSet *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        s = [NSSet setWithArray:@[
            @"plan", @"plan_type", @"tier", @"subscription_tier", @"rate_limit_tier",
            @"billing_type", @"subscription_type", @"product_id", @"sku",
            @"entitlement", @"entitlement_id", @"subscription_status", @"state"]];
    });
    return s;
}

static NSSet<NSString *> *CUCountKeys(void) {
    static NSSet *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        s = [NSSet setWithArray:@[
            @"remaining", @"messages_remaining", @"limit", @"message_limit",
            @"messages_limit", @"quota", @"tokens_remaining", @"max_tokens",
            @"available_tokens", @"remaining_messages", @"messages_left",
            @"limit_value", @"credits", @"monthly_limit", @"max_messages"]];
    });
    return s;
}

static NSString *CUResetString(void) {
    NSDate *d = [NSDate dateWithTimeIntervalSinceNow:86400.0 * CU_RESET_DAYS];
    NSISO8601DateFormatter *f = [[NSISO8601DateFormatter alloc] init];
    return [f stringFromDate:d];
}

static BOOL CUIsBoolNumber(NSNumber *n) {
    const char *t = n.objCType;
    return t && (t[0] == 'c' || t[0] == 'B');
}

static void CUWalk(id obj);

static void CUAugmentModelArray(NSMutableArray *arr) {
    if (arr.count == 0) return;

    for (id o in arr) {
        if (![o isKindOfClass:NSMutableDictionary.class]) return;
        id m = ((NSDictionary *)o)[@"model"];
        if (![m isKindOfClass:NSString.class] || ![m hasPrefix:@"claude-"]) return;
    }

    for (id o in arr) {
        id m = ((NSDictionary *)o)[@"model"];
        if ([m rangeOfString:@"opus"].location != NSNotFound) {
            NSMutableDictionary *d = o;
            d[@"available"] = @YES;
            d[@"is_available"] = @YES;
            [d removeObjectForKey:@"unavailable_reason"];
            [d removeObjectForKey:@"upgrade_required"];
            return;
        }
    }

    NSMutableDictionary *tpl = [(NSMutableDictionary *)arr.firstObject mutableCopy];
    tpl[@"model"] = CU_MODEL_ID;
    if ([tpl[@"display_name"] isKindOfClass:NSString.class]) tpl[@"display_name"] = CU_MODEL_LABEL;
    if ([tpl[@"name"] isKindOfClass:NSString.class])         tpl[@"name"] = CU_MODEL_LABEL;
    if ([tpl[@"id"] isKindOfClass:NSString.class])           tpl[@"id"] = CU_MODEL_ID;
    tpl[@"available"] = @YES;
    tpl[@"is_available"] = @YES;
    [tpl removeObjectForKey:@"unavailable_reason"];
    [tpl removeObjectForKey:@"upgrade_required"];
    [arr insertObject:tpl atIndex:0];
}

static void CUWalkArray(NSMutableArray *arr) {
    CUAugmentModelArray(arr);
    for (id o in arr) CUWalk(o);
}

static void CUWalkDict(NSMutableDictionary *d) {
    for (NSString *k in [d allKeys]) {
        id v = d[k];
        if ([v isKindOfClass:NSMutableDictionary.class] ||
            [v isKindOfClass:NSMutableArray.class]) {
            CUWalk(v);
            v = d[k];
        }
        NSString *lk = k.lowercaseString;

        if ([v isKindOfClass:NSNumber.class] && CUIsBoolNumber(v)) {
            if ([CUTrueKeys() containsObject:lk])  { d[k] = @YES; continue; }
            if ([CUFalseKeys() containsObject:lk]) { d[k] = @NO;  continue; }
        }
        if ([v isKindOfClass:NSNumber.class] && !CUIsBoolNumber(v)) {
            if ([lk isEqualToString:@"utilization"]) { d[k] = @0; continue; }
            if ([CUCountKeys() containsObject:lk])   { d[k] = CU_BIG_COUNT; continue; }
            if ([lk isEqualToString:@"resets_at"]) {
                d[k] = @([[NSDate date] timeIntervalSince1970] + 86400.0 * CU_RESET_DAYS);
                continue;
            }
        }
        if ([v isKindOfClass:NSString.class]) {
            if ([lk isEqualToString:@"status"] &&
                ([v isEqualToString:@"exceeded_limit"] || [v isEqualToString:@"exceeded"] ||
                 [v isEqualToString:@"at_limit"])) {
                d[k] = @"within_limit"; continue;
            }
            if ([lk isEqualToString:@"resets_at"]) { d[k] = CUResetString(); continue; }
            if ([CUPlanKeys() containsObject:lk]) {
                NSString *low = [v lowercaseString];
                if ([low containsString:@"free"] || [low containsString:@"basic"] ||
                    [low containsString:@"none"] || [low containsString:@"trial"] ||
                    [low containsString:@"starter"] || low.length == 0) {
                    d[k] = ([lk containsString:@"product"] || [lk isEqualToString:@"sku"])
                             ? @"claude_max_monthly_ios" : @"max";
                }
                continue;
            }
        }
        if ([v isKindOfClass:NSMutableArray.class] && [lk isEqualToString:@"capabilities"]) {
            NSMutableArray *caps = v;
            for (NSString *c in CUProCaps())
                if (![caps containsObject:c]) [caps addObject:c];
            continue;
        }
    }
}

static void CUWalk(id obj) {
    if ([obj isKindOfClass:NSMutableDictionary.class]) CUWalkDict(obj);
    else if ([obj isKindOfClass:NSMutableArray.class]) CUWalkArray(obj);
}

NSData *CUPatchJSONData(NSData *data) {
    if (data.length == 0) return data;
    @try {
        id root = [NSJSONSerialization JSONObjectWithData:data
                                                  options:NSJSONReadingMutableContainers
                                                    error:NULL];
        if (!root) return data;
        CUWalk(root);
        NSData *out = [NSJSONSerialization dataWithJSONObject:root options:0 error:NULL];
        return out.length ? out : data;
    } @catch (NSException *e) {
        return data;
    }
}

static BOOL CURdVarint(const uint8_t *p, size_t n, size_t *off, uint64_t *out) {
    uint64_t v = 0; int shift = 0; size_t i = *off;
    while (i < n && shift < 64) {
        uint8_t b = p[i++];
        v |= ((uint64_t)(b & 0x7F)) << shift;
        if (!(b & 0x80)) { *off = i; *out = v; return YES; }
        shift += 7;
    }
    return NO;
}

static void CUPatchWindowInner(uint8_t *p, size_t n) {
    size_t off = 0;
    while (off < n) {
        uint64_t tag;
        if (!CURdVarint(p, n, &off, &tag)) return;
        uint32_t field = (uint32_t)(tag >> 3), wire = (uint32_t)(tag & 7);
        if (wire == 0) {
            size_t start = off; uint64_t v;
            if (!CURdVarint(p, n, &off, &v)) return;
            if (field == 1 && (off - start) == 1) p[start] = 1;
        } else if (wire == 1) {
            if (off + 8 > n) return;
            if (field == 3) { double z = 0.0; memcpy(p + off, &z, 8); }
            off += 8;
        } else if (wire == 2) {
            uint64_t len;
            if (!CURdVarint(p, n, &off, &len)) return;
            if (off + len > n) return;
            off += len;
        } else if (wire == 5) {
            if (off + 4 > n) return;
            off += 4;
        } else return;
    }
}

NSData *CUPatchConnectFrames(NSData *payload) {
    NSMutableData *d = [payload mutableCopy];
    uint8_t *p = d.mutableBytes;
    size_t n = d.length;
    for (size_t i = 0; i + 4 <= n; i++) {
        if (p[i] != 0x0A || p[i + 1] != 0x02) continue;
        if (!((p[i + 2] == '5' && p[i + 3] == 'h') ||
              (p[i + 2] == '7' && p[i + 3] == 'd'))) continue;
        CUPatchWindowInner(p + i + 4, n - (i + 4));
    }
    return d;
}

NSData *CUPatchSSELine(NSData *line) {
    NSString *s = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
    if (!s || [s rangeOfString:@"message_limit"].location == NSNotFound) return line;

    NSRange r = [s rangeOfString:@"{"];
    if (r.location == NSNotFound) return line;

    NSString *head = [s substringToIndex:r.location];
    NSString *body = [s substringFromIndex:r.location];
    NSString *trailer = @"";
    while (body.length && ([body hasSuffix:@"\n"] || [body hasSuffix:@"\r"])) {
        NSString *last = [body substringFromIndex:body.length - 1];
        trailer = [last stringByAppendingString:trailer];
        body = [body substringToIndex:body.length - 1];
    }
    if (body.length == 0) return line;

    NSData *jsonPart = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSData *patched = CUPatchJSONData(jsonPart);
    NSString *tail = [[NSString alloc] initWithData:patched encoding:NSUTF8StringEncoding];
    if (!tail) return line;

    NSString *merged = [NSString stringWithFormat:@"%@%@%@", head, tail, trailer];
    return [merged dataUsingEncoding:NSUTF8StringEncoding];
}

@implementation CUStreamPatcher {
    NSInteger _mode;
    NSMutableData *_buf;
}

- (instancetype)initWithMode:(NSInteger)mode {
    if ((self = [super init])) { _mode = mode; _buf = [NSMutableData data]; }
    return self;
}

- (NSData *)consume:(NSData *)chunk {
    if (chunk.length) [_buf appendData:chunk];
    NSMutableData *out = [NSMutableData data];
    NSData *nlData = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];

    if (_mode == 0) {
        NSRange nl;
        while ((nl = [_buf rangeOfData:nlData options:0
                                 range:NSMakeRange(0, _buf.length)]).location != NSNotFound) {
            NSUInteger end = nl.location + nl.length;
            [out appendData:CUPatchSSELine([_buf subdataWithRange:NSMakeRange(0, end)])];
            [_buf replaceBytesInRange:NSMakeRange(0, end) withBytes:NULL length:0];
        }
        if (_buf.length > (1 << 20)) { [out appendData:_buf]; [_buf setLength:0]; }
    } else {
        while (_buf.length >= 5) {
            const uint8_t *p = _buf.bytes;
            uint32_t len = ((uint32_t)p[1] << 24) | ((uint32_t)p[2] << 16) |
                           ((uint32_t)p[3] << 8) | (uint32_t)p[4];
            if (len > (4 << 20)) { [out appendData:_buf]; [_buf setLength:0]; break; }
            if (_buf.length < 5 + len) break;
            NSData *frame = [_buf subdataWithRange:NSMakeRange(5, len)];
            NSData *payload = (p[0] == 0x00) ? CUPatchConnectFrames(frame) : frame;
            [out appendBytes:p length:5];
            [out appendData:payload];
            [_buf replaceBytesInRange:NSMakeRange(0, 5 + len) withBytes:NULL length:0];
        }
    }
    return out;
}

- (NSData *)flush {
    NSData *d = [_buf copy];
    [_buf setLength:0];
    return d;
}
@end
