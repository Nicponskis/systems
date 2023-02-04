let
  machine.builder-ed25519-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICugSUCEy052LaoCT9/ApDJcd6KS+KPTxJN1urGfZOkf";
  user.builder-root-1 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDF14YFQO6wRG3D8J5a0JzqfRsFtL0azbRQimjN+9MpiNUGkv9AMA9ITcztmyJRwzwTZAKSIYOa2B9aFwNvQ/CZyFXsBt/ux18L/uRNF+xeSDOgkxo7Y8ErCdVg024/AphSM5/CEEiOotKoZKV+cYSNsgcuKnr7XY/ESc5Xm47MijxYywG1k1GNudBwxGy5D45wnKq/h1yYxCG/PyFPk2QN2PK5wnsEYhcswJ8Z54C0BcAUMvdnnMZ9v/QVqwJOfZCmhwG0Z3KTKwypmZCAqWapH+r81a7SlGyPupAdw7XK2QhWsiUqUINVyGUtYFA1GUnUiFjwjeUbpjV3xaJMFkFdzCDOtZPnYXgnCkoIwM9ZigS7wHaoSRy94o7UuHksteVKiN8WQ7ehf274NAi68u1BNKoMypjFd5B70o95q4itJ6Rn2vrCb8qC85FFyh4ueFfG4c5QkeKc/erJWQJMb0OSTeBsxV2ZXYviB/sJ0u4AY9+xgfVwCPFjVep7a9Yq94M= root@builder.arm.aws.internal";
  justRoot = [ machine.builder-ed25519-1 user.builder-root-1 ];
in {
  "ddclient-pw.age".publicKeys = justRoot;
  "awscli-ip_builder-pw.age".publicKeys = justRoot;
  "awscli-s3fs-pw.age".publicKeys = justRoot;
  "test-secret.age".publicKeys = justRoot;
}
