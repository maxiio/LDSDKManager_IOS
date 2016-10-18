//
//  LDSDKWeiboServiceImpl.h
//  LDSDKManager
//
//  Created by ss on 15/9/1.
//  Copyright (c) 2015年 张海洋. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LDSDKRegisterService.h"
#import "LDSDKShareService.h"
#import "LDSDKAuthService.h"

@interface LDSDKWeiboServiceImpl : NSObject <LDSDKAuthService, LDSDKRegisterService, LDSDKShareService>


@end
