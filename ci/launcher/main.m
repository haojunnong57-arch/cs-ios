// CS 1.6 iOS launcher
// 职责：首启把 app 内置的 cstrike 资源释放到 Documents，然后 dlopen libxash.dylib
// 调用 Host_Main(argc, argv, "valve", 0, "") 直接进游戏。
// 依据：FWGS/xash3d-fwgs ios/Launcher/AppDelegate.m（GPLv3）。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

static NSString *DocsDir(void)
{
	return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
}

// 递归同步：目标缺失或大小不同就复制（幂等，可重复启动）
static void SyncTree(NSString *src, NSString *dst)
{
	NSFileManager *fm = NSFileManager.defaultManager;
	BOOL isDir = NO;

	if (![fm fileExistsAtPath:src isDirectory:&isDir])
		return;

	if (isDir)
	{
		[fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
		NSArray *names = [fm contentsOfDirectoryAtPath:src error:nil];
		for (NSString *name in names)
			SyncTree([src stringByAppendingPathComponent:name], [dst stringByAppendingPathComponent:name]);
	}
	else
	{
		NSDictionary *srcAttr = [fm attributesOfItemAtPath:src error:nil];
		NSDictionary *dstAttr = [fm attributesOfItemAtPath:dst error:nil];
		if (dstAttr && [dstAttr fileSize] == [srcAttr fileSize])
			return;
		[fm removeItemAtPath:dst error:nil];
		[fm copyItemAtPath:src toPath:dst error:nil];
	}
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic) UIWindow *window;
@property (nonatomic) UILabel *status;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts
{
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

	UIViewController *vc = [[UIViewController alloc] init];
	vc.view.backgroundColor = [UIColor blackColor];

	UILabel *label = [[UILabel alloc] initWithFrame:vc.view.bounds];
	label.text = @"正在准备游戏数据…";
	label.textColor = [UIColor whiteColor];
	label.textAlignment = NSTextAlignmentCenter;
	label.numberOfLines = 0;
	label.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[vc.view addSubview:label];
	self.status = label;

	self.window.rootViewController = vc;
	[self.window makeKeyAndVisible];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		[self prepare];
	});

	return YES;
}

- (void)prepare
{
	NSString *docs = DocsDir();
	NSString *game = [docs stringByAppendingPathComponent:@"cstrike"];
	NSString *seed = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"cstrike"];
	// 每次启动都补齐：bundle 里有、Documents 里没有（或大小不同）的文件会被覆盖，
	// 这样后续资源补丁只要重装包就生效，不用清数据。
	if ([NSFileManager.defaultManager fileExistsAtPath:seed])
	{
		dispatch_async(dispatch_get_main_queue(), ^{ self.status.text = @"正在校验游戏文件…"; });
		SyncTree(seed, game);
	}

	dispatch_async(dispatch_get_main_queue(), ^{ [self runEngine]; });
}

- (void)fail:(NSString *)msg
{
	self.status.text = msg;
	NSLog(@"launcher: %@", msg);
}

- (void)runEngine
{
	NSString *docs = DocsDir();
	chdir(docs.fileSystemRepresentation);

	NSString *lib = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"libxash.dylib"];
	void *handle = dlopen(lib.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
	if (!handle)
	{
		[self fail:[NSString stringWithFormat:@"引擎加载失败：%s", dlerror()]];
		return;
	}

	int (*Host_Main)(int, char **, const char *, int, const char *) =
		(int (*)(int, char **, const char *, int, const char *))dlsym(handle, "Host_Main");
	if (!Host_Main)
	{
		[self fail:@"引擎缺少 Host_Main 符号"];
		return;
	}

	char *argv[] = { "xash", "-log", "-game", "cstrike", NULL };
	self.window.hidden = YES;
	self.window = nil;

	exit(Host_Main(4, argv, "valve", 0, ""));
}

@end

int main(int argc, char *argv[])
{
	@autoreleasepool
	{
		return UIApplicationMain(argc, argv, nil, @"AppDelegate");
	}
}
