//
//  WBHookBlock.h
//  WBHookBlockDemo
//
//  Created by 蔡欣东 on 2018/10/8.
//  Copyright © 2018年 蔡欣东. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, WBHookBlockPosition) {
    WBHookBlockPositionBefore = 0,
    WBHookBlockPositionAfter,
    WBHookBlockPositionReplace,
};

@interface WBHookBlock : NSObject

+ (void)runBlock:(id)block;

+ (void)runBlock_Invocation:(id)block;

+ (void)easy_hookBlock:(id)originBlock alter:(id)alterBlock;

+ (void)hookBlock:(id)originBlock alter:(id)alterBlock position:(WBHookBlockPosition)position;


@end

NS_ASSUME_NONNULL_END
