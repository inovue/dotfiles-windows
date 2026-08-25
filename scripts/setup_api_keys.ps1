#Requires -Version 5.1
<#
.SYNOPSIS
    AI Agent, Graphify, および fal.ai 用の API キーを Windows ユーザー環境変数に安全に登録します。
.DESCRIPTION
    リポジトリ内のファイルは一切変更せず、OSのユーザー環境変数 (HKCU\Environment) にのみ保存します。
    パスワードマスク入力により、画面露出やコマンド履歴への記録を防ぎます。
    全体のインストールとは独立して、単体でいつでも実行可能です。
#>
[CmdletBinding()]
param(
    [switch]$FalOnly,
    [switch]$OpenRouterOnly,
    [switch]$GeminiOnly,
    [switch]$ClaudeOnly,
    [switch]$DeepSeekOnly,
    [switch]$KimiOnly
)

$ErrorActionPreference = "Stop"

# UTF-8 出力エンコーディングの設定（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Secure API Key Setup for AI Agents & Services          " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "※ 入力されたキーは Windows ユーザー環境変数にのみ保存されます。" -ForegroundColor Gray
Write-Host "※ リポジトリ内のファイルには一切保存されません (Git漏洩防止)。" -ForegroundColor Gray
Write-Host "※ 不要な項目や変更しない項目は [Enter] で安全にスキップできます。`n" -ForegroundColor Gray

function Set-SecureUserEnvVar {
    param(
        [string]$DisplayName,
        [string]$VarName,
        [bool]$IsSecret = $true
    )

    $currentVal = [System.Environment]::GetEnvironmentVariable($VarName, "User")
    $statusText = if ($currentVal) { 
        if ($IsSecret) { "[設定済み: ********]" } else { "[設定済み: $currentVal]" }
    } else { 
        "[未設定]" 
    }
    
    Write-Host "$DisplayName ($VarName) $statusText" -ForegroundColor Yellow

    if ($IsSecret) {
        $secureInput = Read-Host -Prompt "  新しいキーを入力 (Enterでスキップ/保持)" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
        $plainInput = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } else {
        $plainInput = Read-Host -Prompt "  新しい値を入力 (Enterでスキップ/保持)"
    }

    if (-not [string]::IsNullOrWhiteSpace($plainInput)) {
        [System.Environment]::SetEnvironmentVariable($VarName, $plainInput, "User")
        [System.Environment]::SetEnvironmentVariable($VarName, $plainInput, "Process")
        Write-Host "  [OK] $VarName をユーザー環境変数に登録しました。`n" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] 変更しませんでした。`n" -ForegroundColor DarkGray
    }
}

$isAll = (-not $FalOnly -and -not $OpenRouterOnly -and -not $GeminiOnly -and -not $ClaudeOnly -and -not $DeepSeekOnly -and -not $KimiOnly)

# --- 1. OpenRouter (Muse Spark / 各種モデル用) ---
if ($isAll -or $OpenRouterOnly) {
    Write-Host "--- OpenRouter (Muse Spark 等) ---" -ForegroundColor Cyan
    Set-SecureUserEnvVar -DisplayName "OpenRouter API Key" -VarName "OPENAI_API_KEY" -IsSecret $true

    $currentBaseUrl = [System.Environment]::GetEnvironmentVariable("OPENAI_BASE_URL", "User")
    $currentModel = [System.Environment]::GetEnvironmentVariable("OPENAI_MODEL", "User")

    $urlPrompt = if ($currentBaseUrl) { "OpenRouter 互換設定 (OPENAI_BASE_URL / OPENAI_MODEL) を更新しますか？ (y/N)" } else { "OpenRouter を OpenAI 互換デフォルト (Muse Spark 1.2) として設定しますか？ (y/N)" }
    $isOpenRouter = Read-Host -Prompt $urlPrompt

    if ($isOpenRouter -match "^[yY]") {
        [System.Environment]::SetEnvironmentVariable("OPENAI_BASE_URL", "https://openrouter.ai/api/v1", "User")
        [System.Environment]::SetEnvironmentVariable("OPENAI_BASE_URL", "https://openrouter.ai/api/v1", "Process")
        [System.Environment]::SetEnvironmentVariable("OPENAI_MODEL", "meta/muse-spark-1.2-contributor", "User")
        [System.Environment]::SetEnvironmentVariable("OPENAI_MODEL", "meta/muse-spark-1.2-contributor", "Process")
        Write-Host "  [OK] OPENAI_BASE_URL (https://openrouter.ai/api/v1) と OPENAI_MODEL (meta/muse-spark-1.2-contributor) を設定しました。`n" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] Base URL / Model 設定はスキップしました。`n" -ForegroundColor DarkGray
    }
}

# --- 2. Google Gemini API (AI Studio) ---
if ($isAll -or $GeminiOnly) {
    Write-Host "--- Google Gemini API ---" -ForegroundColor Cyan
    Set-SecureUserEnvVar -DisplayName "Google Gemini API Key" -VarName "GEMINI_API_KEY" -IsSecret $true
}

# --- 3. Anthropic Claude API ---
if ($isAll -or $ClaudeOnly) {
    Write-Host "--- Anthropic Claude API ---" -ForegroundColor Cyan
    Set-SecureUserEnvVar -DisplayName "Anthropic API Key" -VarName "ANTHROPIC_API_KEY" -IsSecret $true
}

# --- 4. DeepSeek API ---
if ($isAll -or $DeepSeekOnly) {
    Write-Host "--- DeepSeek API ---" -ForegroundColor Cyan
    Set-SecureUserEnvVar -DisplayName "DeepSeek API Key" -VarName "DEEPSEEK_API_KEY" -IsSecret $true
}

# --- 5. Moonshot / Kimi API ---
if ($isAll -or $KimiOnly) {
    Write-Host "--- Moonshot / Kimi API ---" -ForegroundColor Cyan
    Set-SecureUserEnvVar -DisplayName "Moonshot / Kimi API Key" -VarName "KIMI_API_KEY" -IsSecret $true
}

# --- 6. fal.ai API (FAL_KEY) ---
if ($isAll -or $FalOnly) {
    Write-Host "--- fal.ai API (LP Asset Generator / Rembg) ---" -ForegroundColor Cyan
    Set-SecureUserEnvVar -DisplayName "fal.ai API Key" -VarName "FAL_KEY" -IsSecret $true
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   API Key Setup Completed!                               " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "※ 新しく開いたターミナルやセッションから設定値が自動的に反映されます。" -ForegroundColor Yellow
Write-Host '※ 現在のセッションですぐに反映したい場合は . $PROFILE を実行してください。' -ForegroundColor DarkGray
Write-Host ""
