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

    # KEIN "flush ruleset" beim Neuladen – sonst nimmt jeder `rebuild` Docker
    # die Beine weg. Symptom:
    #   Failed to Setup IP tables: Unable to enable ACCEPT OUTGOING rule:
    #   iptables -A DOCKER-FORWARD ...: No chain/target/match by that name
    # Docker legt seine Ketten (DOCKER-FORWARD, DOCKER-USER, ip nat/DOCKER, …)
    # ausschließlich beim Daemon-Start an. Sie liegen über iptables-nft im
    # selben Kernel-Regelwerk wie unseres. Das NixOS-Modul setzt
    # flushRuleset auf true, sobald `ruleset` gesetzt ist
    # (nixos/modules/services/networking/nftables.nix), und die Unit hat
    # reloadIfChanged = true – ein `rebuild` lädt also neu, spült dabei ALLES
    # und Docker steht ohne seine Ketten da. Bestehende Container verlieren
    # ihre Weiterleitung, neue Netze lassen sich gar nicht mehr anlegen. Bis
    # dahin half nur `systemctl restart docker`.
    #
    # Statt alles zu spülen, räumen wir genau unser eigenes weg: die Tabelle
    # inet filter (die benutzt Docker nicht, es arbeitet in ip filter) und in
    # ip nat NUR unsere Kette `postrouting` – Dockers POSTROUTING und DOCKER
    # in derselben Tabelle bleiben stehen.
    #
    # Die Reihenfolge "erst anlegen, dann löschen" ist der vom Modul selbst
    # dokumentierte Kniff: so ist das Löschen eines nicht vorhandenen Objekts
    # kein Fehler. `flush chain` vor `delete chain`, weil delete an einer
    # Kette mit Regeln scheitert.
    #
    # Nachgemessen in einem eigenen Netz-Namespace: 5 Reload-Zyklen
    # hintereinander lassen Dockers Ketten unangetastet und erzeugen weiterhin
    # genau eine masquerade-Regel (keine Anhäufung); mit `flush ruleset` sind
    # Dockers Ketten danach weg – also genau der Fehler oben.
    #
    # EINMALIG BEIM UMSTELLEN: Der allererste rebuild nach dieser Änderung
    # spült trotzdem noch. Das Modul baut sein Skript als
    #     include "/var/lib/nftables/deletions.nft"   # previous deletions
    #     include "<neues Lösch-Skript>"              # current deletions
    # und die gespeicherte Datei stammt noch aus der Generation davor – sie
    # enthält also "flush ruleset". Erst ExecStartPost überschreibt sie mit der
    # Fassung von hier. Nach diesem einen Mal also noch
    #   sudo systemctl restart docker
    # Prüfen lässt sich das an  cat /var/lib/nftables/deletions.nft :
    # dort darf danach kein "flush ruleset" mehr stehen.
    flushRuleset = false;
    extraDeletions = ''
      table inet filter
      delete table inet filter

      table ip nat
      table ip nat {
        chain postrouting {
        }
      }
      flush chain ip nat postrouting
      delete chain ip nat postrouting
    '';

    ruleset = ''
      # Alles wird geblockt, nur explizit erlaubte Verbindungen werden zugelassen

      table inet filter {
        # Container -> HOST. Bewusst KEIN pauschales "accept" für das Docker-
        # Subnetz und erst recht keins für 192.168.0.0/16 (darin liegt der Host
        # selbst -> das hob die komplette Default-Deny-Policy für das ganze LAN
        # auf). Erlaubt sind nur die Ports, die Container am Host tatsächlich
        # brauchen; beides scrapt Prometheus über die docker0-Gateway-IP
        # 172.17.0.1 (siehe config/prometheus/prometheus.yml).
        chain docker_input {
          ip saddr 172.16.0.0/12 tcp dport 9100 accept  # node-exporter (network_mode: host)
          ip saddr 172.16.0.0/12 tcp dport 9323 accept  # Docker-Daemon-Metrics
        }

        chain input {
          type filter hook input priority 0; policy drop;

          # etablierte Verbindungen
          ct state established,related accept

          # Loopback immer erlauben
          iif lo accept

          # Pakete, die zu keinem gültigen Conntrack-Eintrag passen (z.B. späte
          # RSTs, Fragment-Spielereien), früh verwerfen – sie sollen weder eine
          # der Regeln unten treffen noch in der Log-Regel landen.
          ct state invalid drop

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

          # Alles andere DROP + Logging – aber gedrosselt. Solange die Kette
          # 192.168.0.0/16 pauschal akzeptierte, wurde der komplette
          # LAN-Broadcast/Multicast vorher weggefangen. Jetzt landet alles davon
          # hier: SSDP, mDNS, NetBIOS, DHCP, IGMP von jedem Gerät im Heimnetz.
          # Ungedrosselt schreibt das dauerhaft in ein Journal mit
          # Storage=persistent und SystemMaxUse=4G und verdrängt echte Logs.
          limit rate 10/minute burst 20 packets log prefix "[nftables DROP] " level warn
        }

        chain forward {
          type filter hook forward priority 0; policy drop;

          # Etablierte Verbindungen
          ct state established,related accept
          ct state invalid drop

          # Docker-Bridge zu außen (NAT/Masquerade läuft in nat-Table)
          ip saddr 172.16.0.0/12 accept

          # LAN -> Container NUR über von Docker veröffentlichte Ports (80/443
          # an Traefik). "ct status dnat" trifft genau die Pakete, die Docker
          # per Port-Publishing umgeschrieben hat. Ein pauschales
          # "ip saddr 192.168.0.0/16 accept" würde dagegen jedem LAN-Gerät
          # erlauben, mit einer statischen Route nach 172.23.0.0/16 direkt mit
          # jedem Container zu sprechen – an Traefik und Authelia vorbei.
          ct status dnat accept
        }

        # Output ist frei
        chain output {
          type filter hook output priority 0; policy accept;
        }
      }

      table ip nat {
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;

          # Nur Container-Egress maskieren. LAN-Quellen hier zu maskieren war
          # unnötig (der Host ist Gateway der Container, Antworten finden ihren
          # Weg auch ohne NAT zurück) und machte die VM zum offenen Router in
          # die Docker-Netze.
          ip saddr 172.16.0.0/12 masquerade
        }
      }
    '';
  };

  # Fail2ban mit nftables-Backend
  services.fail2ban.banaction = "nftables-multiport";
  services.fail2ban.banaction-allports = "nftables-allports";
}
