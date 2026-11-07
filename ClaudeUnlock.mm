#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "CUURLProtocol.h"

#if CU_DEBUG
#define CU_LOG(fmt, ...) NSLog(@"[ClaudeUnlock] " fmt, ##__VA_ARGS__)
#else
#define CU_LOG(fmt, ...)
#endif

static BOOL CUYes(id self, SEL _cmd) { return YES; }

static BOOL CUHookableReturn(Method m) {
    const char *t = method_getTypeEncoding(m);
    return t && (t[0] == 'B' || t[0] == 'c');
}

static BOOL CUNameMatches(NSString *sel) {
    static NSRegularExpression *re; static dispatch_once_t o;
    dispatch_once(&o, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^(is|has|can|should|are)[A-Z]"
                                                       options:0 error:nil];
    });
    if (![re numberOfMatchesInString:sel options:0 range:NSMakeRange(0, sel.length)]) return NO;
    NSString *low = sel.lowercaseString;
    for (NSString *n in @[@"pro", @"max", @"premium", @"paid", @"subscri",
                          @"active", @"entitle", @"purchas", @"unlock", @"ultra"]) {
        if ([low containsString:n]) return YES;
    }
    return NO;
}

static BOOL CUClassInteresting(NSString *name) {
    for (NSString *n in @[@"Purchas", @"RevenueCat", @"CustomerInfo", @"Entitle",
                          @"Paywall", @"Billing", @"Subscription"]) {
        if ([name containsString:n]) return YES;
    }
    return NO;
}

static void CUHookClass(Class cls) {
    for (int meta = 0; meta < 2; meta++) {
        Class target = meta ? object_getClass(cls) : cls;
        unsigned count = 0;
        Method *methods = class_copyMethodList(target, &count);
        for (unsigned i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            if (!CUNameMatches(NSStringFromSelector(sel))) continue;
            if (!CUHookableReturn(methods[i])) continue;
            method_setImplementation(methods[i], (IMP)CUYes);
        }
        free(methods);
    }
}

static void CUInstallEntitlementHooks(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * count);
    if (!classes) return;
    count = objc_getClassList(classes, count);
    int hooked = 0;
    for (int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (!name) continue;
        if (!CUClassInteresting(@(name))) continue;
        CUHookClass(classes[i]);
        hooked++;
    }
    free(classes);
    CU_LOG("entitlement hooks applied to %d classes", hooked);
}

static IMP CUOrigBoolForKey;

static BOOL CUBoolForKey(id self, SEL _cmd, NSString *key) {
    typedef BOOL (*Fn)(id, SEL, NSString *);
    BOOL real = ((Fn)CUOrigBoolForKey)(self, _cmd, key);
    if (![key isKindOfClass:NSString.class]) return real;
    NSString *low = key.lowercaseString;
    for (NSString *n in @[@"pro", @"premium", @"max", @"subscri", @"paid", @"entitle"]) {
        if ([low containsString:n]) return YES;
    }
    return real;
}

__attribute__((constructor))
static void CUInit(void) {
    [NSURLProtocol registerClass:[CUURLProtocol class]];

    Method m = class_getInstanceMethod([NSUserDefaults class], @selector(boolForKey:));
    if (m) {
        CUOrigBoolForKey = method_getImplementation(m);
        method_setImplementation(m, (IMP)CUBoolForKey);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ CUInstallEntitlementHooks(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ CUInstallEntitlementHooks(); });

    CU_LOG("loaded");
}
