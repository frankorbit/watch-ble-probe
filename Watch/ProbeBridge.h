#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ProbeBridge : NSObject
+ (nullable CBPeripheralManager *)managerWithDelegate:(id<CBPeripheralManagerDelegate>)delegate
                                  runtimeInitializer:(BOOL)runtimeInitializer
                                               error:(NSError **)error;
+ (nullable CBMutableCharacteristic *)characteristicWithUUID:(CBUUID *)uuid
                                                properties:(CBCharacteristicProperties)properties
                                               permissions:(CBAttributePermissions)permissions
                                                     error:(NSError **)error;
+ (nullable CBMutableService *)serviceWithUUID:(CBUUID *)uuid
                              characteristics:(NSArray<CBMutableCharacteristic *> *)characteristics
                                        error:(NSError **)error;
+ (nullable CBMutableDescriptor *)descriptorWithUUID:(CBUUID *)uuid value:(NSData *)value error:(NSError **)error;
+ (BOOL)addService:(CBMutableService *)service manager:(CBPeripheralManager *)manager error:(NSError **)error;
+ (BOOL)advertiseWithManager:(CBPeripheralManager *)manager data:(NSDictionary<NSString *, id> *)data error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
