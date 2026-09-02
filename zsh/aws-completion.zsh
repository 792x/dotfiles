# assume: profile completion and jump-back for the helper in .zshrc.
# `assume -` returns to the profile you were on before the last switch.
_assume_profiles() {
  awk '/^\[profile /{c=$2; sub(/\]$/,"",c); print c}' "${AWS_CONFIG_FILE:-$HOME/.aws/config}"
}
_assume() {
  local -a profiles
  profiles=(${(f)"$(_assume_profiles)"})
  _describe -t profiles 'aws profile' profiles
}
compdef _assume assume
