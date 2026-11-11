-- DELTA FPS DEEP DIAGNOSTIC v2.0 | Observational unless FPS request button is tapped
-- Captures RunService rates, callback intervals, touch/camera/movement activity, viewport, graphics preference, FPS cap readback.
-- The 120/240 buttons call executor-provided setfpscap() only when available.
-- NOT a native GPU, Metal, physical screen Hz or internal AdaptiveSync probe. No usernames, touch coordinates, chat or networking.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService('CoreGui')
local context = (type(getgenv) == 'function' and getgenv()) or _G
if context.DeltaFPSProbeShutdown then pcall(context.DeltaFPSProbeShutdown) end

local active = true
local connections = {}
local prevCap = 60
local havePrevCap = false
local modifiedCap = false
local setCap = setfpscap
local getCap = getfpscap
if type(getCap) == 'function' then
  local ok, value = pcall(getCap)
  if ok and type(value) == 'number' and value > 0 then
    prevCap, havePrevCap = value, true
  end
end

local parent = nil
if type(gethui) == 'function' then
  local ok, value = pcall(gethui)
  if ok and value then parent = value end
end
if not parent then
  local ok = pcall(function() return CoreGui.Name end)
  parent = ok and CoreGui or LocalPlayer:WaitForChild('PlayerGui')
end

local function create(class, props, target)
  local inst = Instance.new(class)
  for prop, value in pairs(props) do inst[prop] = value end
  inst.Parent = target
  return inst
end
local gui = create('ScreenGui', {
  Name='DeltaFPSProbe', ResetOnSpawn=false, IgnoreGuiInset=true,
  ZIndexBehavior=Enum.ZIndexBehavior.Sibling
}, parent)
local frame = create('Frame', {
  Size=UDim2.fromOffset(296,316), Position=UDim2.new(0.5,-148,0.13,0),
  BackgroundColor3=Color3.fromRGB(20,23,30), BorderSizePixel=0, Active=true
}, gui)
create('UICorner',{CornerRadius=UDim.new(0,14)},frame)
create('UIStroke',{Color=Color3.fromRGB(67,77,95),Transparency=0.3,Thickness=1},frame)
local header=create('TextLabel',{
  Size=UDim2.new(1,-75,0,37), Position=UDim2.fromOffset(12,5),
  BackgroundTransparency=1,Text='DELTA  /  DEEP FRAME PROBE',TextColor3=Color3.fromRGB(230,238,250),
  TextSize=15,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold
},frame)
local close=create('TextButton',{
  Size=UDim2.fromOffset(30,30),Position=UDim2.new(1,-37,0,8),
  Text='×',TextSize=23,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(240,240,245),
  BackgroundColor3=Color3.fromRGB(62,65,73),BorderSizePixel=0
},frame)
create('UICorner',{CornerRadius=UDim.new(0,8)},close)
local rate=create('TextLabel',{
  Size=UDim2.new(1,-24,0,42),Position=UDim2.fromOffset(12,46),BackgroundTransparency=1,
  Text='Collecting baseline...',TextColor3=Color3.fromRGB(178,218,255),
  TextSize=17,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold
},frame)
local extra=create('TextLabel',{
  Size=UDim2.new(1,-24,0,43),Position=UDim2.fromOffset(12,92),BackgroundTransparency=1,
  Text='Waiting for 3-second sample.',TextColor3=Color3.fromRGB(190,198,211),
  TextSize=12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
  TextYAlignment=Enum.TextYAlignment.Top,Font=Enum.Font.Gotham
},frame)
local function btn(name,x,y,w)
  local b=create('TextButton',{
    Size=UDim2.fromOffset(w,34),Position=UDim2.fromOffset(x,y),Text=name,TextSize=13,
    Font=Enum.Font.GothamBold,TextColor3=Color3.fromRGB(240,244,250),
    BackgroundColor3=Color3.fromRGB(48,67,88),BorderSizePixel=0
  },frame)
  create('UICorner',{CornerRadius=UDim.new(0,8)},b)
  return b
