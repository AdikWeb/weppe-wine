#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WINDOW_X 100
#define WINDOW_Y 100
#define PANEL_SIZE 200
#define PANEL_MARGIN 20
#define WINDOW_CLIENT_WIDTH (PANEL_SIZE * 2 + PANEL_MARGIN * 3)
#define WINDOW_CLIENT_HEIGHT (PANEL_SIZE + PANEL_MARGIN * 2)
#define OWNER_RUN_MS 30000
#define REMOTE_RUN_MS 25000
#define REMOTE_EXIT_WAIT_MS 10000
#define REMOTE_OPTION "--remote"

static const WCHAR window_class[] = L"weppe-wine-present-test";
static const float cyan[4] = {0, 1, 1, 1};
static const float magenta[4] = {1, 0, 1, 1};

static void pump_messages(void)
{
    MSG message;

    while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE))
    {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
}

static int present_into(HWND window, const float color[4], DWORD run_ms, const char *who)
{
    DXGI_SWAP_CHAIN_DESC desc = {0};
    IDXGISwapChain *swapchain;
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    ID3D11Texture2D *back_buffer;
    ID3D11RenderTargetView *view;
    ULONGLONG start = GetTickCount64();
    unsigned int frames = 0;
    HRESULT hr;

    desc.BufferDesc.Width = PANEL_SIZE;
    desc.BufferDesc.Height = PANEL_SIZE;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 1;
    desc.OutputWindow = window;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &desc,
                                       &swapchain, &device, NULL, &context);
    if (FAILED(hr))
    {
        printf("%s: FAIL: D3D11CreateDeviceAndSwapChain on %p (hr %#lx)\n", who, window, (unsigned long)hr);
        return 1;
    }
    if (FAILED(hr = IDXGISwapChain_GetBuffer(swapchain, 0, &IID_ID3D11Texture2D, (void **)&back_buffer)) ||
        FAILED(hr = ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)back_buffer, NULL, &view)))
    {
        printf("%s: FAIL: no render target view (hr %#lx)\n", who, (unsigned long)hr);
        return 1;
    }
    printf("%s: presenting into %p\n", who, window);
    fflush(stdout);
    while (GetTickCount64() - start < run_ms)
    {
        ID3D11DeviceContext_ClearRenderTargetView(context, view, color);
        if (FAILED(hr = IDXGISwapChain_Present(swapchain, 1, 0)))
        {
            printf("%s: FAIL: Present (hr %#lx) after %u frames\n", who, (unsigned long)hr, frames);
            return 1;
        }
        frames++;
        pump_messages();
    }
    printf("%s: presented %u frames\n", who, frames);
    return 0;
}

static HWND create_panel(HWND parent, int x)
{
    return CreateWindowExW(0, window_class, NULL, WS_CHILD | WS_VISIBLE, x, PANEL_MARGIN, PANEL_SIZE, PANEL_SIZE,
                           parent, NULL, GetModuleHandleW(NULL), NULL);
}

static HWND create_owner_window(void)
{
    WNDCLASSW cls = {0};
    RECT rect = {0, 0, WINDOW_CLIENT_WIDTH, WINDOW_CLIENT_HEIGHT};

    cls.lpfnWndProc = DefWindowProcW;
    cls.hInstance = GetModuleHandleW(NULL);
    cls.hbrBackground = GetStockObject(BLACK_BRUSH);
    cls.lpszClassName = window_class;
    RegisterClassW(&cls);
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);
    return CreateWindowExW(0, window_class, L"weppe-wine present test", WS_OVERLAPPEDWINDOW | WS_VISIBLE, WINDOW_X,
                           WINDOW_Y, rect.right - rect.left, rect.bottom - rect.top, NULL, NULL,
                           GetModuleHandleW(NULL), NULL);
}

static BOOL start_remote(HWND target, PROCESS_INFORMATION *process)
{
    WCHAR path[MAX_PATH], command[MAX_PATH + 64];
    STARTUPINFOW startup = {sizeof(startup)};

    GetModuleFileNameW(NULL, path, MAX_PATH);
    swprintf(command, ARRAYSIZE(command), L"\"%ls\" %hs %Ix", path, REMOTE_OPTION, (ULONG_PTR)target);
    return CreateProcessW(path, command, NULL, NULL, FALSE, 0, NULL, NULL, &startup, process);
}

static int run_owner(void)
{
    PROCESS_INFORMATION remote;
    HWND owner, same_process_panel, other_process_panel;
    DWORD remote_exit = 1;
    int result;

    owner = create_owner_window();
    same_process_panel = create_panel(owner, PANEL_MARGIN);
    other_process_panel = create_panel(owner, PANEL_MARGIN * 2 + PANEL_SIZE);
    if (!owner || !same_process_panel || !other_process_panel)
    {
        printf("owner: FAIL: could not create the windows\n");
        return 1;
    }
    pump_messages();
    if (!start_remote(other_process_panel, &remote))
    {
        printf("owner: FAIL: could not start the remote process (error %lu)\n", GetLastError());
        return 1;
    }
    result = present_into(same_process_panel, cyan, OWNER_RUN_MS, "owner");
    WaitForSingleObject(remote.hProcess, REMOTE_EXIT_WAIT_MS);
    GetExitCodeProcess(remote.hProcess, &remote_exit);
    printf("remote process exit code: %lu\n", remote_exit);
    return result || remote_exit;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], REMOTE_OPTION))
        return present_into((HWND)(ULONG_PTR)strtoull(argv[2], NULL, 16), magenta, REMOTE_RUN_MS, "remote");
    return run_owner();
}
