#import "ProbeBridge.h"
#import <objc/message.h>

// 只绕过 SDK 可用性检查，不修改系统权限、守护进程或蓝牙配置。
static void StoreException(NSError **error, NSException *exception) {
    if (error) {
        *error = [NSError errorWithDomain:@"WatchBLEProbe.Runtime" code:1
                                userInfo:@{NSLocalizedDescriptionKey:
                                               [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @""]}];
    }
}

static id Allocate(NSString *name, SEL selector) {
    Class type = NSClassFromString(name);
    if (!type || ![type instancesRespondToSelector:selector]) {
        [NSException raise:@"ProbeSelectorUnavailable" format:@"%@ %@", name, NSStringFromSelector(selector)];
    }
    return [type alloc];
}

@implementation ProbeBridge
+ (CBPeripheralManager *)managerWithDelegate:(id<CBPeripheralManagerDelegate>)delegate
                         runtimeInitializer:(BOOL)runtimeInitializer
                                      error:(NSError **)error {
    @try {
        CBPeripheralManager *manager;
        if (runtimeInitializer) {
            SEL selector = NSSelectorFromString(@"initWithDelegate:queue:options:");
            id object = Allocate(@"CBPeripheralManager", selector);
            manager = ((id (*)(id, SEL, id, dispatch_queue_t, NSDictionary *))objc_msgSend)(
                object, selector, delegate, nil, nil);
        } else {
            manager = [[CBPeripheralManager alloc] init];
            manager.delegate = delegate;
        }
        return manager;
    } @catch (NSException *exception) {
        StoreException(error, exception);
        return nil;
    }
}

+ (CBMutableCharacteristic *)characteristicWithUUID:(CBUUID *)uuid
                                       properties:(CBCharacteristicProperties)properties
                                      permissions:(CBAttributePermissions)permissions
                                            error:(NSError **)error {
    @try {
        SEL selector = NSSelectorFromString(@"initWithType:properties:value:permissions:");
        id object = Allocate(@"CBMutableCharacteristic", selector);
        return ((id (*)(id, SEL, id, CBCharacteristicProperties, id, CBAttributePermissions))objc_msgSend)(
            object, selector, uuid, properties, nil, permissions);
    } @catch (NSException *exception) {
        StoreException(error, exception);
        return nil;
    }
}

+ (CBMutableService *)serviceWithUUID:(CBUUID *)uuid
                    characteristics:(NSArray<CBMutableCharacteristic *> *)characteristics
                              error:(NSError **)error {
    @try {
        SEL selector = NSSelectorFromString(@"initWithType:primary:");
        id object = Allocate(@"CBMutableService", selector);
        CBMutableService *service = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(object, selector, uuid, YES);
        service.characteristics = characteristics;
        return service;
    } @catch (NSException *exception) {
        StoreException(error, exception);
        return nil;
    }
}

+ (BOOL)addService:(CBMutableService *)service manager:(CBPeripheralManager *)manager error:(NSError **)error {
    @try {
        [manager addService:service];
        return YES;
    } @catch (NSException *exception) {
        StoreException(error, exception);
        return NO;
    }
}

+ (CBMutableDescriptor *)descriptorWithUUID:(CBUUID *)uuid value:(NSData *)value error:(NSError **)error {
    @try {
        SEL selector = NSSelectorFromString(@"initWithType:value:");
        id object = Allocate(@"CBMutableDescriptor", selector);
        return ((id (*)(id, SEL, id, id))objc_msgSend)(object, selector, uuid, value);
    } @catch (NSException *exception) {
        StoreException(error, exception);
        return nil;
    }
}

+ (BOOL)advertiseWithManager:(CBPeripheralManager *)manager data:(NSDictionary<NSString *, id> *)data error:(NSError **)error {
    @try {
        [manager startAdvertising:data];
        return YES;
    } @catch (NSException *exception) {
        StoreException(error, exception);
        return NO;
    }
}
@end