end
local request120=btn('Request 120',12,161,130)
local request240=btn('Request 240',153,161,130)
local restore=btn('Restore cap',12,200,130)
local export=btn('Copy report',153,200,130)
local mark=btn('Mark activity',12,239,130)
local pause=btn('Pause capture',153,239,130)
local phaseText=create('TextLabel',{Size=UDim2.new(1,-24,0,20), Position=UDim2.fromOffset(12,139),BackgroundTransparency=1,Text='Activity: NATURAL',TextColor3=Color3.fromRGB(185,235,185),TextSize=11,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left},frame)
local minimize=btn('–',217,7,25)
minimize.Size=UDim2.fromOffset(27,29)
minimize.Position=UDim2.new(1,-72,0,8)
local status=create('TextLabel',{
  Size=UDim2.new(1,-24,0,30),Position=UDim2.fromOffset(12,280),
  BackgroundTransparency=1,Text='Recording 1-second windows (no FPS cap changed).',
  TextColor3=Color3.fromRGB(183,200,213),TextSize=11,
  TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Gotham
},frame)

-- Drag the HEADER, not all buttons.
local dragging=false
local dragOrigin, frameOrigin
local function bind(signal,fn) table.insert(connections,signal:Connect(fn)) end
bind(header.InputBegan,function(input)
  if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
    dragging=true;dragOrigin=input.Position;frameOrigin=frame.Position
  end
end)
bind(UserInputService.InputChanged,function(input)
  if dragging and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
    local delta=input.Position-dragOrigin
    frame.Position=UDim2.new(frameOrigin.X.Scale,frameOrigin.X.Offset+delta.X,frameOrigin.Y.Scale,frameOrigin.Y.Offset+delta.Y)
  end
end)
bind(UserInputService.InputEnded,function(input)
  if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
    dragging=false
  end
end)


