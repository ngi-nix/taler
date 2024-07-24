{ config, lib, pkgs, ... }:
let
  taler-exchange = pkgs.taler-exchange.overrideAttrs (oa: {
    preConfigure = ''
      ${oa.preConfigure or ""}
      substituteInPlace src/exchangedb/plugin_exchangedb_postgres.c \
        --replace "#define AUTO_EXPLAIN 1" "#define AUTO_EXPLAIN 0"
    '';
  });

  cfg = config.services.taler-exchange;

  settings = lib.recursiveUpdate {
    exchange = {
      PORT = 8081;
      DB = "postgres";
      EXPIRE_IDLE_SLEEP_INTERVAL = "1 s";
      BASE_URL = "https://example.com/";
      MASTER_PRIV_FILE = "/var/lib/taler/master.priv";
    };
    exchangedb-postgres = {
      "CONFIG" = "postgres:///taler-exchange";
    };
    taler = {
      CURRENCY = "KUDOS";
      CURRENCY_ROUND_UNIT = "KUDOS:0.001";
    };
    auditordb-postgres = {
      "CONFIG" = "postgres:///taler-exchange";
    };
    PATHS = {
      TALER_HOME = "/tmp";
    };
  } cfg.settings;
  
  configFile = builtins.toFile "taler.conf" (
    lib.generators.toINI {} settings
  );
