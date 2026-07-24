{ config, pkgs, lib, ... }:
{
  # Netzwerk-Grundkonfiguration
  networking = {
    hostName   = "apphost";
    domain     = "example.com";  # ÄNDERN

    # DNS mit DoT/DoH für sichere DNS-Auflösung via systemd-resolved
    nameservers = [
      "127.0.0.1"
      "::1"
    ];

    # nftables statt iptables (moderner)
    firewall.enable  = false;  # Manuelles nftables-Ruleset unten
  };

  # DNS-over-TLS Konfigration
  services.resolved = {
    enable       = true;
    settings.Resolve = {
      DNSSEC       = "true";
      DNSOverTLS   = "true";    # Erzwingt DoT
      DNS  = [                  # Trusted non logging DoT Server
        "1.1.1.1#cloudflare-dns.com"
        "9.9.9.9#dns.quad9.net"
      ];
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
