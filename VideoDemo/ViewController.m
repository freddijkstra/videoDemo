//
//  ViewController.m
//  VideoDemo
//
//  Created by Fred Dijkstra on 21/09/15.
//  Copyright © 2015 Computerguided B.V. All rights reserved.
//

@import Photos;

#import "ViewController.h"
#import "PlayerView.h"

#import <AssetsLibrary/AssetsLibrary.h>


// Define this constant for the key-value observation context.
static const NSString *ItemStatusContext;

@interface ViewController () <SloMoVideoCaptureManagerDelegate>

@end

@implementation ViewController
{
    uint64_t _frameCnt;
    BOOL     _playing;
    BOOL	 _scrubInFlight; // Indicates whether the UI is updating the scrubber.
    float	 _lastScrubSliderValue;
    float	 _playRateToRestore;
}

// ----------------------------------------------------------------------------------------------------

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Create the slow-motion video capture manager.
    self.captureManager = [[SloMoVideoCaptureManager alloc] initWithPreviewView:self.previewView];
    
    self.captureManager.delegate = self;
    
    // Fix the orientation.
    [self.captureManager updateOrientationWithPreviewView:self.previewView];
    
    // Preset frame rate.
    [self.captureManager switchFormatWithDesiredFPS:120];
}

// ----------------------------------------------------------------------------------------------------

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// ----------------------------------------------------------------------------------------------------
// Configure the file URL for the movie to point the documents directory of the App.
// ----------------------------------------------------------------------------------------------------
- (void) configureFileURL
{
    NSString *documentsDirectory = [NSHomeDirectory()
                                    stringByAppendingPathComponent:@"Documents"];
    NSLog(@"Documents directory: %@",documentsDirectory);
    
    NSString *outputFileName = @"recording";
    NSString *outputFilePath = [documentsDirectory stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
    
    self.fileURL = [NSURL fileURLWithPath:outputFilePath];
    
    
    // Delete the file when it already exists
    
    NSFileManager *manager = [[NSFileManager alloc] init];
    if ([manager fileExistsAtPath:self.fileURL.path] )
    {
        NSError *fileError;
        [manager removeItemAtPath:self.fileURL.path error:&fileError];
        if (fileError) NSLog(@"%@", fileError.localizedDescription);
    }
    
}


// ----------------------------------------------------------------------------------------------------
// Create preview layer
// ----------------------------------------------------------------------------------------------------
- (void) createPreviewLayer
{
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    [self.previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    CALayer *rootLayer = [self.previewView layer];
    [rootLayer setMasksToBounds:YES];
    [self.previewLayer setFrame:[rootLayer bounds]];
    [rootLayer addSublayer:self.previewLayer];
    
    // Set the correct orientation.
    self.previewLayer.connection.videoOrientation = UIDeviceOrientationLandscapeLeft;
}


// ----------------------------------------------------------------------------------------------------
// Authorize video recording
// ----------------------------------------------------------------------------------------------------
- (void) authorizeVideoRecording
{
    // Check video authorization status.
    switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] )
    {
        case AVAuthorizationStatusAuthorized:
        {
            // The user has previously granted access to the camera.
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            // The user has not yet been presented with the option to grant video access.
            // We suspend the session queue to delay session setup until the access request has completed to avoid
            // asking the user for audio access if video access is denied.
            // Note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup.
            dispatch_suspend( self.sessionQueue );
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                if ( ! granted ) {
                    self.setupResult = AVCamSetupResultCameraNotAuthorized;
                }
                dispatch_resume( self.sessionQueue );
            }];
            break;
        }
        default:
        {
            // The user has previously denied access.
            self.setupResult = AVCamSetupResultCameraNotAuthorized;
            break;
        }
    }
}

// ----------------------------------------------------------------------------------------------------
// Update the play button depending on the status of the player.
// ----------------------------------------------------------------------------------------------------
- (void) updatePlayButton
{
    if ((self.player.currentItem != nil) &&
        ([self.player.currentItem status] == AVPlayerItemStatusReadyToPlay))
    {
        self.playButton.enabled = YES;
    }
    else
    {
        self.playButton.enabled = NO;
    }
}

// ====================================================================================================
// ---- Event handlers ----
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Toggle movie recording
// ----------------------------------------------------------------------------------------------------

- (IBAction)toggleMovieRecording:(id)sender
{
    // REC START
    
    if (!self.captureManager.isRecording)
    {
        // change UI
        [self.recordButton setTitle:@"Stop" forState:UIControlStateNormal];
        
        [self.captureManager startRecording];
    }
    // REC STOP
    else
    {
        [self.captureManager stopRecording];
        
        // change UI
        [self.recordButton setTitle:@"Record" forState:UIControlStateNormal];
    }
}

