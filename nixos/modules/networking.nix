{ config, pkgs, lib, ... }:
{
  # Netzwerk-Grundkonfiguration
  networking = {
    hostName   = "apphost";
    domain     = "apphost.lan";

    # Statische IP – nötig, damit das Pi-hole-Mapping apphost.lan -> diese VM
    # dauerhaft stimmt. Pi-hole = .5, App-Host = .6.
    # ens18 = virtio-NIC der Proxmox-VM (siehe `ip -br link`).
    useDHCP = false;
    interfaces.ens18.ipv4.addresses = [
      { address = "192.168.178.6"; prefixLength = 24; }
    ];
    defaultGateway = "192.168.178.1";

    # DNS = Pi-hole (.5), damit *.apphost.lan auch VM-/container-seitig auflöst
    # (der Pi-hole kennt die Wildcard). Ohne das scheitert der OIDC-Token-Call.
    nameservers = [ "192.168.178.5" ];

    # nftables statt iptables (moderner)
    firewall.enable  = false;  # Manuelles nftables-Ruleset unten
  };

  # DNS über den lokalen Pi-hole (Klartext auf :53). DoT/DNSSEC hier bewusst AUS:
  #  - der Pi-hole spricht plain DNS und macht den verschlüsselten Upstream selbst,
  #  - die lokale Domain apphost.lan ist unsigniert (DNSSEC würde sie als bogus
  #    verwerfen und *.apphost.lan gar nicht auflösen).
  # Fällt der Pi-hole aus, greift der Fallback (FritzBox): Internet läuft weiter,
  # nur *.apphost.lan nicht.
  services.resolved = {
    enable      = true;
    settings.Resolve = {
      DNSSEC      = "false";
      DNSOverTLS  = "false";
      FallbackDNS = "192.168.178.1";   # FritzBox, falls Pi-hole down
    };
  };

  # nftables Firewall
  networking.nftables = {
    enable = true;
    ruleset = ''
      # Alles wird geblockt, nur explizit erlaubte Verbindungen werden zugelassen

      table inet filter {
        # Verbindungen von Docker-Netzwerken erlauben (für Container-Kommunikation)
        chain docker_input {
          ip saddr 172.16.0.0/12 accept
          ip saddr 192.168.0.0/16 accept
        }

        chain input {
          type filter hook input priority 0; policy drop;

          # etablierte Verbindungen
          ct state established,related accept

          # Loopback immer erlauben
          iif lo accept

          # Docker-interne Kommunikation
          jump docker_input

          # ICMPv4 begrenzt erlauben
          ip protocol icmp icmp type {
            echo-request,     # Ping
            destination-unreachable,
            time-exceeded,
            parameter-problem
          } limit rate 5/second burst 10 packets accept

          # ICMPv6 für korrekte IPv6-Funktion nötig
          ip6 nexthdr icmpv6 icmpv6 type {
            nd-neighbor-solicit,
            nd-neighbor-advert,
            nd-router-advert,
            destination-unreachable,
            packet-too-big,
            time-exceeded,
            parameter-problem
          } limit rate 10/second burst 20 packets accept

          # SSH
          tcp dport 22 ct state new limit rate 5/minute burst 10 packets accept

          # HTTP/HTTPS (für Traefik)
          tcp dport { 80, 443 } accept

          # HTTP/3 QUIC (Traefik, siehe compose/infrastructure/traefik.yml)
          udp dport 443 accept

          # Prometheus Node-Exporter (nur von Monitoring-Netz)
          # ip saddr 172.20.0.0/24 tcp dport 9100 accept

          # Alles andere DROP + Logging
          log prefix "[nftables DROP] " level warn
        }

        chain forward {
          type filter hook forward priority 0; policy drop;

          # Etablierte Verbindungen
          ct state established,related accept

          # Docker-Bridge zu außen (NAT/Masquerade läuft in nat-Table)
          ip saddr 172.16.0.0/12 accept
          ip saddr 192.168.0.0/16 accept
        }

        # Output ist frei
        chain output {
          type filter hook output priority 0; policy accept;
        }
      }

      table ip nat {
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;

          ip saddr 172.16.0.0/12 masquerade
          ip saddr 192.168.0.0/16 masquerade
        }
      }
    '';
  };

  # Fail2ban mit nftables-Backend
  services.fail2ban.banaction = "nftables-multiport";
  services.fail2ban.banaction-allports = "nftables-allports";
}
