//
//  OWAccountAPIClient.m
//  OpenWatch
//
//  Created by Christopher Ballinger on 11/16/12.
//  Copyright (c) 2012 OpenWatch FPC. All rights reserved.
//

#import "OWAccountAPIClient.h"
#import "AFJSONRequestOperation.h"
#import "OWManagedRecording.h"
#import "OWLocalRecording.h"
#import "OWUtilities.h"
#import "OWTag.h"
#import "OWSettingsController.h"
#import "OWUser.h"
#import "OWStory.h"
#import "OWRecordingController.h"
#import "SDURLCache.h"
#import "OWInvestigation.h"
#import "OWLocalMediaController.h"
#import "AFImageRequestOperation.h"
#import "OWPhoto.h"
#import "OWLocalRecording.h"
#import "OWAudio.h"

#define kRecordingsKey @"recordings/"

#define kEmailKey @"email_address"
#define kPasswordKey @"password"
#define kReasonKey @"reason"
#define kSuccessKey @"success"
#define kUsernameKey @"username"
#define kPubTokenKey @"public_upload_token"
#define kPrivTokenKey @"private_upload_token"
#define kServerIDKey @"server_id"
#define kCSRFTokenKey @"csrf_token"

#define kCreateAccountPath @"create_account"
#define kLoginAccountPath @"login_account"
#define kTagPath @"tag/"
#define kFeedPath @"feed/"
#define kTagsPath @"tags/"
#define kInvestigationPath @"i/"

#define kTypeKey @"type"
#define kVideoTypeKey @"video"
#define kInvestigationTypeKey @"investigation"
#define kStoryTypeKey @"story"
#define kUUIDKey @"uuid"

#define kObjectsKey @"objects"
#define kMetaKey @"meta"
#define kPageCountKey @"page_count"

@implementation OWAccountAPIClient

+ (NSString*) baseURL {
    return [NSURL URLWithString:[[OWUtilities apiBaseURLString] stringByAppendingFormat:@"api/"]];
}

+ (OWAccountAPIClient *)sharedClient {
    static OWAccountAPIClient *_sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedClient = [[OWAccountAPIClient alloc] initWithBaseURL:[OWAccountAPIClient baseURL]];
    });
    
    return _sharedClient;
}

- (id)initWithBaseURL:(NSURL *)url {
    self = [super initWithBaseURL:url];
    if (!self) {
        return nil;
    }
    NSString* string = @"binary/octet-stream";
    [AFImageRequestOperation addAcceptableContentTypes: [NSSet setWithObject:string]];
    SDURLCache *urlCache = [[SDURLCache alloc] initWithMemoryCapacity:1024*1024*10   // 10MB mem cache
                                                         diskCapacity:1024*1024*100 // 100MB disk cache
                                                             diskPath:[SDURLCache defaultCachePath]
                                                   enableForIOS5AndUp:YES];
    urlCache.ignoreMemoryOnlyStoragePolicy = YES;
    [NSURLCache setSharedURLCache:urlCache];
    [self registerHTTPOperationClass:[AFJSONRequestOperation class]];
    // Accept HTTP Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.1
	[self setDefaultHeader:@"Accept" value:@"application/json"];
    self.parameterEncoding = AFJSONParameterEncoding;
    
    return self;
}

- (void) checkEmailAvailability:(NSString*)email callback:(void (^)(BOOL available))callback {
    
    [self getPath:@"email_available" parameters:@{@"email": email} success:^(AFHTTPRequestOperation *operation, id responseObject) {
        BOOL available = [[responseObject objectForKey:@"available"] boolValue];
        callback(available);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error checking email availability: %@", error.userInfo);
        callback(NO);
    }];
}

- (void) quickSignupWithAccount:(OWAccount*)account callback:(void (^)(BOOL success))callback {
    [self postPath:@"quick_signup" parameters:@{@"email": account.email} success:^(AFHTTPRequestOperation *operation, id responseObject) {
        BOOL success = [[responseObject objectForKey:@"success"] boolValue];
        if (success) {
            [self processLoginDictionary:responseObject account:account];
        }
        NSLog(@"quickSignup response: %@", responseObject);
        callback(success);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error signing up for account: %@", error.userInfo);
        callback(NO);
    }];
}

- (void) loginWithAccount:(OWAccount*)account success:(void (^)(void)) success failure:(void (^)(NSString *reason))failure {
    [self registerWithAccount:account path:kLoginAccountPath success:success failure:failure];
}

