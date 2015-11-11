//
//  GameCenterHandler.m
//  GameCenterIosExtension
//
//  Created by Richard Lord on 18/06/2012.
//  Copyright (c) 2012 Stick Sports Ltd. All rights reserved.
//

#import "GameCenterHandler.h"
#import <GameKit/GameKit.h>
#import "GC_NativeMessages.h"
#import "GC_BoardsController.h"
#import "GC_BoardsControllerPhone.h"
#import "GC_BoardsControllerPad.h"
#import "GC_LeaderboardWithNames.h"
#import "GC_TypeConversion.h"

#define DISPATCH_STATUS_EVENT(extensionContext, code, status) FREDispatchStatusEventAsync((extensionContext), (uint8_t*)code, (uint8_t*)status)

#define ASLocalPlayer "com.sticksports.nativeExtensions.gameCenter.GCLocalPlayer"
#define ASLeaderboard "com.sticksports.nativeExtensions.gameCenter.GCLeaderboard"
#define ASVectorScore "Vector.<com.sticksports.nativeExtensions.gameCenter.GCScore>"
#define ASVectorAchievement "Vector.<com.sticksports.nativeExtensions.gameCenter.GCAchievement>"

@interface GameCenterHandler () {
}
@property FREContext context;
@property (retain)NSMutableDictionary* returnObjects;
@property (retain)NSMutableDictionary* playerPhotos;
@property (retain)id<BoardsController> boardsController;
@property (retain)GC_TypeConversion* converter;

@property(nonatomic, retain) UIViewController *authenticateView;
@property(nonatomic) BOOL showAuthenticateView;

@property(nonatomic) bool authenticateViewPresent;

- (void)authenticateTimeout:(GKLocalPlayer *)localPlayer;
- (void)authenticatePlayerHandler:(GKLocalPlayer *)localPlayer withController:(UIViewController *)viewController withError:(NSError *)error;
@end

@implementation GameCenterHandler

@synthesize context, returnObjects, playerPhotos, boardsController, converter, authenticateView, showAuthenticateView;




- (id)initWithContext:(FREContext)extensionContext
{
    self = [super init];
    if( self )
    {
        context = extensionContext;
        returnObjects = [[NSMutableDictionary alloc] init];
        playerPhotos = [[NSMutableDictionary alloc] init];
        converter = [[GC_TypeConversion alloc] init];
    }
    return self;
}

- (void) createBoardsController
{
    if( !boardsController )
    {
        if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
        {
            boardsController = [[BoardsControllerPad alloc] initWithContext:context];
        }
        else
        {
            boardsController = [[BoardsControllerPhone alloc] initWithContext:context];
        }
    }
}

- (NSString*) storeReturnObject:(id)object
{
    NSString* key;
    do
    {
        key = [NSString stringWithFormat: @"%li", random()];
    } while ( [self.returnObjects valueForKey:key] != nil );
    [self.returnObjects setValue:object forKey:key];
    return key;
}

- (id) getReturnObject:(NSString*) key
{
    NSLog(@"getReturnObject:%@", key);
    id object = [self.returnObjects valueForKey:key];
    [self.returnObjects setValue:nil forKey:key];
    return object;
}

- (void) storeReturnedPlayerPhoto:(NSString*)playerId playerPhoto:(UIImage *)photo
{
    NSLog(@"storeReturnedPlayerPhoto:%@", playerId);
    if(photo == nil) {
        NSLog(@"storeReturnedPlayerPhoto: photo is nil");
    }
    [self.playerPhotos setObject:photo forKey:playerId];
}

- (UIImage *) getStoredReturnedPlayerPhoto:(NSString*)key
{
    UIImage * photo = [self.playerPhotos objectForKey:key];
    [self.playerPhotos setValue:nil forKey:key];
    return photo;
}

