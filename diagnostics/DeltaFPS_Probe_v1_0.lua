-- Delta FPS Probe (iOS) v1.1 -- READ ONLY BY DEFAULT
-- Measures RunService callback rates, NOT distinct GPU frames.
-- The 120/240 buttons call executor-provided setfpscap() only when available.
-- Do not mistake reported 120 callbacks for 120 unique GPU-rendered frames.

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
  Size=UDim2.fromOffset(296,250), Position=UDim2.new(0.5,-148,0.24,0),
  BackgroundColor3=Color3.fromRGB(20,23,30), BorderSizePixel=0, Active=true
}, gui)
create('UICorner',{CornerRadius=UDim.new(0,14)},frame)
create('UIStroke',{Color=Color3.fromRGB(67,77,95),Transparency=0.3,Thickness=1},frame)
local header=create('TextLabel',{
  Size=UDim2.new(1,-48,0,37), Position=UDim2.fromOffset(12,5),
  BackgroundTransparency=1,Text='DELTA  /  FRAME PROBE',TextColor3=Color3.fromRGB(230,238,250),
  TextSize=15,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold
},frame)
local close=create('TextButton',{
  Size=UDim2.fromOffset(30,30),Position=UDim2.new(1,-37,0,8),
  Text='×',TextSize=23,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(240,240,245),
  BackgroundColor3=Color3.fromRGB(62,65,73),BorderSizePixel=0
},frame)
create('UICorner',{CornerRadius=UDim.new(0,8)},close)
local rate=create('TextLabel',{
  Size=UDim2.new(1,-24,0,48),Position=UDim2.fromOffset(12,48),BackgroundTransparency=1,
  Text='Collecting baseline...',TextColor3=Color3.fromRGB(178,218,255),
  TextSize=17,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold
},frame)
local extra=create('TextLabel',{
  Size=UDim2.new(1,-24,0,38),Position=UDim2.fromOffset(12,95),BackgroundTransparency=1,
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
local request120=btn('Request 120',12,139,130)
local request240=btn('Request 240',153,139,130)
local restore=btn('Restore cap',12,180,130)
local export=btn('Copy report',153,180,130)
local status=create('TextLabel',{
  Size=UDim2.new(1,-24,0,23),Position=UDim2.fromOffset(12,221),
  BackgroundTransparency=1,Text='Observing only. No FPS cap changed.',
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

local counters={render=0,heartbeat=0,presim=0}
local renderSignal=RunService.PreRender or RunService.RenderStepped
local renderName=(RunService.PreRender and 'PreRender') or 'RenderStepped'
bind(renderSignal,function() counters.render=counters.render+1 end)
bind(RunService.Heartbeat,function() counters.heartbeat=counters.heartbeat+1 end)
if RunService.PreSimulation then
  bind(RunService.PreSimulation,function() counters.presim=counters.presim+1 end)
end
local samples={}
local started=os.clock()
local capRequest='none'
local function requestCap(n)
  if type(setCap)~='function' then
    status.Text='setfpscap() unavailable in this executor.'
    return
  end
  local ok,err=pcall(setCap,n)
  if ok then
    capRequest=tostring(n);modifiedCap=true
    status.Text='Requested '..n..' FPS. Measuring callbacks...'
  else
    status.Text='setfpscap() failed: '..tostring(err):sub(1,45)
  end
end
bind(request120.MouseButton1Click,function()requestCap(120)end)
bind(request240.MouseButton1Click,function()requestCap(240)end)
bind(restore.MouseButton1Click,function()
  if not modifiedCap then status.Text='No change to restore.';return end
  if type(setCap)=='function' then
    pcall(setCap,havePrevCap and prevCap or 60)
  end
  capRequest='restored';modifiedCap=false
  status.Text='Previous cap restored (or fallback 60).'
end)
-- Copy a readable report directly to the clipboard (no files required).
local function buildReport()
  local lines={
    'Delta FPS Probe v1.1 - Relatorio',
    'Tempo desde inicio: '..string.format('%.1f s',os.clock()-started),
    'Evento de render: '..renderName,
    'Cap inicial: '..(havePrevCap and tostring(prevCap) or 'indisponivel'),
    'Cap solicitado: '..capRequest,
    'Amostras: '..tostring(#samples),
    '',
    'Medicoes (cada amostra dura aproximadamente 3 segundos):'
  }
  if #samples==0 then
    lines[#lines+1]='Ainda sem amostras. Aguarde 3 segundos e copie novamente.'
  else
    for i,item in ipairs(samples) do
      lines[#lines+1]=string.format(
        '#%d | t=%.1fs | %s=%.1f/s | Heartbeat=%.1f/s | PreSimulation=%.1f/s | pedido=%s',
        i,item.elapsed,renderName,item.render,item.heartbeat,item.presim,item.cap
      )
    end
  end
  lines[#lines+1]=''
  lines[#lines+1]='ATENCAO: estes sao callbacks do RunService, NAO quadros GPU distintos.'
  return table.concat(lines,'\n')
end
bind(export.MouseButton1Click,function()
  local copyFn=nil
  if type(setclipboard)=='function' then
    copyFn=setclipboard
  elseif type(toclipboard)=='function' then
    copyFn=toclipboard
  end
  if not copyFn then
    status.Text='Clipboard indisponivel neste executor.'
    return
  end
  local ok,err=pcall(copyFn,buildReport())
  status.Text=ok and ('Report copied! ('..tostring(#samples)..' samples)')
    or ('Copy failed: '..tostring(err):sub(1,38))
end)
local function shutdown()
  if not active then return end
  active=false
  if modifiedCap and type(setCap)=='function' then
    pcall(setCap,havePrevCap and prevCap or 60)
  end
  for _,conn in ipairs(connections) do pcall(function()conn:Disconnect()end) end
  if gui then pcall(function()gui:Destroy()end) end
  if context.DeltaFPSProbeShutdown==shutdown then context.DeltaFPSProbeShutdown=nil end
end
context.DeltaFPSProbeShutdown=shutdown
bind(close.MouseButton1Click,shutdown)

task.spawn(function()
  local last=os.clock()
  while active do
    task.wait(3)
    if not active then break end
    local now=os.clock();local dt=now-last
    if dt>0 then
      local r=counters.render/dt;local h=counters.heartbeat/dt;local s=counters.presim/dt
      rate.Text=string.format('%s: %.1f /s',renderName,r)
      extra.Text=string.format('Heartbeat: %.1f/s    PreSimulation: %.1f/s\nMeasured over %.1f seconds; not GPU FPS.',h,s,dt)
      samples[#samples+1]={elapsed=now-started,render=r,heartbeat=h,presim=s,cap=capRequest}
    end
    counters.render=0;counters.heartbeat=0;counters.presim=0;last=now
  end
end)