#import "RCTHealthKit+Characteristics.h"
#import "RCTHealthKit+Utils.h"
#import <React/RCTConvert.h>
#import "RCTHealthKitDataModels.h"

typedef void(^ResultsHandler)(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error);

@interface RCTHealthKit ()

- (NSDictionary*)convertHKSample:(HKSample*)sample unit:(HKUnit *)unit;
- (NSDictionary*)convertHKSource:(HKSource*)source;
- (void)findWorkoutByMetadata:(NSString *)key value:(NSString *)value resultsHandler:(ResultsHandler)handler;

@end

@implementation RCTHealthKit (Characteristics)

- (void)_getDateOfBirth:(RCTPromiseResolveBlock)resolve
              rejecter:(RCTPromiseRejectBlock)reject {
  NSError *error;
  NSDateComponents *dateOfBirthComponents = [self._healthStore dateOfBirthComponentsWithError:&error];

  if (error) {
    [self _rejectWithType:RCTHealthKitErrorTypePermisionDenied error:error rejecter:reject];
    return;
  }

  NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  NSDate *dateOfBirth = [calendar dateFromComponents:dateOfBirthComponents];
  resolve(@([dateOfBirth timeIntervalSince1970]));
}

- (void)_getDefaultSource:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
    HKSource *source = [HKSource defaultSource];
    resolve([self convertHKSource:source]);
}

#pragma mark - Workouts

- (void)_addWorkout:(NSString*)activityType
          startDate:(NSDate*)startDate
            endDate:(NSDate*)endDate
           calories:(float)calories
   distanceInMeters:(float)distance
           metadata:(NSDictionary*)metadata
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject{
    HKUnit *caloriesUnit = [HKUnit kilocalorieUnit];
    HKQuantity *caloriesQuantity = [HKQuantity quantityWithUnit:caloriesUnit doubleValue:calories];
    HKQuantity *distanceQuantity = distance != -1 ? [HKQuantity quantityWithUnit:HKUnit.meterUnit doubleValue:distance] : nil;
    HKWorkoutActivityType type = [RCTHealthKitDataModels.workoutsDict objectForKey:activityType] ? [RCTHealthKitDataModels.workoutsDict[activityType] intValue] : HKWorkoutActivityTypeOther;
    
    HKWorkout *workout = [HKWorkout workoutWithActivityType:type
                                                  startDate:startDate
                                                    endDate:endDate
                                                   duration:0
                                          totalEnergyBurned:caloriesQuantity
                                              totalDistance:distanceQuantity
                                                     device:nil
                                                   metadata:metadata];
    
    [self._healthStore saveObject:workout withCompletion:^(BOOL success, NSError * _Nullable error) {
        if(!success) {
            reject(@"RCTHealthKit_save_workout_fail", @"An error occurred while saving the workout", error);
            return;
        }
        resolve(nil);
    }];
}

- (void)_getWorkoutsWithStartDate:(NSDate*)startDate
              endDate:(NSDate*)endDate
              resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
    HKQuery *query = [HKQuery predicateForSamplesWithStartDate:startDate endDate:endDate options:HKQueryOptionNone];
    HKSampleType *sampleType = [HKSampleType workoutType];
    HKSampleQuery *sampleQuery = [[HKSampleQuery alloc] initWithSampleType:sampleType predicate:query limit:HKObjectQueryNoLimit sortDescriptors:nil resultsHandler:^(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error) {
        if(error) {
            reject(@"RCTHealthKit_read_workouts_fail", @"An error occured while reading workouts", error);
        } else {
            NSMutableArray *array = [[NSMutableArray alloc] init];
            for(id object in results) {
                [array addObject:[self convertHKSample:object unit:nil]];
            }
            resolve(array);
        }
    }];

    [[self _healthStore] executeQuery:sampleQuery];
}

- (void)_getWorkoutsByMetadata:(NSString*)key
                        value:(NSString*)value
                        resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject {
    [self findWorkoutByMetadata:key
                          value:value
                 resultsHandler:^(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error) {
                     if(error) {
                         reject(@"RCTHealthKit_read_workouts_fail", @"An error occured while reading workouts", error);
                     } else {
                         NSMutableArray *array = [[NSMutableArray alloc] init];
                         for(id object in results) {
                             [array addObject:[self convertHKSample:object unit:nil]];
                         }
                         resolve(array);
                     }
                 }];
}


- (void)_deleteWorkoutsByMetadata:(NSString*)key
                            value:(NSString*)value
                          resolve:(RCTPromiseResolveBlock)resolve
                           reject:(RCTPromiseRejectBlock)reject {
    __weak RCTHealthKit *weakSelf = self;
    [self findWorkoutByMetadata:key value:value resultsHandler:^(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error) {
        if (error) {
            reject(@"RCTHealthKit_delete_workouts_fail", @"An error occurred while searching workouts to delete", error);
            return;
        }

        [weakSelf._healthStore deleteObjects:results withCompletion:^(BOOL success, NSError * _Nullable error) {
            if (error) {
                reject(@"RCTHealthKit_delete_workouts_fail", @"An error occurred while delete workouts", error);
                return;
            }

            resolve(@(success));
        }];
    }];
}

#pragma mark - Weight