- (FREObject) isSupported
{
    // Check for presence of GKLocalPlayer class.
    BOOL localPlayerClassAvailable = (NSClassFromString(@"GKLocalPlayer")) != nil;
    
    NSLog(localPlayerClassAvailable ? @"GKLocalPlayer found" : @"GKLocalPlayer not found");
    
    // The device must be running iOS 4.1 or later.
    NSString *reqSysVer = @"4.1";
    NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
    BOOL osVersionSupported = ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending);
    NSLog(osVersionSupported ? @"osVersionSupported == true" : @"osVersionSupported == false");
    
    uint32_t retValue = (localPlayerClassAvailable && osVersionSupported) ? 1 : 0;
    
    FREObject result;
    if ( FRENewObjectFromBool(retValue, &result ) == FRE_OK )
    {
        return result;
    }
    return NULL;
}

- (FREObject) authenticateLocalPlayer
{
    NSLog(@"GC:authenticateLocalPlayer: start");
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( localPlayer == nil ) {
        NSLog(@"GC:authenticateLocalPlayer: no local player");
        DISPATCH_STATUS_EVENT(self.context, @"No local player", localPlayerNotAuthenticated);
        return NULL;
    }
    NSLog(@"GC:authenticateLocalPlayer: have local player");
    if ( localPlayer.isAuthenticated )
    {
        NSLog(@"GC:authenticateLocalPlayer: local player authenticated");
        DISPATCH_STATUS_EVENT( self.context, "", localPlayerAuthenticated );
        return NULL;
    }
    if (self.authenticateView != nil) {
        NSLog(@"GC:authenticateLocalPlayer: present authenticateView");
        UIViewController *rootViewController = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
        [rootViewController presentViewController:self.authenticateView animated:YES completion:nil];
    } else {
        NSLog(@"GC:authenticateLocalPlayer: initiate authentication and timeout");
        self.showAuthenticateView = true;
        localPlayer.authenticateHandler = ^(UIViewController *viewController, NSError *error)
        {
            [self authenticatePlayerHandler:localPlayer withController:viewController withError:error];
        };
        [self performSelector:@selector(authenticateTimeout:) withObject:localPlayer afterDelay:15.0];
    }
    return NULL;
}

- (void)authenticateTimeout:(GKLocalPlayer *)localPlayer {
    if (self.authenticateViewPresent) {
        NSLog(@"GC:authenticateTimeout: authenticateView is present now - ignore authenticate timeout");
        return;
    }
    self.showAuthenticateView = false;
    if (localPlayer.isAuthenticated ){
        NSLog(@"GC:authenticateTimeout: timed out but authenticated");
        DISPATCH_STATUS_EVENT( self.context, "", localPlayerAuthenticated );
    } else {
        NSLog(@"GC:authenticateTimeout: timed out and not authenticated");
        DISPATCH_STATUS_EVENT(self.context, "", localPlayerNotAuthenticated);
    }
}

- (void)authenticatePlayerHandler:(GKLocalPlayer *)localPlayer withController:(UIViewController *)viewController withError:(NSError *)error {
    NSLog(@"GC:authenticatePlayerHandler: start");
    bool showView = self.showAuthenticateView;
    self.showAuthenticateView = false;
    self.authenticateViewPresent = false;
    if (viewController != nil) {
        NSLog(@"GC:authenticatePlayerHandler: viewController != nil");
        if (self.authenticateView != nil) {
            [self.authenticateView release];
        }
        self.authenticateView = viewController;
        if (showView) {
            NSLog(@"GC:authenticatePlayerHandler: present authenticateView");
            self.authenticateViewPresent = true;
            UIViewController *rootViewController = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
            [rootViewController presentViewController:viewController animated:YES completion:nil];
            return; 
        } // else fail authentication
    }
    if (localPlayer.isAuthenticated) {
        NSLog(@"GC:authenticatePlayerHandler: local player authenticated");
        DISPATCH_STATUS_EVENT( self.context, "", localPlayerAuthenticated );
    } else {
        if(error != nil) {
            NSLog(@"GC:authenticatePlayerHandler failed with error: %@", error.localizedDescription);
            DISPATCH_STATUS_EVENT( self.context, [error.localizedDescription UTF8String], localPlayerNotAuthenticated );
        } else {
            NSLog(@"GC:authenticatePlayerHandler failed without error");
            DISPATCH_STATUS_EVENT( self.context, "", localPlayerNotAuthenticated );
        }
    }
}

