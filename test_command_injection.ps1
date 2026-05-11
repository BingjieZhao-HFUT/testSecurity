param(
    [Parameter(Mandatory=$true)]
    [string]$UserInput
)

# Very small deny-list based check for demonstration purposes.
$dangerousPattern = '(;|&&|\|\||\||`|\$\(|>|<)'

Write-Host "Input: $UserInput"

if ($UserInput -match $dangerousPattern) {
    Write-Host "[BLOCKED] Potential command injection detected." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Input passed basic command-injection checks." -ForegroundColor Green
# Simulate safe command handling instead of running user input.
Write-Host "Would process sanitized input: $UserInput"
