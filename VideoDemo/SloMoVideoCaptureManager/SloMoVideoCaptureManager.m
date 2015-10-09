//
//  SloMoVideoCaptureManager.m
//  VideoDemo
//
//  Created by Fred Dijkstra on 08/10/15.
//  Copyright © 2015 Computerguided B.V. All rights reserved.
//

#import "SloMoVideoCaptureManager.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

@interface SloMoVideoCaptureManager ()<AVCaptureVideoDataOutputSampleBufferDelegate>
{
    CMTime defaultVideoMaxFrameDuration;
    BOOL readyToRecordVideo;
    AVCaptureVideoOrientation videoOrientation;
    AVCaptureVideoOrientation referenceOrientation;
    dispatch_queue_t movieWritingQueue;
    CMBufferQueueRef previewBufferQueue;
    BOOL recordingWillBeStarted;
}

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDeviceFormat *defaultFormat;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

// For video data output
@property (nonatomic, strong) AVAssetWriter       *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput  *assetWriterVideoInput;
@property (nonatomic, strong) AVCaptureConnection *audioConnection;
@property (nonatomic, strong) AVCaptureConnection *videoConnection;

// Asynch handling
@property          BOOL                 isWaitingForInputReady;
@property (strong) dispatch_semaphore_t writeSemaphore;

@end


@implementation SloMoVideoCaptureManager