- (FREObject) getLocalPlayer
{
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if ( localPlayer && localPlayer.isAuthenticated )
    {
        FREObject asPlayer;
        if ( FRENewObject( ASLocalPlayer, 0, NULL, &asPlayer, NULL ) == FRE_OK
            && [self.converter FRESetObject:asPlayer property:"id" toString:localPlayer.playerID] == FRE_OK
            && [self.converter FRESetObject:asPlayer property:"alias" toString:localPlayer.alias] == FRE_OK )
        {
            return asPlayer;
        }
    }
    else
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
    }
    return NULL;
}

- (FREObject) reportScore:(FREObject)asScore inCategory:(FREObject)asCategory
{
    NSString* category;
    if( [self.converter FREGetObject:asCategory asString:&category] != FRE_OK ) return NULL;
    
    int32_t scoreValue = 0;
    if( FREGetObjectAsInt32( asScore, &scoreValue ) != FRE_OK ) return NULL;
    
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( !localPlayer.isAuthenticated )
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
        return NULL;
    }
    
    GKScore* score = [[[GKScore alloc] initWithCategory:category] autorelease];
    if( score )
    {
        score.value = scoreValue;
        [score reportScoreWithCompletionHandler:^(NSError* error)
         {
             if( error == nil )
             {
                 DISPATCH_STATUS_EVENT( self.context, "", scoreReported );
             }
             else
             {
                 DISPATCH_STATUS_EVENT( self.context, "", scoreNotReported );
             }
         }];
    }
    return NULL;
}

- (FREObject) showStandardLeaderboard
{
    [self createBoardsController];
    [self.boardsController displayLeaderboard];
    return NULL;
}

- (FREObject) showStandardLeaderboardWithCategory:(FREObject)asCategory
{
    NSString* category;
    if( [self.converter FREGetObject:asCategory asString:&category] != FRE_OK ) return NULL;
    
    [self createBoardsController];
    [self.boardsController displayLeaderboardWithCategory:category];
    return NULL;
}

- (FREObject) showStandardLeaderboardWithTimescope:(FREObject)asTimescope
{
    int timeScope;
    if( FREGetObjectAsInt32( asTimescope, &timeScope ) != FRE_OK ) return NULL;
    
    [self createBoardsController];
    [self.boardsController displayLeaderboardWithTimescope:timeScope];
    return NULL;
}

- (FREObject) showStandardLeaderboardWithCategory:(FREObject)asCategory andTimescope:(FREObject)asTimescope
{
    NSString* category;
    if( [self.converter FREGetObject:asCategory asString:&category] != FRE_OK ) return NULL;
    int timeScope;
    if( FREGetObjectAsInt32( asTimescope, &timeScope ) != FRE_OK ) return NULL;
    
    [self createBoardsController];
    [self.boardsController displayLeaderboardWithCategory:category andTimescope:timeScope];
    return NULL;
}

