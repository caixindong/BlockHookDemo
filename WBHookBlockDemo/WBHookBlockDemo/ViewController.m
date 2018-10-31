//
//  ViewController.m
//  WBHookBlockDemo
//
//  Created by 蔡欣东 on 2018/10/8.
//  Copyright © 2018年 蔡欣东. All rights reserved.
//

#import "ViewController.h"
#import "WBHookBlock.h"

typedef void(^testBlock_04)(void);

typedef void(^testBlock)(int a);

typedef void(^testBlock_02)(int b);

typedef void(^testBlock_03)(int b);

@interface testObj : NSObject

- (void(^)(int a))somefuncBlock:(void(^)(int a)) block;

+ (void (^)(int))c_somefuncBlock:(void (^)(int))block;

- (void)testID:(id)block;

+ (void)testID:(id)block;


@end

@implementation testObj

- (void (^)(int))somefuncBlock:(void (^)(int))block {
    NSLog(@"obj test block is %@",block);
    return block;
}

+ (void (^)(int))c_somefuncBlock:(void (^)(int))block {
    NSLog(@"class obj test block is %@",block);
    return block;
}

- (void)testID:(id)block {
    NSLog(@"testID %@",block);
}

+ (void)testID:(id)block {
    NSLog(@"testID %@",block);
}

@end

@interface ViewController ()

@property (nonatomic, copy)testBlock testBlock;

@property (nonatomic, assign) int c;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self runBlock];
    
    [self run_block_02];
    
    [self testEasyHook];
    
    [self testHook];
}

- (void)runBlock {
    testBlock_04 block4 = ^(){
        NSLog(@"hello block4");
    };
    
    [WBHookBlock runBlock:block4];
}

- (void)run_block_02 {
    testBlock_04 block4 = ^(){
        NSLog(@"hello block4");
    };
    
    [WBHookBlock runBlock_Invocation:block4];
}

- (void)testEasyHook {
    testBlock block1 = ^(int a) {
        NSLog(@"block1 is %d",a);
    };
    
    testBlock block2 = ^(int a) {
        NSLog(@"block2 is %d",a);
    };
    
    [WBHookBlock easy_hookBlock:block1 alter:block2];
    
    block1(20);
}

- (void)testHook {
    NSObject *obj = [[NSObject alloc] init];
    int c = 100;
    testBlock block1 = ^(int a) {
        NSLog(@"block1 a is %d",a);
        NSLog(@"block1 c is %d",c);
        NSLog(@"obj is %@",obj);
    };
    
    testBlock block2 = ^(int a) {
        NSLog(@"block2 a is %d",a);
        NSLog(@"block2 c is %d",c);

    };
    
    [WBHookBlock hookBlock:block1 alter:block2 position:WBHookBlockPositionBefore];
    
    block1(20);
}

- (void(^)(int a))somefuncBlock:(void(^)(int a)) block {
    NSLog(@"test block is %@",block);
    return block;
}

- (IBAction)testBtn:(id)sender {
    self.testBlock(10);
}

@end
