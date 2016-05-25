//
//  CTVideoView.m
//  CTVideoView
//
//  Created by casa on 16/5/23.
//  Copyright © 2016年 casa. All rights reserved.
//

@import AVFoundation;
@import CoreMedia;

#import "CTVideoView.h"

#import "CTVideoView+Time.h"
#import "CTVideoView+Download.h"
#import "CTVideoView+VideoCoverView.h"
#import "CTVideoView+OperationButtons.h"

NSString * const kCTVideoViewShouldPlayRemoteVideoWhenNotWifi = @"kCTVideoViewShouldPlayRemoteVideoWhenNotWifi";

NSString * const kCTVideoViewKVOKeyPathPlayerItemStatus = @"player.currentItem.status";

static void * kCTVideoViewKVOContext = &kCTVideoViewKVOContext;

@interface CTVideoView ()

@property (nonatomic, assign) BOOL isVideoUrlChanged;
@property (nonatomic, assign) BOOL isVideoUrlPrepared;
@property (nonatomic, assign) BOOL isPreparedForPlay;

@property (nonatomic, strong, readwrite) NSURL *actualVideoPlayingUrl;
@property (nonatomic, assign, readwrite) CTVideoViewVideoUrlType videoUrlType;

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVURLAsset *asset;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, readonly) AVPlayerLayer *playerLayer;

@end

@implementation CTVideoView

#pragma mark - life cycle
- (instancetype)init
{
    self = [super init];
    if (self) {
        // KVO
        [self addObserver:self
               forKeyPath:kCTVideoViewKVOKeyPathPlayerItemStatus
                  options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                  context:&kCTVideoViewKVOContext];

        _shouldPlayAfterPrepareFinished = YES;
        _shouldReplayWhenFinish = NO;
        _shouldChangeOrientationToFitVideo = NO;
        _isPreparedForPlay = NO;

        if ([self.playerLayer isKindOfClass:[AVPlayerLayer class]]) {
            self.playerLayer.player = self.player;
        }
    }
    return self;
}

- (void)dealloc
{
    [self removeObserver:self forKeyPath:kCTVideoViewKVOKeyPathPlayerItemStatus context:kCTVideoViewKVOContext];
}

#pragma mark - methods override
+ (Class)layerClass
{
    return [AVPlayerLayer class];
}

#pragma mark - public methods
- (void)prepare
{
    if (self.isPlaying == YES && self.isVideoUrlChanged == NO) {
        if ([self.operationDelegate respondsToSelector:@selector(videoViewDidFinishPrepare:)]) {
            [self.operationDelegate videoViewDidFinishPrepare:self];
        }
        return;
    }

    if (self.asset) {
        [self asynchronouslyLoadURLAsset:self.asset];
    }
}

- (void)play
{
    if (self.isPlaying) {
        return;
    }
    
    if (self.isVideoUrlPrepared) {
        [self.player play];
    } else {
        self.isPreparedForPlay = YES;
        [self prepare];
    }
}

- (void)pause
{
    if (self.isPlaying) {
        [self.player pause];
    }
}

- (void)stop:(BOOL)shouldReleaseVideo
{
    [self pause];
    if (shouldReleaseVideo) {
        [self.player replaceCurrentItemWithPlayerItem:nil];
    }
}

#pragma mark - private methods
- (void)asynchronouslyLoadURLAsset:(AVURLAsset *)asset
{
    if ([self.operationDelegate respondsToSelector:@selector(videoViewWillStartPrepare:)]) {
        [self.operationDelegate videoViewWillStartPrepare:self];
    }
    WeakSelf;
    [asset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            StrongSelf;

            strongSelf.isVideoUrlChanged = NO;
            strongSelf.isVideoUrlPrepared = YES;
            
            if (asset != strongSelf.asset) {
                return;
            }

            NSError *error = nil;
            if ([asset statusOfValueForKey:@"playable" error:&error] == AVKeyValueStatusFailed) {
                if ([strongSelf.operationDelegate respondsToSelector:@selector(videoViewDidFailPrepare:error:)]) {
                    [strongSelf.operationDelegate videoViewDidFailPrepare:strongSelf error:error];
                }
                return;
            }
            
            strongSelf.playerItem = [AVPlayerItem playerItemWithAsset:strongSelf.asset];

            if ([strongSelf.operationDelegate respondsToSelector:@selector(videoViewDidFinishPrepare:)]) {
                [strongSelf.operationDelegate videoViewDidFinishPrepare:strongSelf];
            }
            
            if (strongSelf.shouldPlayAfterPrepareFinished || strongSelf.isPreparedForPlay) {
                strongSelf.isPreparedForPlay = NO;
                [strongSelf play];
            }
            
        });
    }];
}

#pragma mark - KVO
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    if (context != &kCTVideoViewKVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    if ([keyPath isEqualToString:kCTVideoViewKVOKeyPathPlayerItemStatus]) {
        NSNumber *newStatusAsNumber = change[NSKeyValueChangeNewKey];
        AVPlayerItemStatus newStatus = [newStatusAsNumber isKindOfClass:[NSNumber class]] ? newStatusAsNumber.integerValue : AVPlayerItemStatusUnknown;

        if (newStatus == AVPlayerItemStatusFailed) {
            NSLog(@"%@", self.player.currentItem.error);
        }
    }
}

#pragma mark - getters and setters
- (AVPlayerLayer *)playerLayer
{
    return (AVPlayerLayer *)self.layer;
}

- (void)setIsMuted:(BOOL)isMuted
{
    self.player.muted = isMuted;
}

- (BOOL)isMuted
{
    return self.player.muted;
}

- (BOOL)shouldPlayRemoteVideoWhenNotWifi
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kCTVideoViewShouldPlayRemoteVideoWhenNotWifi];
}

- (void)setVideoUrl:(NSURL *)videoUrl
{
    if (_videoUrl && [_videoUrl isEqual:videoUrl]) {
        self.isVideoUrlChanged = NO;
    } else {
        self.isVideoUrlPrepared = NO;
        self.isVideoUrlChanged = YES;
    }

    _videoUrl = videoUrl;
    self.actualVideoPlayingUrl = videoUrl;
    
    if ([[videoUrl pathExtension] isEqualToString:@"m3u8"]) {
#warning todo check whether has downloaded this url, and set to actual video url
        self.videoUrlType = CTVideoViewVideoUrlTypeLiveStream;
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:[videoUrl path]]) {
        self.videoUrlType = CTVideoViewVideoUrlTypeNative;
    } else {
#warning todo check whether has downloaded this url, and set to actual video url
        self.videoUrlType = CTVideoViewVideoUrlTypeRemote;
    }

    self.asset = [AVURLAsset assetWithURL:self.actualVideoPlayingUrl];
}

- (void)setPlayerItem:(AVPlayerItem *)playerItem
{
    if (_playerItem != playerItem) {
        _playerItem = playerItem;
        [self.player replaceCurrentItemWithPlayerItem:_playerItem];
    }
}

- (BOOL)isPlaying
{
    return self.player.rate >= 1.0;
}

- (AVPlayer *)player
{
    if (_player == nil) {
        _player = [[AVPlayer alloc] init];
    }
    return _player;
}

@end