- (FREObject) getLeaderboardWithCategory:(FREObject)asCategory playerScope:(FREObject)asPlayerScope timeScope:(FREObject)asTimeScope rangeMin:(FREObject)asRangeMin rangeMax:(FREObject)asRangeMax
{
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( !localPlayer.isAuthenticated )
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
        return NULL;
    }
    
    GKLeaderboard* leaderboard = [[GKLeaderboard alloc] init];
    
    NSString* propertyString;
    if( [self.converter FREGetObject:asCategory asString:&propertyString] != FRE_OK ) return NULL;
    leaderboard.category = propertyString;
    
    int propertyInt;
    if( FREGetObjectAsInt32( asPlayerScope, &propertyInt ) != FRE_OK ) return NULL;
    leaderboard.playerScope = propertyInt;
    
    if( FREGetObjectAsInt32( asTimeScope, &propertyInt ) != FRE_OK ) return NULL;
    leaderboard.timeScope = propertyInt;
    
    int propertyInt2;
    if( FREGetObjectAsInt32( asRangeMin, &propertyInt ) != FRE_OK ) return NULL;
    if( FREGetObjectAsInt32( asRangeMax, &propertyInt2 ) != FRE_OK ) return NULL;
    leaderboard.range = NSMakeRange( propertyInt, propertyInt2 );
    
    [leaderboard loadScoresWithCompletionHandler:^( NSArray* scores, NSError* error )
     {
         if( error == nil && scores != nil )
         {
             LeaderboardWithNames* leaderboardWithNames = [[LeaderboardWithNames alloc] initWithLeaderboard:leaderboard];
             NSMutableArray* playerIds = [[[NSMutableArray alloc] initWithCapacity:scores.count] autorelease];
             int i = 0;
             for ( GKScore* score in scores )
             {
                 [playerIds insertObject:score.playerID atIndex:i];
                 ++i;
             }
             [GKPlayer loadPlayersForIdentifiers:playerIds withCompletionHandler:^(NSArray *playerDetails, NSError *error)
              {
                  if ( error == nil && playerDetails != nil )
                  {
                      NSMutableDictionary* names = [[[NSMutableDictionary alloc] init] autorelease];
                      for( GKPlayer* player in playerDetails )
                      {
                          [names setValue:player forKey:player.playerID];
                      }
                      leaderboardWithNames.names = names;
                      NSString* code = [self storeReturnObject:leaderboardWithNames];
                      DISPATCH_STATUS_EVENT( self.context, code.UTF8String, loadLeaderboardComplete );
                  }
                  else
                  {
                      [leaderboardWithNames release];
                      DISPATCH_STATUS_EVENT( self.context, "", loadLeaderboardFailed );
                  }
              }];
         }
         else
         {
             [leaderboard release];
             DISPATCH_STATUS_EVENT( self.context, "", loadLeaderboardFailed );
         }
     }];
    return NULL;
}

- (FREObject) reportAchievement:(FREObject)asId withValue:(FREObject)asValue andBanner:(FREObject)asBanner
{
    NSString* identifier;
    if( [self.converter FREGetObject:asId asString:&identifier] != FRE_OK ) return NULL;
    
    double value = 0;
    if( FREGetObjectAsDouble( asValue, &value ) != FRE_OK ) return NULL;
    
    uint32_t banner = 0;
    if( FREGetObjectAsBool( asBanner, &banner ) != FRE_OK ) return NULL;
    
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( !localPlayer.isAuthenticated )
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
        return NULL;
    }
    
    GKAchievement* achievement = [[[GKAchievement alloc] initWithIdentifier:identifier] autorelease];
    if( achievement )
    {
        achievement.percentComplete = value * 100;
        if( [achievement respondsToSelector:@selector(showsCompletionBanner)] )
        {
            achievement.showsCompletionBanner = ( banner == 1 );
        }
        [achievement reportAchievementWithCompletionHandler:^(NSError* error)
         {
             if( error == nil )
             {
                 DISPATCH_STATUS_EVENT( self.context, "", achievementReported );
             }
             else
             {
                 DISPATCH_STATUS_EVENT( self.context, "", achievementNotReported );
             }
         }];
    }
    return NULL;
}


- (FREObject) showStandardAchievements
{
    [self createBoardsController];
    [self.boardsController displayAchievements];
    return NULL;
}

- (FREObject) getAchievements
{
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( !localPlayer.isAuthenticated )
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
        return NULL;
    }
    
    [GKAchievement loadAchievementsWithCompletionHandler:^( NSArray* achievements, NSError* error )
     {
         if( error == nil && achievements != nil )
         {
             [achievements retain];
             NSString* code = [self storeReturnObject:achievements];
             DISPATCH_STATUS_EVENT( self.context, code.UTF8String, loadAchievementsComplete );
         }
         else
         {
             DISPATCH_STATUS_EVENT( self.context, "", loadAchievementsFailed );
         }
     }];
    return NULL;
}

