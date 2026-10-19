#include <windows.h>
#include <propidl.h>
#include <stdio.h>

#define BITS_PER_BYTE 8

typedef HRESULT (WINAPI *init_from_file_time)(const FILETIME *time, PROPVARIANT *value);

static const FILETIME sample_time = {0x89abcdef, 0x01234567};

static int failed(const char *what)
{
    printf("FAIL: %s\n", what);
    return 1;
}

int main(void)
{
    HMODULE propsys;
    init_from_file_time init;
    PROPVARIANT value;
    HRESULT hr;

    printf("propvariant filetime, %u-bit process\n", (unsigned)(sizeof(void *) * BITS_PER_BYTE));
    propsys = LoadLibraryA("propsys.dll");
    if (!propsys)
        return failed("propsys.dll does not load");
    init = (init_from_file_time)(void *)GetProcAddress(propsys, "InitPropVariantFromFileTime");
    if (!init)
        return failed("propsys.dll does not export InitPropVariantFromFileTime");

    PropVariantInit(&value);
    hr = init(&sample_time, &value);
    if (hr != S_OK)
    {
        printf("FAIL: InitPropVariantFromFileTime returned %#lx\n", (unsigned long)hr);
        return 1;
    }
    if (value.vt != VT_FILETIME)
    {
        printf("FAIL: the variant type is %u, not VT_FILETIME\n", value.vt);
        return 1;
    }
    if (value.filetime.dwLowDateTime != sample_time.dwLowDateTime
            || value.filetime.dwHighDateTime != sample_time.dwHighDateTime)
        return failed("the variant holds another time");

    printf("propvariant filetime: ok\n");
    return 0;
}
