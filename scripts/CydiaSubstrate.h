#ifndef CI_MINIMAL_CYDIASUBSTRATE_H
#define CI_MINIMAL_CYDIASUBSTRATE_H
/* Minimal substrate API surface for CI builds.
 * theos/headers 自带的 CydiaSubstrate.h 只是一层 #include 转发，
 * 缺少被转发目标的实体声明，这里补一份仅供编译期使用的最小声明。 */
#include <objc/runtime.h>
#include <stddef.h>

typedef struct MSImageRef_s *MSImageRef;

void MSHookFunction(void *symbol, void *replace, void **result);
void MSHookMessageEx(Class _class, SEL selector, IMP replacement, IMP *result);
MSImageRef MSGetImageByName(const char *file);
void *MSFindSymbol(MSImageRef image, const char *name);
void MSCloseImage(MSImageRef image);
char *MSFindAddress(MSImageRef image, void *addr);
char *MSImageAddress(MSImageRef image);
void *MSHookMemory(void *target, const void *data, size_t size);

#endif
