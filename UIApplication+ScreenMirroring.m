//  
//  UIApplication+ScreenMirroring.m
//  Created by Francois Proulx on 10-04-17.
//  
//  Copyright (c) 2010 Francois Proulx.  All rights reserved.
//  All rights reserved.
//  
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions
//  are met:
//  1. Redistributions of source code must retain the above copyright
//     notice, this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer in the
//     documentation and/or other materials provided with the distribution.
//  
//  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
//  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
//  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
//  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "UIApplication+ScreenMirroring.h"

#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

#define CORE_ANIMATION_MAX_FRAMES_PER_SECOND (60)

CGImageRef UIGetScreenImage(); // Not so private API anymore

static CFTimeInterval startTime = 0;
static NSUInteger frames = 0;

@interface UIApplication(ScreenMirroringPrivate)

- (void) setupMirroringForScreen:(UIScreen *)anExternalScreen;
- (void) disableMirroringOnCurrentScreen;
- (void) updateMirroredScreenOnTimer;

@end

@implementation UIApplication (ScreenMirroring)

static double targetFramesPerSecond = 0;
static CADisplayLink *displayLink = nil;
static UIScreen *mirroredScreen = nil;
static UIWindow *mirroredScreenWindow = nil;
static UIImageView *mirroredImageView = nil;

- (void) setupScreenMirroring
{
	[self setupScreenMirroringWithFramesPerSecond:ScreenMirroringDefaultFramesPerSecond];
}

- (void) setupScreenMirroringWithFramesPerSecond:(double)fps
{
	// Set the desired frame rate
	targetFramesPerSecond = fps;

	// Subscribe to screen notifications
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(screenDidConnect:) name:UIScreenDidConnectNotification object:nil]; 
	[center addObserver:self selector:@selector(screenDidDisconnect:) name:UIScreenDidDisconnectNotification object:nil]; 
	[center addObserver:self selector:@selector(screenModeDidChange:) name:UIScreenModeDidChangeNotification object:nil]; 
	
	// Setup screen mirroring for an existing screen
	NSArray *connectedScreens = [UIScreen screens];
	if ([connectedScreens count] > 1) {
		UIScreen *mainScreen = [UIScreen mainScreen];
		for (UIScreen *aScreen in connectedScreens) {
			if (aScreen != mainScreen) {
				// We've found an external screen !
				[self setupMirroringForScreen:aScreen];
				break;
			}
		}
	}
}

- (void) disableScreenMirroring
{
	// Subscribe to screen notifications
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center removeObserver:self name:UIScreenDidConnectNotification object:nil];
	[center removeObserver:self name:UIScreenDidDisconnectNotification object:nil];
	[center removeObserver:self name:UIScreenModeDidChangeNotification object:nil];
	
	// Remove mirroring
	[self disableMirroringOnCurrentScreen];
}

#pragma mark -
#pragma mark UIScreen notifications

- (void) screenDidConnect:(NSNotification *)aNotification
{
	NSLog(@"A new screen got connected: %@", [aNotification object]);
	[self setupMirroringForScreen:[aNotification object]];
}

- (void) screenDidDisconnect:(NSNotification *)aNotification
{
	NSLog(@"A screen got disconnected: %@", [aNotification object]);
	[self disableMirroringOnCurrentScreen];
}

- (void) screenModeDidChange:(NSNotification *)aNotification
{
	UIScreen *someScreen = [aNotification object];
	NSLog(@"The screen mode for a screen did change: %@", [someScreen currentMode]);
	
	// Disable, then reenable with new config
	[self disableMirroringOnCurrentScreen];
	[self setupMirroringForScreen:[aNotification object]];
}

#pragma mark -
#pragma mark Screen mirroring