- (void) signupWithAccount:(OWAccount*)account success:(void (^)(void)) success failure:(void (^)(NSString *reason))failure {
    [self registerWithAccount:account path:kCreateAccountPath success:success failure:failure];
}

- (void) processLoginDictionary:(NSDictionary*)responseObject account:(OWAccount*)account {
    account.username = [responseObject objectForKey:kUsernameKey];
    account.publicUploadToken = [responseObject objectForKey:kPubTokenKey];
    account.privateUploadToken = [responseObject objectForKey:kPrivTokenKey];
    account.accountID = [responseObject objectForKey:kServerIDKey];
    account.user.csrfToken = [responseObject objectForKey:kCSRFTokenKey];
}

- (void) registerWithAccount:(OWAccount*)account path:(NSString*)path success:(void (^)(void)) success failure:(void (^)(NSString *reason))failure {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithCapacity:2];
    [parameters setObject:account.email forKey:kEmailKey];
    [parameters setObject:account.password forKey:kPasswordKey];
    NSMutableURLRequest *request = [self requestWithMethod:@"POST" path:path parameters:parameters];
    request.HTTPShouldHandleCookies = YES;
	AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"Response: %@", [responseObject description]);
        if ([[responseObject objectForKey:kSuccessKey] boolValue]) {
            
            [self processLoginDictionary:responseObject account:account];
            
            success();
        } else {
            failure([responseObject objectForKey:kReasonKey]);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failure Response: %@", operation.responseString);
        failure([error localizedDescription]);
    }];
    
    [self enqueueHTTPRequestOperation:operation];
}

- (NSString*) pathForClass:(Class)class uuid:(NSString*)uuid {
    NSString *prefix = nil;
    if ([class isEqual:[OWPhoto class]]) {
        prefix = @"p";
    } else if ([class isEqual:[OWManagedRecording class]] || [class isEqual:[OWLocalRecording class]]) {
        prefix = @"v";
    } else if ([class isEqual:[OWAudio class]]) {
        prefix = @"a";
    } else {
        return nil;
    }
    return [NSString stringWithFormat:@"%@/%@/", prefix, uuid];
}

- (void) getObjectWithUUID:(NSString*)UUID objectClass:(Class)objectClass success:(void (^)(NSManagedObjectID *objectID))success failure:(void (^)(NSString *reason))failure {
    
    NSString *path = [self pathForClass:objectClass uuid:UUID];
    NSLog(@"Fetching %@", path);
    [self getPath:path parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSManagedObjectContext *context = [NSManagedObjectContext MR_contextForCurrentThread];
        NSLog(@"GET Response: %@", operation.responseString);
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            OWLocalMediaObject *mediaObject = [objectClass localMediaObjectWithUUID:UUID];
            if (mediaObject) {
                [mediaObject loadMetadataFromDictionary:responseObject];
                [context MR_saveToPersistentStoreAndWait];
                success(mediaObject.objectID);
            } else {
                failure(@"No recording found");
            }
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        failure([error description]);
    }];
}

- (void) postObjectWithUUID:(NSString*)UUID objectClass:(Class)objectClass success:(void (^)(void))success failure:(void (^)(NSString *reason))failure {
    NSString *path = [self pathForClass:objectClass uuid:UUID];
    
    
    OWLocalMediaObject *mediaObject = [objectClass localMediaObjectWithUUID:UUID];
    if (!mediaObject) {
        NSLog(@"Object %@ (%@) not found!", UUID, NSStringFromClass(objectClass));
        return;
    }
    [self postPath:path parameters:mediaObject.metadataDictionary success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"POST response: %@", [responseObject description]);
        //NSLog(@"POST body: %@", operation.request.HTTPBody);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"failed to POST recording: %@ %@", operation.responseString, error.userInfo);
        //failure(@"Failed to POST recording");
    }];
}

- (NSString*) pathForUserRecordingsOnPage:(NSUInteger)page {
    return [NSString stringWithFormat:@"recordings/%d/", page];
}

- (NSString*) pathForFeedType:(OWFeedType)feedType {
    NSString *prefix = nil;
    // TODO rewrite the feed and tag to use GET params
    if (feedType == kOWFeedTypeFeed) {
        prefix = kFeedPath;
    } else if (feedType == kOWFeedTypeFrontPage) {
        prefix = kInvestigationPath;
    }
    return prefix;
}