- (FREObject) getLocalPlayerFriends
{
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( !localPlayer.isAuthenticated )
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
        return NULL;
    }
    [localPlayer loadFriendsWithCompletionHandler:^(NSArray *friendIds, NSError *error)
     {
         if ( error == nil && friendIds != nil )
         {
             if( friendIds.count == 0 )
             {
                 [friendIds retain];
                 NSString* code = [self storeReturnObject:friendIds];
                 DISPATCH_STATUS_EVENT( self.context, code.UTF8String, loadFriendsComplete );
             }
             else
             {
                 [GKPlayer loadPlayersForIdentifiers:friendIds withCompletionHandler:^(NSArray *friendDetails, NSError *error)
                  {
                      if ( error == nil && friendDetails != nil )
                      {
                          [friendDetails retain];
                          NSString* code = [self storeReturnObject:friendDetails];
                          DISPATCH_STATUS_EVENT( self.context, code.UTF8String, loadFriendsComplete );
                      }
                      else
                      {
                          DISPATCH_STATUS_EVENT( self.context, "", loadFriendsFailed );
                      }
                  }];
             }
         }
         else
         {
             DISPATCH_STATUS_EVENT( self.context, "", loadFriendsFailed );
         }
     }];
    return NULL;
}

- (FREObject) getLocalPlayerScoreInCategory:(FREObject)asCategory playerScope:(FREObject)asPlayerScope timeScope:(FREObject)asTimeScope
{
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( !localPlayer.isAuthenticated )
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
        return NULL;
    }

    GKLeaderboard* leaderboard = [[GKLeaderboard alloc] init];
    
    NSString* propertyString;
    if( [self.converter FREGetObject:asCategory asString:&propertyString] != FRE_OK ) return NULL;
    leaderboard.category = propertyString;
    
    int propertyInt;
    if( FREGetObjectAsInt32( asPlayerScope, &propertyInt ) != FRE_OK ) return NULL;
    leaderboard.playerScope = propertyInt;
    
    if( FREGetObjectAsInt32( asTimeScope, &propertyInt ) != FRE_OK ) return NULL;
    leaderboard.timeScope = propertyInt;
    
    leaderboard.range = NSMakeRange( 1, 1 );
    
    [leaderboard loadScoresWithCompletionHandler:^( NSArray* scores, NSError* error )
     {
         if( error == nil && scores != nil )
         {
             NSString* code = [self storeReturnObject:leaderboard];
             DISPATCH_STATUS_EVENT( self.context, code.UTF8String, loadLocalPlayerScoreComplete );
         }
         else
         {
             [leaderboard release];
             DISPATCH_STATUS_EVENT( self.context, "", loadLocalPlayerScoreFailed );
         }
     }];
    return NULL;
}

- (FREObject) getStoredLocalPlayerScore:(FREObject)asKey
{
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( !localPlayer.isAuthenticated )
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
        return NULL;
    }
    
    NSString* key;
    if( [self.converter FREGetObject:asKey asString:&key] != FRE_OK ) return NULL;
    
    GKLeaderboard* leaderboard = [self getReturnObject:key];
    
    if( leaderboard == nil )
    {
        return NULL;
    }
    FREObject asLeaderboard;
    FREObject asScore;
    
    if ( FRENewObject( ASLeaderboard, 0, NULL, &asLeaderboard, NULL) == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"timeScope" toInt:leaderboard.timeScope] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"playerScope" toInt:leaderboard.playerScope] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"category" toString:leaderboard.category] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"title" toString:leaderboard.title] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"rangeMax" toInt:leaderboard.maxRange] == FRE_OK )
    {
        if( leaderboard.localPlayerScore && [self.converter FREGetGKScore:leaderboard.localPlayerScore forPlayer:localPlayer asObject:&asScore] == FRE_OK )
        {
            FRESetObjectProperty( asLeaderboard, "localPlayerScore", asScore, NULL );
        }
        [leaderboard release];
        return asLeaderboard;
    }
    [leaderboard release];
    return NULL;
}