in
{
  options.services.taler-exchange = with lib; {
    enable = mkEnableOption "GNU Taler Exchange";

    settings = mkOption {
      type = with types; attrsOf (oneOf [ bool float int str ]);
      default = {};
      example = literalExpression ''
        {
          taler = {
            CURRENCY = "EUR";
            CURRENCY_ROUND_UNIT = "EUR:0.01";
          };
          exchange = {
            BASE_URL = "https://example.com/";
            MASTER_PUBLIC_KEY = "";
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gnunet taler-exchange
    ];
    environment.etc."taler/taler.conf".source = "/var/lib/taler/taler.conf";

    systemd.tmpfiles.rules = [
      "d /run/taler 0755 root root - -"
      "d /run/taler/auditor-httpd 0755 root root - -"
      "d /var/lib/taler 0755 root root - -"
      "d /var/lib/taler/exchange-offline 0700 root root - -"
      "d /run/taler/exchange-secmod-rsa 0755 root root - -"
      "d /run/taler/exchange-secmod-eddsa 0755 root root - -"
      "d /run/taler/exchange-secmod-cs 0755 root root - -"
      "d /run/taler/exchange-httpd 0750 root root - -"
      "d /var/lib/taler/exchange-offline 0700 root root - -"
      "d /var/lib/taler/exchange-secmod-rsa 0700 root root - -"
      "d /var/lib/taler/exchange-secmod-eddsa 0700 root root - -"
    ];

    systemd.slices.taler-exchange = {
      description = "Slice for GNU taler exchange processes";
      before = [ "slices.target" ];
    };

    systemd.targets.taler-exchange = {
      description = "GNU taler exchange";
      after = [ "postgresql.service" "network.target" ];
      wants = [
        "taler-init.service"
        "taler-exchange-dbinit.service"
        "taler-exchange-httpd.service"
        "taler-exchange-wirewatch.service"
        "taler-exchange-aggregator.service"
        "taler-exchange-closer.service"
        "taler-exchange-expire.service"
        "taler-exchange-transfer.service"
      ];
      wantedBy = [ "multi-user.target" ];
    };

    # TODO: is needed?
    # systemd.services.taler-auditor-httpd = {
    #   description = "GNU Taler payment system auditor REST API";
    #   after = [ "postgresql.service" "network.target" ];
    #   wantedBy = [ "multi-user.target" ];

    #   serviceConfig = {
    #     DynamicUser = true;
    #     User = "taler-auditor-httpd";
    #     Type = "simple";
    #     Restart = "on-failure";
    #     ExecStart = "${taler-exchange}/bin/taler-auditor-httpd -c ${configFile}";
    #     CacheDirectory = "/run/taler/auditor-httpd";
    #   };
    # };

    systemd.services.taler-exchange-aggregator = {
      description = "GNU Taler payment system exchange aggregator service";
      after = [ "postgresql.service" "taler-init.service" "taler-exchange-dbinit.service" "network.target" ];
      partOf = [ "taler-exchange.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-aggregator";
        Type = "simple";
        Restart = "always";
        RestartSec = "100ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-aggregator -c ${configFile}";
        PrivateTmp = "yes";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        Slice = "taler-exchange.slice";
      };
    };
    systemd.services.taler-exchange-closer = {
      description = "GNU Taler payment system exchange closer service";
      after = [ "postgresql.service" "taler-init.service" "taler-exchange-dbinit.service" "network.target" ];
      partOf = [ "taler-exchange.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-closer";
        Type = "simple";
        Restart = "always";
        RestartSec = "100ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-closer -c ${configFile}";
        PrivateTmp = "yes";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        Slice = "taler-exchange.slice";
      };
    };
    systemd.services.taler-exchange-expire = {
      description = "GNU Taler payment system exchange expire service";
      after = [ "postgresql.service" "taler-init.service" "taler-exchange-dbinit.service" "network.target" ];
      partOf = [ "taler-exchange.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-expire";
        Type = "simple";
        Restart = "always";
        RestartSec = "100ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-expire -c ${configFile}";
        PrivateTmp = "yes";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        Slice = "taler-exchange.slice";
      };
    };
    systemd.services.taler-exchange-httpd = {
      description = "GNU Taler payment system exchange REST API";
      unitConfig.AssertPathExists = "/run/taler/exchange-httpd";
      requires = [ "taler-exchange-httpd.socket" "taler-exchange-secmod-cs.service" "taler-exchange-secmod-rsa.service" "taler-exchange-secmod-eddsa.service" ];
      after = [ "postgresql.service" "taler-init.service" "taler-exchange-dbinit.service" "network.target" "taler-exchange-secmod-cs.service" "taler-exchange-secmod-rsa.service" "taler-exchange-secmod-eddsa.service" ];
      partOf = [ "taler-exchange.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-httpd";
        Type = "simple";
        # Depending on the configuration, the service suicides and then
        # needs to be restarted.
        Restart = "always";
        # Do not dally on restarts.
        RestartSec = "1ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-httpd -c ${configFile}";
        PrivateTmp = "no";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        Slice = "taler-exchange.slice";
        CacheDirectory = "/run/taler/exchange-httpd";
      };
    };
    systemd.services.taler-exchange-secmod-cs = {
      description = "GNU Taler payment system exchange CS security module";
      unitConfig.AssertPathExists = "/run/taler/exchange-secmod-cs";
      partOf = [ "taler-exchange.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-secmod-cs";
        Type = "simple";
        Restart = "always";
        RestartSec = "100ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-secmod-cs -c ${configFile}";
        PrivateTmp = "no";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        IPAddressDeny = "any";
        Slice = "taler-exchange.slice";
      };
    };
    systemd.services.taler-exchange-secmod-eddsa = {
      description = "GNU Taler payment system exchange EdDSA security module";
      unitConfig.AssertPathExists  = "/run/taler/exchange-secmod-eddsa";
      partOf = [ "taler-exchange.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-secmod-eddsa";
        Type = "simple";
        Restart = "always";
        RestartSec = "100ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-secmod-eddsa -c ${configFile}";
        PrivateTmp = "no";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        IPAddressDeny = "any";
        Slice = "taler-exchange.slice";
        WorkingDirectory = "/run/taler/exchange-secmod-eddsa";
        CacheDirectory = "/run/taler/exchange-secmod-eddsa";
        StateDirectory = "/var/lib/taler/exchange-secmod-eddsa";
      };
    };
    systemd.services.taler-exchange-secmod-rsa = {
      description = "GNU Taler payment system exchange RSA security module";
      unitConfig.AssertPathExists  = "/run/taler/exchange-secmod-rsa";
      partOf = [ "taler-exchange.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-secmod-rsa";
        Type = "simple";
        Restart = "always";
        RestartSec = "100ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-secmod-rsa -c ${configFile}";
        PrivateTmp = "no";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        IPAddressDeny = "any";
        Slice = "taler-exchange.slice";
        WorkingDirectory = "/run/taler/exchange-secmod-rsa";
        CacheDirectory = "/run/taler/exchange-secmod-rsa";
        StateDirectory = "/var/lib/taler/exchange-secmod-rsa";
      };
    };
    systemd.services.taler-exchange-transfer = {
      description = "GNU Taler Exchange Transfer Service";
      after = [ "postgresql.service" "taler-init.service" "taler-exchange-dbinit.service" "network.target" ];
      partOf = [ "taler-exchange.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-wire";
        Type = "simple";
        Restart = "always";
        RestartSec = "100ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-transfer -c ${configFile}";
        PrivateTmp = "yes";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        Slice = "taler-exchange.slice";
      };
    };
    systemd.services.taler-exchange-wirewatch = {
      description = "GNU Taler payment system exchange wirewatch service";
      after = [ "postgresql.service" "taler-init.service" "taler-exchange-dbinit.service" "network.target" ];
      partOf = [ "taler-exchange.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "taler-exchange-wire";
        Type = "simple";
        Restart = "always";
        RestartSec = "100ms";
        ExecStart = "${taler-exchange}/bin/taler-exchange-wirewatch -c ${configFile}";
        PrivateTmp = "yes";
        PrivateDevices = "yes";
        ProtectSystem = "full";
        Slice = "taler-exchange.slice";
      };
    };

    systemd.services.taler-init = {
      after = [ "systemd-tmpfiles.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      path = with pkgs; [
        taler-exchange
        gnunet
        which
      ];
      script = ''
        cd /var/lib/taler
        rm -f taler.conf
        cat ${configFile} > taler.conf

        MASTER_PRIV_FILE=`taler-config -f -s EXCHANGE -o MASTER_PRIV_FILE`
        MASTER_PRIV_DIR=`dirname $MASTER_PRIV_FILE`
        mkdir -p $MASTER_PRIV_DIR

        if ! [ -e "$MASTER_PRIV_FILE" ]; then
          umask 0077
          gnunet-ecc -g1 $MASTER_PRIV_FILE
        fi
        MASTER_PUB=`gnunet-ecc -p $MASTER_PRIV_FILE`

        taler-config -s exchange -o MASTER_PUBLIC_KEY -V $MASTER_PUB
        taler-config -s merchant-exchange-default -o MASTER_KEY -V $MASTER_PUB
      '';
    };

    systemd.services.taler-exchange-dbinit = {
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };
      path = with pkgs; [
        postgresql
        taler-exchange
      ];
      script =
        let
          ensureUsers = [{
            name = "taler-exchange-httpd";
            ensurePermissions = { "DATABASE \"taler-exchange\"" = "ALL PRIVILEGES"; };
          } {
            name = "taler-exchange-aggregator";
            ensurePermissions = { "ALL TABLES IN SCHEMA public" = "SELECT,INSERT,UPDATE"; };
          } {
            name = "taler-exchange-closer";
            ensurePermissions = { "ALL TABLES IN SCHEMA public" = "SELECT,INSERT,UPDATE"; };
          } {
            name = "taler-exchange-wire";
            ensurePermissions = { "ALL TABLES IN SCHEMA public" = "SELECT,INSERT,UPDATE"; };
          } {
            name = "taler-exchange-aggregator";
            ensurePermissions = { "ALL SEQUENCES IN SCHEMA public" = "USAGE"; };
          } {
            name = "taler-exchange-closer";
            ensurePermissions = { "ALL SEQUENCES IN SCHEMA public" = "USAGE"; };
          } {
            name = "taler-exchange-wire";
            ensurePermissions = { "ALL SEQUENCES IN SCHEMA public" = "USAGE"; };
          } {
            name = "taler-exchange-expire";
            ensurePermissions = { "ALL SEQUENCES IN SCHEMA public" = "USAGE";
                                  "ALL TABLES IN SCHEMA public" = "SELECT,INSERT,UPDATE"; };
          }];
          database = "taler-exchange";
        in with lib; ''
          PSQL="psql --port=${toString config.services.postgresql.port}"

          if [ -e "${config.services.postgresql.dataDir}/.taler-init" ]; then
            exit 0
          fi

          $PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = '${database}'" | grep -q 1 || $PSQL -tAc 'CREATE DATABASE "${database}"'

          taler-exchange-dbinit -L TRACE

          ${concatMapStrings (user: ''
            $PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname='${user.name}'" ${database} | \
              grep -q 1 || \
              $PSQL -tAc 'CREATE USER "${user.name}"' ${database}
            ${concatStringsSep "\n" (mapAttrsToList (object: permission: ''
                $PSQL -tAc 'GRANT ${permission} ON ${object} TO "${user.name}"' ${database}
            '') user.ensurePermissions)}
          '') ensureUsers}

          touch "${config.services.postgresql.dataDir}/.taler-init"
        '';
    };

    systemd.sockets.taler-exchange-httpd = {
      description = "Taler Exchange Socket";
      partOf = [ "taler-exchange-httpd.service" ];
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        "ListenStream" = "/run/taler/exchange-httpd/exchange-http.sock";
        "Accept" = "no";
        "Service" = "taler-exchange-httpd.service";
        "SocketMode" = "0660";
      };
    };

    services.postgresql = {
      enable = true;
    };
  };
}
