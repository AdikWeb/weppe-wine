#include <windows.h>
#include <stdio.h>

#define BITS_PER_BYTE 8
#define PARENT_X 100
#define PARENT_Y 100
#define PARENT_WIDTH 480
#define PARENT_HEIGHT 360
#define OVERLAY_X 50
#define OVERLAY_Y 40
#define OVERLAY_WIDTH 300
#define OVERLAY_HEIGHT 200
#define OVERLAY_STRIP_HEIGHT 4

static const char window_class[] = "weppe-child-window-from-point-region";

static HWND content, overlay;

static HWND create_window(DWORD style, HWND parent, int x, int y, int width, int height)
{
    return CreateWindowExA(0, window_class, "", style, x, y, width, height, parent, NULL,
                           GetModuleHandleA(NULL), NULL);
}

static const char *window_name(HWND hwnd)
{
    if (hwnd == content)
        return "content";
    if (hwnd == overlay)
        return "overlay";
    return "another window";
}

static int check(const char *call, HWND found, HWND expected)
{
    printf("%s: %s\n", call, window_name(found));
    if (found == expected)
        return 0;
    printf("FAIL: %s returned %s, expected %s\n", call, window_name(found), window_name(expected));
    return 1;
}

int main(void)
{
    WNDCLASSA class = { .lpfnWndProc = DefWindowProcA, .hInstance = GetModuleHandleA(NULL), .lpszClassName = window_class };
    POINT outside_region = { OVERLAY_X + OVERLAY_WIDTH / 2, OVERLAY_Y + OVERLAY_HEIGHT / 2 };
    POINT inside_region = { OVERLAY_X + OVERLAY_WIDTH / 2, OVERLAY_Y + OVERLAY_STRIP_HEIGHT / 2 };
    HWND parent;
    int failures = 0;

    printf("child window from point with a window region, %u-bit process\n", (unsigned)(sizeof(void *) * BITS_PER_BYTE));
    if (!RegisterClassA(&class)) {
        printf("FAIL: RegisterClassA failed with %lu\n", GetLastError());
        return 1;
    }
    parent = create_window(WS_OVERLAPPEDWINDOW | WS_VISIBLE, NULL, PARENT_X, PARENT_Y, PARENT_WIDTH, PARENT_HEIGHT);
    content = create_window(WS_CHILD | WS_VISIBLE, parent, 0, 0, PARENT_WIDTH, PARENT_HEIGHT);
    overlay = create_window(WS_CHILD | WS_VISIBLE, parent, OVERLAY_X, OVERLAY_Y, OVERLAY_WIDTH, OVERLAY_HEIGHT);
    if (!parent || !content || !overlay) {
        printf("FAIL: CreateWindowExA failed with %lu\n", GetLastError());
        return 1;
    }
    SetWindowPos(overlay, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    if (!SetWindowRgn(overlay, CreateRectRgn(0, 0, OVERLAY_WIDTH, OVERLAY_STRIP_HEIGHT), FALSE)) {
        printf("FAIL: SetWindowRgn failed with %lu\n", GetLastError());
        return 1;
    }

    failures += check("ChildWindowFromPointEx(CWP_SKIPINVISIBLE) outside the region",
                      ChildWindowFromPointEx(parent, outside_region, CWP_SKIPINVISIBLE), content);
    failures += check("ChildWindowFromPointEx(CWP_ALL) outside the region",
                      ChildWindowFromPointEx(parent, outside_region, CWP_ALL), content);
    failures += check("ChildWindowFromPoint outside the region", ChildWindowFromPoint(parent, outside_region), content);
    failures += check("RealChildWindowFromPoint outside the region", RealChildWindowFromPoint(parent, outside_region), content);
    failures += check("ChildWindowFromPointEx(CWP_SKIPINVISIBLE) inside the region",
                      ChildWindowFromPointEx(parent, inside_region, CWP_SKIPINVISIBLE), overlay);

    DestroyWindow(parent);
    if (failures)
        return 1;
    printf("child window from point region: ok\n");
    return 0;
}
