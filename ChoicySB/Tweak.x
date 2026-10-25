#import <Foundation/Foundation.h>
#import "../Shared.h"
#import "../ChoicyPrefsMigrator.h"
#import "ChoicyOverrideManager.h"
#import "ChoicySB.h"
#import "../ChoicyPrefs/CoreServices.h"

NSDictionary *preferences;
BOOL gIsSpringBoard = NO;

extern void choicy_initSpringBoard(void);
extern void choicy_initRunningBoardd(void);

extern char** *_NSGetArgv();
NSString *safe_getExecutablePath()
{
	char *executablePathC = **_NSGetArgv();
	return [NSString stringWithUTF8String:executablePathC];
}

void choicy_reloadPreferences(void)
{
	if (preferences) {
		NSDictionary *oldPreferences = [preferences copy];
		preferences = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath];

		if (gIsSpringBoard) {
			NSDictionary *appSettings = [preferences objectForKey:kChoicyPrefsKeyAppSettings];
			NSDictionary *oldAppSettings = [oldPreferences objectForKey:kChoicyPrefsKeyAppSettings];

			NSMutableSet *allApps = [NSMutableSet setWithArray:[appSettings allKeys]];
			[allApps unionSet:[NSMutableSet setWithArray:[oldAppSettings allKeys]]];

			NSMutableSet *changedApps = [NSMutableSet new];

			for (NSString *appKey in allApps) {
				if (![((NSDictionary *)[appSettings objectForKey:appKey]) isEqualToDictionary:((NSDictionary *)[oldAppSettings objectForKey:appKey])]) {
					[changedApps addObject:appKey];
				}
			}

			for (NSString *applicationID in changedApps) {
				if (![applicationID isEqualToString:kSpringboardBundleID] && ![applicationID isEqualToString:kPreferencesBundleID]) {
					BKSTerminateApplicationForReasonAndReportWithDescription(applicationID, 5, false, @"Choicy - prefs changed, killed");
				}
			}
		}
	}
	else {
		NSString *parentDir = [kChoicyPrefsPlistPath stringByDeletingLastPathComponent];
		if (![[NSFileManager defaultManager] fileExistsAtPath:parentDir]) {
			[[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
		}
		preferences = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath];
	}
}

// 判断某个 BundleID 是否对应 /Applications 下由越狱环境安装的 App
BOOL CHWhitelistAppExistsInApplications(NSString *applicationID)
{
	if (!applicationID.length) return NO;

	LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:applicationID];
	if (!proxy) return NO;

	NSString *applicationsRoot = jbroot(@"/Applications");

	// roothide 下 bundleURL 可能带 jbroot 前缀也可能不带，两种都试
	NSString *proxyBundlePath = proxy.bundleURL.path;
	if (!proxyBundlePath.length) return NO;

	NSString *standardized = proxyBundlePath.stringByStandardizingPath;
	NSString *standardizedRoot = applicationsRoot.stringByStandardizingPath;

	// SpringBoard / 系统 App 都在 /System 或 /private/var/containers 下，
	// 只有越狱环境安装在 /Applications 下的 App 才会命中这里
	NSString *relativePath = nil;
	if ([standardized hasPrefix:[standardizedRoot stringByAppendingString:@"/"]]) {
		relativePath = [standardized substringFromIndex:standardizedRoot.length + 1];
	}
	else if ([standardized hasPrefix:@"/Applications/"]) {
		relativePath = [standardized substringFromIndex:[@"/Applications/" length]];
	}

	if (!relativePath.length) return NO;
	// 必须直接位于 /Applications 一级目录下
	return ![relativePath containsString:@"/"];
}

BOOL choicy_shouldDisableTweakInjectionForApplication(NSString *applicationID)
{
	BOOL overrideExists;
	BOOL disableTweakInjectionOverrideValue = [[ChoicyOverrideManager sharedManager] disableTweakInjectionOverrideForApplication:applicationID overrideExists:&overrideExists];
	if (overrideExists) {
		return disableTweakInjectionOverrideValue;
	}

	NSDictionary *settingsForApp = processPreferencesForApplication(preferences, applicationID);

	// 白名单模式：没有显式允许的 App 一律禁用注入。
	// 与旧版不同，这里的结果会被用来写入 _MSSafeMode，从而让注入框架
	// 根本不会把 Choicy 的 dylib 送进该 App —— App 端完全看不到管理工具的存在。
	if (settingsForApp && [settingsForApp isKindOfClass:[NSDictionary class]]) {
		id enabledVal = [settingsForApp objectForKey:kChoicyProcessPrefsKeyTweakInjectionEnabled];
		if ([enabledVal isKindOfClass:[NSNumber class]]) {
			return !((NSNumber *)enabledVal).boolValue;
		}

		id disabledVal = [settingsForApp objectForKey:kChoicyProcessPrefsKeyTweakInjectionDisabled];
		if ([disabledVal isKindOfClass:[NSNumber class]]) {
			return ((NSNumber *)disabledVal).boolValue;
		}
	}

	// 越狱环境安装的 App 默认放行，否则用户没有入口去管理它们自己的插件
	if (CHWhitelistAppExistsInApplications(applicationID)) {
		return NO;
	}

	return YES;
}

