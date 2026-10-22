"""Offline regression against real manual captures; no game/reader is launched."""
import copy
import ctypes
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/luaqa'))
sys.path.insert(0, str(ROOT / 'src'))
from lupa.lua54 import LuaRuntime


class MenuPipeline(unittest.TestCase):
    def test_real_focus_changes_ignore_hidden_focus_without_extra_shortcuts(self):
        fixture = ROOT / 'tests/fixtures'
        captures = [json.loads((fixture / name).read_text(encoding='utf-8'))
                    for name in ('menu-first.json', 'menu-second.json')]
        with tempfile.TemporaryDirectory(dir=ROOT / 'runtime') as directory:
            short = ctypes.create_unicode_buffer(32768)
            self.assertTrue(ctypes.windll.kernel32.GetShortPathNameW(directory, short, len(short)))
            lua = LuaRuntime(unpack_returned_tuples=True)
            def table(value):
                if isinstance(value, dict):
                    return lua.table_from({k: table(v) for k, v in value.items()})
                if isinstance(value, list):
                    return lua.table_from([table(v) for v in value])
                return value
            lua.globals().fixtures = table(captures)
            lua.globals().test_output = short.value.replace('\\', '/')
            lua.execute('''
                active = 1; loops = {}; keys = {}; Key = {F6=6,F7=7,F8=8,F9=9,F10=10}
                EObjectFlags={RF_BeginDestroyed=0x8000,RF_FinishDestroyed=0x10000}
                print = function() end
                spoken = {}; counters={searches=0,finds=0,focus=0,texts=0}
                local window_for
                package.loadlib = function() return function() return {clock_ms=function() return os.clock()*1000 end,init=function() return true end,say=function(text) spoken[#spoken+1]=text; return true end} end end
                dofile = function() return {output=test_output,session='offline',profile='UI'} end
                UE4SS = {GetVersion=function() return 3,0,1 end}
                UnrealVersion = {GetMajor=function() return 4 end,GetMinor=function() return 21 end}
                RegisterKeyBind = function(key, callback) keys[key]=callback end
                LoopAsync = function(ms, callback) loops[ms]=callback end
                ExecuteInGameThread = function(callback) callback() end
                local invalid = {IsValid=function() return false end}
                local function ftext(text) return {ToString=function() return text end} end
                local function simple_text(text,path)
                    return {IsValid=function() return true end,HasAnyFlags=function() return false end,IsVisible=function() return true end,
                        IsA=function(_,class) return class=='/Script/UMG.TextBlock' end,
                        GetParent=function() return invalid end,GetOuter=function() return invalid end,
                        GetFullName=function() return 'TextBlock '..path end,
                        GetText=function() return ftext(text or '') end}
                end
                local function widget(row)
                    local parent = {
                        IsValid=function() return true end,HasAnyFlags=function() return false end,
                        IsVisible=function() return row.ancestorsVisible end,
                        GetParent=function() return invalid end,
                        GetOuter=function() return invalid end,
                        IsA=function(_,class) return class=='/Script/UMG.PanelWidget' end,
                        GetClass=function() return {GetFName=function() return ftext('CanvasPanel') end} end
                    }
                    local label = {IsValid=function() return true end,HasAnyFlags=function() return false end,
                        IsA=function(_,class) return class=='/Script/UMG.TextBlock' end,
                        IsVisible=function() return true end,
                        GetAddress=function() return row.identity..'label' end,
                        GetFullName=function() return row.labelPath or row.identity..'.Text' end,
                        GetParent=function() return invalid end,GetOuter=function() return invalid end,
                        GetText=function() counters.texts=counters.texts+1; return ftext(row.value or (not row.controlKind and row.label) or '') end}
                    local context = {IsValid=function() return true end,HasAnyFlags=function() return false end,
                        IsA=function(_,class) return class=='/Script/UMG.TextBlock' end,
                        IsVisible=function() return true end,
                        GetAddress=function() return row.identity..'context' end,
                        GetFullName=function() return row.identity..'.Context' end,
                        GetParent=function() return invalid end,GetOuter=function() return invalid end,
                        GetText=function() return ftext(row.mappedLabel or row.contextLabel or '') end}
                    local result
                    parent.GetChildrenCount=function() return row.contextLabel and 2 or 1 end
                    parent.GetChildAt=function(_,index) if index==0 then return context else return result end end
                    parent.GetAddress=function() return row.identity..'parent' end
                    local tree={IsValid=function() return true end,HasAnyFlags=function() return false end,GetPropertyValue=function() return label end}

                    local window = window_for(row)
                    local owner={IsValid=function() return true end,HasAnyFlags=function() return false end,GetOuter=function() return invalid end,
                        IsA=function(_,class)
                            if row.ownerKind=='controls' then return class=='/Game/UI/GameMenu/LoadableScreenWidgets/UI_LoadableScreenWidget_Settings_Controls.UI_LoadableScreenWidget_Settings_Controls_C' end
                            if row.ownerKind=='account' then return class=='/Game/UI/GameMenu/LoadableScreenWidgets/UI_LoadableScreenWidget_Settings_Account.UI_LoadableScreenWidget_Settings_Account_C' end
                            return false
                        end,
                        GetPropertyValue=function(_,field)
                            if field==row.ownerControl then return result end
                            if field==row.ownerLabel or field=='ActionName' then return context end
                            return invalid
                        end}
                    result = {IsValid=function() return true end,HasAnyFlags=function() return row.destroying==true end,
                        GetOuter=function() return row.ownerKind and owner or invalid end,
                        GetAddress=function() return row.identity end,
                        GetFocusGroup=function() return row.focusGroup or 0 end,
                        IsA=function(_,class)
                            if class=='/Script/RsGameTechRT.RsUiButton' or class=='/Script/UMG.Widget' or class=='/Script/UMG.UserWidget' then return true end
                            if not row.controlKind then return class=='/Game/UI/UI_TitleScreenButton.UI_TitleScreenButton_C' end
                            if row.controlKind=='remap' then return class=='/Game/UI/GameMenu/ControlsMenu/UI_ControlRemapBtn.UI_ControlRemapBtn_C' end
                            if row.controlKind=='action' then return class=='/Game/UI/GameMenu/Elements/Buttons/UI_Button_LoadableSubWidgetOpener.UI_Button_LoadableSubWidgetOpener_C' end
                            if row.controlKind=='combo' then return class=='/Game/UI/PauseMenu/UI_PauseMenuToggle.UI_PauseMenuToggle_C' end
                            if row.controlKind=='selector_combo' then
                                return class=='/Game/UI/PauseMenu/UI_PauseMenuBtn_Selector.UI_PauseMenuBtn_Selector_C' or class=='/Game/UI/PauseMenu/UI_PauseMenuToggle_TagDebugParent.UI_PauseMenuToggle_TagDebugParent_C'
                            end
                            if row.controlKind=='selector' then return class=='/Game/UI/PauseMenu/UI_PauseMenuBtn_Selector.UI_PauseMenuBtn_Selector_C' end
                            return class=='/Game/UI/PauseMenu/UI_PauseMenuSwitch.UI_PauseMenuSwitch_C'
                        end,
                        GetFullName=function() assert(not row.destroying,'Destroyed button was read'); return row.identity end,
                        IsVisible=function() return row.localVisible end,
                        IsFocused=function() return row.focused end,
                        GetParent=function() return parent end,
                        GetContainingUiWindow=function() return window end,
                        GetPropertyValue=function(_, name)
                            if name=='ButtonLabel' then
                                if row.badBindingLabel then error(function() end) end
                                return row.noBindingLabel and invalid or label
                            end
                            if name=='UI_MenuButtonPrompt' then
                                if not row.promptValue then return invalid end
                                local content={IsValid=function() return true end,HasAnyFlags=function() return false end,
                                    GetPropertyValue=function() return simple_text(row.promptValue,'/Engine/Transient.Prompt.KeyLabel') end}
                                return {IsValid=function() return true end,HasAnyFlags=function() return false end,
                                    GetPropertyValue=function() return content end}
                            end
                            if name=='IsAToggle' then return false end
                            if name=='RemapRow' then return owner end
                            if name=='ComboBoxRef' or name=='cmbDropdown' then
                                if not ((row.controlKind=='combo' and name=='ComboBoxRef') or (row.controlKind=='selector_combo' and name=='cmbDropdown')) then return invalid end
                                return {IsValid=function() return true end,HasAnyFlags=function() return false end,
                                    HasAnyUserFocus=function() return row.comboFocus==true end,
                                    HasFocusedDescendants=function() return false end,
                                    GetSelectedOption=function() return ftext(row.selectedOption or row.value) end}
                            end
                            if name=='WidgetTree' then
                                assert(not row.deepRemap, 'Remap reader traversed deep visual tree')
                                return tree
                            end
                            if name=='IsToggled' then return row.state end
                            if name=='LabelTxt' then return label end
                            if name=='ButtonLabelText' then return ftext(row.dataLabel) end
                            error('Unexpected field: '..name)
                        end}
                    result.labelWidget=label; result.contextWidget=context
                    return result
                end
                window_for=function(row)
                    return {IsValid=function() return true end,HasAnyFlags=function() return false end,
                        GetFullName=function() return row.window or 'window' end,
                        IsA=function(_,class)
                            if (row.window or ''):match('^UI_ShellContainer_C ') then return class=='/Game/UI/UI_ShellContainer.UI_ShellContainer_C' end
                            if (row.window or ''):match('^UI_ControllerRemapWindow_C ') then return class=='/Game/UI/GameMenu/ControlsMenu/UI_ControllerRemapWindow.UI_ControllerRemapWindow_C' end
                            if (row.window or ''):match('^UI_GameMenu_C ') then return class=='/Game/UI/GameMenu/UI_GameMenu.UI_GameMenu_C' end
                            return false
                        end,
                        GetPropertyValue=function(_,field)
                            local function tab(title)
                                return {IsValid=function() return true end,HasAnyFlags=function() return false end,
                                    IsA=function(_,class) return class=='/Game/UI/GameMenu/ControlsMenu/UI_ControlRemapRow.UI_ControlRemapRow_C' end,
                                    GetAddress=function() return 'tab:'..title end,
                                    GetPropertyValue=function() return simple_text(title,'/Engine/Transient.RemapWindow.Section') end}
                            end
                            if field=='CurrentRow' and row.currentTab then return tab(row.currentTab) end
                            if field=='TabRows' then
                                local result={}
                                for _,title in ipairs(row.tabs or {}) do result[#result+1]=tab(title) end
                                return result
                            end
                            return simple_text((row.windowTexts or {})[field],'/Engine/Transient.RemapWindow.'..field)
                        end,
                        IsInputEnabled=function() assert(row.windowOpen~=false,'Closed window was queried'); return row.windowInputEnabled~=false end,
                        GetFocusGroupToAccept=function() return row.acceptGroup or 0 end,
                        IsInViewport=function() assert(row.windowOpen~=false,'Closed window was queried'); return row.windowInViewport end,
                        IsVisible=function() assert(row.windowOpen~=false,'Closed window was queried'); return row.windowVisible end,
                        GetFocusedButton=function(_,group,clicked)
                            assert(clicked==false); counters.focus=counters.focus+1
                            for _,target in ipairs(fixtures[active]) do
                                if target.window==row.window and target.focused and target.ancestorsVisible
                                    and (target.focusGroup or 0)==group then return widget(target) end
                            end
                            return invalid
                        end,
                        GetChildButtons=function()
                            local result={}
                            for _,target in ipairs(fixtures[active]) do
                                if target.window==row.window then result[#result+1]=widget(target) end
                            end
                            return result
                        end}
                end
                dropdown_widget=function(row)
                    return {IsValid=function() return true end,HasAnyFlags=function() return false end,IsVisible=function() return true end,
                        IsA=function() return false end,GetOuter=function() return invalid end,GetParent=function() return invalid end,
                        GetFullName=function() assert(not row.destroying,'Destroyed button was read'); return row.identity end,
                        GetPropertyValue=function(_,field)
                            if field=='txt' then return simple_text(row.text,row.identity:match('^[^ ]+ (.+)$')..'.txt') end
                            return {IsValid=function() return true end,HasAnyFlags=function() return false end,HasAnyUserFocus=function() return row.focused end,
                                HasFocusedDescendants=function() return false end,IsHovered=function() return false end}
                        end}
                end
                local function root_widget()
                    return {IsValid=function() return true end,HasAnyFlags=function() return false end,
                        GetFullName=function() return 'RsUiRoot /Engine/Transient.UiRoot' end,
                        GetPropertyValue=function(_,field)
                            assert(field=='OpenWindows')
                            local result,seen={},{}
                            for _,row in ipairs(fixtures[active] or {}) do
                                if row.windowOpen~=false and not seen[row.window] then
                                    seen[row.window]=true;result[#result+1]=window_for(row)
                                end
                            end
                            return result
                        end}
                end
                FindAllOf = function(class)
                    if class=='UI_Dropdown_Element_C' then
                        local result={}
                        for _,row in ipairs(fixtures[active] or {}) do
                            for _,item in ipairs(row.dropdownEntries or {}) do result[#result+1]=dropdown_widget(item) end
                        end
                        return result
                    end
                    assert(class=='RsUiRoot', 'Unexpected global window/control scan: '..class)
                    counters.searches=counters.searches+1
                    return {root_widget()}
                end
                StaticFindObject = function(path)
                    counters.finds=counters.finds+1
                    if path=='/Engine/Transient.UiRoot' then return root_widget() end
                    if active==0 then return invalid end
                    for _,row in ipairs(fixtures[active]) do
                        for _,item in ipairs(row.dropdownEntries or {}) do
                            if item.identity:match('^[^ ]+ (.+)$')==path then return dropdown_widget(item) end
                        end
                        if row.identity:match('^[^ ]+ (.+)$')==path then return widget(row) end
                        if row.window:match('^[^ ]+ (.+)$')==path then return window_for(row) end
                        local item=widget(row)
                        for _,text in ipairs({item.labelWidget,item.contextWidget}) do
                            if text:GetFullName():match('^[^ ]+ (.+)$')==path then return text end
                        end
                    end
                    return invalid
                end
            ''')
            lua.execute((ROOT / 'src/diagnostic.lua').read_text(encoding='utf-8'),
                        name='@offline/diagnostic.lua')
            lua.execute('for i=1,8 do loops[100]() end')
            queue = Path(directory) / 'speech-requests.jsonl'
            events = lambda: [json.loads(line) for line in queue.read_text(encoding='utf-8').splitlines()]
            self.assertEqual([e['text'] for e in events()], ['CONTINUAR'])
            lua.execute('active=2; for i=1,8 do loops[100]() end')
            self.assertEqual([e['text'] for e in events()], ['CONTINUAR', 'INICIAR NOVA JORNADA'])
            # Returning to the same selection after the menu disappears must speak again.
            lua.execute('active=0; loops[100](); active=2; for i=1,3 do loops[100]() end')
            self.assertEqual(len(events()), 3)
            self.assertIsNone(lua.globals()['keys'][7])
            self.assertIsNone(lua.globals()['keys'][10])
            # Accents come from the captured label, without normalization or guessing.
            third = copy.deepcopy(captures[1])
            for row in third:
                row['focused'] = row['identity'].endswith('.OptionsButton')
            lua.globals().fixtures[3] = table(third)
            lua.execute('active=3; for i=1,3 do loops[100]() end')
            self.assertEqual(events()[-1]['text'], 'OPÇÕES')
            self.assertTrue(all(e['interrupt'] and e['session']=='offline' for e in events()))

            # Unit controls use real schema with synthetic values, not claims about live settings.
            volume = copy.deepcopy(captures[0][0])
            volume.update(identity=volume['identity']+'.VolumeTest',controlKind='selector',
                          contextLabel='Volume da música',value='100')
            lua.globals().fixtures[4] = table([volume])
            lua.execute('active=0; loops[100](); active=4; for i=1,35 do loops[100]() end')
            self.assertEqual(events()[-1]['text'], 'Volume da música: 100')
            for value in ('99','98','99','100'):
                lua.globals().fixtures[4][1]['value']=value
                lua.execute('loops[100]()')
                self.assertEqual(events()[-1]['text'],value)
            before=len(events()); lua.execute('for i=1,5 do loops[100]() end')
            self.assertEqual(len(events()),before)

            lua.execute('keys[8](); for i=1,30 do loops[100]() end')
            self.assertEqual(lua.globals().spoken[len(lua.globals().spoken)], 'Diagnóstico salvo.')
            diagnostic = [json.loads(line) for line in (Path(directory) / 'probe.jsonl').read_text(encoding='utf-8').splitlines()]
            self.assertTrue(any(row['event']=='capture.saved' for row in diagnostic))
            self.assertFalse(any(row['event'].endswith('.error') or row['event']=='control.unsupported' for row in diagnostic))
            toggle=copy.deepcopy(volume)
            toggle.update(identity=volume['identity']+'.ToggleTest',controlKind='switch',
                          contextLabel='Mira automática',value=None,state=True)
            lua.globals().fixtures[5]=table([toggle])
            lua.execute('active=0; loops[100](); active=5; for i=1,35 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'Mira automática: ativado')
            lua.globals().fixtures[5][1]['state']=False
            lua.execute('loops[100]()')
            self.assertEqual(events()[-1]['text'],'desativado')

            # Real failing session: both the shell and the options window retain focus.
            for number, name, expected in (
                (6, 'options-overlay.json', 'JOGABILIDADE'),
                (7, 'gameplay-overlay.json', 'Escala do texto dos indicadores: 1'),
            ):
                rows=json.loads((fixture / name).read_text(encoding='utf-8'))
                self.assertEqual(len(rows), 2)
                for row in rows:
                    if row['identity'].startswith('UI_PauseMenuBtn_Selector_C '):
                        row['controlKind']='selector'
                        row['contextLabel']=row['label']
                lua.globals().fixtures[number]=table(rows)
                lua.execute(f'active=0; loops[100](); active={number}; for i=1,35 do loops[100]() end')
                self.assertEqual(events()[-1]['text'],expected)
                before=len(events()); lua.execute('for i=1,5 do loops[100]() end')
                self.assertEqual(len(events()),before)
            # Returning from the overlay reads the real shell selection again.
            lua.execute('active=3; for i=1,35 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'OPÇÕES')

            transition=copy.deepcopy(rows)
            transition[1]['focused']=False
            lua.globals().fixtures[10]=table(transition)
            before=len(events())
            lua.execute('active=0; for i=1,35 do loops[100]() end; active=10; for i=1,35 do loops[100]() end')
            self.assertEqual(len(events()),before)

            # Unknown competing windows must remain ambiguous, regardless of list order.
            unknown=copy.deepcopy(rows)
            unknown[1]['window']='UnknownWindow /Engine/Transient.UnknownWindow'
            lua.globals().fixtures[8]=table(unknown)
            before=len(events())
            lua.execute('active=0; for i=1,35 do loops[100]() end; active=8; for i=1,35 do loops[100]() end')
            self.assertEqual(len(events()),before)

            # The hot path must stay independent of the number of inactive buttons.
            busy=copy.deepcopy(rows)
            for index in range(1000):
                extra=copy.deepcopy(busy[1])
                extra.update(identity=extra['identity']+f'.Inactive{index}',focused=False)
                busy.append(extra)
            lua.globals().fixtures[9]=table(busy)
            lua.execute('active=0; for i=1,35 do loops[100]() end; active=9; for i=1,35 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'Escala do texto dos indicadores: 1')
            initial={key:lua.globals().counters[key] for key in ('finds','searches','texts')}
            lua.execute('for i=1,60 do loops[100]() end')
            delta={key:lua.globals().counters[key]-initial[key] for key in initial}
            self.assertLessEqual(delta['searches'],2)
            self.assertLessEqual(delta['finds'],60*6)
            self.assertLessEqual(delta['texts'],60*4)
            # Captures do not dump a whole menu in the key callback or a single step.
            diagnostic_path=Path(directory)/'probe.jsonl'
            completed=diagnostic_path.read_text(encoding='utf-8').count('"event":"capture.saved"')
            lua.execute('keys[8](); loops[100](); loops[100]()')
            self.assertEqual(diagnostic_path.read_text(encoding='utf-8').count('"event":"capture.saved"'),completed)
            # Clean up the open incremental capture in this isolated harness.
            lua.execute('for i=1,520 do loops[100]() end')
            self.assertEqual(diagnostic_path.read_text(encoding='utf-8').count('"event":"capture.saved"'),completed+1)

            # Synthetic values below exercise schema-backed adapters, not live-menu claims.
            def enter(number, controls):
                lua.globals().fixtures[number]=table(controls)
                lua.execute(f'active=0; for i=1,35 do loops[100]() end; active={number}; for i=1,35 do loops[100]() end')
            photo=copy.deepcopy(toggle)
            photo.update(identity=volume['identity']+'.Photo', ownerKind='controls',ownerControl='btnPhotomode',
                         ownerLabel='PhotomodeText',contextLabel=None,mappedLabel='Modo Foto',state=False)
            enter(11,[photo])
            self.assertEqual(events()[-1]['text'],'Modo Foto: desativado')
            extra=copy.deepcopy(volume)
            extra.update(identity=volume['identity']+'.Credits',controlKind='action',ownerKind='account',
                         ownerControl='OpenCredits',ownerLabel='CreditsText',contextLabel=None,
                         mappedLabel='Créditos',value='VER')
            enter(12,[extra])
            self.assertEqual(events()[-1]['text'],'Créditos: VER')
            bind=copy.deepcopy(volume)
            bind.update(identity='UI_ControlRemapBtn_C /Engine/Transient.RemapRow.PC',
                        window='UI_ControllerRemapWindow_C /Engine/Transient.RemapWindow',
                        controlKind='remap',mappedLabel='Pular',contextLabel=None,value='ESPAÇO',
                        deepRemap=True,windowTexts={'RemapInput':'Editar controles','BasicsTxt':'BÁSICO','NavigationTxt':'NAVEGAÇÃO'})
            background=copy.deepcopy(rows[1])
            enter(13,[background,bind])
            self.assertEqual(events()[-1]['text'],'Pular: ESPAÇO')
            lua.globals().fixtures[13][2]['value']='F'
            lua.execute('loops[100]()')
            self.assertEqual(events()[-1]['text'],'F')
            lua.globals().fixtures[13][2]['windowTexts']['Message']='Pressione uma tecla'
            lua.execute('loops[100]()')
            self.assertEqual(events()[-1]['text'],'Pressione uma tecla')
            before=len(events()); lua.execute('for i=1,5 do loops[100]() end')
            self.assertEqual(len(events()),before)
            lua.globals().fixtures[13][2]['tabs']=table(['BÁSICO','NAVEGAÇÃO','HOLOMAP'])
            lua.globals().fixtures[13][2]['currentTab']='NAVEGAÇÃO'
            lua.execute('loops[100]()')
            self.assertEqual(events()[-1]['text'],'NAVEGAÇÃO')
            before=len(events());lua.execute('for i=1,5 do loops[100]() end')
            self.assertEqual(len(events()),before)
            lua.globals().fixtures[13][2]['currentTab']='HOLOMAP'
            lua.execute('loops[100]()')
            self.assertEqual(events()[-1]['text'],'HOLOMAP')
            lua.globals().fixtures[13][2]['currentTab']=None
            lua.globals().fixtures[13][2]['mappedLabel']='Interagir'
            lua.globals().fixtures[13][2]['value']='E'
            lua.execute('loops[100]()')
            self.assertEqual(events()[-1]['text'],'Interagir: E')
            combo=copy.deepcopy(volume)
            combo.update(identity=volume['identity']+'.Quality',controlKind='selector_combo',
                         contextLabel='Qualidade gráfica',value='ALTA',selectedOption='ALTA',comboFocus=False)
            enter(14,[combo])
            self.assertEqual(events()[-1]['text'],'Qualidade gráfica: ALTA')
            lua.globals().fixtures[14][1]['dropdownEntries']=table([
                {'identity':'UI_Dropdown_Element_C /Engine/Transient.Choice1','text':'MÉDIA','focused':True},
                {'identity':'UI_Dropdown_Element_C /Engine/Transient.Choice2','text':'BAIXA','focused':False}])
            lua.globals().fixtures[14][1]['comboFocus']=True
            lua.execute('for i=1,3 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'MÉDIA')
            lua.globals().fixtures[14][1]['dropdownEntries'][1]['focused']=False
            lua.globals().fixtures[14][1]['dropdownEntries'][2]['focused']=True
            lua.execute('for i=1,3 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'BAIXA')
            lua.globals().fixtures[14][1]['comboFocus']=False
            lua.globals().fixtures[14][1]['selectedOption']='BAIXA'
            lua.execute('for i=1,3 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'Qualidade gráfica: BAIXA')
            # A popup can keep Slate focus while the native parent button loses focus.
            lua.globals().fixtures[14][1]['focused']=False
            lua.globals().fixtures[14][1]['comboFocus']=True
            lua.globals().fixtures[14][1]['dropdownEntries'][1]['focused']=True
            lua.globals().fixtures[14][1]['dropdownEntries'][2]['focused']=False
            lua.execute('for i=1,3 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'MÉDIA')

            lua.execute('for i=1,65 do loops[100]() end; keys[8](); for i=1,20 do loops[100]() end')
            final_diagnostic=[json.loads(line) for line in diagnostic_path.read_text(encoding='utf-8').splitlines()]
            self.assertFalse(any(row['event'].endswith('.error') or row['event']=='window.unsupported' for row in final_diagnostic))


            # Do not touch a button that starts destruction between focus resolution and reading.
            dead=copy.deepcopy(bind)
            dead.update(identity='UI_ControlRemapBtn_C /Engine/Transient.Destroyed.PC',destroying=True)
            before=len(events());enter(15,[dead])
            self.assertEqual(len(events()),before)
            # Hidden binding labels use the game's displayed prompt, with no FKey call.
            prompt=copy.deepcopy(bind)
            prompt.update(identity='UI_ControlRemapBtn_C /Engine/Transient.PromptRow.PC',
                          noBindingLabel=True,promptValue='ESPAÇO')
            enter(16,[prompt])
            self.assertEqual(events()[-1]['text'],'Pular: ESPAÇO')
            # A queued callback must resolve the final live screen rather than a closed screen.
            lua.execute('queued={}; ExecuteInGameThread=function(callback) queued[#queued+1]=callback end; loops[100]()')
            lua.execute('active=15; loops[100](); active=14; loops[100](); active=3; loops[100]()')
            self.assertEqual(len(lua.globals().queued),1)
            lua.execute('queued[1](); ExecuteInGameThread=function(callback) callback() end; for i=1,35 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'OPÇÕES')
            final_diagnostic=[json.loads(line) for line in diagnostic_path.read_text(encoding='utf-8').splitlines()]
            self.assertFalse(any(row['event'].endswith('.error') for row in final_diagnostic))

            # A failing optional key field must not silence a real action label or retry forever.
            partial=copy.deepcopy(bind)
            partial.update(identity='UI_ControlRemapBtn_C /Engine/Transient.PartialRow.PC',badBindingLabel=True)
            enter(17,[partial])
            self.assertEqual(events()[-1]['text'],'Pular')
            error_count=diagnostic_path.read_text(encoding='utf-8').count('"event":"ui.read.error"')
            lua.execute('for i=1,5 do loops[100]() end')
            self.assertEqual(diagnostic_path.read_text(encoding='utf-8').count('"event":"ui.read.error"'),error_count)
            self.assertEqual(error_count,1)
            self.assertNotIn('"event":"reader.disabled.error"',diagnostic_path.read_text(encoding='utf-8'))

            # A closed window can still be a valid UObject with stale visible/focus flags.
            # Its getters deliberately fail: only membership in OpenWindows authorizes queries.
            closed=json.loads((fixture / 'options-overlay.json').read_text(encoding='utf-8'))
            closed[1]['windowOpen']=False
            lua.globals().fixtures[18]=table(closed)
            lua.execute('active=18; for i=1,3 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'OPÇÕES')
            initial_searches=lua.globals().counters['searches']
            before=len(events())
            # A new window is recognized on the next polls, without rediscovery or 3s delay.
            lua.execute('active=6; loops[100](); loops[100]()')
            self.assertEqual(len(events()),before+1)
            self.assertEqual(events()[-1]['text'],'JOGABILIDADE')
            self.assertEqual(lua.globals().counters['searches'],initial_searches)
            # Rapid close/reopen cycles never query the closed but still allocated window.
            lua.execute('for i=1,20 do active=18; loops[100](); active=6; loops[100]() end; active=18; for i=1,3 do loops[100]() end')
            self.assertEqual(events()[-1]['text'],'OPÇÕES')
            diagnostic_text=diagnostic_path.read_text(encoding='utf-8')
            self.assertNotIn('Closed window was queried',diagnostic_text)
            self.assertNotIn('"event":"window.unsupported"',diagnostic_text)
            self.assertEqual(diagnostic_text.count('"event":"ui.read.error"'),error_count)




if __name__ == '__main__':
    unittest.main()
