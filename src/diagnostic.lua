-- Diagnostic probe. No fabricated labels or automatic scene scans.
local source = debug.getinfo(1, 'S').source
local script_dir = source:gsub('^@', ''):match('(.*[/\\])')
assert(script_dir, 'FallenAccess: cannot resolve script directory')
local config = dofile(script_dir .. 'config.lua')
local build = 'FallenAccess-open-windows-2026-10-22-12'
local run_id = os.date('!%Y%m%dT%H%M%SZ')
local sequence, capture_sequence = 0, 0
local function quote(value)
    return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(c)
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        return string.format('\\u%04x', c:byte())
    end) .. '"'
end
local function log(event, detail)
    sequence = sequence + 1
    local line = '{"session":' .. quote(config.session) .. ',"run":' .. quote(run_id) .. ',"sequence":' .. sequence
        .. ',"utc":' .. quote(os.date('!%Y-%m-%dT%H:%M:%SZ'))
        .. ',"event":' .. quote(event) .. ',"detail":' .. quote(detail or '') .. '}\n'
    local file, err = io.open(config.output .. '/probe.jsonl', 'a')
    if not file then print('[FallenAccess] log failure: ' .. tostring(err) .. '\n'); return false end
    file:write(line); file:flush(); file:close()
    if event ~= 'heartbeat' then print('[FallenAccess] ' .. event .. ' ' .. tostring(detail or '') .. '\n') end
    return true
end
local function traceback(err) return debug.traceback(tostring(err), 2) end
local function guarded(name, callback)
    return function(...)
        log(name .. '.begin')
        local ok, err = xpcall(callback, traceback, ...)
        log(name .. (ok and '.end' or '.error'), ok and '' or err)
    end