NSDictionary *choicy_applyEnvironmentChanges(NSDictionary *originalEnvironment, NSString *bundleIdentifier)
{
	if (originalEnvironment[@"_MSSafeMode"] || originalEnvironment[@"_SafeMode"]) {
		// "Launch without tweaks" pressed on SpringBoard
		return originalEnvironment;
	}
	else if (originalEnvironment[@"_ChoicyInjectionEnabledFromSpringBoard"]) {
		// "Launch with tweaks" pressed on SpringBoard
		return originalEnvironment;
	}

	NSMutableDictionary *newEnvironment = originalEnvironment.mutableCopy ?: [NSMutableDictionary new];
	if (choicy_shouldDisableTweakInjectionForApplication(bundleIdentifier)) {
		[newEnvironment setObject:@(1) forKey:@"_MSSafeMode"];
		[newEnvironment setObject:@(1) forKey:@"_SafeMode"];
	}
	else {
		ChoicyOverrideManager *overrideManager = [ChoicyOverrideManager sharedManager];
		BOOL overrideExists = NO;

		BOOL customTweakConfigurationEnabledOverride = [overrideManager customTweakConfigurationEnabledOverwriteForApplication:bundleIdentifier overrideExists:&overrideExists];
		if (overrideExists) {
			if (!customTweakConfigurationEnabledOverride) {
				// if custom tweak configuration has been overwritten with NO
				// set up an empty deny list
				[newEnvironment setObject:@"" forKey:@kEnvDeniedTweaksOverride];
			}
			else {
				BOOL customTweakAllowDenyOverride = [overrideManager customTweakConfigurationAllowDenyModeOverrideForApplication:bundleIdentifier overrideExists:&overrideExists];
				NSArray *allowDenyList = [overrideManager customTweakConfigurationAllowOrDenyListOverrideForApplication:bundleIdentifier overrideExists:&overrideExists];

				if (overrideManager && allowDenyList) {
					NSString *allowDenyString = [allowDenyList componentsJoinedByString:@":"];

					NSString *envName;
					if (customTweakAllowDenyOverride) { // DENY
						envName = @kEnvDeniedTweaksOverride;
					}
					else { //ALLOW
						envName = @kEnvAllowedTweaksOverride;
					}

					//NSLog(@"set %@ to %@", envName, allowDenyString);

					[newEnvironment setObject:allowDenyString forKey:envName];
				}
			}
		}

		BOOL overwriteGlobalConfigurationOverride = [overrideManager overwriteGlobalConfigurationOverrideForApplication:bundleIdentifier overrideExists:&overrideExists];
		//NSLog(@"overwriteGlobalConfigurationOverride=%i overrideExists=%i", overwriteGlobalConfigurationOverride, overrideExists);
		if (overrideExists) {
			NSString *envToSet;
			if (overwriteGlobalConfigurationOverride) {
				envToSet = @"1";
			}
			else {
				envToSet = @"0";
			}

			[newEnvironment setObject:envToSet forKey:@kEnvOverwriteGlobalConfigurationOverride];
		}
	}
	return newEnvironment;
}

void choicy_applyEnvironmentChangesToLaunchContext(RBSLaunchContext *launchContext)
{
	NSString *bundleIdentifier;
	if ([launchContext respondsToSelector:@selector(bundleIdentifier)]) {
		bundleIdentifier = launchContext.bundleIdentifier;
	}
	else {
		bundleIdentifier = launchContext.identity.embeddedApplicationIdentifier;
	}
	launchContext._additionalEnvironment = choicy_applyEnvironmentChanges(launchContext._additionalEnvironment, bundleIdentifier);
}

void choicy_applyEnvironmentChangesToExecutionContext(FBProcessExecutionContext *executionContext, NSString *bundleIdentifier)
{
	executionContext.environment = choicy_applyEnvironmentChanges(executionContext.environment, bundleIdentifier);
}

%ctor
{
	choicy_reloadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)choicy_reloadPreferences, CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	if (preferences && [ChoicyPrefsMigrator preferencesNeedMigration:preferences]) {
		NSMutableDictionary *preferencesM = preferences.mutableCopy;
		[ChoicyPrefsMigrator migratePreferences:preferencesM];
		[ChoicyPrefsMigrator updatePreferenceVersion:preferencesM];
		[preferencesM writeToFile:kChoicyPrefsPlistPath atomically:NO];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, NULL, YES);
	}

	NSString *executablePath = safe_getExecutablePath();
	if ([executablePath.lastPathComponent isEqualToString:@"SpringBoard"]) {
		gIsSpringBoard = YES;
		choicy_initSpringBoard();
	}
	else if ([executablePath.lastPathComponent isEqualToString:@"runningboardd"]) {
		choicy_initRunningBoardd();
	}
}