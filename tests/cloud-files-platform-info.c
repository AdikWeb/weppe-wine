#include <windows.h>
#include <stdio.h>

#define BITS_PER_BYTE 8

typedef struct
{
    DWORD build_number;
    DWORD revision_number;
    DWORD integration_number;
} platform_info;

typedef HRESULT (WINAPI *get_platform_info)(platform_info *info);

static int failed(const char *what)
{
    printf("FAIL: %s\n", what);
    return 1;
}

int main(void)
{
    HMODULE cldapi;
    get_platform_info get;
    platform_info info = {0};
    HRESULT hr;

    printf("cloud files platform info, %u-bit process\n", (unsigned)(sizeof(void *) * BITS_PER_BYTE));
    cldapi = LoadLibraryA("CldApi.dll");
    if (!cldapi)
        return failed("CldApi.dll does not load");
    get = (get_platform_info)(void *)GetProcAddress(cldapi, "CfGetPlatformInfo");
    if (!get)
        return failed("CldApi.dll does not export CfGetPlatformInfo");

    hr = get(&info);
    FreeLibrary(cldapi);
    printf("CfGetPlatformInfo returned %#lx, build %lu\n", (unsigned long)hr, (unsigned long)info.build_number);
    printf("cloud files platform info: ok\n");
    return 0;
}
