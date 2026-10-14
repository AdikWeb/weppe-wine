#define COBJMACROS
#include <windows.h>
#include <d3d11_1.h>
#include <dxgi1_2.h>
#include <stdio.h>

#define TEXTURE_SIZE 64

static ID3D11Device *create_device(void)
{
    ID3D11Device *device = NULL;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &device, NULL,
                                   NULL);

    if (FAILED(hr)) printf("FAIL: D3D11CreateDevice (hr %#lx)\n", (unsigned long)hr);
    return device;
}

static ID3D11Texture2D *create_shared_texture(ID3D11Device *device, UINT misc_flags)
{
    D3D11_TEXTURE2D_DESC desc = {0};
    ID3D11Texture2D *texture = NULL;
    HRESULT hr;

    desc.Width = TEXTURE_SIZE;
    desc.Height = TEXTURE_SIZE;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
    desc.MiscFlags = misc_flags;
    hr = ID3D11Device_CreateTexture2D(device, &desc, NULL, &texture);
    printf("CreateTexture2D misc %#x: hr %#lx\n", misc_flags, (unsigned long)hr);
    return SUCCEEDED(hr) ? texture : NULL;
}

static BOOL share_with_nt_handle(ID3D11Device *creator, ID3D11Device *opener, UINT misc_flags)
{
    ID3D11Texture2D *texture = create_shared_texture(creator, misc_flags);
    IDXGIResource1 *resource;
    ID3D11Device1 *opener1;
    ID3D11Texture2D *opened = NULL;
    HANDLE handle = NULL;
    HRESULT hr;

    if (!texture) return FALSE;
    if (FAILED(hr = ID3D11Texture2D_QueryInterface(texture, &IID_IDXGIResource1, (void **)&resource)))
    {
        printf("FAIL: IDXGIResource1 (hr %#lx)\n", (unsigned long)hr);
        return FALSE;
    }
    hr = IDXGIResource1_CreateSharedHandle(resource, NULL, DXGI_SHARED_RESOURCE_READ | DXGI_SHARED_RESOURCE_WRITE, NULL,
                                           &handle);
    printf("CreateSharedHandle: hr %#lx handle %p\n", (unsigned long)hr, handle);
    if (FAILED(hr)) return FALSE;
    if (FAILED(hr = ID3D11Device_QueryInterface(opener, &IID_ID3D11Device1, (void **)&opener1)))
    {
        printf("FAIL: ID3D11Device1 (hr %#lx)\n", (unsigned long)hr);
        return FALSE;
    }
    hr = ID3D11Device1_OpenSharedResource1(opener1, handle, &IID_ID3D11Texture2D, (void **)&opened);
    printf("OpenSharedResource1: hr %#lx\n", (unsigned long)hr);
    return SUCCEEDED(hr) && opened;
}

static BOOL share_with_global_handle(ID3D11Device *creator, ID3D11Device *opener)
{
    ID3D11Texture2D *texture = create_shared_texture(creator, D3D11_RESOURCE_MISC_SHARED);
    IDXGIResource *resource;
    ID3D11Texture2D *opened = NULL;
    HANDLE handle = NULL;
    HRESULT hr;

    if (!texture) return FALSE;
    if (FAILED(hr = ID3D11Texture2D_QueryInterface(texture, &IID_IDXGIResource, (void **)&resource)))
    {
        printf("FAIL: IDXGIResource (hr %#lx)\n", (unsigned long)hr);
        return FALSE;
    }
    hr = IDXGIResource_GetSharedHandle(resource, &handle);
    printf("GetSharedHandle: hr %#lx handle %p\n", (unsigned long)hr, handle);
    if (FAILED(hr)) return FALSE;
    hr = ID3D11Device_OpenSharedResource(opener, handle, &IID_ID3D11Texture2D, (void **)&opened);
    printf("OpenSharedResource: hr %#lx\n", (unsigned long)hr);
    return SUCCEEDED(hr) && opened;
}

int main(void)
{
    ID3D11Device *creator, *opener;
    int failed = 0;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (!(creator = create_device()) || !(opener = create_device())) return 1;
    if (!share_with_nt_handle(creator, opener, D3D11_RESOURCE_MISC_SHARED_NTHANDLE | D3D11_RESOURCE_MISC_SHARED))
    {
        printf("FAIL: NT handle sharing\n");
        failed = 1;
    }
    if (!share_with_nt_handle(creator, opener,
                              D3D11_RESOURCE_MISC_SHARED_NTHANDLE | D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX))
    {
        printf("FAIL: NT handle sharing with a keyed mutex\n");
        failed = 1;
    }
    if (!share_with_global_handle(creator, opener))
    {
        printf("FAIL: global handle sharing\n");
        failed = 1;
    }
    if (!failed) printf("d3d11 shared texture: ok\n");
    return failed;
}