end
log('lua.start', build .. ' profile=' .. config.profile .. ' lua=' .. _VERSION)
guarded('versions', function()
    local major, minor, patch = UE4SS.GetVersion()
    log('versions.value', 'loader=' .. major .. '.' .. minor .. '.' .. patch
        .. ' engine=' .. UnrealVersion.GetMajor() .. '.' .. UnrealVersion.GetMinor() .. ' bitness=64')
end)()
RegisterKeyBind(Key.F6, guarded('manual.ping', function() log('ping', 'keyboard callback reached') end))
local request_capture, loop_ticks = nil, 0
LoopAsync(250, function()
    loop_ticks = loop_ticks + 1
    if loop_ticks % 20 == 0 then log('heartbeat', 'async loop alive') end
    if request_capture then
        local path = config.output .. '/capture.request'
        local file = io.open(path, 'r')
        if file then
            local token = file:read('*l') or ''
            file:close()
            local removed, err = os.remove(path)
            if removed then
                if token:match('^[a-z0-9-]+$') and #token <= 100 then
                    log('capture.command', token)
                    guarded('capture.dispatch', request_capture)()
                else log('capture.command.error', 'invalid token') end
            else log('capture.command.error', err) end
        end
    end
    return false
end)
log('probe.ready', 'F6 ping; no widget functions called')
if config.profile == 'UI' then
    local quiet_reads = true
    local read_errors = 0
    local native = nil
    local function stage(name) if native and native.stage then native.stage(name) end end
    local function clock_ms() return native and native.clock_ms() or os.clock() * 1000 end
    local function json(value)
        local kind = type(value)
        if kind == 'string' then return quote(value) end
        if kind == 'boolean' or kind == 'number' then return tostring(value) end
        if kind == 'nil' then return 'null' end
        assert(kind == 'table', 'unsupported snapshot JSON type: ' .. kind)
        local parts, keys = {}, {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do parts[#parts + 1] = quote(key) .. ':' .. json(value[key]) end
        return '{' .. table.concat(parts, ',') .. '}'
    end
    local function read(identity, operation, callback)
        -- Normal reads do not perform disk I/O. Native crashes cannot be caught by xpcall.
        if not quiet_reads then log('ui.read.begin', identity .. ' operation=' .. operation) end
        stage(operation .. ' ' .. identity)
        local ok, value = xpcall(callback, traceback)
        if not ok then
            read_errors = read_errors + 1
            log('ui.read.error', identity .. ' operation=' .. operation .. ' ' .. tostring(value))
            return nil
        end
        if not quiet_reads then log('ui.read.end', operation) end
        return value
    end
    local function text_value(value)
        if type(value) == 'string' then return value end
        if value == nil then return nil end
        local ok, result = pcall(function() return value:ToString() end)
        if ok and type(result) == 'string' then return result end
        ok, result = pcall(function() return value:get():ToString() end)
        if ok and type(result) == 'string' then return result end
        error('FText conversion failed; no object name substituted for label')
    end
    local RS_BUTTON = '/Script/RsGameTechRT.RsUiButton'
    local RS_WINDOW = '/Script/RsGameTechRT.RsUiWindow'
    local ELEMENT = '/Game/UI/GameMenu/Elements/UI_Element_Base.UI_Element_Base_C'
    local TITLE = '/Game/UI/UI_TitleScreenButton.UI_TitleScreenButton_C'
    local SELECTOR = '/Game/UI/PauseMenu/UI_PauseMenuBtn_Selector.UI_PauseMenuBtn_Selector_C'
    local SWITCH = '/Game/UI/PauseMenu/UI_PauseMenuSwitch.UI_PauseMenuSwitch_C'
    local TOGGLE = '/Game/UI/PauseMenu/UI_PauseMenuToggle.UI_PauseMenuToggle_C'
    local SELECTOR_PARENT = '/Game/UI/PauseMenu/UI_PauseMenuToggle_TagDebugParent.UI_PauseMenuToggle_TagDebugParent_C'
    local SHELL = '/Game/UI/UI_ShellContainer.UI_ShellContainer_C'
    local GAME_MENU = '/Game/UI/GameMenu/UI_GameMenu.UI_GameMenu_C'
    local REMAP = '/Game/UI/GameMenu/ControlsMenu/UI_ControllerRemapWindow.UI_ControllerRemapWindow_C'
    local REMAP_BUTTON = '/Game/UI/GameMenu/ControlsMenu/UI_ControlRemapBtn.UI_ControlRemapBtn_C'
    local REMAP_ROW = '/Game/UI/GameMenu/ControlsMenu/UI_ControlRemapRow.UI_ControlRemapRow_C'
    local DROPDOWN = '/Game/UI/GameMenu/Widgets/UI_Dropdown_Element.UI_Dropdown_Element_C'
    local OPENER = '/Game/UI/GameMenu/Elements/Buttons/UI_Button_LoadableSubWidgetOpener.UI_Button_LoadableSubWidgetOpener_C'
    local CONTROLS = '/Game/UI/GameMenu/LoadableScreenWidgets/UI_LoadableScreenWidget_Settings_Controls.UI_LoadableScreenWidget_Settings_Controls_C'
    local ACCOUNT = '/Game/UI/GameMenu/LoadableScreenWidgets/UI_LoadableScreenWidget_Settings_Account.UI_LoadableScreenWidget_Settings_Account_C'
    local destroy_flags = EObjectFlags.RF_BeginDestroyed | EObjectFlags.RF_FinishDestroyed
    local function valid(object)
        return object and object:IsValid() and not object:HasAnyFlags(destroy_flags)
    end
    local function isa(object, class) return valid(object) and object:IsA(class) end
    local function parent_widget(node)
        local parent = node:GetParent()
        if valid(parent) then return parent end
        -- A nested UserWidget's root panel has no UMG parent. Cross WidgetTree to its owner.
        local tree = node:GetOuter()
        if isa(tree, '/Script/UMG.WidgetTree') then
            local owner = tree:GetOuter()
            if isa(owner, '/Script/UMG.Widget') then return owner end
        end
        return nil
    end
    local function visible_chain(button, identity)
        local node = button
        for _ = 1, 48 do
            local visible = read(identity, 'ancestor.IsVisible', function() return node:IsVisible() end)
            if visible ~= true then return visible end
            local parent = parent_widget(node)
            if not valid(parent) then return true end
            if isa(parent, '/Script/UMG.WidgetSwitcher') then
                local active = read(identity, 'switcher.GetActiveWidget', function() return parent:GetActiveWidget() end)
                if not valid(active) or active:GetAddress() ~= node:GetAddress() then return false end
            end
            node = parent
        end
        log('ui.read.error', identity .. ' ancestor chain exceeded 48 levels')
        return nil
    end
    local function widget_text(widget)
        if isa(widget, '/Script/UMG.TextBlock') then return text_value(widget:GetText()) end
        if isa(widget, '/Script/UMG.RichTextBlock') then return text_value(widget:GetPropertyValue('Text')) end
        return nil
    end
    local function text_parts(widget, excluded)
        local parts, seen, visited = {}, {}, 0
        local function visit(node, depth)
            if not valid(node) then return end
            assert(depth <= 12 and visited < 96, 'Text subtree exceeds bounded traversal; no partial label used')
            if excluded and node:GetAddress() == excluded:GetAddress() then return end
            if excluded and (isa(node, RS_BUTTON) or isa(node, ELEMENT)) then return end
            visited = visited + 1
            if node:IsVisible() ~= true then return end
            local text = widget_text(node)
            if text and text:match('%S') and not seen[text] then
                seen[text] = true
                parts[#parts + 1] = {text=text, path=node:GetFullName()}
            elseif isa(node, '/Script/UMG.UserWidget') then
                local tree = node:GetPropertyValue('WidgetTree')
                if valid(tree) then visit(tree:GetPropertyValue('RootWidget'), depth + 1) end
            elseif isa(node, '/Script/UMG.PanelWidget') then
                local count = node:GetChildrenCount()
                assert(count <= 96, 'Text container exceeds bounded traversal')
                for index = 0, count - 1 do
                    local child = node:GetChildAt(index)
                    if isa(node, '/Script/UMG.WidgetSwitcher') then
                        local active = node:GetActiveWidget()
                        if valid(active) and valid(child) and active:GetAddress() == child:GetAddress() then visit(child, depth+1) end
                    else visit(child, depth + 1) end
                end
            end
        end
        visit(widget, 0)
        return parts
    end
    local function joined(parts)
        local strings = {}
        for _, part in ipairs(parts or {}) do strings[#strings + 1] = part.text end
        return #strings > 0 and table.concat(strings, ', ') or nil
    end
    local function row_label(button)
        local parent = button:GetParent()
        for _ = 1, 4 do
            if not valid(parent) then return nil end
            -- Stop before a whole list: do not turn other controls into this control's label.
            if isa(parent, '/Script/UMG.ScrollBox') or isa(parent, '/Script/UMG.VerticalBox') then return nil end
            local parts = text_parts(parent, button)
            if #parts == 1 then return joined(parts), parts end
            if #parts > 1 then return nil end
            parent = parent:GetParent()
        end
        return nil
    end
    local function field_parts(owner, field)
        local widget = owner:GetPropertyValue(field)
        if valid(widget) and visible_chain(widget, field) then
            local text = widget_text(widget)
            if text and text:match('%S') then return {{text=text,path=widget:GetFullName()}} end
        end
        return nil
    end
    local field_blocked = {}
    local function direct_parts(owner, field, identity)
        local key=identity .. ':' .. field
        if field_blocked[key] then return nil end
        local before=read_errors
        local widget=read(identity,'field.' .. field,function() return owner:GetPropertyValue(field) end)
        if valid(widget) then
            local visible=read(identity,'field.visible.' .. field,function() return widget:IsVisible() end)
            if visible then
                local text=read(identity,'field.text.' .. field,function() return widget_text(widget) end)
                if text and text:match('%S') then return {{text=text,path=widget:GetFullName()}} end
            end
        end
        if read_errors~=before then field_blocked[key]=true end
        return nil
    end
    local function mapped_label(button)
        if isa(button, REMAP_BUTTON) then
            local owner = button:GetPropertyValue('RemapRow')
            if valid(owner) then return field_parts(owner, 'ActionName') end
        end
        local node = button:GetOuter()
        for _ = 1, 4 do
            if not valid(node) then return nil end
            local mappings
            if isa(node, CONTROLS) then mappings = {btnPhotomode='PhotomodeText'}
            elseif isa(node, ACCOUNT) then
                mappings = {OpenCredits='CreditsText',OpenPrivacyPolicy='PrivacyText',OpenUserAgreement='UserAgreementText'}
            end
            if mappings then
                for control, label in pairs(mappings) do
                    local ref = node:GetPropertyValue(control)
                    if valid(ref) and ref:GetAddress() == button:GetAddress() then return field_parts(node, label) end
                end
                return nil
            end
            node = node:GetOuter()
        end
        return nil
    end
    local function containing_window(button)
        if isa(button, RS_BUTTON) then return button:GetContainingUiWindow() end
        local node = button
        for _ = 1, 48 do
            if isa(node, RS_WINDOW) then return node end
            node = parent_widget(node)
            if not valid(node) then return nil end
        end
        return nil
    end
    local function focus_kind(button)
        if isa(button, RS_BUTTON) then return 'rs' end
        if isa(button, ELEMENT) then return 'element' end
        return 'umg'
    end
    local function is_focused(button, kind)
        if kind == 'rs' then return button:IsFocused() end
        if kind == 'element' then
            return button:GetPropertyValue('ElementFocusState') == true
                and button:GetPropertyValue('ParentSubMenuHasFocus') == true
        end
        return button:HasAnyUserFocus()
    end
    local function window_info(window)
        local identity = window:GetFullName()
        local info = {window=identity}
        if isa(window, SHELL) then info.windowRole = 'shell'
        elseif isa(window, GAME_MENU) then info.windowRole = 'game-menu'
        elseif isa(window, REMAP) then info.windowRole = 'remap' end
        stage('window.IsInViewport ' .. identity)
        info.windowInViewport = window:IsInViewport()
        stage('window.IsVisible ' .. identity)
        info.windowVisible = window:IsVisible()
        stage('window.IsInputEnabled ' .. identity)
        info.windowInputEnabled = window:IsInputEnabled()
        if info.windowInViewport and info.windowVisible and info.windowInputEnabled then
            stage('window.GetFocusGroupToAccept ' .. identity)
            info.acceptGroup = window:GetFocusGroupToAccept()
        end
        return info
    end
    local function combo_of(button)
        if isa(button, SELECTOR) or isa(button, SELECTOR_PARENT) then
            local ok, combo=pcall(function() return button:GetPropertyValue('cmbDropdown') end)
            if ok and valid(combo) then return combo, 'cmbDropdown' end
        end
        if isa(button, TOGGLE) or isa(button, SELECTOR) or isa(button, SELECTOR_PARENT) then
            local ok, combo=pcall(function() return button:GetPropertyValue('ComboBoxRef') end)
            if ok and valid(combo) then return combo, 'ComboBoxRef' end
        end
        return nil
    end
    local content_cache = nil
    local function read_parts(parts)
        local result = {}
        for _, part in ipairs(parts or {}) do
            local widget = StaticFindObject(part.path:match('^[^ ]+ (.+)$'))
            if not valid(widget) or not visible_chain(widget, part.path) then return nil end
            local text = widget_text(widget)
            if not text then return nil end
            result[#result + 1] = {path=part.path, text=text}
        end
        return result
    end
    local function describe_content(button, row, use_cache)
        -- Remap buttons contain a deep icon hierarchy; read the exposed fields directly.
        if isa(button, REMAP_BUTTON) then
            local owner=read(row.identity,'remap.RemapRow',function() return button:GetPropertyValue('RemapRow') end)
            if valid(owner) then row.label=joined(direct_parts(owner,'ActionName',row.identity)) end
            row.value=joined(direct_parts(button,'ButtonLabel',row.identity))
            row.valueSource='ButtonLabel.GetText'
            if not row.value then
                local prompt=read(row.identity,'remap.prompt',function() return button:GetPropertyValue('UI_MenuButtonPrompt') end)
                if valid(prompt) then
                    local content=read(row.identity,'remap.prompt.content',function() return prompt:GetPropertyValue('UI_MenuButtonPrompt_Content') end)
                    if valid(content) then row.value=joined(direct_parts(content,'KeyLabel',row.identity)) end
                    row.valueSource='displayed prompt KeyLabel'
                end
            end
            row.bindingMissing = not row.value
            return
        end
        local toggle = isa(button, TOGGLE) and button:GetPropertyValue('IsAToggle') == true
        local checkbox = isa(button, '/Script/UMG.CheckBox')
        local combo, combo_field = combo_of(button)
        local control = isa(button, SELECTOR) or isa(button, SWITCH) or toggle or valid(combo)
        local remap = isa(button, REMAP_BUTTON)
        local action = isa(button, OPENER)
        local own, label_parts
        if use_cache and content_cache and content_cache.identity == row.identity
            and clock_ms() < content_cache.expires then
            own = read_parts(content_cache.own)
            label_parts = read_parts(content_cache.label)
            if own and label_parts then
                row.label = joined(label_parts)
            else content_cache = nil end
        end
        if not own or not label_parts then
            own = text_parts(button)
            local parts
            parts = mapped_label(button)
            if not parts and (control or checkbox or remap or action) then
                local _, found = row_label(button); parts = found
            end
            label_parts = parts or {}
            row.label = joined(label_parts)
            if use_cache then
                content_cache = {identity=row.identity, expires=clock_ms()+1000, own=own, label=label_parts}
            end
        end
        own = joined(own)
        if control then
            if isa(button, SWITCH) or toggle then
                row.state = button:GetPropertyValue('IsToggled')
                if type(row.state) == 'boolean' then row.value = row.state and 'ativado' or 'desativado' end
                row.valueSource = 'IsToggled'
            else row.value = own; row.valueSource = 'visible widget text' end
            if not row.label then row.label = own; if row.value == own then row.value = nil end end
        elseif remap or action then
            if row.label then row.value=own else row.label=own end
            row.valueSource = remap and 'displayed binding' or 'displayed action'
        else row.label = own end
        if valid(combo) then
            local selected = text_value(combo:GetSelectedOption())
            if selected and selected:match('%S') then row.value=selected; row.valueSource=combo_field .. '.GetSelectedOption' end
        end
        if checkbox then
            row.label = row.label or joined(label_parts)
            row.state = button:IsChecked()
            row.value = row.state and 'ativado' or 'desativado'
            row.valueSource = 'IsChecked'
        end
    end
    local function describe(button, identity, kind, context, include_content)
        local row = {kind=kind, identity=identity, session=config.session, run=run_id}
        row.localVisible = read(identity, 'widget.IsVisible', function() return button:IsVisible() end)
        row.ancestorsVisible = visible_chain(button, identity)
        row.focused = read(identity, 'widget.focus', function() return is_focused(button, kind) end)
        if not context then
            local window = containing_window(button)
            if valid(window) then context = window_info(window) end
        end
        if context then
            for key, value in pairs(context) do row[key] = value end
            if kind == 'rs' then
                row.focusGroup = button:GetFocusGroup()
            end
        end
        row.active = row.focused == true and row.ancestorsVisible == true
            and row.windowInViewport == true and row.windowVisible == true
            and row.windowInputEnabled == true
            and (kind ~= 'rs' or row.focusGroup == row.acceptGroup)
        if row.ancestorsVisible ~= true or include_content == false then return row end
        if isa(button, TITLE) then
            local label = button:GetPropertyValue('LabelTxt')
            if valid(label) then row.label = text_value(label:GetText()); row.labelPath = label:GetFullName() end
        else
            describe_content(button, row, include_content == 'cached')
        end
        return row
    end
    -- Only window paths survive frames. Query the game's own focus manager, not every button.
    local paths = {}
    local dropdown_cache = {paths={},owner=nil,due=0,focused=false}
    local function each_object(values, callback)
        if not values then return end
        if type(values) == 'table' then
            for _, value in ipairs(values) do callback(value) end
        else
            values:ForEach(function(_, value) callback(value:get()) end)
        end
    end
    local root_paths, root_retry = {}, 0
    local function find_windows()
        local result, live, remaining, seen = {}, {}, {}, {}
        if #root_paths == 0 and clock_ms() >= root_retry then
            root_retry=clock_ms()+3000
            for _, root in ipairs(FindAllOf('RsUiRoot') or {}) do
                if valid(root) then
                    local identity=root:GetFullName()
                    if identity:find('/Engine/Transient.',1,true) then
                        root_paths[#root_paths+1]={identity=identity,path=identity:match('^[^ ]+ (.+)$')}
                    end
                end
            end
            log('roots.discovered','count=' .. #root_paths)
        end
        for _, entry in ipairs(root_paths) do
            stage('root.resolve ' .. entry.identity)
            local root=StaticFindObject(entry.path)
            if valid(root) then
                remaining[#remaining+1]=entry
                local windows=read(entry.identity,'root.OpenWindows',function() return root:GetPropertyValue('OpenWindows') end)
                each_object(windows,function(window)
                    if valid(window) then
                        local identity=window:GetFullName()
                        if not seen[identity] then
                            seen[identity]=true
                            local path=identity:match('^[^ ]+ (.+)$')
                            result[#result+1]={identity=identity,path=path}
                            live[path]=window
                        end
                    end
                end)
            end
        end
        root_paths=remaining
        -- Strong references come from the game's OpenWindows array, scoped to this call.
        -- Only root/window path strings are kept for subsequent frames.
        return result, live
    end
    local pending, capture = false, nil
    local function dump()
        if pending then log('capture.busy', 'capture is already in progress'); return end
        pending = true
        log('capture.request', 'incremental capture queued; no full widget scan')
    end
    local function capture_step()
        if not pending then return end
        if not capture then
            capture_sequence = capture_sequence + 1
            local path = config.output .. '/ui-' .. run_id .. '-' .. capture_sequence .. '.jsonl'
            capture = {path=path, file=assert(io.open(path, 'w')), entries={}, index=1, count=0}
            local seen = {}
            for _, entry in ipairs(paths) do
                local window = StaticFindObject(entry.path)
                if valid(window) then
                    local info = window_info(window)
                    capture.file:write(json(info), '\n')
                    if info.windowInViewport and info.windowVisible and info.windowInputEnabled then
                        local children = window:GetChildButtons()
                        each_object(children, function(button)
                            if #capture.entries >= 512 then capture.limited = true; return end
                            if valid(button) then
                                local identity = button:GetFullName()
                                if not seen[identity] then
                                    seen[identity] = true
                                    capture.entries[#capture.entries+1] = {
                                        identity=identity, path=identity:match('^[^ ]+ (.+)$')}
                                end
                            end
                        end)
                    end
                end
            end
            -- A manual capture also discovers rows if Slate focus was not propagated to the owner.
            local capture_dropdowns = {}
            for _, item in ipairs(FindAllOf('UI_Dropdown_Element_C') or {}) do
                if valid(item) and #capture_dropdowns < 64 then
                    local identity=item:GetFullName()
                    if identity:find('/Engine/Transient.',1,true) then
                        capture_dropdowns[#capture_dropdowns+1]=identity:match('^[^ ]+ (.+)$')
                    end
                end
            end
            for _, path in ipairs(capture_dropdowns) do
                if #capture.entries < 512 then
                    capture.entries[#capture.entries+1]={path=path,identity='UI_Dropdown_Element_C '..path,kind='dropdown'}
                end
            end
            if capture.limited then log('capture.limit', '512 controls; capture is explicitly truncated') end
            log('capture.begin', 'controls=' .. #capture.entries .. '; at most 2 per step')
            return
        end
        local started = clock_ms()
        for _ = 1, 2 do
            local entry = capture.entries[capture.index]
            if not entry then break end
            local button = StaticFindObject(entry.path)
            if valid(button) then
                local ok, row = xpcall(function()
                    if entry.kind == 'dropdown' then
                        local target=button:GetPropertyValue('Button_0')
                        return {identity=entry.identity,kind='dropdown',label=joined(field_parts(button,'txt')),
                            visible=visible_chain(button,entry.identity),focused=valid(target) and target:HasAnyUserFocus(),
                            descendantFocus=valid(target) and target:HasFocusedDescendants(),hovered=valid(target) and target:IsHovered()}
                    end
                    return describe(button, entry.identity, 'rs')
                end, traceback)
                if not ok then row = {identity=entry.identity, error=row} end
                capture.file:write(json(row), '\n')
                capture.count = capture.count + 1
            end
            capture.index = capture.index + 1
            if clock_ms() - started >= 3 then break end
        end
        if capture.index > #capture.entries then
            capture.file:close()
            log('capture.saved', 'count=' .. capture.count .. ' path=' .. capture.path)
            capture, pending = nil, false
            if native then
                local accepted = native.say('Diagnóstico salvo.', true)
                log('capture.feedback', accepted and 'accepted' or 'rejected')
            end
        end
    end
    request_capture = dump
    RegisterKeyBind(Key.F8, guarded('key.F8', dump))
    RegisterKeyBind(Key.F9, guarded('key.F9', dump))
    log('ui.keys.ready', 'F8/F9 incremental capture of registered window buttons')

    local quarantined = {}
    local content_blocked = {}
    local unlabeled = {}
    local poll_pending = false
    local enabled = true
    local function initialize_native()
        if native then return end
        log('native.load.begin', script_dir .. 'fallen_speech.dll')
        local open, err = package.loadlib(script_dir .. 'fallen_speech.dll', 'luaopen_fallen_speech')
        assert(open, err)
        native = open()
        assert(native.init(config.output), 'Native speech initialization failed')
        log('native.load.end', 'Speech worker started inside game process')
    end
    local last_identity, candidate_identity, stable_count = nil, nil, 0
    local last_label, last_value, last_window, last_notice, last_tab = nil, nil, nil, nil, nil
    local function reset_selection()
        last_identity, candidate_identity, stable_count = nil, nil, 0
        last_label, last_value = nil, nil
        last_window = nil
        content_cache = nil
    end
    local function enqueue(identity, text)
        if type(text) ~= 'string' or text:match('^%s*$') then return false end
        if not utf8.len(text) then log('speech.invalid_utf8', identity); return false end
        local file, err = io.open(config.output .. '/speech-requests.jsonl', 'a')
        if not file then log('speech.queue.error', err); return false end
        file:write(json({session=config.session, run=run_id, time=os.time(), identity=identity,
            text=text, interrupt=true}), '\n')
        file:flush(); file:close()
        local accepted = native.say(text, true)
        log(accepted and 'speech.accepted' or 'speech.rejected', identity .. ' text=' .. text)
        return accepted
    end
    local ambiguity_signature = nil
    local popup_owner = nil
    local combo_seen = {}
    local combo_state = nil
    local function list_choice(button, owner)
        local combo, source_field=combo_of(button)
        if not valid(combo) then return nil end
        if not combo_seen[owner.identity] then
            combo_seen[owner.identity]=true
            log('dropdown.owner',owner.identity .. ' source=' .. source_field)
        end
        popup_owner = {identity=owner.identity,window=owner.window}
        local own_focus, descendant_focus = combo:HasAnyUserFocus(),combo:HasFocusedDescendants()
        local focused = own_focus or descendant_focus
        local selected=text_value(combo:GetSelectedOption())
        local state=owner.identity .. '\n' .. tostring(own_focus) .. '\n' .. tostring(descendant_focus) .. '\n' .. tostring(selected)
        if state ~= combo_state then
            combo_state=state
            log('dropdown.state',json({identity=owner.identity,source=source_field,focus=own_focus,
                descendantFocus=descendant_focus,selected=selected}))
        end
        if not focused then dropdown_cache.focused=false; return nil end
        if dropdown_cache.owner ~= owner.identity or not dropdown_cache.focused
            or (#dropdown_cache.paths == 0 and clock_ms() >= dropdown_cache.due) then
            dropdown_cache = {paths={},owner=owner.identity,due=clock_ms()+3000,focused=true}
            -- One targeted discovery when the combo takes Slate focus. Never scan all buttons.
            for _, item in ipairs(FindAllOf('UI_Dropdown_Element_C') or {}) do
                if valid(item) then
                    local identity = item:GetFullName()
                    if identity:find('/Engine/Transient.',1,true) and #dropdown_cache.paths < 64 then
                        dropdown_cache.paths[#dropdown_cache.paths+1] = identity:match('^[^ ]+ (.+)$')
                    end
                end
            end
            log('dropdown.discovered', 'count=' .. #dropdown_cache.paths)
        end
        local selected, hovered, focus_count, hover_count = nil,nil,0,0
        for _, path in ipairs(dropdown_cache.paths) do
            local item = StaticFindObject(path)
            if valid(item) and visible_chain(item,path) then
                local target = item:GetPropertyValue('Button_0')
                if valid(target) then
                    if target:HasAnyUserFocus() or target:HasFocusedDescendants() then selected=item; focus_count=focus_count+1
                    elseif target:IsHovered() then hovered=item; hover_count=hover_count+1 end
                end
            end
        end
        if focus_count > 1 then return nil end
        local item = focus_count == 1 and selected or (hover_count == 1 and hovered or nil)
        if not item then return nil end
        local parts = field_parts(item, 'txt')
        if not parts then return nil end
        return {identity=item:GetFullName(), label=joined(parts), kind='dropdown', active=true,
            window=owner.window, session=config.session,run=run_id,valueSource='focused displayed dropdown text'}
    end
    local function current_tab(window)
        local row=window:GetPropertyValue('CurrentRow')
        if not isa(row, REMAP_ROW) then return nil end
        local found=false
        each_object(window:GetPropertyValue('TabRows'),function(tab)
            if valid(tab) and tab:GetAddress()==row:GetAddress() then found=true end
        end)
        if found then return joined(field_parts(row,'ActionName')) end
        return nil
    end
    local function choose_control(candidates)
        -- The manual options captures prove the shell retains its focus behind GameMenu.
        -- Route that known overlay explicitly; do not guess the order of other windows.
        local game_menu_active = false
        for _, row in ipairs(candidates) do
            if row.windowRole == 'game-menu' then game_menu_active = true end
        end
        local chosen, identities = nil, {}
        for _, row in ipairs(candidates) do
            if not (game_menu_active and row.windowRole == 'shell') then
                identities[#identities + 1] = row.identity
                chosen = row
            end
        end
        if #identities > 1 then
            table.sort(identities)
            local signature = table.concat(identities, '\n')
            if signature ~= ambiguity_signature then log('selection.ambiguous', json(candidates)) end
            ambiguity_signature = signature
            return nil
        end
        ambiguity_signature = nil
        return chosen
    end
    local window_signature=nil
    local function poll_selection()
        initialize_native()
        local live_windows
        paths,live_windows=find_windows()
        local candidates, buttons, game_menu_open, remap_open, remap_window = {}, {}, false, false, nil
        local visible_windows, frames, signature_parts = {}, {}, {}
        for _, entry in ipairs(paths) do
            stage('window.resolve ' .. entry.identity)
            local window = live_windows[entry.path]
            if valid(window) and (not quarantined[entry.identity] or clock_ms() >= quarantined[entry.identity]) then
                local before_errors = read_errors
                local ok, err = xpcall(function()
                    stage('window.state ' .. entry.identity)
                    local info = window_info(window)
                    if info.windowInViewport and info.windowVisible then
                        visible_windows[info.window]=true
                        signature_parts[#signature_parts+1]=info.window .. ':' .. tostring(info.windowInputEnabled) .. ':' .. tostring(info.acceptGroup)
                    end
                    if info.windowRole == 'remap' and info.windowInViewport and info.windowVisible then
                        remap_open=true; remap_window=window
                    end
                    if info.windowInViewport and info.windowVisible and info.windowInputEnabled then
                        if info.windowRole == 'game-menu' then game_menu_open = true end
                        frames[#frames+1]={window=window,info=info,entry=entry}
                    end
                end, traceback)
                if not ok or read_errors ~= before_errors then
                    quarantined[entry.identity] = clock_ms()+1000
                    log('window.unsupported', entry.identity .. ' ' .. (ok and 'getter error' or tostring(err)))
                end
            end
        end
        table.sort(signature_parts)
        local signature=table.concat(signature_parts,'\n')
        if signature ~= window_signature then
            window_signature=signature
            reset_selection()
            content_blocked={}; field_blocked={}; popup_owner=nil
            dropdown_cache={paths={},owner=nil,due=0,focused=false}
            if capture then
                capture.file:close(); capture,pending=nil,false
                log('capture.cancelled','window changed during capture')
            end
            log('windows.transition','live OpenWindows changed; old context discarded')
        end
        for _, frame in ipairs(frames) do
            local entry,window,info=frame.entry,frame.window,frame.info
            local before_errors=read_errors
            local ok,err=xpcall(function()
                stage('window.focus ' .. entry.identity)
                local button=window:GetFocusedButton(info.acceptGroup,false)
                if valid(button) then
                    local identity=button:GetFullName()
                    stage('button.state ' .. identity)
                    local row=describe(button,identity,'rs',info,false)
                    if row.active then candidates[#candidates+1]=row;buttons[identity]=button end
                end
            end,traceback)
            if not ok or read_errors~=before_errors then
                quarantined[entry.identity]=clock_ms()+1000
                log('window.unsupported',entry.identity .. ' ' .. (ok and 'getter error' or tostring(err)))
            end
        end
        -- An open options window can briefly have no focus during a page transition.
        if game_menu_open or remap_open then
            local foreground = {}
            for _, row in ipairs(candidates) do
                if row.windowRole ~= 'shell' and not (remap_open and row.windowRole == 'game-menu') then
                    foreground[#foreground+1] = row
                end
            end
            candidates = foreground
        end
        local chosen = choose_control(candidates)
        if not chosen and popup_owner and visible_windows[popup_owner.window] and not remap_open then
            local owner=StaticFindObject(popup_owner.identity:match('^[^ ]+ (.+)$'))
            if valid(owner) then
                local ok, result=pcall(list_choice,owner,popup_owner)
                if ok then chosen=result end
            end
        end
        local notice, notice_key
        if remap_window then
            notice = joined(field_parts(remap_window, 'Message'))
            if notice then notice_key = remap_window:GetFullName() .. '\n' .. notice end
        else last_notice = nil end
        if not chosen and notice_key and notice_key ~= last_notice then
            if enqueue(remap_window:GetFullName(), notice) then last_notice=notice_key end
        end
        if not chosen then reset_selection(); return end
        local choice_ok, choice = true,nil
        if chosen.kind ~= 'dropdown' then choice_ok,choice=pcall(list_choice, buttons[chosen.identity], chosen) end
        if not choice_ok then
            if not unlabeled['dropdown:' .. chosen.identity] then
                unlabeled['dropdown:' .. chosen.identity]=true; log('dropdown.error',tostring(choice))
            end
        elseif choice then chosen=choice end
        if candidate_identity ~= chosen.identity then
            candidate_identity, stable_count = chosen.identity, 1
            return
        end
        stable_count = stable_count + 1
        if stable_count < 2 then return end
        if content_blocked[chosen.identity] then return end
        local before_errors = read_errors
        local ok, row = xpcall(function()
            if chosen.kind == 'dropdown' then return chosen end
            return describe(buttons[chosen.identity], chosen.identity, 'rs', chosen, 'cached')
        end, traceback)
        if not ok or (read_errors ~= before_errors and (not row.label or not row.label:match('%S'))) then
            content_blocked[chosen.identity] = true
            if not unlabeled[chosen.identity] then
                unlabeled[chosen.identity] = true
                log('control.unsupported', chosen.identity .. ' ' .. (ok and 'getter error' or tostring(row)))
            end
            return
        end
        if read_errors ~= before_errors then log('control.partial',chosen.identity .. ' binding field unavailable; actual label retained') end
        chosen = row
        local tab, tab_key
        if remap_window then
            local tab_ok, result=pcall(current_tab,remap_window)
            if tab_ok then tab=result
            elseif not unlabeled['tab:' .. chosen.window] then
                unlabeled['tab:' .. chosen.window]=true;log('tab.unsupported',tostring(result))
            end
            if tab then tab_key=remap_window:GetFullName() .. '\n' .. tab end
        else last_tab=nil end
        if not tab then last_tab=nil end
        if not chosen.label or not chosen.label:match('%S') then
            if not unlabeled[chosen.identity] then
                unlabeled[chosen.identity] = true
                log('selection.unlabeled', json(chosen))
            end
            return
        end
        local text
        if chosen.identity ~= last_identity or chosen.label ~= last_label then
            text = chosen.label
            if chosen.value and chosen.value ~= '' then text = text .. ': ' .. chosen.value end
        elseif chosen.value ~= last_value and chosen.value and chosen.value ~= '' then
            text = chosen.value
        end
        if tab_key and tab_key ~= last_tab then text=tab end
        if notice_key and notice_key ~= last_notice then
            text = text and (notice .. '. ' .. text) or notice
        end
        if text and enqueue(chosen.identity, text) then
            log('selection.reading', json(chosen))
            last_identity, last_label, last_value = chosen.identity, chosen.label, chosen.value
            last_window, last_notice = chosen.window, notice_key
            if tab_key then last_tab=tab_key end
        end
    end
    local performance = {polls=0, total=0, max=0, slow=0}
    LoopAsync(100, function()
        if not enabled or poll_pending then return false end
        poll_pending = true
        local queued, queue_error = pcall(function()
            ExecuteInGameThread(function()
                if not enabled then poll_pending = false; return end
                local started = native and clock_ms() or nil
                stage('poll.begin')
                local ok, err = xpcall(poll_selection, traceback)
                local elapsed = started and clock_ms() - started or 0
                performance.polls = performance.polls + 1
                performance.total = performance.total + elapsed
                performance.max = math.max(performance.max, elapsed)
                if elapsed >= 12 then performance.slow = performance.slow + 1 end
                if performance.polls % 50 == 0 then
                    log('performance.poll', json({count=performance.polls, meanMs=performance.total/performance.polls,
                        maxMs=performance.max, slowOver12Ms=performance.slow, windows=#paths,
                        captureMaxMs=performance.captureMax or 0}))
                end
                if ok and pending and elapsed < 3 then
                    local capture_started = clock_ms()
                    local captured, capture_error = xpcall(capture_step, traceback)
                    performance.captureMax = math.max(performance.captureMax or 0, clock_ms()-capture_started)
                    if not captured then
                        if capture then capture.file:close() end
                        capture, pending = nil, false
                        log('capture.error', capture_error)
                    end
                end
                stage('idle')
                poll_pending = false
                if not ok then
                    enabled = false
                    reset_selection()
                    log('reader.disabled.error', ok and 'native getter returned Lua error; reader disabled for this run' or err)
                end
            end)
        end)
        if not queued then
            poll_pending, enabled = false, false
            log('reader.disabled.error', queue_error)
        end
        return false
    end)
    log('reader.ready', '100ms live OpenWindows poll; root discovery only when needed; incremental diagnostics; in-process Prism')
end
