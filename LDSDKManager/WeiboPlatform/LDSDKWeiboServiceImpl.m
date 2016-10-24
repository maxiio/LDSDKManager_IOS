//
//  LDSDKWeiboServiceImpl.m
//  LDSDKManager
//
//  Created by ss on 15/9/1.
//  Copyright (c) 2015年 张海洋. All rights reserved.
//

#import "LDSDKWeiboServiceImpl.h"
#import "WeiboSDK.h"


#define kRedirectURI    @"http://www.maishoudang.com/auth/weibo/callback"
typedef void (^LDWeiboCallbackBlock)(WBBaseResponse *resp);

@interface LDSDKWeiboServiceImpl () <WeiboSDKDelegate,WBHttpRequestDelegate> {
    BOOL isRegistered;
    NSString *shareText;
    UIImage *shareImage;
    NSString *redirectURI;
    NSError *error;
    void (^MyBlock)(NSDictionary *oauthInfo, NSDictionary *userInfo, NSError *weiboerror);
}

@property (strong, nonatomic) NSString *wbtoken;
@property (strong, nonatomic) NSString *wbCurrentUserID;
@property (nonatomic, copy) LDWeiboCallbackBlock callbackBlock;

@end

@implementation LDSDKWeiboServiceImpl

+ (instancetype)sharedService
{
    static LDSDKWeiboServiceImpl *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}


#pragma mark -
#pragma mark - 配置部分

- (BOOL)isPlatformAppInstalled
{
    return [WeiboSDK isWeiboAppInstalled];
}

- (void)registerWithPlatformConfig:(NSDictionary *)config
{
    if (config == nil || config.allKeys.count == 0) return;

    isRegistered = NO;
    NSString *appid = config[LDSDKConfigAppIdKey];
    if (appid && [appid length] > 0) {
        NSLog(@"appid = %@", appid);
        isRegistered = [WeiboSDK registerApp:appid];
    }
}

- (BOOL)isRegistered
{
    return isRegistered;
}


#pragma mark -
#pragma mark - 处理URL回调

- (BOOL)handleResultUrl:(NSURL *)url
{
    return [WeiboSDK handleOpenURL:url delegate:self];
}


#pragma mark -
#pragma mark - 登陆部分

- (BOOL)isLoginEnabledOnPlatform
{
    return [WeiboSDK isWeiboAppInstalled];
}

- (void)loginToPlatformWithCallback:(LDSDKLoginCallback)callback {
    if (![WeiboSDK isWeiboAppInstalled] || ![WeiboSDK isCanSSOInWeiboApp]) {
        error = [NSError
                 errorWithDomain:@"WeiboLogin"
                 code:0
                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"请先安装微博客户端",
                           @"NSLocalizedDescription",
                           nil]];
        if (callback) {
            callback(nil, nil, error);
        }
        return;
    }
    if ([WeiboSDK isWeiboAppInstalled]) {  //手机QQ登录流程
        
        WBAuthorizeRequest *request = [WBAuthorizeRequest request];
        request.redirectURI = kRedirectURI;
        request.scope = @"all";
        [WeiboSDK sendRequest:request];
        [self sendReq:request callback:^(WBBaseResponse *resp) {
            if (callback) {
                MyBlock = callback;
            }
            if ([resp isKindOfClass:[WBAuthorizeResponse class]]) {
                WBAuthorizeResponse *response = (WBAuthorizeResponse *)resp;
                if ([response accessToken] && 0 != [[response accessToken] length]) {
                    NSMutableDictionary *oauthInfo = [NSMutableDictionary dictionary];
                    [oauthInfo setObject:[response userID] forKey:kWB_USER_ID];
                    [oauthInfo setObject:[response accessToken] forKey:kWB_TOKEN_KEY];
                    [oauthInfo setObject:[response userInfo] forKey:kWB_USERINFO_KEY];
                    if (MyBlock) {
                        MyBlock(oauthInfo, nil, nil);
                    }
                    
                    NSMutableDictionary *params = [NSMutableDictionary dictionary];
                    [params setObject:[response accessToken] forKey:@"access_token"];
                    [params setObject:[response userID] forKey:@"uid"];
                    
                    [WBHttpRequest requestWithURL:@"https://api.weibo.com/2/users/show.json" httpMethod:@"GET" params:params delegate:self withTag:@"Me"];
                    
                } else {  //登录失败，没有获取授权accesstoken
                    error = [NSError
                             errorWithDomain:@"WeiboLogin"
                             code:0
                             userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"登录失败",
                                       @"NSLocalizedDescription",
                                       nil]];
                    if (MyBlock) {
                        MyBlock(nil, nil, error);
                    }
                }
            }
        }];
    }
}

-(void)request:(WBHttpRequest *)request didFinishLoadingWithResult:(NSString *)result
{
    NSData *data=[result dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *userInfo=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (userInfo && 0 != [userInfo count]) {
        MyBlock(nil, userInfo, nil);
    }
    else
    {
        error = [NSError
                 errorWithDomain:@"WeiboLogin"
                 code:0
                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"登录失败",
                           @"NSLocalizedDescription",
                           nil]];
        if (MyBlock) {
            MyBlock(nil, nil, error);
        }
    }
}

- (void)logoutFromPlatform {
}


#pragma mark -
#pragma mark - 分享部分

