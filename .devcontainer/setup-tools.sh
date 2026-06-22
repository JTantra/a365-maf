#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.dotnet/tools:$HOME/.azd/bin:$HOME/.local/bin:$PATH"

log() {
  printf '\n==> %s\n' "$1"
}

ensure_shell_path() {
  local marker_start="# >>> a365-maf devcontainer tools >>>"
  local marker_end="# <<< a365-maf devcontainer tools <<<"
  local path_block
  path_block="${marker_start}
export PATH=\"\$HOME/.dotnet/tools:\$HOME/.azd/bin:\$HOME/.local/bin:\$PATH\"
${marker_end}"

  for profile_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
    touch "$profile_file"
    if ! grep -qF "$marker_start" "$profile_file"; then
      printf '\n%s\n' "$path_block" >> "$profile_file"
    fi
  done
}

configure_git_line_endings() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "Configuring Git line ending handling"
    git config --local core.autocrlf input
    git config --local core.eol lf
    git config --local core.safecrlf warn
    git config --local core.filemode false
  fi
}

install_azd() {
  if command -v azd >/dev/null 2>&1; then
    log "Azure Developer CLI already installed"
    azd version
    return
  fi

  log "Installing Azure Developer CLI"
  curl -fsSL https://aka.ms/install-azd.sh | bash
}

install_uv() {
  log "Installing or updating uv"
  python3 -m pip install --user --upgrade uv
  uv --version
}

install_a365_cli() {
  log "Installing or updating Agent 365 CLI"
  if dotnet tool list --global | awk '{print tolower($1)}' | grep -qx "microsoft.agents.a365.devtools.cli"; then
    dotnet tool update --global Microsoft.Agents.A365.DevTools.Cli --prerelease
  else
    dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli --prerelease
  fi
  a365 --version
}

install_atk_cli() {
  log "Installing or updating Microsoft 365 Agents Toolkit CLI"
  npm install --global --prefix "$HOME/.local" @microsoft/m365agentstoolkit-cli
  atk --version
}

install_graph_powershell_modules() {
  if [[ "${INSTALL_GRAPH_PS_MODULES:-true}" != "true" ]]; then
    log "Skipping Microsoft Graph PowerShell modules"
    return
  fi

  log "Installing Microsoft Graph PowerShell modules"
  local install_script
  install_script="$(mktemp)"
  cat > "$install_script" <<'POWERSHELL'
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$modules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Applications")
$missing = @()
foreach ($module in $modules) {
  if (-not (Get-Module -ListAvailable -Name $module)) {
    $missing += $module
  }
}
if ($missing.Count -gt 0) {
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
  Install-Module -Name $missing -Scope CurrentUser -Force -AllowClobber
}
$modules | ForEach-Object {
  $installed = Get-Module -ListAvailable -Name $_ | Sort-Object Version -Descending | Select-Object -First 1
  "{0} {1}" -f $installed.Name, $installed.Version
}
POWERSHELL
  if ! pwsh -NoLogo -NoProfile -NonInteractive -File "$install_script"; then
    rm -f "$install_script"
    return 1
  fi
  rm -f "$install_script"
}

install_bicep_cli() {
  log "Installing Azure CLI Bicep support"
  az bicep install >/dev/null
  az bicep version
}

install_python_dependencies() {
  log "Creating project virtual environment"
  uv venv .venv --python python3 --clear

  log "Installing project dependencies"
  uv pip install --python .venv/bin/python -e .
}

print_versions() {
  log "Tool versions"
  python3 --version
  node --version
  npm --version
  dotnet --version
  pwsh --version
  az --version | head -n 1
  azd version
  atk --version
  a365 --version
  uv --version
}

main() {
  ensure_shell_path
  configure_git_line_endings
  install_azd
  install_uv
  install_a365_cli
  install_atk_cli
  install_graph_powershell_modules
  install_bicep_cli
  install_python_dependencies
  print_versions

  log "Dev Container setup complete"
  printf '%s\n' "Next: run az login --use-device-code, then azd auth login inside the container."
}

main "$@"