// ----------------------------------------------------------------------------------------------------
- (id)initWithPreviewView:(UIView *)previewView
{
    self = [super init];
    
    if (self)
    {
        referenceOrientation = (AVCaptureVideoOrientation)UIDeviceOrientationPortrait;
        
        NSError *error;
        
        // Create the session.
        self.captureSession = [[AVCaptureSession alloc] init];
        self.captureSession.sessionPreset = AVCaptureSessionPresetInputPriority;
        
        // Create the device and the input.
        AVCaptureDevice      *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        AVCaptureDeviceInput *videoIn     = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        
        if (error)
        {
            NSLog(@"Video input creation failed");
            return nil;
        }
        
        if (![self.captureSession canAddInput:videoIn])
        {
            NSLog(@"Video input add-to-session failed");
            return nil;
        }
        [self.captureSession addInput:videoIn];
        
        
        // Save the default format
        self.defaultFormat = videoDevice.activeFormat;
        defaultVideoMaxFrameDuration = videoDevice.activeVideoMaxFrameDuration;
        
        NSLog(@"videoDevice.activeFormat:%@", videoDevice.activeFormat);
        
        [self setPreviewView:previewView];
        
        // Async stuff
        _isWaitingForInputReady = NO;
        _writeSemaphore = dispatch_semaphore_create(0);
        

        // Video
        AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        [self.captureSession addOutput:videoDataOutput];
        
        [videoDataOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        
        // Create the dispatch queue for writing the sample buffers.
        movieWritingQueue = dispatch_queue_create("com.computerguided.movieWritingQueue", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_t videoCaptureQueue = dispatch_queue_create("movieWritingQueue", NULL);
        
        [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
        [videoDataOutput setSampleBufferDelegate:self queue:videoCaptureQueue];
        
        // Create video connection.
        self.videoConnection = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
        videoOrientation = [self.videoConnection videoOrientation];
        

        // BufferQueue
        OSStatus err = CMBufferQueueCreate(kCFAllocatorDefault, 1, CMBufferQueueGetCallbacksForUnsortedSampleBuffers(), &previewBufferQueue);
        NSLog(@"CMBufferQueueCreate error:%d", err);

        
        self.timestampsArray = [[NSMutableArray alloc] initWithCapacity:1200];
        
        [self.captureSession startRunning];
    }
    return self;
}

// ----------------------------------------------------------------------------------------------------
- (void) setPreviewView:(UIView *)previewView
{
    // Set the preview layer.
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
    self.previewLayer.frame = previewView.bounds;
    self.previewLayer.contentsGravity = kCAGravityResizeAspectFill;
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [previewView.layer insertSublayer:self.previewLayer atIndex:0];
}

// ----------------------------------------------------------------------------------------------------
+ (CGFloat)angleOffsetFromPortraitOrientationToOrientation:(AVCaptureVideoOrientation)orientation
{
    CGFloat angle = 0.0;
    
    switch (orientation) {
        case AVCaptureVideoOrientationPortrait:
            angle = 0.0;
            break;
        case AVCaptureVideoOrientationPortraitUpsideDown:
            angle = M_PI;
            break;
        case AVCaptureVideoOrientationLandscapeRight:
            angle = -M_PI_2;
            break;
        case AVCaptureVideoOrientationLandscapeLeft:
            angle = M_PI_2;
            break;
        default:
            break;
    }
    
    return angle;
}

- (CGAffineTransform)transformFromCurrentVideoOrientationToOrientation:(AVCaptureVideoOrientation)orientation
{
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    // Calculate offsets from an arbitrary reference orientation (portrait)
    CGFloat orientationAngleOffset = [SloMoVideoCaptureManager angleOffsetFromPortraitOrientationToOrientation:orientation];
    CGFloat videoOrientationAngleOffset = [SloMoVideoCaptureManager angleOffsetFromPortraitOrientationToOrientation:videoOrientation];
    
    // Find the difference in angle between the passed in orientation and the current video orientation
    CGFloat angleOffset = orientationAngleOffset - videoOrientationAngleOffset;
    transform = CGAffineTransformMakeRotation(angleOffset);
    
    return transform;
}


// ----------------------------------------------------------------------------------------------------

- (BOOL)setupAssetWriterVideoInput:(CMFormatDescriptionRef)currentFormatDescription
{
    float bitsPerPixel;
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(currentFormatDescription);
    int numPixels = dimensions.width * dimensions.height;
    int bitsPerSecond;
    
    // Assume that lower-than-SD resolutions are intended for streaming, and use a lower bitrate
    if ( numPixels < (640 * 480) )
    {
        bitsPerPixel = 4.05; // This bitrate matches the quality produced by AVCaptureSessionPresetMedium or Low.
    }
    else
    {
        bitsPerPixel = 11.4; // This bitrate matches the quality produced by AVCaptureSessionPresetHigh.
    }
    
    bitsPerSecond = numPixels * bitsPerPixel;
    
    NSDictionary *videoCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                              AVVideoCodecH264, AVVideoCodecKey,
                                              [NSNumber numberWithInteger:dimensions.width], AVVideoWidthKey,
                                              [NSNumber numberWithInteger:dimensions.height], AVVideoHeightKey,
                                              [NSDictionary dictionaryWithObjectsAndKeys:
                                               [NSNumber numberWithInteger:bitsPerSecond], AVVideoAverageBitRateKey,
                                               [NSNumber numberWithInteger:30], AVVideoMaxKeyFrameIntervalKey,
                                               nil], AVVideoCompressionPropertiesKey,
                                              nil];
    
    NSLog(@"videoCompressionSetting:%@", videoCompressionSettings);
    
    if ([self.assetWriter canApplyOutputSettings:videoCompressionSettings forMediaType:AVMediaTypeVideo])
    {
        self.assetWriterVideoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                                    outputSettings:videoCompressionSettings];
        
        self.assetWriterVideoInput.expectsMediaDataInRealTime = YES;
        self.assetWriterVideoInput.transform = [self transformFromCurrentVideoOrientationToOrientation:referenceOrientation];
        
        // -- Add an observer for the readyForMoreData --
        _isWaitingForInputReady = NO;
        
        [self.assetWriterVideoInput addObserver:self forKeyPath:@"readyForMoreMediaData" options:0 context:nil];
        
        
        
        if ([self.assetWriter canAddInput:self.assetWriterVideoInput])
        {
            [self.assetWriter addInput:self.assetWriterVideoInput];
        }
        else
        {
            NSLog(@"Couldn't add asset writer video input.");
            return NO;
        }
    }
    else
    {
        NSLog(@"Couldn't apply video output settings.");
        return NO;
    }
    
    return YES;
}

// ----------------------------------------------------------------------------------------------------

- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType
{
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    if (self.assetWriter.status == AVAssetWriterStatusUnknown)
    {
        if ([self.assetWriter startWriting])
        {
            [self.assetWriter startSessionAtSourceTime:timestamp];
        }
        else
        {
            NSLog(@"AVAssetWriter startWriting error:%@", self.assetWriter.error);
        }
    }
    
    if (self.assetWriter.status == AVAssetWriterStatusWriting)
    {

        if (!self.assetWriterVideoInput.isReadyForMoreMediaData)
        {
            // Wait for it...
            _isWaitingForInputReady = YES;
            dispatch_semaphore_wait(_writeSemaphore, DISPATCH_TIME_FOREVER);
        }
        
        if (self.assetWriterVideoInput.readyForMoreMediaData)
        {
            if (![self.assetWriterVideoInput appendSampleBuffer:sampleBuffer])
            {
                NSLog(@"isRecording:%d, willBeStarted:%d", self.isRecording, recordingWillBeStarted);
                NSLog(@"AVAssetWriterInput video appendSapleBuffer error:%@", self.assetWriter.error);
            }
            
            
            // Save the  timestamp of the sample.
            NSNumber *timestampObject = [[NSNumber alloc] initWithDouble:(double)timestamp.value/(double)timestamp.timescale];
            [self.timestampsArray addObject:timestampObject];
        }
        else
        {
            CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            NSLog(@"NOT READY, timestamp:%@",CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, timestamp)));
        }
    }
}


