#include <windows.h>
#include <string>
#include <utility>
#include "ldraw.h"
#include "resource1.h"
#include "NXRegistry.h"

#include "LDRightClick.h"

using std::string;

static string ExecutorCommand;

#define MAGIC_SOURCE_EDIT_CMD 90210

struct menuctr {
    HMENU hMenu;
    menuctr(UINT resource_id) {
        hMenu = LoadMenu(NULL, MAKEINTRESOURCE(resource_id));
    }
    ~menuctr() { if (hMenu) DeleteObject(hMenu); }
};

void EnhanceMenu(HMENU sub, const string relay_name){
    string S{ "Source Edit " + relay_name };
    UINT flags = MF_STRING | MF_ENABLED;
    AppendMenu(sub, flags, MAGIC_SOURCE_EDIT_CMD, S.c_str());
}

void SubmitEditCommand(const char* relay_name) {
    ShellExecute(NULL, "open", ExecutorCommand.c_str(), relay_name, NULL, SW_HIDE);

}

int Menu(HWND hWnd, int resource_id, int x, int y, const char* relay_name) {
    menuctr M(IDM_LDRCLICK);
    if (!M.hMenu)
        return 0;
    POINT p{ x, y };
    ClientToScreen(hWnd, &p);
    HMENU sub = GetSubMenu(M.hMenu, 0);
    if (ExecutorCommand.size() && relay_name != nullptr)
        EnhanceMenu(sub, relay_name);
    int flgs = TPM_LEFTALIGN | TPM_TOPALIGN | TPM_NONOTIFY | TPM_RETURNCMD;
    return TrackPopupMenu(sub, flgs, p.x, p.y, 0, hWnd, NULL);
}

int RelayGraphicsRightClick(HWND ldWindow, WPARAM, int x, int y) {
	const char* relay_name = RelayGraphicsNameFromXY(x, y);
    int cmd = Menu(ldWindow, IDM_LDRCLICK, x, y, relay_name);
    if (cmd == MAGIC_SOURCE_EDIT_CMD) {
        SubmitEditCommand(relay_name);
        return 0;
    }
	return cmd;
}

void InitRelayGraphicsSourceClick() {
    auto result = getStringRegItem("SourceLocatorScript");
    if (result.valid)
        ExecutorCommand = result.value;

}