- (FREObject) getStoredLeaderboard:(FREObject)asKey
{
    GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
    if( !localPlayer.isAuthenticated )
    {
        DISPATCH_STATUS_EVENT( self.context, "", notAuthenticated );
        return NULL;
    }
    
    NSString* key;
    if( [self.converter FREGetObject:asKey asString:&key] != FRE_OK ) return NULL;
    
    LeaderboardWithNames* leaderboardWithNames = [self getReturnObject:key];
    GKLeaderboard* leaderboard = leaderboardWithNames.leaderboard;
    NSDictionary* names = leaderboardWithNames.names;
    
    if( leaderboard == nil || names == nil )
    {
        return NULL;
    }
    FREObject asLeaderboard;
    FREObject asLocalScore;
    
    if ( FRENewObject( ASLeaderboard, 0, NULL, &asLeaderboard, NULL) == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"timeScope" toInt:leaderboard.timeScope] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"playerScope" toInt:leaderboard.playerScope] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"category" toString:leaderboard.category] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"title" toString:leaderboard.title] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"rangeMax" toInt:leaderboard.maxRange] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"rangeStart" toInt:leaderboard.range.location] == FRE_OK
        && [self.converter FRESetObject:asLeaderboard property:"rangeLength" toInt:leaderboard.range.length] == FRE_OK
        )
    {
        if( leaderboard.localPlayerScore && [self.converter FREGetGKScore:leaderboard.localPlayerScore forPlayer:localPlayer asObject:&asLocalScore] == FRE_OK )
        {
            FRESetObjectProperty( asLeaderboard, "localPlayerScore", asLocalScore, NULL );
        }
        if( leaderboard.scores )
        {
            FREObject asScores;
            if ( FRENewObject( ASVectorScore, 0, NULL, &asScores, NULL ) == FRE_OK && FRESetArrayLength( asScores, leaderboard.scores.count ) == FRE_OK )
            {
                int nextIndex = 0;
                for( GKScore* score in leaderboard.scores )
                {
                    GKPlayer* player = [names valueForKey:score.playerID];
                    if( player != nil )
                    {
                        FREObject asScore;
                        if( [self.converter FREGetGKScore:score forPlayer:player asObject:&asScore] == FRE_OK )
                        {
                            FRESetArrayElementAt( asScores, nextIndex, asScore );
                            ++nextIndex;
                        }
                    }
                }
                FRESetObjectProperty( asLeaderboard, "scores", asScores, NULL );
            }
        }
        [leaderboardWithNames release];
        return asLeaderboard;
    }
    [leaderboardWithNames release];
    return NULL;
}

- (FREObject) getStoredAchievements:(FREObject)asKey
{
    NSString* key;
    if( [self.converter FREGetObject:asKey asString:&key] != FRE_OK ) return NULL;
    
    NSArray* achievements = [self getReturnObject:key];
    if( achievements == nil )
    {
        return NULL;
    }
    FREObject asAchievements;
    if ( FRENewObject( ASVectorAchievement, 0, NULL, &asAchievements, NULL ) == FRE_OK && FRESetArrayLength( asAchievements, achievements.count ) == FRE_OK )
    {
        int nextIndex = 0;
        for( GKAchievement* achievement in achievements )
        {
            FREObject asAchievement;
            if( [self.converter FREGetGKAchievement:achievement asObject:&asAchievement] == FRE_OK )
            {
                FRESetArrayElementAt( asAchievements, nextIndex, asAchievement );
                ++nextIndex;
            }
        }
        [achievements release];
        return asAchievements;
    }
    [achievements release];
    return NULL;
}

- (FREObject) getStoredPlayers:(FREObject)asKey
{
    NSString* key;
    if( [self.converter FREGetObject:asKey asString:&key] != FRE_OK ) return NULL;
    
    NSArray* friendDetails = [self getReturnObject:key];
    if( friendDetails == nil )
    {
        return NULL;
    }
    FREObject friends;
    if ( FRENewObject( "Array", 0, NULL, &friends, NULL ) == FRE_OK && FRESetArrayLength( friends, friendDetails.count ) == FRE_OK )
    {
        int nextIndex = 0;
        for( GKPlayer* friend in friendDetails )
        {
            FREObject asPlayer;
            if( [self.converter FREGetGKPlayer:friend asObject:&asPlayer] == FRE_OK )
            {
                FRESetArrayElementAt( friends, nextIndex, asPlayer );
                ++nextIndex;
            }
        }
        [friendDetails release];
        return friends;
    }
    [friendDetails release];
    return NULL;
}