// =============================================================================
#pragma mark - Public

- (void)toggleContentsGravity
{
    
    if ([self.previewLayer.videoGravity isEqualToString:AVLayerVideoGravityResizeAspectFill])
    {
        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    }
    else
    {
        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    }
}

// ----------------------------------------------------------------------------------------------------

- (void)resetFormat
{
    BOOL isRunning = self.captureSession.isRunning;
    
    if (isRunning)
    {
        [self.captureSession stopRunning];
    }
    
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [videoDevice lockForConfiguration:nil];
    videoDevice.activeFormat = self.defaultFormat;
    videoDevice.activeVideoMaxFrameDuration = defaultVideoMaxFrameDuration;
    [videoDevice unlockForConfiguration];
    
    if (isRunning)
    {
        [self.captureSession startRunning];
    }
}

// ----------------------------------------------------------------------------------------------------

- (void)switchFormatWithDesiredFPS:(CGFloat)desiredFPS
{
    BOOL isRunning = self.captureSession.isRunning;
    
    if (isRunning)  [self.captureSession stopRunning];
    
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceFormat *selectedFormat = nil;
    int32_t maxWidth = 0;
    AVFrameRateRange *frameRateRange = nil;
    
    for (AVCaptureDeviceFormat *format in [videoDevice formats])
    {
        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges)
        {
            CMFormatDescriptionRef desc = format.formatDescription;
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);
            int32_t width = dimensions.width;
            
            if (range.minFrameRate <= desiredFPS && desiredFPS <= range.maxFrameRate && width >= maxWidth)
            {
                selectedFormat = format;
                frameRateRange = range;
                maxWidth = width;
            }
        }
    }
    
    if (selectedFormat)
    {
        if ([videoDevice lockForConfiguration:nil])
        {
            NSLog(@"selected format:%@", selectedFormat);
            videoDevice.activeFormat = selectedFormat;
            videoDevice.activeVideoMinFrameDuration = CMTimeMake(1, (int32_t)desiredFPS);
            videoDevice.activeVideoMaxFrameDuration = CMTimeMake(1, (int32_t)desiredFPS);
            [videoDevice unlockForConfiguration];
        }
    }
    
    if (isRunning) [self.captureSession startRunning];
}

// ----------------------------------------------------------------------------------------------------