-- Lightweight telemetry, kept exclusively in memory until "Copy report".
local started=os.clock()
local activeCapture=true
local phases={'NATURAL','STILL','CAMERA','MOVEMENT','JUMP','TOUCH','BUSY SCENE'}
local phaseIdx=1
local logs, events={},{}
local total=0
local maxSamples=180
local values={render=0,heartbeat=0,pre=0,post=0,touchBegin=0,touchMove=0,keyboard=0,gamepad=0,jumps=0,move=0}
local elapsedWindow=os.clock()
local intervals,lookPrevious={},nil
local renderPrevious=nil
local angleSum=0
local speedMax=0
local humanoid,root
local charConnections={}
local function logEvent(kind,message)
  events[#events+1]=string.format('t=%.1f %s: %s',os.clock()-started,kind,message)
  if #events>80 then table.remove(events,1) end
end
local function resetWindow()
  for k in pairs(values) do values[k]=0 end
  intervals={};lookPrevious=nil;renderPrevious=nil;angleSum=0;speedMax=0
end
local function disconnectChar()
  for _,conn in ipairs(charConnections) do pcall(function()conn:Disconnect()end) end
  charConnections={}
end
local function attachCharacter(char)
  disconnectChar()
  if not char then humanoid=nil;root=nil;return end
  humanoid=char:FindFirstChildOfClass('Humanoid')
  root=char:FindFirstChild('HumanoidRootPart')
  if humanoid then
    table.insert(charConnections,humanoid.StateChanged:Connect(function(_,state)
      if activeCapture and state==Enum.HumanoidStateType.Jumping then values.jumps=values.jumps+1 end
    end))
  end
  task.defer(function()
    if not active or LocalPlayer.Character~=char then return end
    local hum=char:FindFirstChildOfClass('Humanoid') or char:WaitForChild('Humanoid',5)
    local rp=char:FindFirstChild('HumanoidRootPart') or char:WaitForChild('HumanoidRootPart',5)
    if not active or LocalPlayer.Character~=char then return end
    if hum and hum~=humanoid then
      disconnectChar()
      humanoid=hum
      table.insert(charConnections,hum.StateChanged:Connect(function(_,state)
        if activeCapture and state==Enum.HumanoidStateType.Jumping then values.jumps=values.jumps+1 end
      end))
    end
    root=rp
  end)
end
attachCharacter(LocalPlayer.Character)
bind(LocalPlayer.CharacterAdded,attachCharacter)
local signal=RunService.PreRender or RunService.RenderStepped
local renderEvent=(RunService.PreRender and 'PreRender') or 'RenderStepped'
local velocityRead=0
bind(signal,function()
  if not activeCapture then return end
  values.render=values.render+1
  local now=os.clock()
  if renderPrevious then
    local diff=(now-renderPrevious)*1000
    if diff>0 and diff<3000 then intervals[#intervals+1]=diff end
  end
  renderPrevious=now
  local cam=workspace.CurrentCamera
  if cam then
    local direction=cam.CFrame.LookVector
    if lookPrevious then
      local dot=math.clamp(direction:Dot(lookPrevious),-1,1)
      angleSum=angleSum+math.deg(math.acos(dot))
    end
    lookPrevious=direction
  end
  if now-velocityRead>=0.2 then
    velocityRead=now
    if root and root.Parent then
      local v=root.AssemblyLinearVelocity
      local speed=math.sqrt(v.X*v.X+v.Z*v.Z)
      if speed>1 then values.move=values.move+1 end
      if speed>speedMax then speedMax=speed end
    end
  end
end)
bind(RunService.Heartbeat,function() if activeCapture then values.heartbeat=values.heartbeat+1 end end)
if RunService.PreSimulation then bind(RunService.PreSimulation,function() if activeCapture then values.pre=values.pre+1 end end) end
if RunService.PostSimulation then bind(RunService.PostSimulation,function() if activeCapture then values.post=values.post+1 end end) end
bind(UserInputService.InputBegan,function(input)
  if not activeCapture then return end
  local kind=input.UserInputType
  if kind==Enum.UserInputType.Touch then values.touchBegin=values.touchBegin+1
  elseif kind==Enum.UserInputType.Keyboard then values.keyboard=values.keyboard+1
  elseif tostring(kind):find('Gamepad',1,true) then values.gamepad=values.gamepad+1 end
end)
bind(UserInputService.InputChanged,function(input)
  if activeCapture and input.UserInputType==Enum.UserInputType.Touch then
    values.touchMove=values.touchMove+1
  end
end)
local settings
pcall(function()settings=UserSettings():GetService('UserGameSettings')end)
local function readState()
  local cam=workspace.CurrentCamera
  local size=cam and cam.ViewportSize
  local viewport=size and string.format('%dx%d',size.X,size.Y) or '?'
  local fov=cam and string.format('%.1f',cam.FieldOfView) or '?'
  local quality='unavailable'
  if settings then
    local ok,v=pcall(function()return settings.SavedQualityLevel end)
    if ok then quality=tostring(v) end
  end
  local cap='unavailable'
  if type(getCap)=='function' then
    local ok,v=pcall(getCap)
    if ok then cap=tostring(v) end
  end
  local physics='unavailable'
  local ok,p=pcall(function()return workspace:GetRealPhysicsFPS() end)
  if ok and type(p)=='number' then physics=string.format('%.1f',p) end
  return {viewport=viewport,fov=fov,quality=quality,cap=cap,physics=physics}
end
local initialState=readState()
local lastState=initialState
local capRequest='none'
local function percentile(array,p)
  if #array==0 then return 0 end
  return array[math.max(1,math.ceil(#array*p))]
end
local function aggregate(dt)
  if dt<=0 then return end
  table.sort(intervals)
  local spikes25,spikes33,spikes50=0,0,0
  for _,v in ipairs(intervals) do
    if v>25 then spikes25=spikes25+1 end
    if v>33.3 then spikes33=spikes33+1 end
    if v>50 then spikes50=spikes50+1 end
  end
  local state=readState()
  for _,key in ipairs({'viewport','fov','quality','cap'}) do
    if state[key]~=lastState[key] then
      logEvent('CHANGE',key..' '..lastState[key]..' -> '..state[key])
    end
  end
  lastState=state
  local row={
    t=os.clock()-started,phase=phases[phaseIdx],
    render=values.render/dt,heart=values.heartbeat/dt,
    pre=values.pre/dt,post=values.post/dt,
    p50=percentile(intervals,0.50),p95=percentile(intervals,0.95),
    p99=percentile(intervals,0.99),max=percentile(intervals,1),
    spikes25=spikes25,spikes33=spikes33,spikes50=spikes50,
    camera=angleSum/dt,move=values.move,topSpeed=speedMax,
    touches=values.touchBegin,touchChanges=values.touchMove,
    jumps=values.jumps,keys=values.keyboard,gamepads=values.gamepad,
    viewport=state.viewport,fov=state.fov,quality=state.quality,
    requested=capRequest,cap=state.cap,physics=state.physics
  }
  logs[#logs+1]=row;total=total+1
  if #logs>maxSamples then table.remove(logs,1) end
  rate.Text=string.format('%s %.1f/s | p95 %.1fms',renderEvent,row.render,row.p95)
  extra.Text=string.format('Heartbeat %.1f/s | PreSim %.1f/s | physics %s\nCam %.0f°/s | Touch changes %d | Viewport %s',row.heart,row.pre,row.physics,row.camera,row.touchChanges,row.viewport)
  resetWindow()
end
bind(mark.MouseButton1Click,function()
  phaseIdx=phaseIdx%#phases+1
  phaseText.Text='Activity: '..phases[phaseIdx]
  logEvent('PHASE',phases[phaseIdx])
end)
bind(pause.MouseButton1Click,function()
  activeCapture=not activeCapture
  pause.Text=activeCapture and 'Pause capture' or 'Resume capture'
  phaseText.Text='Activity: '..phases[phaseIdx]..(activeCapture and '' or ' (paused)')
  logEvent('CAPTURE',activeCapture and 'resumed' or 'paused')
  resetWindow()
end)
bind(minimize.MouseButton1Click,function()
  local small=frame.Size.Y.Offset>50
  frame.Size=UDim2.fromOffset(296,small and 45 or 316)
  for _,v in ipairs({rate,extra,phaseText,request120,request240,restore,export,mark,pause,status}) do v.Visible=not small end
  minimize.Text=small and '+' or '–'
end)
local function changeCap(n)
  if type(setCap)~='function' then status.Text='setfpscap() unavailable.';return end
  local ok,err=pcall(setCap,n)
  if not ok then status.Text='FPS request error: '..tostring(err):sub(1,42);return end
  modifiedCap=true;capRequest=tostring(n)
  local state=readState()
  logEvent('CAP','requested '..n..', getfpscap='..state.cap)
  status.Text='Requested '..n..'; readback: '..state.cap
end
bind(request120.MouseButton1Click,function()changeCap(120)end)
bind(request240.MouseButton1Click,function()changeCap(240)end)
bind(restore.MouseButton1Click,function()
  if not modifiedCap then status.Text='No requested change to restore.';return end
  if type(setCap)=='function' then
    local ok,err=pcall(setCap,havePrevCap and prevCap or 60)
    if not ok then status.Text='Restore error: '..tostring(err):sub(1,42);return end
  end
  modifiedCap=false;capRequest='restored'
  logEvent('CAP','restored cap')
  status.Text='Original cap restored.'
end)
local function report()
  local out={
    'DELTA DEEP FPS PROBE v2.0 | Local telemetry',
    string.format('Elapsed %.1f seconds | samples kept %d | samples total %d',os.clock()-started,#logs,total),
    'Render event: '..renderEvent,
    'Initial cap: '..(havePrevCap and tostring(prevCap) or 'unavailable'),
    'Last cap request: '..capRequest,
    'Current cap: '..readState().cap,
    'Initial viewport: '..initialState.viewport..' | current viewport: '..readState().viewport,
    'Initial graphics preference: '..initialState.quality,
    'TouchEnabled='..tostring(UserInputService.TouchEnabled)..'; KeyboardEnabled='..tostring(UserInputService.KeyboardEnabled),
    'NOTE: Viewport dimensions are the Roblox camera viewport, NOT physical display resolution.',
    'NOTE: Cannot read true display refresh Hz, GPU present counts, native Metal calls or internal AdaptiveSync requests from Luau.',
    'NOTE: setfpscap success only means no API error; does not prove actual FPS scheduling changed.',
    '',
    'TIMELINE / MANUAL MARKERS:'
  }
  if #events==0 then out[#out+1]='No markers or property changes.' end
  for _,ev in ipairs(events) do out[#out+1]=ev end
  out[#out+1]=''
  out[#out+1]='SAMPLES (one per second; callback intervals are NOT GPU frame times):'
  if #logs==0 then out[#out+1]='No samples yet; leave recording on for a few seconds.' end
  for i,v in ipairs(logs) do
    out[#out+1]=string.format(
      '#%03d t=%.1fs phase=%s | preRender=%.1f/s heartbeat=%.1f/s preSim=%.1f/s postSim=%.1f/s | interFrameMs p50/p95/p99/max=%.1f/%.1f/%.1f/%.1f | spikes >25/33/50ms=%d/%d/%d | cameraDeg/s=%.0f moveSamples=%d maxSpeed=%.1f | touchStarts=%d touchChanges=%d jumps=%d keys=%d gamepads=%d | request=%s getfpscap=%s viewport=%s FOV=%s graphics=%s physicsFPS=%s',
      i,v.t,v.phase,v.render,v.heart,v.pre,v.post,v.p50,v.p95,v.p99,v.max,
      v.spikes25,v.spikes33,v.spikes50,v.camera,v.move,v.topSpeed,
      v.touches,v.touchChanges,v.jumps,v.keys,v.gamepads,
      v.requested,v.cap,v.viewport,v.fov,v.quality,v.physics
    )
  end
  out[#out+1]=''
  out[#out+1]='PRIVACY: No player identity, chat messages, touch positions or camera coordinates collected. No file or network output.'
  out[#out+1]='LIMITATION: RunService callbacks are not distinct GPU-rendered frames.'
  return table.concat(out,'\n')
end
bind(export.MouseButton1Click,function()
  local copyFn=type(setclipboard)=='function' and setclipboard or
    (type(toclipboard)=='function' and toclipboard or nil)
  if not copyFn then status.Text='Clipboard API unavailable.';return end
  local output=report()
  local ok,err=pcall(copyFn,output)
  status.Text=ok and string.format('Copied %d samples (%d chars).',#logs,#output)
    or ('Copy failed: '..tostring(err):sub(1,45))
end)
local function shutdown()
  if not active then return end
  active=false
  if modifiedCap and type(setCap)=='function' then
    pcall(setCap,havePrevCap and prevCap or 60)
  end
  disconnectChar()
  for _,conn in ipairs(connections) do pcall(function()conn:Disconnect()end) end
  pcall(function()gui:Destroy()end)
  if context.DeltaFPSProbeShutdown==shutdown then context.DeltaFPSProbeShutdown=nil end
end
context.DeltaFPSProbeShutdown=shutdown
bind(close.MouseButton1Click,shutdown)
task.spawn(function()
  local last=os.clock()
  while active do
    task.wait(1)
    if not active then break end
    local now=os.clock()
    local dt=now-last
    last=now
    if activeCapture then aggregate(dt) end
  end
end)
