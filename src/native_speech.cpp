// In-process Lua 5.4.4 bridge. Only the dedicated worker calls Prism/COM.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "lua.h"
#include "prism.h"

static SRWLOCK queue_lock = SRWLOCK_INIT;
static HANDLE wake_event;
static volatile LONG initialized;
static char* pending_text;
static bool pending_interrupt;
static ULONGLONG pending_time;
static wchar_t log_path[32768];
static HMODULE pinned_module;
static wchar_t exception_path[32768];
static thread_local char current_stage[512] = "idle";
static volatile LONG exception_count;
static HMODULE game_module, loader_module;

// Evidence only: first-chance exceptions continue through the game's normal handlers.
static LONG CALLBACK observe_exception(EXCEPTION_POINTERS* info) {
    const DWORD code=info->ExceptionRecord->ExceptionCode;
    if (code!=EXCEPTION_ACCESS_VIOLATION && code!=EXCEPTION_ILLEGAL_INSTRUCTION
        && code!=0xc0000409 && code!=0x40000015) return EXCEPTION_CONTINUE_SEARCH;
    if (InterlockedIncrement(&exception_count)>16) return EXCEPTION_CONTINUE_SEARCH;
    HANDLE file=CreateFileW(exception_path,FILE_APPEND_DATA,FILE_SHARE_READ|FILE_SHARE_WRITE,
                            NULL,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if (file==INVALID_HANDLE_VALUE) return EXCEPTION_CONTINUE_SEARCH;
    char line[1024]; DWORD written; SYSTEMTIME utc;GetSystemTime(&utc);
    int length=snprintf(line,sizeof(line),"first-chance utc=%04u-%02u-%02uT%02u:%02u:%02uZ code=%08lx rip=%llx thread=%lu game=%llx ue4ss=%llx stage=%.511s\n",
        utc.wYear,utc.wMonth,utc.wDay,utc.wHour,utc.wMinute,utc.wSecond,
        (unsigned long)code,(unsigned long long)info->ContextRecord->Rip,GetCurrentThreadId(),
        (unsigned long long)game_module,(unsigned long long)loader_module,current_stage);
    if (length>0) WriteFile(file,line,(DWORD)length,&written,NULL);
    void* frames[24]; USHORT count=CaptureStackBackTrace(0,24,frames,NULL);
    for (USHORT index=0;index<count;++index) {
        length=snprintf(line,sizeof(line),"frame=%u address=%llx\n",index,(unsigned long long)frames[index]);
        if (length>0) WriteFile(file,line,(DWORD)length,&written,NULL);
    }
    CloseHandle(file);
    return EXCEPTION_CONTINUE_SEARCH;
}

static void log_line(const char* kind, const char* text, int result) {
    FILE* file = _wfopen(log_path, L"ab");
    if (!file) return;
    SYSTEMTIME t; GetSystemTime(&t);
    fprintf(file, "%04u-%02u-%02uT%02u:%02u:%02uZ %s result=%d %s\n",
            t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond,kind,result,text ? text : "");
    fflush(file); fclose(file);
}

static DWORD WINAPI speech_thread(void*) {
    HRESULT com = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(com) && com != RPC_E_CHANGED_MODE) { log_line("com.error", "", (int)com); return 1; }
    wchar_t path[32768];
    if (!GetModuleFileNameW(pinned_module,path,32768)) return 1;
    wchar_t* slash = wcsrchr(path,L'\\'); if (!slash) return 1;
    wcscpy(slash+1,L"prism.dll");
    HMODULE prism = LoadLibraryW(path);
    if (!prism) { log_line("load.error", "prism.dll", (int)GetLastError()); return 1; }
#define BIND(name) auto name = reinterpret_cast<decltype(&::name)>(GetProcAddress(prism,#name)); if (!name) { log_line("export.error",#name,0); return 1; }
    BIND(prism_init) BIND(prism_registry_count) BIND(prism_registry_id_at)
    BIND(prism_registry_priority) BIND(prism_registry_create)
    BIND(prism_backend_get_features) BIND(prism_backend_initialize)
    BIND(prism_backend_free) BIND(prism_backend_name)
    BIND(prism_backend_output) BIND(prism_error_string)
    PrismContext* context = prism_init(NULL);
    if (!context) { log_line("init.error","Prism context",0); return 1; }
    PrismBackend* backend = NULL;
    size_t count = prism_registry_count(context);
    struct Candidate { PrismBackendId id; int priority; } candidates[64];
    size_t used = 0;
    for (size_t i=0; i<count && used<63; ++i) {
        PrismBackendId id = prism_registry_id_at(context,i);
        if (id == PRISM_BACKEND_SAPI || id == PRISM_BACKEND_ONE_CORE || id == PRISM_BACKEND_UIA) continue;
        candidates[used++] = {id,prism_registry_priority(context,id)};
    }
    for (size_t i=0;i<used;++i) for (size_t j=i+1;j<used;++j) {
        if (candidates[j].priority>candidates[i].priority) { auto tmp=candidates[i];candidates[i]=candidates[j];candidates[j]=tmp; }
    }
    candidates[used++] = {PRISM_BACKEND_SAPI,0};
    for (size_t i=0;i<used;++i) {
        PrismBackend* candidate = prism_registry_create(context,candidates[i].id);
        if (!candidate) continue;
        if ((prism_backend_get_features(candidate)&PRISM_BACKEND_IS_SUPPORTED_AT_RUNTIME)
            && prism_backend_initialize(candidate)==PRISM_OK) { backend=candidate; break; }
        prism_backend_free(candidate);
    }
    if (!backend) { log_line("backend.error","No reader or SAPI",0); return 1; }
    log_line("backend.ready",prism_backend_name(backend),0);
    log_line("startup","FallenAccess carregado.",prism_backend_output(backend,"FallenAccess carregado.",true));
    for (;;) {
        WaitForSingleObject(wake_event,INFINITE);
        AcquireSRWLockExclusive(&queue_lock);
        char* text=pending_text; pending_text=NULL;
        bool interrupt=pending_interrupt; ULONGLONG queued=pending_time;
        ReleaseSRWLockExclusive(&queue_lock);
        if (!text) continue;
        if (GetTickCount64()-queued<=3000) {
            PrismError result=prism_backend_output(backend,text,interrupt);
            log_line("speak",text,(int)result);
            if (result!=PRISM_OK) log_line("prism.error",prism_error_string(result),(int)result);
        } else log_line("discard.stale",text,0);
        free(text);
    }
    // No COM or Prism teardown under DllMain/loader lock. OS owns process exit.
}

