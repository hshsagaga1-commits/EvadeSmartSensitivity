# EvadeSmartSensitivity

Sensibilidade adaptativa de câmera para testar no Evade pelo celular.

## Como funciona
- Arrasto lento: multiplicador baixo para mirar com precisão.
- Giro rápido: o multiplicador sobe progressivamente.
- Viradas secas para esquerda/direita: a velocidade angular é medida em valor absoluto, então inverter o sentido não zera automaticamente a aceleração.
- Suavização e limite máximo para reduzir picos.
- Só escreve na rotação da câmera; não altera o CFrame do personagem nem os controles de movimento.

## Arquivo
`EvadeSmartSensitivity.lua`

## Loader
Depois que o arquivo estiver na branch `main`, o loader será:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/EvadeSmartSensitivity/main/EvadeSmartSensitivity.lua?nocache=" .. tostring(os.time()) .. tostring(math.random(100000,999999))))()
```

## Importante
Esta versão é experimental e ainda precisa ser testada no cliente do jogo. Ela depende de a câmera estar em `CameraType.Scriptable` e de o ambiente permitir execução de Lua no cliente. Se o controlador de câmera do jogo sobrescrever o resultado, a implementação precisará ser adaptada ao controlador real. Não há promessa de compatibilidade universal.
