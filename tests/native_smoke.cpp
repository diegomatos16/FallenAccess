#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <stdio.h>
int main(int argc,char** argv) {
    if(argc!=2)return 2;
    lua_State* state=luaL_newstate();luaL_openlibs(state);
    lua_pushstring(state,argv[1]);lua_setglobal(state,"module_path");
    const char* code="local open,err=package.loadlib(module_path,'luaopen_fallen_speech'); assert(open,err); local m=open(); assert(type(m.init)=='function'); assert(type(m.say)=='function'); assert(type(m.stage)=='function'); m.stage('offline ABI check'); local t=m.clock_ms(); assert(type(t)=='number' and m.clock_ms()>=t); assert(m.say('no initialization, no audio',true)==false)";
    int result=luaL_dostring(state,code);
    if(result)fprintf(stderr,"%s\n",lua_tostring(state,-1));
    lua_close(state);
    if(!result)puts("Native Lua bridge loaded; no speech thread or game started.");
    return result;
}