- (void) fetchMediaObjectsForFeedType:(OWFeedType)feedType feedName:(NSString*)feedName page:(NSUInteger)page success:(void (^)(NSArray *mediaObjectIDs, NSUInteger totalPages))success failure:(void (^)(NSString *reason))failure {
    NSString *path = [self pathForFeedType:feedType];
    if (!path) {
        failure(@"Path is nil!");
        return;
    }
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    [parameters setObject:@(page) forKey:@"page"];
    if (feedName) {
        [parameters setObject:feedName forKey:@"type"];
    }
    [self getPath:path parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSArray *mediaObjects = [self objectIDsFromMediaObjectsMetadataArray:[responseObject objectForKey:kObjectsKey]];
        NSDictionary *meta = [responseObject objectForKey:kMetaKey];
        NSUInteger pageCount = [[meta objectForKey:kPageCountKey] unsignedIntegerValue];
        success(mediaObjects, pageCount);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"failure: %@", [error userInfo]);
        failure(@"couldn't fetch objects");
    }];

}

- (NSArray*) objectIDsFromMediaObjectsMetadataArray:(NSArray*)array {
    NSManagedObjectContext *context = [NSManagedObjectContext MR_contextForCurrentThread];
    NSMutableArray *objectIDsToReturn = [NSMutableArray arrayWithCapacity:[array count]];
    for (NSDictionary *recordingDict in array) {
        OWMediaObject *mediaObject = [self mediaObjectForShortMetadataDictionary:recordingDict];
        if (mediaObject) {
            [objectIDsToReturn addObject:mediaObject.objectID];
        }
    }
    [context MR_saveToPersistentStoreAndWait];
    return objectIDsToReturn;
}

- (OWMediaObject*) mediaObjectForShortMetadataDictionary:(NSDictionary*)dictionary {
    OWMediaObject *mediaObject = nil;
    NSString *type = [dictionary objectForKey:kTypeKey];
    NSManagedObjectContext *context = [NSManagedObjectContext MR_contextForCurrentThread];
    if ([type isEqualToString:kVideoTypeKey]) {
        NSString *uuid = [dictionary objectForKey:kUUIDKey];
        if (uuid.length == 0) {
            NSLog(@"no uuid!");
        }
        mediaObject = [OWManagedRecording MR_findFirstByAttribute:@"uuid" withValue:uuid];
        if (!mediaObject) {
            mediaObject = [OWManagedRecording MR_createEntity];
        }
    } else if ([type isEqualToString:kStoryTypeKey]) {
        NSString *serverID = [dictionary objectForKey:kIDKey];
        mediaObject = [OWStory MR_findFirstByAttribute:@"serverID" withValue:serverID];
        if (!mediaObject) {
            mediaObject = [OWStory MR_createEntity];
        }
    } else if ([type isEqualToString:kInvestigationTypeKey]) {
        NSString *serverID = [dictionary objectForKey:kIDKey];
        mediaObject = [OWInvestigation MR_findFirstByAttribute:@"serverID" withValue:serverID];
        if (!mediaObject) {
            mediaObject = [OWInvestigation MR_createEntity];
        }
    } else {
        return nil;
    }
    NSError *error = nil;
    [context obtainPermanentIDsForObjects:@[mediaObject] error:&error];
    if (error) {
        NSLog(@"Error getting permanent ID: %@", [error userInfo]);
    }
    [mediaObject loadMetadataFromDictionary:dictionary];
    return mediaObject;
}

- (void) postSubscribedTags {
    OWAccount *account = [OWSettingsController sharedInstance].account;
    if (!account.isLoggedIn) {
        return;
    }
    NSSet *tags = account.user.tags;
    NSMutableArray *tagsArray = [NSMutableArray arrayWithCapacity:tags.count];
    for (OWTag *tag in tags) {
        NSDictionary *tagDictionary = @{@"name" : [tag.name lowercaseString]};
        [tagsArray addObject:tagDictionary];
    }
    NSDictionary *parameters = @{kTagsKey : tagsArray};
    
    [self postPath:kTagsPath parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"Tags updated on server");
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failed to post tags: %@", operation.responseString);

    }];
}


