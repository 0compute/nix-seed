{ inputs, ... }:
{

  perSystem =
    { lib, pkgs, ... }:
    {

      checks.bats = pkgs.runCommand "bats-tests" { buildInputs = [ pkgs.bats ]; } ''
        cd ${inputs.self}
        ${lib.getExe pkgs.bats} tests/bin | tee $out
      '';

    };

}
