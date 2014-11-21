//
//  ViewController.m
//  AWSS3UploadCrash
//
//  Created by Daniel Hammond on 11/13/14.
//  Copyright (c) 2014 Sparks Labs. All rights reserved.
//

#import "ViewController.h"
#import <AWSiOSSDKv2/AWSS3TransferManager.h>
#import <AWSiOSSDKv2/AWSS3.h>
#import <AWSiOSSDKv2/AWSNetworking.h>
#import <AWSiOSSDKv2/AWSURLSessionManager.h>
#import <Bolts/Bolts.h>
#import <URLMock/URLMock.h>

@interface AWSS3TransferManager ()
- (AWSS3 *)s3;
@end

@interface AWSS3 ()
- (AWSNetworking *)networking;
@end

@interface AWSNetworking ()
- (AWSURLSessionManager *)networkManager;
@end

@interface AWSURLSessionManager ()
- (NSURLSession *)session;
@end

@interface ViewController ()

@property (nonatomic, strong) AWSS3TransferManager *manager;

@end

@implementation ViewController

- (IBAction)uploadAction:(id)sender
{
    [self uploadRandomFile];
}

- (void)uploadRandomFile
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *fileName = [[NSUUID UUID] UUIDString];
    NSString *randomFilePath = [[paths firstObject] stringByAppendingPathComponent:fileName];
    NSData *randomData = [self randomData];
    BOOL result = [randomData writeToFile:randomFilePath atomically:NO];
    if (!result) {
        [NSException raise:@"Unexpected write error" format:@"Unable to write random data to documents directory"];
    }
    
    // This is the problem: When the file is removed and the upload is retried then it crashes. If it is removed before the first request (or never requested) there is an apropriate error returned.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:randomFilePath error:nil];
    });

    AWSS3TransferManagerUploadRequest *request = [AWSS3TransferManagerUploadRequest new];
    request.bucket = @"some-bucket";
    request.key = fileName;
    request.body = [NSURL fileURLWithPath:randomFilePath];
    [[self.manager upload:request] continueWithBlock:^id(BFTask *task) {
        if (task.result) {
            NSLog(@"%@ %@", fileName, task.result);
        } else {
            NSLog(@"%@ error: %@", fileName, task.error);
        }
        return nil;
    }];
}

- (NSData *)randomData
{
    size_t len = 1024 * 5;
    unsigned char foo[len];
    arc4random_buf(&foo, len);
    return [NSData dataWithBytes:foo length:sizeof(foo)];
}

- (AWSS3TransferManager *)manager
{
    if (!_manager) {
        // Key / Secret aren't important since we're mocking the HTTP responses
        NSString *KEY = @"";
        NSString *SECRET = @"";
        AWSStaticCredentialsProvider *credentialProvider = [[AWSStaticCredentialsProvider alloc] initWithAccessKey:KEY secretKey:SECRET];
        _manager = [[AWSS3TransferManager alloc] initWithConfiguration:[AWSServiceConfiguration configurationWithRegion:AWSRegionUSWest2 credentialsProvider:credentialProvider] identifier:@"foo.bar"];
        
        // Configure URLMock to stub out all PUT requests with a NSURL error so that the upload will be retried
        [[_manager.s3.networking.networkManager.session configuration] setProtocolClasses:@[ [UMKMockURLProtocol class] ]];
        [UMKMockURLProtocol enable];
        [UMKMockURLProtocol expectMockHTTPPatchRequestWithURL:[NSURL URLWithString:@"https://s3-us-west-2.amazonaws.com"] requestJSON:nil responseError:[NSError errorWithDomain:@"foo" code:-1 userInfo:nil]];
        
        NSString *pattern = @"https://s3-us-west-2.amazonaws.com/some-bucket/:slug";
        UMKPatternMatchingMockRequest *mockRequest = [[UMKPatternMatchingMockRequest alloc] initWithURLPattern:pattern];
        mockRequest.HTTPMethods = [NSSet setWithObject:kUMKMockHTTPRequestPutMethod];
        mockRequest.responderGenerationBlock = ^id<UMKMockURLResponder>(NSURLRequest *request, NSDictionary *parameters) {
            UMKMockHTTPResponder *responder = [UMKMockHTTPResponder mockHTTPResponderWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil]];
            NSLog(@"generating response for req %@", request);
            return responder;
        };
        [UMKMockURLProtocol expectMockRequest:mockRequest];
    }
    return _manager;
}

@end
