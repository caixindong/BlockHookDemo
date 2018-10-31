//
//  WBHookBlock.m
//  WBHookBlockDemo
//
//  Created by 蔡欣东 on 2018/10/8.
//  Copyright © 2018年 蔡欣东. All rights reserved.
//

#import "WBHookBlock.h"
#import <objc/runtime.h>
#import <objc/message.h>

typedef NS_OPTIONS(int, WBFishBlockFlage) {
    WBFish_BLOCK_DEALLOCATING =      (0x0001),  // runtime
    WBFish_BLOCK_REFCOUNT_MASK =     (0xfffe),  // runtime
    WBFish_BLOCK_NEEDS_FREE =        (1 << 24), // runtime
    WBFish_BLOCK_HAS_COPY_DISPOSE =  (1 << 25), // compiler
    WBFish_BLOCK_HAS_CTOR =          (1 << 26), // compiler: helpers have C++ code
    WBFish_BLOCK_IS_GC =             (1 << 27), // runtime
    WBFish_BLOCK_IS_GLOBAL =         (1 << 28), // compiler
    WBFish_BLOCK_USE_STRET =         (1 << 29), // compiler: undefined if !BLOCK_HAS_SIGNATURE
    WBFish_BLOCK_HAS_SIGNATURE  =    (1 << 30), // compiler
    WBFish_BLOCK_HAS_EXTENDED_LAYOUT=(1 << 31)  // compiler
};

struct WBFishBlock_layout {
    void *isa;
    volatile int32_t flags;
    int32_t reserved;
    void (*invoke)(void *, ...);
    struct WBFishBlock_descriptor_1 *descriptor;
};
typedef struct WBFishBlock_layout  *WBFishBlock;

struct WBFishBlock_descriptor_1 {
    uintptr_t reserved;
    uintptr_t size;
};

struct WBFishBlock_descriptor_2 {
    void (*copy)(void *dst, const void *src);
    void (*dispose)(const void *);
};

struct WBFishBlock_descriptor_3 {
    const char *signature;
    const char *layout;
};

//获取descriptor_2
static struct WBFishBlock_descriptor_2 * get_WBFishBlock_descriptor_2(WBFishBlock block) {
    if (!(block->flags & WBFish_BLOCK_HAS_COPY_DISPOSE)) {
        return NULL;
    }
    uint8_t *desc = (uint8_t *)block->descriptor;
    desc += sizeof(struct WBFishBlock_descriptor_1);
    return (struct WBFishBlock_descriptor_2 *)desc;
}

//获取descriptor_3
static struct WBFishBlock_descriptor_3 * get_WBFishBlock_descriptor_3(WBFishBlock block) {
    if (!(block->flags & WBFish_BLOCK_HAS_SIGNATURE)) {
        return NULL;
    }
    uint8_t *desc = (uint8_t *)block->descriptor;
    desc += sizeof(struct WBFishBlock_descriptor_1);
    if (block->flags & WBFish_BLOCK_HAS_COPY_DISPOSE) {
        desc += sizeof(struct WBFishBlock_descriptor_2);
    }
    return (struct WBFishBlock_descriptor_3 *)desc;
}

static NSMethodSignature *wb_block_methodSignatureForSelector(id self, SEL _cmd, SEL aSelector) {
    struct WBFishBlock_descriptor_3 *desc_3 = get_WBFishBlock_descriptor_3((__bridge void *)self);
    return [NSMethodSignature signatureWithObjCTypes:desc_3->signature];
}