- (void)shareWithContent:(NSDictionary *)content
             shareModule:(NSUInteger)shareModule
              onComplete:(LDSDKShareCallback)complete
{
    WBAuthorizeRequest *authRequest = [WBAuthorizeRequest request];
    redirectURI = content[LDSDKShareContentRedirectURIKey];
    shareText = content[LDSDKShareContentTextKey];
    shareImage = content[LDSDKShareContentImageKey];
    NSLog(@"redirectURI = %@", redirectURI);
    NSLog(@"shareText = %@", shareText);
    authRequest.redirectURI = redirectURI;
    authRequest.scope = @"all";

    WBSendMessageToWeiboRequest *request =
        [WBSendMessageToWeiboRequest requestWithMessage:[self messageToShare]
                                               authInfo:authRequest
                                           access_token:self.wbtoken];
    //    request.shouldOpenWeiboAppInstallPageIfNotInstalled = NO;
    [self sendReq:request
         callback:^(WBBaseResponse *resp) {
             if ([resp isKindOfClass:WBSendMessageToWeiboResponse.class]) {
                 [self handleShareResultInActivity:resp onComplete:complete];
             }
         }];
}

- (WBMessageObject *)messageToShare
{
    WBMessageObject *message = [WBMessageObject message];

    if (!shareText) {
        message.text = NSLocalizedString(@"测试通过WeiboSDK发送文字到微博!", nil);
    } else {
        message.text = shareText;
    }

    if (shareImage) {
        WBImageObject *image = [WBImageObject object];
        image.imageData = UIImageJPEGRepresentation(shareImage, 1);
        message.imageObject = image;
    }

    return message;
}

- (void)handleShareResultInActivity:(id)result onComplete:(void (^)(BOOL, NSError *))complete
{
    WBSendMessageToWeiboResponse *response = (WBSendMessageToWeiboResponse *)result;

    switch (response.statusCode) {
        case WeiboSDKResponseStatusCodeSuccess:
            if (complete) {
                complete(YES, nil);
            }

            break;
        case WeiboSDKResponseStatusCodeUserCancel: {
            NSError *error = [NSError
                errorWithDomain:@"WeiboShare"
                           code:-2
                       userInfo:[NSDictionary
                                    dictionaryWithObjectsAndKeys:@"用户取消分享",
                                                                 @"NSLocalizedDescription", nil]];
            if (complete) {
                complete(NO, error);
            }
        } break;
        default: {
            NSError *error = [NSError
                errorWithDomain:@"WeiboShare"
                           code:-1
                       userInfo:[NSDictionary
                                    dictionaryWithObjectsAndKeys:@"分享失败",
                                                                 @"NSLocalizedDescription", nil]];
            if (complete) {
                complete(NO, error);
            }
        }

        break;
    }
}

- (BOOL)sendReq:(WBBaseRequest *)req callback:(LDWeiboCallbackBlock)callbackBlock
{
    self.callbackBlock = callbackBlock;
    return [WeiboSDK sendRequest:req];
}


#pragma mark - WeiboSDKDelegate

- (void)didReceiveWeiboRequest:(WBBaseRequest *)request;
{
#ifdef DEBUG
    NSLog(@"[%@]%s", NSStringFromClass([self class]), __FUNCTION__);
#endif
}

- (void)didReceiveWeiboResponse:(WBBaseResponse *)response
{
#ifdef DEBUG
    NSLog(@"[%@]%s", NSStringFromClass([self class]), __FUNCTION__);
#endif

    if ([response isKindOfClass:WBSendMessageToWeiboResponse.class]) {
        //        NSString *title = NSLocalizedString(@"发送结果", nil);
        //        NSString *message = [NSString stringWithFormat:@"%@: %d\n%@: %@\n%@: %@",
        //        NSLocalizedString(@"响应状态", nil), (int)response.statusCode,
        //        NSLocalizedString(@"响应UserInfo数据", nil), response.userInfo,
        //        NSLocalizedString(@"原请求UserInfo数据", nil),response.requestUserInfo];

        WBSendMessageToWeiboResponse *sendMessageToWeiboResponse =
            (WBSendMessageToWeiboResponse *)response;
        NSString *accessToken = [sendMessageToWeiboResponse.authResponse accessToken];
        if (accessToken) {
            self.wbtoken = accessToken;
        }
        NSString *userID = [sendMessageToWeiboResponse.authResponse userID];
        if (userID) {
            self.wbCurrentUserID = userID;
        }
    } else if ([response isKindOfClass:WBAuthorizeResponse.class]) {
        //        NSString *title = NSLocalizedString(@"认证结果", nil);
        //        NSString *message = [NSString stringWithFormat:@"%@: %d\nresponse.userId:
        //        %@\nresponse.accessToken: %@\n%@: %@\n%@: %@", NSLocalizedString(@"响应状态",
        //        nil), (int)response.statusCode,[(WBAuthorizeResponse *)response userID],
        //        [(WBAuthorizeResponse *)response accessToken],
        //        NSLocalizedString(@"响应UserInfo数据", nil), response.userInfo,
        //        NSLocalizedString(@"原请求UserInfo数据", nil), response.requestUserInfo];

        self.wbtoken = [(WBAuthorizeResponse *)response accessToken];
        self.wbCurrentUserID = [(WBAuthorizeResponse *)response userID];
    } else if ([response isKindOfClass:WBPaymentResponse.class]) {
        //        NSString *title = NSLocalizedString(@"支付结果", nil);
        //        NSString *message = [NSString stringWithFormat:@"%@: %d\nresponse.payStatusCode:
        //        %@\nresponse.payStatusMessage: %@\n%@: %@\n%@: %@", NSLocalizedString(@"响应状态",
        //        nil), (int)response.statusCode,[(WBPaymentResponse *)response payStatusCode],
        //        [(WBPaymentResponse *)response payStatusMessage],
        //        NSLocalizedString(@"响应UserInfo数据", nil),response.userInfo,
        //        NSLocalizedString(@"原请求UserInfo数据", nil), response.requestUserInfo];
    }

    if (self.callbackBlock) {
        self.callbackBlock(response);
    }
}

@end