extern "C" __declspec(dllexport) int fallen_speech_init(const char* directory) {
    if (InterlockedCompareExchange(&initialized,1,0)) return 1;
    if (!directory || !MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,directory,-1,log_path,32700)) return 0;
    wcscat(log_path,L"/native-speech.log");
    if (!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,directory,-1,exception_path,32700)) return 0;
    wcscat(exception_path,L"/native-exceptions.log");
    // Pin our code while the worker is alive, including during Lua mod destruction.
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
            reinterpret_cast<LPCWSTR>(&fallen_speech_init),&pinned_module)) return 0;
    game_module=GetModuleHandleW(NULL);loader_module=GetModuleHandleW(L"UE4SS.dll");
    void* observer=AddVectoredExceptionHandler(1,observe_exception);
    log_line(observer ? "diagnostic.ready" : "diagnostic.error","first-chance observer; normal exception handling preserved",
             observer ? 0 : (int)GetLastError());
    wake_event=CreateEventW(NULL,FALSE,FALSE,NULL);
    if (!wake_event) return 0;
    HANDLE thread=CreateThread(NULL,0,speech_thread,NULL,0,NULL);
    if (!thread) return 0;
    CloseHandle(thread);
    return 1;
}

extern "C" __declspec(dllexport) int fallen_speech_enqueue(const char* text, size_t length, int interrupt) {
    if (!wake_event || !text || !length || length>65536 || memchr(text,0,length)) return 0;
    if (!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text,(int)length,NULL,0)) return 0;
    char* copy=(char*)malloc(length+1); if (!copy) return 0;
    memcpy(copy,text,length); copy[length]=0;
    AcquireSRWLockExclusive(&queue_lock);
    free(pending_text); pending_text=copy; pending_interrupt=interrupt!=0;pending_time=GetTickCount64();
    ReleaseSRWLockExclusive(&queue_lock);
    SetEvent(wake_event);
    return 1;
}

static int lua_init(lua_State* state) {
    const char* directory=lua_tolstring(state,1,NULL);
    lua_pushboolean(state,fallen_speech_init(directory)); return 1;
}
static int lua_say(lua_State* state) {
    size_t length=0; const char* text=lua_tolstring(state,1,&length);
    lua_pushboolean(state,fallen_speech_enqueue(text,length,lua_toboolean(state,2))); return 1;
}
static int lua_clock_ms(lua_State* state) {
    LARGE_INTEGER counter, frequency;
    QueryPerformanceCounter(&counter); QueryPerformanceFrequency(&frequency);
    lua_pushnumber(state, (lua_Number)counter.QuadPart * 1000.0 / (lua_Number)frequency.QuadPart);
    return 1;
}
static int lua_stage(lua_State* state) {
    size_t length=0; const char* text=lua_tolstring(state,1,&length);
    if (text) {
        if(length>=sizeof(current_stage))length=sizeof(current_stage)-1;
        memcpy(current_stage,text,length);current_stage[length]=0;
    }
    return 0;
}
extern "C" __declspec(dllexport) int luaopen_fallen_speech(lua_State* state) {
    lua_createtable(state,0,4);
    lua_pushcfunction(state,lua_init); lua_setfield(state,-2,"init");
    lua_pushcfunction(state,lua_say); lua_setfield(state,-2,"say");
    lua_pushcfunction(state,lua_clock_ms); lua_setfield(state,-2,"clock_ms");
    lua_pushcfunction(state,lua_stage); lua_setfield(state,-2,"stage");
    return 1;
}