- (void) getSubscribedTags {
    OWAccount *account = [OWSettingsController sharedInstance].account;
    if (!account.isLoggedIn) {
        return;
    }
    [self getPath:kTagsPath parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSManagedObjectContext *context = [NSManagedObjectContext MR_contextForCurrentThread];
        OWUser *user = account.user;
        NSArray *rawTags = [responseObject objectForKey:@"tags"];
        NSMutableSet *tags = [NSMutableSet setWithCapacity:[rawTags count]];
        for (NSDictionary *tagDictionary in rawTags) {
            OWTag *tag = [OWTag tagWithDictionary:tagDictionary];
            [tags addObject:tag];
        }
        user.tags = tags;
        [context MR_saveToPersistentStoreAndWait];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failed to load tags: %@", operation.responseString);
    }];

}

- (void) hitMediaObject:(NSManagedObjectID*)objectID hitType:(NSString*)hitType {
    NSManagedObjectContext *context = [NSManagedObjectContext MR_contextForCurrentThread];
    OWMediaObject *mediaObject = (OWMediaObject*)[context existingObjectWithID:objectID error:nil];
    if (!mediaObject) {
        return;
    }
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithCapacity:3];
    [parameters setObject:mediaObject.serverID forKey:@"serverID"];
    [parameters setObject:hitType forKey:@"hit_type"];
    [parameters setObject:mediaObject.type forKey:@"media_type"];
    
    [self postPath:@"increase_hitcount/" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"hit response: %@", operation.responseString);
        NSLog(@"request: %@", operation.request.allHTTPHeaderFields);
        NSString *httpBody = [NSString stringWithUTF8String:operation.request.HTTPBody.bytes];
        NSLog(@"request body: %@", httpBody);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"hit failure: %@", operation.responseString);
        NSLog(@"request: %@", operation.request.allHTTPHeaderFields);
        NSString *httpBody = [NSString stringWithUTF8String:operation.request.HTTPBody.bytes];
        NSLog(@"request body: %@", httpBody);
    }];
    
    
}

- (void) getObjectWithObjectID:(NSManagedObjectID *)objectID success:(void (^)(NSManagedObjectID *objectID))success failure:(void (^)(NSString *reason))failure {
    NSManagedObjectContext *context = [NSManagedObjectContext MR_contextForCurrentThread];
    OWMediaObject *mediaObject = (OWMediaObject*)[context existingObjectWithID:objectID error:nil];
    NSString *path = [self pathForMediaObject:mediaObject];
    
    NSDictionary *parameters = [self parametersForMediaObject:mediaObject];
    
    [self getPath:path parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            [mediaObject loadMetadataFromDictionary:responseObject];
            success(objectID);
        } else {
            failure(@"not a dict");
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failed to GET object: %@", error.userInfo);
    }];
}

- (NSDictionary*) parametersForMediaObject:(OWMediaObject*)mediaObject {
    if ([mediaObject isKindOfClass:[OWInvestigation class]]) {
        NSDictionary *parameters = @{@"html": @"true"};
        return parameters;
    }
    return nil;
}

- (NSString*) pathForMediaObject:(OWMediaObject*)mediaObject {
    NSString *type = @"";
    if ([mediaObject isKindOfClass:[OWPhoto class]]) {
        type = @"p";
    } else if ([mediaObject isKindOfClass:[OWInvestigation class]]) {
        type = @"i";
    } else if ([mediaObject isKindOfClass:[OWLocalRecording class]] || [mediaObject isKindOfClass:[OWManagedRecording class]]) {
        type = @"v";
    } else {
        return nil;
    }
    return [NSString stringWithFormat:@"/api/%@/%d/", type, mediaObject.serverID.intValue];
}

- (void) fetchMediaObjectsForLocation:(CLLocation*)location page:(NSUInteger)page success:(void (^)(NSArray *mediaObjectIDs, NSUInteger totalPages))success failure:(void (^)(NSString *reason))failure {
    NSString *path = [self pathForFeedType:kOWFeedTypeFeed];
    if (!path) {
        failure(@"Path is nil!");
        return;
    }
    NSDictionary *locationDictionary = @{@"latitude": @(location.coordinate.latitude), @"longitude": @(location.coordinate.longitude)};
    [self getPath:path parameters:locationDictionary success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSArray *recordings = [self objectIDsFromMediaObjectsMetadataArray:[responseObject objectForKey:kObjectsKey]];
        NSDictionary *meta = [responseObject objectForKey:kMetaKey];
        NSUInteger pageCount = [[meta objectForKey:kPageCountKey] unsignedIntegerValue];
        success(recordings, pageCount);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"failure: %@", [error userInfo]);
        failure(@"couldn't fetch objects");
    }];
}

@end