static void wbhook_block_setTmpBlock(WBFishBlock block, WBFishBlock tmpBlock) {
    objc_setAssociatedObject((__bridge id)block, @"wbhook_block_TmpBlock", (__bridge id)tmpBlock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static id wbhook_block_getTmpBlock(WBFishBlock block) {
    return objc_getAssociatedObject((__bridge id)block, @"wbhook_block_TmpBlock");
}

//retain hook block
static void wbhook_setHookBlock(WBFishBlock block, WBFishBlock hookBlock) {
    objc_setAssociatedObject((__bridge id _Nonnull)(block), @"wbhook_block_hookBlock", (__bridge id _Nullable)(hookBlock), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
}

static id wbhook_getHookBlock(WBFishBlock block) {
    return objc_getAssociatedObject((__bridge id _Nonnull)(block), @"wbhook_block_hookBlock");
}

static void wbhook_setPosInfo(WBFishBlock block, NSUInteger pos) {
    objc_setAssociatedObject((__bridge id _Nonnull)(block), @"wbhookblock_pos", @(pos), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

}

static NSNumber* wbhook_getPosInfo(WBFishBlock block) {
    return objc_getAssociatedObject((__bridge id _Nonnull)(block), @"wbhookblock_pos");
}

static void _wbFish_block_deepCopy(WBFishBlock block) {
    struct WBFishBlock_descriptor_2 *desc_2 = get_WBFishBlock_descriptor_2(block);
    //如果捕获的变量存在对象或者被__block修饰的变量时，在__main_block_desc_0函数内部会增加copy跟dispose函数，copy函数内部会根据修饰类型（weak or strong）对对象进行强引用还是弱引用，当block释放之后会进行dispose函数，release掉修饰对象的引用，如果都没有引用对象，将对象释放

    if (desc_2) {
        WBFishBlock newBlock = malloc(block->descriptor->size);
        if (!newBlock) {
            return;
        }
        memmove(newBlock, block, block->descriptor->size);
        newBlock->flags &= ~(WBFish_BLOCK_REFCOUNT_MASK|WBFish_BLOCK_DEALLOCATING);
        newBlock->flags |= WBFish_BLOCK_NEEDS_FREE | 2;  // logical refcount 1
        
        (desc_2->copy)(newBlock, block);
        wbhook_block_setTmpBlock(block, newBlock);
    } else {
        //FishBind缺陷：以前那种grouph方式没办法拷贝变量
        WBFishBlock newBlock = malloc(block->descriptor->size);
        if (!newBlock) {
            return;
        }
        memmove(newBlock, block, block->descriptor->size);
        newBlock->flags &= ~(WBFish_BLOCK_REFCOUNT_MASK|WBFish_BLOCK_DEALLOCATING);
        newBlock->flags |= WBFish_BLOCK_NEEDS_FREE | 2;  // logical refcount 1
        wbhook_block_setTmpBlock(block, newBlock);
    }
}

//关键，block转化为NSInvocation对象，一个NSInvocation代表一条oc消息，包含方法的调用方、消息名、参数、返回值
static void wb_block_forwardInvocation(id self, SEL _cmd, NSInvocation *invo) {
    WBFishBlock block = (__bridge void *)invo.target;
    
    NSUInteger originArgNum = invo.methodSignature.numberOfArguments;
    NSUInteger hookArgNum = invo.methodSignature.numberOfArguments;
    
    //block转invoation
    WBFishBlock hookBlock = (__bridge void*)wbhook_getHookBlock(block);
    struct WBFishBlock_descriptor_3 * hookBlock_des_3 = get_WBFishBlock_descriptor_3(hookBlock);
    NSMethodSignature *hookBlockMethodSignature = [NSMethodSignature signatureWithObjCTypes:hookBlock_des_3->signature];
    NSInvocation *hookBlockInv = [NSInvocation invocationWithMethodSignature:hookBlockMethodSignature];
    
    if (originArgNum != hookArgNum) {
        NSLog(@"arguments count is not fit");
        return;
    }
    
    if (hookArgNum > 1) {
        void *tmpArg = NULL;
        for (NSUInteger i = 1; i < hookArgNum; i++) {
            const char *type = [invo.methodSignature getArgumentTypeAtIndex:i];
            NSUInteger argsSize;
            NSGetSizeAndAlignment(type, &argsSize, NULL);
            if (!(tmpArg = realloc(tmpArg, argsSize))) {
                NSLog(@"fail allocate memory for block arg");
                return;
            }
            [invo getArgument:tmpArg atIndex:i];
            [hookBlockInv setArgument:tmpArg atIndex:i];
        }
    }
    
    WBFishBlock tmpBlock = (__bridge void *)wbhook_block_getTmpBlock(block);
    
    NSNumber *pos = wbhook_getPosInfo(block);
    NSUInteger posInx = [pos unsignedIntegerValue];
    switch (posInx) {
        case 0:
            [invo invokeWithTarget:(__bridge id _Nonnull)(tmpBlock)];
            [hookBlockInv invokeWithTarget:(__bridge id _Nonnull)(hookBlock)];
            break;
        case 1:
            [hookBlockInv invokeWithTarget:(__bridge id _Nonnull)(hookBlock)];
            [invo invokeWithTarget:(__bridge id _Nonnull)(tmpBlock)];
            break;
        case 2:
            [hookBlockInv invokeWithTarget:(__bridge id _Nonnull)(hookBlock)];
            break;
        default:
            [invo invokeWithTarget:(__bridge id _Nonnull)(tmpBlock)];
            [hookBlockInv invokeWithTarget:(__bridge id _Nonnull)(hookBlock)];
            break;
    }
    
 

}

#define WBFish_StrongHookMethod(selector, func) { Class cls = NSClassFromString(@"NSBlock");Method method = class_getInstanceMethod([NSObject class], selector); \
BOOL success = class_addMethod(cls, selector, (IMP)func, method_getTypeEncoding(method)); \
if (!success) { class_replaceMethod(cls, selector, (IMP)func, method_getTypeEncoding(method));}}

static void wbblock_hook_once() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WBFish_StrongHookMethod(@selector(methodSignatureForSelector:), wb_block_methodSignatureForSelector);
        //在forwardInvocation:中执行完自己的逻辑后，将invocation的target设置为刚刚copy的block，执行invoke。完成Hook
        WBFish_StrongHookMethod(@selector(forwardInvocation:), wb_block_forwardInvocation);
    });
}


