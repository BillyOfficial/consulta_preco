<#
  gerar_apk.ps1  -  Gera o APK de release do Consulta de Preco (Windows).

  O que faz, em um comando:
    1. Confere se 'flutter' e 'keytool' estao disponiveis.
    2. Na primeira vez: cria a keystore de release e o android/key.properties.
       (a keystore e a senha ficam SO na sua maquina - nunca vao para o Git)
    3. Roda 'flutter build apk --release' e mostra onde o APK ficou.

  COMO USAR (no PowerShell, dentro da pasta do projeto):
    powershell -ExecutionPolicy Bypass -File scripts\gerar_apk.ps1

  Opcoes:
    -SplitPerAbi   gera um APK menor por arquitetura (use o arm64-v8a no celular)
#>

param(
  [switch]$SplitPerAbi
)

$ErrorActionPreference = "Stop"

# Vai para a raiz do projeto (a pasta acima de scripts\)
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz
Write-Host "Projeto: $raiz`n" -ForegroundColor Cyan

# --- 1) Checagens de ambiente -------------------------------------------------
function Find-Command($nome) {
  $c = Get-Command $nome -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  return $null
}

if (-not (Find-Command "flutter")) {
  Write-Host "ERRO: 'flutter' nao encontrado no PATH. Instale o Flutter e tente de novo." -ForegroundColor Red
  exit 1
}

# keytool vem com o JDK. Tenta no PATH; senao, tenta o JAVA_HOME.
$keytool = Find-Command "keytool"
if (-not $keytool -and $env:JAVA_HOME) {
  $tent = Join-Path $env:JAVA_HOME "bin\keytool.exe"
  if (Test-Path $tent) { $keytool = $tent }
}

$keyProps = Join-Path $raiz "android\key.properties"
$keystore = Join-Path $raiz "android\app\consulta_preco-release.jks"

# --- 2) Keystore + key.properties (so na primeira vez) ------------------------
if (Test-Path $keyProps) {
  Write-Host "android\key.properties ja existe - pulando geracao da keystore.`n" -ForegroundColor Green
}
else {
  if (-not $keytool) {
    Write-Host "ERRO: 'keytool' nao encontrado. Ele vem com o JDK." -ForegroundColor Red
    Write-Host "Dica: defina JAVA_HOME apontando para o JDK (ex.: o 'jbr' do Android Studio) e rode de novo." -ForegroundColor Yellow
    exit 1
  }

  Write-Host "== Primeira execucao: vamos criar sua keystore de release ==" -ForegroundColor Cyan
  Write-Host "GUARDE BEM a senha e um backup do arquivo .jks." -ForegroundColor Yellow
  Write-Host "Sem eles, voce nao consegue ATUALIZAR o app nos celulares depois.`n" -ForegroundColor Yellow

  $senha = Read-Host "Crie uma senha para a keystore"
  if ([string]::IsNullOrWhiteSpace($senha)) {
    Write-Host "ERRO: senha vazia. Abortando." -ForegroundColor Red
    exit 1
  }
  $alias = "consulta_preco"

  if (-not (Test-Path $keystore)) {
    Write-Host "`nGerando keystore em: $keystore" -ForegroundColor Cyan
    $ktArgs = @(
      "-genkeypair", "-v",
      "-keystore", $keystore,
      "-storepass", $senha,
      "-keypass", $senha,
      "-alias", $alias,
      "-keyalg", "RSA",
      "-keysize", "2048",
      "-validity", "10000",
      "-dname", "CN=Consulta de Preco, OU=Pessoal, O=Pessoal, L=NA, ST=NA, C=BR"
    )
    & $keytool @ktArgs
    if ($LASTEXITCODE -ne 0) {
      Write-Host "ERRO ao gerar a keystore." -ForegroundColor Red
      exit 1
    }
  }
  else {
    Write-Host "Keystore ja existe em $keystore - reaproveitando." -ForegroundColor Green
  }

  # Escreve o key.properties (arquivo local, ignorado pelo Git)
  $linhas = @(
    "storePassword=$senha",
    "keyPassword=$senha",
    "keyAlias=$alias",
    "storeFile=consulta_preco-release.jks"
  )
  Set-Content -Path $keyProps -Value $linhas -Encoding ASCII
  Write-Host "`nCriado android\key.properties (fica so na sua maquina).`n" -ForegroundColor Green
}

# --- 3) Build do APK ----------------------------------------------------------
Write-Host "== Baixando dependencias (flutter pub get) ==" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERRO no 'flutter pub get'." -ForegroundColor Red
  exit 1
}

Write-Host "`n== Compilando o APK de release ==" -ForegroundColor Cyan
if ($SplitPerAbi) {
  flutter build apk --release --split-per-abi
}
else {
  flutter build apk --release
}
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERRO no 'flutter build apk'." -ForegroundColor Red
  exit 1
}

# --- 4) Resultado -------------------------------------------------------------
$saida = Join-Path $raiz "build\app\outputs\flutter-apk"
Write-Host "`n============================================" -ForegroundColor Green
Write-Host " APK gerado com sucesso!" -ForegroundColor Green
Write-Host " Pasta: $saida" -ForegroundColor Green
Get-ChildItem $saida -Filter *.apk | ForEach-Object {
  "{0,-38} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB) | Write-Host
}
Write-Host "============================================`n" -ForegroundColor Green
if ($SplitPerAbi) {
  Write-Host "Para celular moderno, use o arquivo:  app-arm64-v8a-release.apk" -ForegroundColor Cyan
}
else {
  Write-Host "Instale o arquivo:  app-release.apk  no seu celular e no da sua esposa." -ForegroundColor Cyan
}
