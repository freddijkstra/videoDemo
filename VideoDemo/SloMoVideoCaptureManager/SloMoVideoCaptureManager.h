//
//  SloMoVideoCaptureManager.h
//  VideoDemo
//
//  Created by Fred Dijkstra on 08/10/15.
//  Copyright © 2015 Computerguided B.V. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>


@protocol SloMoVideoCaptureManagerDelegate <NSObject>
- (void) didStartRecordingAtSystemTime:(uint64_t)systemTime;
- (void) didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL error:(NSError *)error;
@end


@interface SloMoVideoCaptureManager : NSObject

@property (nonatomic, assign) id<SloMoVideoCaptureManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL isRecording;

@property (nonatomic) NSMutableArray *timestampsArray; // Array of NSNumbers.
@property (nonatomic) Float64 startTime;

// -- Public methods --
- (id)  initWithPreviewView:(UIView *)previewView;
- (void)setPreviewView:(UIView *)previewView;
- (void)toggleContentsGravity;
- (void)resetFormat;
- (void)switchFormatWithDesiredFPS:(CGFloat)desiredFPS;
- (void)startRecording;
- (void)stopRecording;
- (void)updateOrientationWithPreviewView:(UIView *)previewView;

@end
