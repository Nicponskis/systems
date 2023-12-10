# Here's how you use this.  Assumes you're operating on osx, switch system type
# otherwise.  From root of this repo:
# ```
#  # nix repl
#  nix-repl> :lf .
#  nix-repl> :u inputs.agenix.packages.x86_64-darwin.agenix
#  > cd hosts/nixos/stagingfreshlybakednyc/secrets
#  > agenix -e test-secret.age
# ```
# 
# To add more secrets, optionally add more SSH keys, optionally define a new keylist,
# add a new attribute for the encrypted filename with value of the keylist, then
# repeat the above steps to add (or modify) the secret.
let
  machine.stagingfreshlybakednyc.ed25519-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKjV7oJjzQqlvGTM98wtIciTEYy7WMU2DGcg711kg9o root@ip-10-0-2-69.ec2.internal";
  user.stagingfreshlybakednyc.root-1 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDda3KfnCf8hE3TOi7YoAvW4RnP1+b7z0EvggAWazrJNh56QTZt6QN4tYrVdS8mU5OrEfLcUYbIswq79wKL4Htc502KDbhrEMn6NhAhH93UVTPeAVYeNKZu0ZGUk/LPj+Tj+O21YDPoH9XwY3E6O56BAAPYkG0Dym0u0rDSuhW/qPIcUCrCD/i6QU4Dab+ZOU2wQvWc4k7rfP9BOA51pnpmixrjdhCkRJzMTKDz0lwl7aF8lIR1pCzTQkKTH+NDN2tqJZaktOmnvEqidRIMNYnRG46tEB8eppyLlluUl4pJxGvnxWUbHfNDurq7lwIjFakyydu1zJ5FxWYsqRgLkIVUWgHEcZNGp/N5AE5GYtTQwblegeL67/vxlEXvTahK/ZACYZOFrgxr4JFnVTy1NljGmskfBGFGGkI2w0fgVPC3Z95/840cv3f7iyGrWdGR2iiqPfuVc5SQ84kbuUtVib9V9ezoytQJX9xuJNYFyb/vFJFCu7sdy4xajm1gv9NvvGE= root@stagingfreshlybakednyc";
  user.davembp1.dave-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJUDAkeKrg+WezAO8PVK0BNzAnbtncL7p59ftJg4+IJ dave.nicponski@gmail.com davembp1";
  justRoot = [ machine.stagingfreshlybakednyc.ed25519-1 user.stagingfreshlybakednyc.root-1 ];
  editor = [ user.davembp1.dave-1 ];
in {
  "test-secret.age".publicKeys = justRoot ++ editor;
  "inadyn-password.age".publicKeys = justRoot ++ editor;
}
