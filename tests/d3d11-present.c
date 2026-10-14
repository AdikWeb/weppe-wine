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
#define REMOTE_OPTION_W L"--remote"

struct target
{
    const char *name;
    HWND window;
    UINT width, height;
    const float *color;
    IDXGISwapChain *swapchain;
    ID3D11DeviceContext *context;
    ID3D11RenderTargetView *view;
};

static const WCHAR window_class[] = L"weppe-wine-present-test";
static const float cyan[4] = {0, 1, 1, 1};
static const float yellow[4] = {1, 1, 0, 1};
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

static BOOL open_target(struct target *target)
{
    DXGI_SWAP_CHAIN_DESC desc = {0};
    ID3D11Device *device;
    ID3D11Texture2D *back_buffer;
    DWORD window_process = 0;
    HRESULT hr;

    desc.BufferDesc.Width = target->width;
    desc.BufferDesc.Height = target->height;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 1;
    desc.OutputWindow = target->window;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    GetWindowThreadProcessId(target->window, &window_process);
    printf("%s: window %p of process %lu\n", target->name, target->window, window_process);
    hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &desc,
                                       &target->swapchain, &device, NULL, &target->context);
    if (FAILED(hr))
    {
        printf("%s: FAIL: D3D11CreateDeviceAndSwapChain (hr %#lx)\n", target->name, (unsigned long)hr);
        return FALSE;
    }
    if (FAILED(hr = IDXGISwapChain_GetBuffer(target->swapchain, 0, &IID_ID3D11Texture2D, (void **)&back_buffer)) ||
        FAILED(hr = ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)back_buffer, NULL, &target->view)))
    {
        printf("%s: FAIL: no render target view (hr %#lx)\n", target->name, (unsigned long)hr);
        return FALSE;
    }
    return TRUE;
}

static int present_targets(struct target *targets, unsigned int count, DWORD run_ms)
{
    ULONGLONG start = GetTickCount64();
    unsigned int frames = 0, i;
    HRESULT hr;

    for (i = 0; i < count; i++)
        if (!open_target(&targets[i])) return 1;
    while (GetTickCount64() - start < run_ms)
    {
        for (i = 0; i < count; i++)
        {
            ID3D11DeviceContext_ClearRenderTargetView(targets[i].context, targets[i].view, targets[i].color);
            if (FAILED(hr = IDXGISwapChain_Present(targets[i].swapchain, 1, 0)))
            {
                printf("%s: FAIL: Present (hr %#lx) after %u frames\n", targets[i].name, (unsigned long)hr, frames);
                return 1;
            }
        }
        frames++;
        pump_messages();
    }
    for (i = 0; i < count; i++) printf("%s: presented %u frames\n", targets[i].name, frames);
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
    swprintf(command, ARRAYSIZE(command), L"\"%ls\" " REMOTE_OPTION_W L" %llu", path,
             (unsigned long long)(ULONG_PTR)target);
    return CreateProcessW(path, command, NULL, NULL, FALSE, 0, NULL, NULL, &startup, process);
}

static int run_owner(void)
{
    struct target targets[2] = {
        {"owner window", NULL, WINDOW_CLIENT_WIDTH, WINDOW_CLIENT_HEIGHT, cyan},
        {"owner child window", NULL, PANEL_SIZE, PANEL_SIZE, yellow},
    };
    PROCESS_INFORMATION remote;
    HWND remote_panel;
    DWORD remote_exit = 1;
    int result;

    targets[0].window = create_owner_window();
    targets[1].window = create_panel(targets[0].window, PANEL_MARGIN);
    remote_panel = create_panel(targets[0].window, PANEL_MARGIN * 2 + PANEL_SIZE);
    if (!targets[0].window || !targets[1].window || !remote_panel)
    {
        printf("owner: FAIL: could not create the windows\n");
        return 1;
    }
    pump_messages();
    if (!start_remote(remote_panel, &remote))
    {
        printf("owner: FAIL: could not start the remote process (error %lu)\n", GetLastError());
        return 1;
    }
    result = present_targets(targets, ARRAYSIZE(targets), OWNER_RUN_MS);
    WaitForSingleObject(remote.hProcess, REMOTE_EXIT_WAIT_MS);
    GetExitCodeProcess(remote.hProcess, &remote_exit);
    printf("remote process exit code: %lu\n", remote_exit);
    return result || remote_exit;
}

static int run_remote(HWND window)
{
    struct target target = {"other process", window, PANEL_SIZE, PANEL_SIZE, magenta};

    return present_targets(&target, 1, REMOTE_RUN_MS);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc == 3 && !strcmp(argv[1], REMOTE_OPTION))
        return run_remote((HWND)(ULONG_PTR)strtoull(argv[2], NULL, 10));
    return run_owner();
}
