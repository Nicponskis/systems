# Here's how you use this.  Assumes you're operating on osx, switch system type
# otherwise.  From root of this repo:
# ```
#  # nix repl
#  nix-repl> :lf .
#  nix-repl> :u inputs.agenix.packages.x86_64-darwin.agenix
#  > cd hosts/nixos/wwwfreshlybakednyc/secrets
#  > agenix -e test-secret.age
# ```
# 
# To add more secrets, optionally add more SSH keys, optionally define a new keylist,
# add a new attribute for the encrypted filename with value of the keylist, then
# repeat the above steps to add (or modify) the secret.
let
  machine.wwwfreshlybakednyc.ed25519-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKjV7oJjzQqlvGTM98wtIciTEYy7WMU2DGcg711kg9o root@ip-10-0-2-69.ec2.internal";
  user.wwwfreshlybakednyc.root-1 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCpwcRQ/GEDqX2ahDe8oKwxikNe+O8q3BVVzjG3Kr/dpEe6jsXHq+SrGtAEwwu09FGSv/DS+adxkZJZmxlqEkT0txB2Xg2HKYpocDcvz86U83ZXgZj57+dHlzpY1bum0ZCDB0ncjYT2eT2/JAztP1U9mTXq/jzytC4qteiewX7OyLJmQBhrhKlXRXUNbHKZulqCmhE4UaLbSpJIXDveDNPMRoxsVOtQJxhPNnkv6r4uUcsA0tHz9zUZzk1NtCLv8rluv84rYf6ieib/dVI12oBrgyWOTfNExtFxnocICKBAVnMEK9dpWqUuWdDNVQ6lHYR5FmPFRXn1A+wC0+J1YZzATF13pOXKrkm2PR4T5ooMu8qFklF/UYZ3BEiZ39RbpjXfDDNec7lSudzp3raryjMxJvWjBeijB2CSKWj63iZXlEcRK/I9D5oyswmWlPxIS56GE9iQgEE80kyk3a0HEy+6tigwnJzL562U3SHXfJZ0iPxoe40fcCyt5wYx/qBrKSk= root@wwwfreshlybakednyc";
  user.davembp1.dave-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJUDAkeKrg+WezAO8PVK0BNzAnbtncL7p59ftJg4+IJ dave.nicponski@gmail.com davembp1";
  justRoot = [ machine.wwwfreshlybakednyc.ed25519-1 user.wwwfreshlybakednyc.root-1 ];
  editor = [ user.davembp1.dave-1 ];
in {
  "test-secret.age".publicKeys = justRoot ++ editor;
  # "inadyn-password.age".publicKeys = justRoot ++ editor;
}
