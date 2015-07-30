//
//  NSDictionary+Blocks.h
//  UsefulBits
//
//  Created by Kevin O'Neill on 25/11/11.
//

#import <Foundation/Foundation.h>

@interface NSDictionary (Blocks)

- (void)each:(void (^) (id key, id value))action;
- (NSArray *)map:(id (^) (id key, id value))action;
- (id)reduce:(id (^)(id current, id key, id value))block initial:(id)initial;
              
- (void)withValueForKey:(id)key meetingCondition:(BOOL (^) (id value))condition do:(void (^) (id value))action;

- (void)withValueForKey:(id)key meetingCondition:(BOOL (^) (id value))condition do:(void (^) (id value))action default:(void (^) (void))default_action;

- (void)withValueForKey:(id)key ofClass:(Class)class do:(void (^) (id value))action;
- (void)withValueForKey:(id)key ofClass:(Class)class do:(void (^) (id value))action default:(void (^) (void))default_action;

- (void)withValueForKey:(id)key do:(void (^) (id value))action;
- (void)withValueForKey:(id)key do:(void (^) (id value))action default:(void (^) (void))default_action;

@end
