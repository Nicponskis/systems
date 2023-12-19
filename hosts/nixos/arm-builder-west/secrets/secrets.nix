# Here's how you use this.  Assumes you're operating on osx, switch system type
# otherwise.  From root of this repo:
# ```
#  # nix repl
#  nix-repl> :lf .
#  nix-repl> :u inputs.agenix.packages.x86_64-darwin.agenix
#  > cd hosts/nixos/arm-builder-west/secrets
#  > agenix -e test-secret.age
# ```
#
# To add more secrets, optionally add more SSH keys, optionally define a new keylist,
# add a new attribute for the encrypted filename with value of the keylist, then
# repeat the above steps to add (or modify) the secret.
let
  machine.builder-ed25519-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICugSUCEy052LaoCT9/ApDJcd6KS+KPTxJN1urGfZOkf";
  user.builder-root-1 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDF14YFQO6wRG3D8J5a0JzqfRsFtL0azbRQimjN+9MpiNUGkv9AMA9ITcztmyJRwzwTZAKSIYOa2B9aFwNvQ/CZyFXsBt/ux18L/uRNF+xeSDOgkxo7Y8ErCdVg024/AphSM5/CEEiOotKoZKV+cYSNsgcuKnr7XY/ESc5Xm47MijxYywG1k1GNudBwxGy5D45wnKq/h1yYxCG/PyFPk2QN2PK5wnsEYhcswJ8Z54C0BcAUMvdnnMZ9v/QVqwJOfZCmhwG0Z3KTKwypmZCAqWapH+r81a7SlGyPupAdw7XK2QhWsiUqUINVyGUtYFA1GUnUiFjwjeUbpjV3xaJMFkFdzCDOtZPnYXgnCkoIwM9ZigS7wHaoSRy94o7UuHksteVKiN8WQ7ehf274NAi68u1BNKoMypjFd5B70o95q4itJ6Rn2vrCb8qC85FFyh4ueFfG4c5QkeKc/erJWQJMb0OSTeBsxV2ZXYviB/sJ0u4AY9+xgfVwCPFjVep7a9Yq94M= root@builder.arm.aws.internal";
  user.davembp1.dave-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJUDAkeKrg+WezAO8PVK0BNzAnbtncL7p59ftJg4+IJ dave.nicponski@gmail.com davembp1";
  justRoot = [ machine.builder-ed25519-1 user.builder-root-1 ];
  editor = [ user.davembp1.dave-1 ];
in {
  "ddclient-pw.age".publicKeys = justRoot ++ editor;
  "awscli-ip_builder-pw.age".publicKeys = justRoot ++ editor;
  "awscli-s3fs-pw.age".publicKeys = justRoot ++ editor;
  "inadyn-pw.age".publicKeys = justRoot ++ editor;
  "test-secret.age".publicKeys = justRoot ++ editor;
}
