# tflint with the bundled terraform ruleset only. The libvirt provider has
# no tflint ruleset.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