// code from
// https://github.com/bang590/JSPatch/blob/master/JSPatch/JPEngine.m
// line 975
static IMP _wbfish_getMsgForward(const char *methodTypes) {
    IMP msgForwardIMP = _objc_msgForward;
#if !defined(__arm64__)
    if (methodTypes[0] == '{') {
        NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:methodTypes];
        if ([methodSignature.debugDescription rangeOfString:@"is special struct return? YES"].location != NSNotFound) {
            msgForwardIMP = (IMP)_objc_msgForward_stret;
        }
    }
#endif
    return msgForwardIMP;
}

static void wbhook_block(id obj) {
    wbblock_hook_once();
    WBFishBlock block = (__bridge WBFishBlock)(obj);
    if (!wbhook_block_getTmpBlock(block)) {
        //先copy一份,目的是为了复制外部变量
        _wbFish_block_deepCopy(block);
        struct WBFishBlock_descriptor_3 *desc_3 = get_WBFishBlock_descriptor_3(block);
        //设置block的invoke指针为_objc_msgForward为了调用block触发消息转发。
        block->invoke = (void *)_wbfish_getMsgForward(desc_3->signature);
    }
}


@implementation WBHookBlock

+ (void)hookBlock:(id)originBlock alter:(id)alterBlock position:(WBHookBlockPosition)position{
    WBFishBlock u_originBlock = (__bridge WBFishBlock)originBlock;
    WBFishBlock u_alterBlock = (__bridge WBFishBlock)alterBlock;
    
    wbhook_setPosInfo(u_originBlock, position);
    wbhook_setHookBlock(u_originBlock, u_alterBlock);
    wbhook_block(originBlock);
}


+ (void)easy_hookBlock:(id)originBlock alter:(id)alterBlock {
    WBFishBlock u_originBlock = (__bridge WBFishBlock)originBlock;
    WBFishBlock u_alterBlock = (__bridge WBFishBlock)alterBlock;
    u_originBlock->invoke = u_alterBlock->invoke;
}

+ (void)runBlock:(id)block {
    WBFishBlock u_block = (__bridge WBFishBlock)block;
    (u_block->invoke)(u_block);
}

+ (void)runBlock_Invocation:(id)block {
    WBFishBlock u_block = (__bridge WBFishBlock)block;
    struct WBFishBlock_descriptor_3 *des_3 = get_WBFishBlock_descriptor_3(u_block);
    NSMethodSignature *sign = [NSMethodSignature signatureWithObjCTypes:des_3->signature];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sign];
    inv.target = (__bridge id)(u_block);
    [inv invoke];
}

@end
