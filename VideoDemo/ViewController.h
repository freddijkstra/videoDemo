//
//  ViewController.h
//  VideoDemo
//
//  Created by Fred Dijkstra on 21/09/15.
//  Copyright © 2015 Computerguided B.V. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#import "SloMoVideoCaptureManager.h"

@class PlayerView;

typedef NS_ENUM( NSInteger, AVCamSetupResult )
{
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};

@interface ViewController : UIViewController

@property (nonatomic, strong) SloMoVideoCaptureManager *captureManager;


@property (nonatomic) AVPlayer *player;
@property (nonatomic) AVPlayerItem *playerItem;


// -- For use in the storyboards --

// Recording
@property (weak, nonatomic) IBOutlet UIButton *recordButton;
@property (weak, nonatomic) IBOutlet UILabel  *frameCntLabel;
@property (weak, nonatomic) IBOutlet UIView   *previewView;

// Playback
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet PlayerView *playerView;

// Session management.
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;

// Video I/O
//@property (nonatomic) AVCaptureDevice          *videoDevice;
//@property (nonatomic) AVCaptureDeviceInput     *videoDeviceInput;
//@property (nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
//@property (nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
//
//@property (nonatomic, strong) AVAssetWriter *assetWriter;
//@property (nonatomic, strong) AVAssetWriterInput *assetWriterInput;


// Preview
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;

// Utilities.
@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

// File management
@property (nonatomic) NSURL *fileURL;

// ----------------------------------------------------------------------------------------------------
// Event handlers
// ----------------------------------------------------------------------------------------------------
- (IBAction)toggleMovieRecording:(id)sender;
- (IBAction)togglePlayPause:(id)sender;
- (IBAction)loadFile:(id)sender;
- (IBAction)playSpeedSliderValueChanged:(id)sender;

// ----------------------------------------------------------------------------------------------------
// Notification handlers
// ----------------------------------------------------------------------------------------------------
- (void) playerItemDidReachEnd:(NSNotification *)notification;

// ----------------------------------------------------------------------------------------------------
// Methods
// ----------------------------------------------------------------------------------------------------

- (void) configureFileURL;
- (void) createSession;
- (void) addInputDevice;
- (void) setupVideoCapture;
- (void) createPreviewLayer;
- (void) createAssetWriter;
- (void) authorizeVideoRecording;
- (void) setupMovieFileOutput;
- (void) configureCameraForHighestFrameRate:(AVCaptureDevice *)device;

- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;

- (void) updatePlayButton;

@end

