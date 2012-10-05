This is a fork of `JMImageCache` with a few key differences:
 * It uses `NSOperations` for remote downloads, which prevents the number of threads from exploding when you are downloading many images. 
 * It makes reading from disk asynchronous (not just writing), which improves scrolling performance when there are many images.
 * It uses [`CBOperationStack`](https://github.com/cbrauchli/CBOperationStack) to execute the download and disk read `NSOperations`, which means they get executed in a Last In, First Out (LIFO) order. For most cases, this more desirable than FIFO order, since the most recently added image to the download queue is generally the most likely to still be on screen.

# JMImageCache

## Introduction

`JMImageCache` is an `NSCache` based remote-image caching mechanism for iOS projects.

## Screenshots (Demo App)

<center><img src="http://cl.ly/IHSG/iOS%20Simulator%20Screen%20shot%20Jul%2023,%202012%208.25.33%20PM.png" title="UITableView Loading Images" width="320" /></center>

## How It Works (Logically)

There are three states an image can be in:

*  Cached In Memory
*  Cached On Disk
*  Not Cached
	
If an image is requested from cache, and it has never been cached, it is downloaded, stored on disk, put into memory and returned via a delegate callback.

If an image is requested from cache, and it has been cached, but hasn't been requested this session, it is read from disk, brought into memory and returned immediately.

If an image is requested from cache, and it has been cached and it is already in memory, it is simply returned immediately.

The idea behind `JMImageCache` is to always return images the **fastest** way possible, thus the in-memory caching. Reading from disk can be expensive, and should only be done if it has to be.

## How It Works (Code)

The clean and easy way (uses a category that `JMImageCache` adds to `UIImageView`):

``` objective-c
[cell.imageView setImageWithURL:[NSURL URLWithString:@"http://dundermifflin.com/i/MichaelScott.png"]
                        placeholder:[UIImage imageNamed:@"placeholder.png"]];
```

Request an image like so:

``` objective-c
[[JMImageCache sharedCache] imageForURL:[NSURL URLWithString:@"http://dundermifflin.com/i/MichaelScott.png"] completionBlock:^(UIImage *downloadedImage) {
	someImageView.image = downloadedImage;
}];
```

If you need more control all the methods allow to specify the key of an image. 
This can be used to keep track of different images associated with the same url (e.g. different border radius).
This can also be used to access an image that might have been downloaded in situations where the url is not readily available.

``` objective-c
[cell.imageView setImageWithURL:urlWhichMightBeNil
                            key:@"$ImageKey"
                    placeholder:[UIImage imageNamed:@"placeholder.png"]];
```

## Clearing The Cache

The beauty of building on top of `NSCache` is that` JMImageCache` handles low memory situations gracefully. It will evict objects on its own when memory gets tight, you don't need to worry about it.

However, if you really need to, clearing the cache manually is this simple:
	
``` objective-c
[[JMImageCache sharedCache] removeAllObjects];
```
	
If you'd like to remove a specific image from the cache, you can do this:

``` objective-c
[[JMImageCache sharedCache] removeImageForURL:@"http://dundermifflin.com/i/MichaelScott.png"];
```

##Demo App

This repository is actually a demo project itself. Just a simple `UITableViewController` app that loads a few images. Nothing too fancy, but it should give you a good idea of a standard usage of `JMImageCache`.

## Adding To Your Project

[Download](https://github.com/jakemarsh/JMImageCache/zipball/master) the source files or add it as a [git submodule](http://schacon.github.com/git/user-manual.html#submodules). Here's how to add it as a submodule:

    $ cd YourProject
    $ git submodule add https://github.com/jakemarsh/JMImageCache.git Vendor/JMImageCache

Add the 6 Objective-C files inside the `JMImageCache` folder to your project. `#import "JMImageCache.h" where you need it.`

## ARC (Automatic Reference Counting)

`JMImageCache` uses [Automatic Reference Counting (ARC)](http://clang.llvm.org/docs/AutomaticReferenceCounting.html). If your project doesn't use ARC, you will need to set the `-fobjc-arc` compiler flag on all of the `JMImageCache` source files. To do this in Xcode, go to your active target and select the "Build Phases" tab. In the "Compiler Flags" column, set `-fobjc-arc` for each of the `JMImageCache` source files.