- (FREObject) getStoredPlayerPhoto:(FREObject)playerId inBitmapData:(FREObject)asBitmapData
{
    FREObject success;
    uint32_t resultValue = 0;
    
    NSString* key;
    if( [self.converter FREGetObject:playerId asString:&key] != FRE_OK ) {
        FRENewObjectFromBool(resultValue, &success);
        NSLog(@"couldn't get key");
        return success;
    }
    UIImage* photo = [self getStoredReturnedPlayerPhoto:key];
    
    if(photo == nil) {
        NSLog(@"No stored photo for player id %@", playerId);
        FRENewObjectFromBool(resultValue, &success);
        return success;
    }

    FREBitmapData bitmapData;
    FREResult rslt = FREAcquireBitmapData(asBitmapData, &bitmapData);
    if(rslt != FRE_OK) {
        NSLog(@"Error: invalid bitmapdata passed to getStoredPlayerPhoto");
        FRENewObjectFromBool(resultValue, &success);
        [photo release];
        return success;
    }
    
    CGImageRef imageRef = [photo CGImage];
    NSUInteger width = bitmapData.width;
    NSUInteger height = bitmapData.height;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = malloc(height * width * 4);
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    
    CGContextRef cgCtx = CGBitmapContextCreate(rawData, width, height, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(cgCtx, CGRectMake(0, 0, width, height), imageRef);
    
    int x, y;
    int offset = bitmapData.lineStride32 - bitmapData.width;
    int offset2 = bytesPerRow - bitmapData.width*4;
    int byteIndex = 0;
    uint32_t *bitmapDataPixels = bitmapData.bits32;
    
    for (y=0; y<bitmapData.height; y++)
    {
        for (x=0; x<bitmapData.width; x++, bitmapDataPixels++, byteIndex += 4)
        {
            // Values are currently in RGBA7777, so each color value is currently a separate number.
            int red     = (rawData[byteIndex]);
            int green   = (rawData[byteIndex + 1]);
            int blue    = (rawData[byteIndex + 2]);
            int alpha   = (rawData[byteIndex + 3]);
            
            // Combine values into ARGB32
            *bitmapDataPixels = (alpha << 24) | (red << 16) | (green << 8) | blue;
        }
        
        bitmapDataPixels += offset;
        byteIndex += offset2;
    }
    
    // Free the memory we allocated
    free(rawData);
    
    FREInvalidateBitmapDataRect(asBitmapData, 0, 0, bitmapData.width, bitmapData.height);
    FREReleaseBitmapData(asBitmapData);

    [photo release];
    
    
    resultValue = 1;
    if (FRENewObjectFromBool(resultValue, &success) == FRE_OK) {
        NSLog(@"Returning true (success) from getStoredPlayerPhoto");
    } else {
        NSLog(@"Error trying to return true (success) from getStoredPlayerPhoto");
        return NULL;
    }
    return success;
}



- (FREObject) getPlayerPhoto:(FREObject)asPlayerId
{
    NSString* playerId;
    if( [self.converter FREGetObject:asPlayerId asString:&playerId] != FRE_OK )
        return NULL;

    NSArray* idArray = [NSArray arrayWithObject:playerId];

    [GKPlayer loadPlayersForIdentifiers:idArray withCompletionHandler:
    ^(NSArray* players, NSError* error) {
        if(players.count > 0) {
            GKPlayer *player = players[0];
            [player loadPhotoForSize:GKPhotoSizeSmall withCompletionHandler:
             ^(UIImage *photo, NSError *error) {
                 if(error != nil) {
                     DISPATCH_STATUS_EVENT( self.context, playerId.UTF8String, loadPlayerPhotoFailed );
                     return;
                 }
                 [photo retain];
                 [self storeReturnedPlayerPhoto:playerId playerPhoto:photo];
                 DISPATCH_STATUS_EVENT( self.context, playerId.UTF8String, loadPlayerPhotoComplete );
                 
             }];
        }
    }];
    
    return NULL;
}


@end