- (void)startRecording
{
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HH-mm-ss"];
    NSString* dateTimePrefix = [formatter stringFromDate:[NSDate date]];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
        
    dispatch_async(movieWritingQueue, ^{
        
        UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
        
        // Don't update the reference orientation when the device orientation is face up/down or unknown.
        if (UIDeviceOrientationIsPortrait(orientation) || UIDeviceOrientationIsLandscape(orientation))
        {
            referenceOrientation = (AVCaptureVideoOrientation)orientation;
        }
        
        int fileNamePostfix = 0;
        NSString *filePath = nil;
        
        do
            filePath =[NSString stringWithFormat:@"/%@/%@-%i.MOV", documentsDirectory, dateTimePrefix, fileNamePostfix++];
        while ([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
        
        self.fileURL = [NSURL URLWithString:[@"file://" stringByAppendingString:filePath]];
        
        NSError *error;
        self.assetWriter = [[AVAssetWriter alloc] initWithURL:self.fileURL
                                                     fileType:AVFileTypeQuickTimeMovie
                                                        error:&error];
        NSLog(@"AVAssetWriter error:%@", error);
        
        recordingWillBeStarted = YES;
    });
}

// ----------------------------------------------------------------------------------------------------

- (void)stopRecording
{
    dispatch_async(movieWritingQueue, ^{
        
        _isRecording = NO;
        readyToRecordVideo = NO;
        
        [self.assetWriter finishWritingWithCompletionHandler:^{
            
            // Remove observer
            [self.assetWriterVideoInput removeObserver:self forKeyPath:@"readyForMoreMediaData"];
            
            self.assetWriterVideoInput = nil;
            self.assetWriter = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                if ([self.delegate respondsToSelector:@selector(didFinishRecordingToOutputFileAtURL:error:)])
                {
                    [self.delegate didFinishRecordingToOutputFileAtURL:self.fileURL error:nil];
                }
            });
        }];
        
        double currentTimestamp = ((NSNumber*)self.timestampsArray.firstObject).doubleValue;
        for(NSNumber *timestamp in self.timestampsArray )
        {
            NSLog(@"Frame timestep: %lf, step: %lf", timestamp.doubleValue, timestamp.doubleValue - currentTimestamp );
            currentTimestamp = timestamp.doubleValue;
        }
        
        [self.timestampsArray removeAllObjects];
        
    });
}

// ----------------------------------------------------------------------------------------------------

- (void)updateOrientationWithPreviewView:(UIView *)previewView
{
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    // Don't update the reference orientation when the device orientation is face up/down or unknown.
    if (UIDeviceOrientationIsPortrait(orientation) || UIDeviceOrientationIsLandscape(orientation))
    {
        referenceOrientation = (AVCaptureVideoOrientation)orientation;
    }
    
    self.previewLayer.frame = previewView.bounds;
    
    [[self.previewLayer connection] setVideoOrientation:self.videoConnection.videoOrientation];
    
    readyToRecordVideo = NO;
}

// =============================================================================
#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    CFRetain(sampleBuffer); // Retrain the buffer for the asynchroneous block.
    
    dispatch_async(movieWritingQueue, ^{
        
        if (self.assetWriter && (self.isRecording || recordingWillBeStarted))
        {
            BOOL wasReadyToRecord = readyToRecordVideo;
            
            if (connection == self.videoConnection)
            {
                // Initialize the video input if this is not done yet
                if (!readyToRecordVideo)
                {
                    readyToRecordVideo = [self setupAssetWriterVideoInput:formatDescription];
                }
                
                // Write video data to file
                if (readyToRecordVideo)
                {
                    [self writeSampleBuffer:sampleBuffer ofType:AVMediaTypeVideo];
                }
            }
            
            if (!wasReadyToRecord && readyToRecordVideo)
            {
                recordingWillBeStarted = NO;
                _isRecording = YES;
            }
        }
        CFRelease(sampleBuffer);
    });
}

// =============================================================================

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"readyForMoreMediaData"])
    {
        if (_isWaitingForInputReady && self.assetWriterVideoInput.isReadyForMoreMediaData)
        {
            _isWaitingForInputReady = NO;
            dispatch_semaphore_signal(_writeSemaphore);
        }
    }
}


@end
