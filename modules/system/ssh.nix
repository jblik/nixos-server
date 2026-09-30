{ ... }:
# Headless server: SSH is the primary way in.
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      # Leave password auth on for initial bootstrap; switch to "no" once your
      # SSH key is in users.users.jblik.openssh.authorizedKeys.
      PasswordAuthentication = true;
    };
  };
}
