//
//  PlayerView.h
//  VideoDemo
//
//  Created by Fred Dijkstra on 06/10/15.
//  Copyright © 2015 Computerguided B.V. All rights reserved.
//


// To play the visual component of an asset, a subclass of UIView
// is defined, containing an AVPlayerLayer layer
// to which the output of an AVPlayer object can be directed.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface PlayerView : UIView

@property (nonatomic) AVPlayer *player;

- (void)setPlayer:(AVPlayer *)player;

@end
