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

                
                
                for (AVPlayerItemTrack *track in self.playerItem.tracks)
                {
                    if ([track.assetTrack.mediaType isEqual:AVMediaTypeAudio])
                    {
                        track.enabled = NO;
                    }
                }

                
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
}

- (IBAction)playSpeedSliderValueChanged:(id)sender
{
    UISlider *slider = sender;
    
    if( self.playerItem.canPlaySlowForward)
    {
        [self.player setRate:slider.value/100];
    }
    else
    {
        NSLog(@"Cannot play slow forward");
    }
    
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



// ====================================================================================================
// ---- Notification handlers ----
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// The complete movie was played.
// ----------------------------------------------------------------------------------------------------
- (void)playerItemDidReachEnd:(NSNotification *)notification
{
    [self.player seekToTime:kCMTimeZero];
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

