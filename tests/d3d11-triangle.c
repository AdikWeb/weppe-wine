#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <stdio.h>
#include <string.h>

#define TARGET_SIZE 64
#define BYTES_PER_PIXEL 4

static const char shader_source[] =
    "float4 vs(uint id : SV_VertexID) : SV_Position\n"
    "{\n"
    "    float2 corners[3] = { float2(-1, -1), float2(-1, 3), float2(3, -1) };\n"
    "    return float4(corners[id], 0, 1);\n"
    "}\n"
    "float4 ps() : SV_Target { return float4(1, 0, 0, 1); }\n";

static const float clear_color[4] = {0, 0, 1, 1};
static const BYTE expected_red[BYTES_PER_PIXEL] = {255, 0, 0, 255};

static int failed(const char *what, HRESULT hr)
{
    printf("FAIL: %s (hr %#lx)\n", what, (unsigned long)hr);
    return 1;
}

static void print_adapter(ID3D11Device *device, D3D_FEATURE_LEVEL level)
{
    IDXGIDevice *dxgi_device;
    IDXGIAdapter *adapter;
    DXGI_ADAPTER_DESC desc;

    printf("feature level: %#x\n", level);
    if (FAILED(ID3D11Device_QueryInterface(device, &IID_IDXGIDevice, (void **)&dxgi_device))) return;
    if (SUCCEEDED(IDXGIDevice_GetAdapter(dxgi_device, &adapter)))
    {
        if (SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc))) printf("adapter: %ls\n", desc.Description);
        IDXGIAdapter_Release(adapter);
    }
    IDXGIDevice_Release(dxgi_device);
}

static HRESULT compile(const char *entry, const char *profile, ID3DBlob **blob)
{
    ID3DBlob *errors = NULL;
    HRESULT hr = D3DCompile(shader_source, strlen(shader_source), "triangle", NULL, NULL, entry, profile, 0, 0, blob,
                            &errors);
    if (errors)
    {
        printf("%s: %s\n", entry, (const char *)ID3D10Blob_GetBufferPointer(errors));
        ID3D10Blob_Release(errors);
    }
    return hr;
}

static HRESULT create_target(ID3D11Device *device, D3D11_USAGE usage, UINT bind, UINT cpu, ID3D11Texture2D **texture)
{
    D3D11_TEXTURE2D_DESC desc = {0};

    desc.Width = TARGET_SIZE;
    desc.Height = TARGET_SIZE;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = usage;
    desc.BindFlags = bind;
    desc.CPUAccessFlags = cpu;
    return ID3D11Device_CreateTexture2D(device, &desc, NULL, texture);
}

int main(void)
{
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    D3D_FEATURE_LEVEL level;
    ID3DBlob *vs_blob, *ps_blob;
    ID3D11VertexShader *vs;
    ID3D11PixelShader *ps;
    ID3D11Texture2D *target, *readback;
    ID3D11RenderTargetView *view;
    ID3D11RasterizerState *rasterizer;
    D3D11_RASTERIZER_DESC rasterizer_desc = {0};
    D3D11_VIEWPORT viewport = {0, 0, TARGET_SIZE, TARGET_SIZE, 0, 1};
    D3D11_MAPPED_SUBRESOURCE mapped;
    const BYTE *pixel;
    HRESULT hr;
    int matches;

    if (FAILED(hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &device,
                                      &level, &context)))
        return failed("D3D11CreateDevice", hr);
    print_adapter(device, level);

    if (FAILED(hr = compile("vs", "vs_4_0", &vs_blob))) return failed("compiling the vertex shader", hr);
    if (FAILED(hr = compile("ps", "ps_4_0", &ps_blob))) return failed("compiling the pixel shader", hr);
    if (FAILED(hr = ID3D11Device_CreateVertexShader(device, ID3D10Blob_GetBufferPointer(vs_blob),
                                                    ID3D10Blob_GetBufferSize(vs_blob), NULL, &vs)))
        return failed("CreateVertexShader", hr);
    if (FAILED(hr = ID3D11Device_CreatePixelShader(device, ID3D10Blob_GetBufferPointer(ps_blob),
                                                   ID3D10Blob_GetBufferSize(ps_blob), NULL, &ps)))
        return failed("CreatePixelShader", hr);

    if (FAILED(hr = create_target(device, D3D11_USAGE_DEFAULT, D3D11_BIND_RENDER_TARGET, 0, &target)))
        return failed("creating the render target", hr);
    if (FAILED(hr = create_target(device, D3D11_USAGE_STAGING, 0, D3D11_CPU_ACCESS_READ, &readback)))
        return failed("creating the readback texture", hr);
    if (FAILED(hr = ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)target, NULL, &view)))
        return failed("CreateRenderTargetView", hr);
    rasterizer_desc.FillMode = D3D11_FILL_SOLID;
    rasterizer_desc.CullMode = D3D11_CULL_NONE;
    rasterizer_desc.DepthClipEnable = TRUE;
    if (FAILED(hr = ID3D11Device_CreateRasterizerState(device, &rasterizer_desc, &rasterizer)))
        return failed("CreateRasterizerState", hr);

    ID3D11DeviceContext_ClearRenderTargetView(context, view, clear_color);
    ID3D11DeviceContext_OMSetRenderTargets(context, 1, &view, NULL);
    ID3D11DeviceContext_RSSetViewports(context, 1, &viewport);
    ID3D11DeviceContext_RSSetState(context, rasterizer);
    ID3D11DeviceContext_IASetPrimitiveTopology(context, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ID3D11DeviceContext_VSSetShader(context, vs, NULL, 0);
    ID3D11DeviceContext_PSSetShader(context, ps, NULL, 0);
    ID3D11DeviceContext_Draw(context, 3, 0);
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)readback, (ID3D11Resource *)target);

    if (FAILED(hr = ID3D11DeviceContext_Map(context, (ID3D11Resource *)readback, 0, D3D11_MAP_READ, 0, &mapped)))
        return failed("mapping the readback texture", hr);
    pixel = (const BYTE *)mapped.pData + (TARGET_SIZE / 2) * mapped.RowPitch + (TARGET_SIZE / 2) * BYTES_PER_PIXEL;
    printf("center pixel (RGBA): %u %u %u %u\n", pixel[0], pixel[1], pixel[2], pixel[3]);
    matches = !memcmp(pixel, expected_red, BYTES_PER_PIXEL);
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)readback, 0);

    if (!matches)
    {
        printf("FAIL: the red triangle was not drawn\n");
        return 1;
    }
    printf("d3d11 triangle: ok\n");
    return 0;
}