- (void) setupMirroringForScreen:(UIScreen *)anExternalScreen
{       
	// Reset timer
	startTime = CFAbsoluteTimeGetCurrent();
	frames = 0;
	
	// Set the new screen to mirror
	BOOL done = NO;
	UIScreenMode *mainScreenMode = [UIScreen mainScreen].currentMode;
	for (UIScreenMode *externalScreenMode in anExternalScreen.availableModes) {
		if (CGSizeEqualToSize(externalScreenMode.size, mainScreenMode.size)) {
			// Select a screen that matches the main screen
			anExternalScreen.currentMode = externalScreenMode;
			done = YES;
			break;
		}
	}
	
	if (!done && [anExternalScreen.availableModes count]) {
		anExternalScreen.currentMode = [anExternalScreen.availableModes objectAtIndex:0];
	}
	
	[mirroredScreen release];
	mirroredScreen = [anExternalScreen retain];
	
	// Setup window in external screen
//	UIWindow *newWindow = [[UIWindow alloc] initWithFrame:mirroredScreen.bounds];
//	newWindow.opaque = YES;
//	newWindow.backgroundColor = [UIColor blackColor];
//	
//	UIImageView *newMirroredImageView = [[UIImageView alloc] initWithFrame:mirroredScreen.bounds];
//	newMirroredImageView.contentMode = UIViewContentModeScaleAspectFit;
//	newMirroredImageView.opaque = YES;
//	newMirroredImageView.backgroundColor = [UIColor blackColor];
//	[newWindow addSubview:newMirroredImageView];
//	[mirroredImageView release];
//	mirroredImageView = [newMirroredImageView retain];
//	[newMirroredImageView release];
//	
//	[mirroredScreenWindow release];
//	mirroredScreenWindow = [newWindow retain];
//	mirroredScreenWindow.screen = mirroredScreen;
//	[newWindow makeKeyAndVisible];
//	[newWindow release];
	
	UIWindow *newWindow = [[UIWindow alloc] initWithFrame:mirroredScreen.bounds];
	newWindow.opaque = YES;
	newWindow.hidden = NO;
	newWindow.backgroundColor = [UIColor blackColor];
	newWindow.layer.contentsGravity = kCAGravityResizeAspect;
	[mirroredScreenWindow release];
	mirroredScreenWindow = [newWindow retain];
	mirroredScreenWindow.screen = mirroredScreen;
	[newWindow release];
	
	// Setup periodic callbacks
	[displayLink invalidate];
	[displayLink release], displayLink = nil;
	
	displayLink = [[CADisplayLink displayLinkWithTarget:self selector:@selector(updateMirroredScreenOnTimer)] retain];
	[displayLink setFrameInterval:(targetFramesPerSecond >= CORE_ANIMATION_MAX_FRAMES_PER_SECOND) ? 1 : (CORE_ANIMATION_MAX_FRAMES_PER_SECOND / targetFramesPerSecond)];
	[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void) disableMirroringOnCurrentScreen
{
	[displayLink invalidate];
	[displayLink release], displayLink = nil;
	
	[mirroredScreen release], mirroredScreen = nil;
	[mirroredScreenWindow release], mirroredScreenWindow = nil;
	[mirroredImageView release], mirroredImageView = nil;
}

- (void) updateMirroredScreenOnTimer
{
	// Part of this code inspired by http://gist.github.com/119128
	// Get a screenshot of the main window
	CGImageRef mainWindowScreenshot = UIGetScreenImage();
	if (mainWindowScreenshot) {
//		UIImage *image = [[UIImage alloc] initWithCGImage:mainWindowScreenshot];
//		CFRelease(mainWindowScreenshot); // UIGetScreenImage does NOT respect retain / release semantics
//		
//		// Rotate the screenshot to match screen orientation
//		if (self.statusBarOrientation == UIInterfaceOrientationPortrait) {
//			mirroredImageView.transform = CGAffineTransformIdentity;
//		} else if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationLandscapeLeft) {
//			mirroredImageView.transform = CGAffineTransformMakeRotation(M_PI / 2);
//		} else if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationLandscapeRight) {
//			mirroredImageView.transform = CGAffineTransformMakeRotation(-M_PI / 2);
//		} else if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortraitUpsideDown) {
//			mirroredImageView.transform = CGAffineTransformMakeRotation(M_PI);
//		}
//		
//		// Output mirrored image to seconday screen
//		mirroredImageView.image = image;
//		[image release];
		
		// Grab the secondary window layer
		CALayer *mirrorLayer = mirroredScreenWindow.layer;
		
		// Copy to secondary screen
		mirrorLayer.contents = (id) mainWindowScreenshot;
		
		// Rotate the screenshot to match screen orientation
		if (self.statusBarOrientation == UIInterfaceOrientationPortrait) {
			mirrorLayer.transform = CATransform3DIdentity;
		} else if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationLandscapeLeft) {
			mirrorLayer.transform = CATransform3DMakeRotation(M_PI / 2, 0.0f, 0.0f, 1.0f);
		} else if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationLandscapeRight) {
			mirrorLayer.transform = CATransform3DMakeRotation(-(M_PI / 2), 0.0f, 0.0f, 1.0f);
		} else if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortraitUpsideDown) {
			mirrorLayer.transform = CATransform3DMakeRotation(M_PI, 0.0f, 0.0f, 1.0f);
		}
	}
}

@end