// ----------------------------------------------------------------------------------------------------
// Toggle movie playback
// ----------------------------------------------------------------------------------------------------
- (IBAction)togglePlayPause:(id)sender
{
    _playing = !_playing;
    if ( _playing )
    {
        [self.player seekToTime:kCMTimeZero];
        [self.player play];
    }
    else
    {
        [self.player pause];
    }
}

// ----------------------------------------------------------------------------------------------------
// Load the recorded movie.
// ----------------------------------------------------------------------------------------------------
- (IBAction)loadFile:(id)sender
{
    // Create the asset.
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:self.fileURL options:nil];
    
    NSString *tracksKey = @"tracks";
    [asset loadValuesAsynchronouslyForKeys:@[tracksKey] completionHandler:
     ^{
         dispatch_async(dispatch_get_main_queue(),
        ^{
            NSError *error;
            AVKeyValueStatus status = [asset statusOfValueForKey:tracksKey error:&error];
            
            if( status == AVKeyValueStatusLoaded )
            {
                self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
                
                [self.playerItem addObserver:self forKeyPath:@"status"
                    options:NSKeyValueObservingOptionInitial context:&ItemStatusContext];
                
                [[NSNotificationCenter defaultCenter]
                    addObserver:self
                    selector:@selector(playerItemDidReachEnd:)
                    name:AVPlayerItemDidPlayToEndTimeNotification
                    object:self.playerItem];
                
                self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
                [self.playerView setPlayer:self.player];
            }
            else
            {
                // TODO: handle error appropriately.
                NSLog(@"The asset's tracks were not loaded:\n%@", [error localizedDescription]);
            }
            
         });
     }];
    
    // -- Configure the frame stepper --
    self.frameStepper.value = 0;
    self.frameStepper.maximumValue = self.captureManager.timestampsArray.count-1;
    
    
    self.displayTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                    target:self
                                                  selector:@selector(updateTimeout:)
                                                  userInfo:nil
                                                   repeats:YES];
}

// ----------------------------------------------------------------------------------------------------
- (IBAction)frameStepperChanged:(id)sender
{
    UIStepper *stepper = sender;
    
    NSNumber *dataTimestamp = [self.captureManager.timestampsArray objectAtIndex:(uint32_t)stepper.value];
    
    [self.frameStepLabel setText:[NSString stringWithFormat:@"%d", (int)stepper.value]];
    
    NSLog(@"Time: %f", dataTimestamp.doubleValue);
    
    [self.player seekToTime:CMTimeMakeWithSeconds(dataTimestamp.doubleValue, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

// ----------------------------------------------------------------------------------------------------

- (IBAction)displayRateChanged:(id)sender
{
    UISegmentedControl *segmentControl = sender;
    
    switch (segmentControl.selectedSegmentIndex)
    {
        case 0:
            [self.player setRate:1];
            break;
        case 1:
            [self.player setRate:1/2.0];
            break;
        case 2:
            [self.player setRate:1/10.0];
            break;
        case 3:
            [self.player setRate:1/120.0];
            break;
        case 4:
            [self.player setRate:0];
            break;
    }
}

// ----------------------------------------------------------------------------------------------------

- (IBAction)beginScrubbing:(id)sender
{
    _playRateToRestore = [self.player rate];
    [self.player setRate:0.0];
}

// ----------------------------------------------------------------------------------------------------

- (IBAction)scrub:(id)sender
{
    _lastScrubSliderValue = [self.scrubSlider value];
    
    if ( !_scrubInFlight ) [self scrubToSliderValue:_lastScrubSliderValue];
}

- (void)scrubToSliderValue:(float)sliderValue
{
    double duration = CMTimeGetSeconds([self playerItemDuration]);
    
    if (isfinite(duration))
    {
        double time = duration*sliderValue/100.0f;
        double tolerance = 1.0f * duration / 100.0f;
        
        _scrubInFlight = YES;
        
        [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)
                toleranceBefore:CMTimeMakeWithSeconds(tolerance, NSEC_PER_SEC)
                 toleranceAfter:CMTimeMakeWithSeconds(tolerance, NSEC_PER_SEC)
              completionHandler:^(BOOL finished)
              {
                  _scrubInFlight = NO;
              }];
    }
}

// ----------------------------------------------------------------------------------------------------

- (CMTime)playerItemDuration
{
    AVPlayerItem *playerItem = [self.player currentItem];
    CMTime itemDuration = kCMTimeInvalid;
    
    if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
        itemDuration = [playerItem duration];
    }
    
    /* Will be kCMTimeInvalid if the item is not ready to play. */
    return itemDuration;
}

// ----------------------------------------------------------------------------------------------------

- (IBAction)endScrubbing:(id)sender
{
    if ( _scrubInFlight ) [self scrubToSliderValue:_lastScrubSliderValue];
    
    [self.player setRate:_playRateToRestore];
    _playRateToRestore = 0.f;
}


- (void)saveRecordedFile:(NSURL *)recordedFile
{
    
    self.fileURL = recordedFile;
    
    ///[SVProgressHUD showWithStatus:@"Saving..." maskType:SVProgressHUDMaskTypeGradient];
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        
        ALAssetsLibrary *assetLibrary = [[ALAssetsLibrary alloc] init];
        [assetLibrary writeVideoAtPathToSavedPhotosAlbum:recordedFile
                                         completionBlock:
         ^(NSURL *assetURL, NSError *error) {
             
             dispatch_async(dispatch_get_main_queue(), ^{
                 
                 ///[SVProgressHUD dismiss];
                 
                 NSString *title;
                 NSString *message;
                 
                 if (error != nil) {
                     
                     title = @"Failed to save video";
                     message = [error localizedDescription];
                 }
                 else {
                     title = @"Saved!";
                     message = nil;
                 }
                 
                 UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                                 message:message
                                                                delegate:nil
                                                       cancelButtonTitle:@"OK"
                                                       otherButtonTitles:nil];
                 [alert show];
             });
         }];
    });
}



