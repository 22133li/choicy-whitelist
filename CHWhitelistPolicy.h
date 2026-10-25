// CHWhitelistPolicy.h
// Choicy 严格白名单补丁 —— 纯 C 策略层
//
// 设计目标：
//   1. 默认拒绝：没有显式允许的进程一律不加载 Choicy，也不加载任何 tweak。
//   2. 管理工具自身隐身：被拒绝的 App 进程里，连 Choicy 的 dylib 都不能出现，
//      也不能安装任何 dyld hook、不能写入 SafeMode 环境键。
//      （这是"白名单版仍被检测出越狱"的根因所在）
//
// 关键原则：判断"禁用注入"和"不安装钩子"必须是同一个条件，
// 绝不能出现"注入关掉了但钩子还在"的中间态。

#ifndef CH_WHITELIST_POLICY_H
#define CH_WHITELIST_POLICY_H

#include <stdbool.h>
#include <string.h>

#define CH_PRIVILEGED_TWEAKS_KEY "privilegedTweaks"

static inline bool CHStringIs(const char *value, const char *expected)
{
	return value && expected && !strcmp(value, expected);
}

static inline bool CHIsUIKitBundle(const char *identifier)
{
	return CHStringIs(identifier, "com.apple.UIKit") || CHStringIs(identifier, "com.apple.UIKitCore");
}

// 这些进程必须始终放行，否则设备会失去设置入口 / tweak 加载链断裂。
// 注意：这里只放行"Choicy 自身可以进入并管理"的进程，
// 与"该进程的 tweak 是否放行"是两件事，后者由白名单决定。
static inline bool CHForcedInjection(const char *bundle, const char *executable)
{
	if (bundle && *bundle) {
		return CHStringIs(bundle, "com.apple.Preferences") ||
		       CHStringIs(bundle, "com.apple.springboard");
	}
	if (!executable) return false;
	const char *names[] = {"Preferences", "SpringBoard"};
	for (unsigned i = 0; i < sizeof(names) / sizeof(*names); i++) {
		if (CHStringIs(executable, names[i])) return true;
	}
	return false;
}

// 越狱环境安装的 App（/Applications 下且 BundleID 对得上）默认允许注入，
// 否则用户没有入口去管理这些 App 自己的插件。
static inline bool CHJailbreakAppDefaultAllow(bool isApplication, bool existsInApplications, bool identifierMatches)
{
	return isApplication && existsInApplications && identifierMatches;
}

// 决定该进程是否加载 Choicy 以及是否安装 dyld 钩子。
// required_allow_list_enabled = 是否处于"白名单模式"（本次补丁始终为 true，
// 保留该参数以便后续做成可关闭的开关）。
// has_explicit = 进程配置里是否有显式的 injectionEnabled 值。
static inline bool CHChoicyActive(bool forced, bool jailbreakAppDefault, bool hasExplicit,
                                  bool explicitEnabled, bool allowListEnabled)
{
	if (forced) return true;
	if (hasExplicit) return explicitEnabled;
	return jailbreakAppDefault || !allowListEnabled;
}

static inline bool CHShouldLoadTweak(bool choicyActive, bool globallyDenied,
                                     bool hasAllowList, bool allowed, bool denied)
{
	if (!choicyActive) return false;
	if (globallyDenied) return false;
	if (hasAllowList) return allowed && !denied;
	return !denied;
}

#endif