- (void)_getWeightsWithUnit:(HKUnit *)unit
                  startDate:(NSDate *)startDate
                    endDate:(NSDate *)endDate
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject {
    HKQuery *query = [HKQuery predicateForSamplesWithStartDate:startDate endDate:endDate options:HKQueryOptionNone];
    HKSampleType *sampleType = [HKSampleType quantityTypeForIdentifier:HKQuantityTypeIdentifierBodyMass];
    HKSampleQuery *sampleQuery = [[HKSampleQuery alloc]
        initWithSampleType:sampleType
        predicate:query
        limit:HKObjectQueryNoLimit
        sortDescriptors:nil
        resultsHandler:^(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(error) {
                    reject(@"RCTHealthKit_read_weight_fail", @"An error occured while reading weight", error);
                } else {
                    NSMutableArray *array = [[NSMutableArray alloc] init];
                    for(id object in results) {
                        [array addObject:[self convertHKSample:object unit:unit]];
                    }
                    resolve(array);
                }
            });
        }
    ];
    [[self _healthStore] executeQuery:sampleQuery];
}

- (void)_addWeight:(float)weight
              unit:(HKUnit *)unit
              date:(NSDate *)date
              resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
    HKQuantity *weightQuantity = [HKQuantity quantityWithUnit:unit doubleValue:weight];

    HKQuantitySample *weightSample = [HKQuantitySample
                                      quantitySampleWithType:[HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierBodyMass]
                                      quantity:weightQuantity
                                      startDate:(date ?: [NSDate date])
                                      endDate:(date ?: [NSDate date])
                                      ];

    [self._healthStore saveObject:weightSample withCompletion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(!success) {
                reject(@"RCTHealthKit_add_weight_fail", @"An error occurred while saving the weight", error);
                return;
            }
            resolve(nil);
        });
    }];
};

#pragma mark - Generic Quantity

- (void)_getQuantity:(NSString *)quantityIdentifier
                unit:(NSString *)unit
           startDate:(NSDate *)startDate
             endDate:(NSDate *)endDate
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
    HKQuery *query = [HKQuery predicateForSamplesWithStartDate:startDate endDate:endDate options:HKQueryOptionNone];
    HKSampleType *sampleType = [HKSampleType quantityTypeForIdentifier:quantityIdentifier];
    HKSampleQuery *sampleQuery = [[HKSampleQuery alloc]
                                  initWithSampleType:sampleType
                                  predicate:query
                                  limit:HKObjectQueryNoLimit
                                  sortDescriptors:nil
                                  resultsHandler:^(
                                                   HKSampleQuery * _Nonnull query,
                                                   NSArray<__kindof HKSample *> * _Nullable results,
                                                   NSError * _Nullable error
                                                   ) {
                                      dispatch_async(dispatch_get_main_queue(), ^{
                                          if(error) {
                                              reject(@"RCTHealthKit_read_quantity_fail", @"An error occured while reading quantity", error);
                                          } else {
                                              NSMutableArray *array = [[NSMutableArray alloc] init];
                                              for(id object in results) {
                                                  [array addObject:[self convertHKSample:object unit:unit]];
                                              }
                                              resolve(array);
                                          }
                                      });
                                  }
                                  ];

    [self._healthStore executeQuery:sampleQuery];
}

#pragma mark - Private Methods

- (NSDictionary*)convertHKSample:(HKSample*)sample unit:(HKUnit *)unit {
    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    dateFormatter.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSS'Z'";
    if([sample startDate]){
        dictionary[@"startDate"] = [dateFormatter stringFromDate:[sample startDate]];
    }
    if([sample endDate]) {
        dictionary[@"endDate"] = [dateFormatter stringFromDate:[sample endDate]];
    }
    if([sample isKindOfClass:[HKWorkout class]]) {
        if ([((HKWorkout *)sample) totalEnergyBurned]) {
            double calories = [[((HKWorkout *)sample) totalEnergyBurned] doubleValueForUnit:[HKUnit kilocalorieUnit]];
            dictionary[@"calories"] = [NSNumber numberWithFloat:calories];
        }
        if ([((HKWorkout *)sample) totalDistance]) {
            double distance = [[((HKWorkout *)sample) totalDistance] doubleValueForUnit:[HKUnit meterUnitWithMetricPrefix:HKMetricPrefixKilo]];
            dictionary[@"distance"] = [NSNumber numberWithFloat:distance];
        }
        dictionary[@"activityType"] = [[NSNumber alloc] initWithInt:[((HKWorkout *)sample) workoutActivityType]];
    }
    if([sample isKindOfClass:[HKQuantitySample class]]) {
        HKQuantitySample *quantity = (HKQuantitySample *)sample;
        dictionary[@"count"] = @([quantity.quantity doubleValueForUnit:unit]);
    }
    if([sample metadata]) {
        dictionary[@"metadata"] = [sample metadata];
    }
    dictionary[@"id"] = [[sample UUID] UUIDString];
    dictionary[@"source"] = [self convertHKSource:[[sample sourceRevision] source]];
    return dictionary;
}

- (NSDictionary*)convertHKSource:(HKSource*)source {
    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
    dictionary[@"name"] = [source name];
    dictionary[@"bundleIdentifier"] = [source bundleIdentifier];
    return dictionary;
}

- (void)findWorkoutByMetadata:(NSString *)key value:(NSString *)value resultsHandler:(ResultsHandler)handler {
    HKQuery *sourceQuery = [HKQuery predicateForObjectsFromSource:[HKSource defaultSource]];
    HKQuery *metadataQuery = [HKQuery predicateForObjectsWithMetadataKey:key operatorType:NSEqualToPredicateOperatorType value:value];
    HKQuery *query = [NSCompoundPredicate andPredicateWithSubpredicates:@[sourceQuery, metadataQuery]];
    HKSampleType *sampleType = [HKSampleType workoutType];
    HKSampleQuery *sampleQuery = [[HKSampleQuery alloc] initWithSampleType:sampleType
                                                                 predicate:query
                                                                     limit:0
                                                           sortDescriptors:nil
                                                            resultsHandler:handler];

    [[self _healthStore] executeQuery:sampleQuery];
}

@end