// ====================================================================================================

- (void)didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL error:(NSError *)error
{

    if (error)
    {
        NSLog(@"error:%@", error);
        return;
    }
    
    [self saveRecordedFile:outputFileURL];
}

// ----------------------------------------------------------------------------------------------------

- (void) didStartRecordingAtSystemTime:(uint64_t)systemTime
{
    
}

// ====================================================================================================

- (void)updateTimeout:(NSTimer *)timer
{
    [self updateUI];
}

// ----------------------------------------------------------------------------------------------------

- (void) updateUI
{
    [self updateTimecode];
    [self updateFrameNumber];
    [self updateScrubber];
}

// ----------------------------------------------------------------------------------------------------

- (void) updateTimecode
{
    float t = CMTimeGetSeconds([self.player currentTime]);
    
    int minutes = (int)(t/60.0f);
    int seconds = (int)(t-minutes*60);
    int milliseconds = 1000*(t - (int)t);
    
    [self.timeCodeLabel setText:[NSString stringWithFormat:@"%d:%.2d.%.3d", minutes, seconds, milliseconds]];
}

// ----------------------------------------------------------------------------------------------------

- (void) updateFrameNumber
{
    float t = CMTimeGetSeconds([self.player currentTime]);
    
    NSNumber *timestamp = [self.captureManager.timestampsArray objectAtIndex:(uint32_t)self.frameStepper.value];
    
    if( t < timestamp.floatValue-0.004 || t > timestamp.floatValue+0.004 )
    {
        // Shift required.
        
        if( timestamp.floatValue < t && (uint32_t)self.frameStepper.value < self.captureManager.timestampsArray.count-1 )
        {
            // -- Seek forward --
            
            while (timestamp.floatValue < t && (uint32_t)self.frameStepper.value < self.captureManager.timestampsArray.count-2)
            {
                self.frameStepper.value = self.frameStepper.value+1;
                
                timestamp = [self.captureManager.timestampsArray objectAtIndex:(uint32_t)self.frameStepper.value];
            }
        }
        else if( (uint32_t)self.frameStepper.value > 0 )
        {
            // -- Seek backward --
            
            while (timestamp.floatValue > t && (uint32_t)self.frameStepper.value > 1)
            {
                self.frameStepper.value = self.frameStepper.value-1;
                timestamp = [self.captureManager.timestampsArray objectAtIndex:(uint32_t)self.frameStepper.value];
            }
        }
        
        [self.frameStepLabel setText:[NSString stringWithFormat:@"%d", (uint32_t)self.frameStepper.value]];
    }
}

// ----------------------------------------------------------------------------------------------------

- (void) updateScrubber
{
    if( !_scrubInFlight )
    {
        double duration = CMTimeGetSeconds([self playerItemDuration]);
        
        if (isfinite(duration))
        {
            double time = CMTimeGetSeconds([self.player currentTime]);
            [self.scrubSlider setValue:100.0f*(time / duration)];
        }
        else
        {
            [self.scrubSlider setValue:0.0];
        }
    }
}

// ====================================================================================================
// ---- Notification handlers ----
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// The complete movie was played.
// ----------------------------------------------------------------------------------------------------
- (void)playerItemDidReachEnd:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(),
    ^{
        [self.player seekToTime:kCMTimeZero];
//        self.frameStepper.value = 0;
//        self.scrubSlider.value = 0;
    });
}

// ----------------------------------------------------------------------------------------------------
// When the player item’s status changes, the view controller receives a key-value observing change
// notification. AV Foundation does not specify what thread that the notification is sent on.
// If you want to update the user interface, you must make sure that any relevant code is invoked on
// the main thread.
// This method uses dispatch_async to queue a message on the main thread to synchronize the
// user interface.
// ----------------------------------------------------------------------------------------------------
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (context == &ItemStatusContext)
    {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           [self updatePlayButton];
                       });
        return;
    }
    
    // Unknown notification.
    [super observeValueForKeyPath:keyPath ofObject:object
                           change:change context:context];
    return;
}

@end

