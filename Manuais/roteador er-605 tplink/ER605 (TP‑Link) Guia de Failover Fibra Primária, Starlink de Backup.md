# ER605 (TP‑Link) — Guia de Failover: Fibra Primária, Starlink de Backup

> **Objetivo**: todo o tráfego sai pela **fibra (WAN1)**. A **Starlink (WAN2)** só é usada **quando a fibra falhar** e o roteador **retorna automaticamente** para a fibra quando ela voltar.

---

## Resumo

Configuração do ER605 (standalone) para **failover puro**: desabilitar o balanceamento, habilitar **Link Backup** com **WAN1 como primária** e **WAN2 como backup**, e ajustar o **Online Detection** em **Auto** (detecção pelo gateway). Inclui passos de teste e checklist.

---

## Sumário

* [Visão geral](#visão-geral)
* [Pré‑requisitos](#pré-requisitos)
* [Topologia de referência](#topologia-de-referência)
* [Passo a passo](#passo-a-passo)

  * [1) Desativar o Load Balancing](#1-desativar-o-load-balancing)
  * [2) Configurar o Link Backup (failover)](#2-configurar-o-link-backup-failover)
  * [3) Ajustar o Online Detection (Manual)](#3-ajustar-o-online-detection-manual)
  * [4) Ajustar DNS/DHCP](#4-ajustar-dnsdhcp)
  * [5) Informar as larguras de banda](#5-informar-as-larguras-de-banda)
  * [6) Conferir Policy Routing](#6-conferir-policy-routing)
  * [7) Testes de failover/failback](#7-testes-de-failoverfailback)
  * [8) Logs e monitoramento](#8-logs-e-monitoramento)
* [Checklist final](#checklist-final)
* [FAQ](#faq)
* [Troubleshooting rápido](#troubleshooting-rápido)
* [Referências rápidas (menus)](#referências-rápidas-menus)
* [Assinatura](#assinatura)

---

## Visão geral

| Função                       | Onde                            | Configuração recomendada                                                                                                   | Observações                                                                                              |
| ---------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **Load Balancing**           | Transmission → Load Balancing   | **Desativado**                                                                                                             | Failover puro, sem distribuição de tráfego.                                                              |
| **Link Backup**              | Transmission → Link Backup      | **Primary: WAN1**, **Backup: WAN/LAN2**; **Mode:** *Failover (Enable backup link when all primary WANs fail)*; **All day** | "All primary" serve para hoje (1 primária) e para futuro (2+ primárias).                                 |
| **Online Detection**         | Transmission → Online Detection | **Auto** (detecção pelo gateway)                                                                                           | Se preferir validação dupla, use Manual com ICMP + DNS (DNS Lookup exige **nome**, ex.: `dns.google`).   |
| **DHCP/DNS da LAN**          | Network → LAN / DHCP Server     | **Gateway/DNS para clientes = 192.168.31.2**                                                                               | O ER605 decide o upstream conforme o estado das WANs.                                                    |
| **Port Forward na Starlink** | N/A                             | **Não disponível (CGNAT)**                                                                                                 | Se precisar acesso remoto durante o backup, usar túnel (Tailscale/ZeroTier/WireGuard/Cloudflare Tunnel). |

---

## Pré‑requisitos

* ER605 em modo **standalone** (não Omada Controller).
* Firmware recente.
* Endereçamento do ambiente (exemplo usado aqui):

  * **LAN**: 192.168.31.0/24 — **ER605 = 192.168.31.2** (gateway/DHCP/DNS)
  * **WAN1 (Fibra)**: rede 192.168.1.0/24, gateway **192.168.1.1**
  * **WAN2 (Starlink)**: rede 192.168.2.0/24, gateway **192.168.2.1**

---

## Topologia de referência

```
[Internet]──(Fibra)──[Modem/ONT 192.168.1.1]──┐
                                          ┌───┤ WAN1 (ER605)
[Internet]──(Starlink)──[Router 192.168.2.1]──┘   WAN2 (backup)
                                                 │
                                         LAN 192.168.31.0/24
                                         GW/DHCP/DNS: 192.168.31.2
```

---

## Passo a passo

### 1) Desativar o Load Balancing

* **Transmission → Load Balancing**

  * Desmarque **Enable Load Balancing**.
  * Deixe **Application Optimized Routing** desmarcado.
  * **Save**.

### 2) Configurar o Link Backup (failover)

* **Transmission → Link Backup → Add**

  * **Primary WAN:** `WAN1`
  * **Backup WAN:** `WAN/LAN2`
  * **Mode:** **Failover (Enable backup link when all primary WANs fail)**
  * **Effective Time:** *All day*
  * **Save** e marque **Enable** na regra.

### 3) Ajustar o Online Detection (Auto)

No firmware standalone do ER605, o **Auto** usa a detecção do **gateway** da WAN para decidir se o link está online/offline. É simples e, para failover puro, funciona muito bem.

**WAN1 (Fibra)**

* **Mode:** Auto

**WAN/LAN2 (Starlink)**

* **Mode:** Auto

> Dica: se notar flaps/oscilações, você pode testar o modo **Manual** e definir alvos estáveis (ICMP para `1.1.1.1`/`8.8.8.8` e *DNS Lookup* para um **nome**, ex.: `dns.google`). No Manual, lembre que *DNS Lookup* requer **nome**, não IP.

### 4) Ajustar DNS/DHCP Ajustar DNS/DHCP

* **Network → WAN → WAN1/WAN2**

  * **Primary DNS / Secondary DNS**: prefira públicos (ex.: `1.1.1.1` e `8.8.8.8`).
* **Network → LAN → DHCP Server**

  * **Gateway (Option 3):** `192.168.31.2`
  * **DNS (Option 6):** `192.168.31.2`

### 5) Informar as larguras de banda

* **Network → WAN → [WAN1/WAN2]**

  * Ajuste **Upstream/Downstream Bandwidth** para os valores reais dos links.
  * Isso melhora QoS/shaping interno e os relatórios.

### 6) Conferir Policy Routing

* **Transmission → Routing**

  * Verifique se **não há** regras de **Policy Routing** forçando sub‑redes/hosts para a `WAN/LAN2`. Para failover puro, deixe sem exceções.

### 7) Testes de failover/failback

Em um host da LAN, deixe um ping contínuo e faça a simulação.

```bash
# Na sua máquina Linux
ping 1.1.1.1
```

* Desconecte o cabo da **WAN1** (Fibra) ou desligue a porta do modem.
* O ping deve ter **poucas perdas** e retomar pela **Starlink**.
* Reconecte a **WAN1** e verifique o **failback** (volta automática à Fibra).

Diagnósticos úteis:

```bash
ip route
traceroute 1.1.1.1
nslookup github.com 192.168.31.2
```

### 8) Logs e monitoramento

* **Status → System Status**: confirma o estado “Link Up”/“Down” de cada WAN.
* **Status → Traffic Statistics** e **Interface Statistics**: tráfego por interface.
* **System Tools → Time Settings**: mantenha NTP ativo para logs corretos.

---

## Checklist final

* [ ] **Load Balancing desativado**
* [ ] **Link Backup**: Primary = **WAN1**, Backup = **WAN/LAN2**, modo **Failover (all primary)**
* [ ] **Online Detection em Manual** com *Ping* **e** *DNS Lookup* (nomes válidos)
* [ ] **DHCP entrega Gateway/DNS = 192.168.31.2** aos clientes
* [ ] **Sem Policy Routing** direcionando para WAN2
* [ ] **Teste de failover/failback** executado com sucesso

---

## FAQ

**Port‑forwarding funciona quando cair para a Starlink?**
Não. Starlink costuma usar **CGNAT**, então redirecionamento de portas não chega. Para acesso remoto durante o backup, use **túneis** (Tailscale, ZeroTier, WireGuard em servidor externo, Cloudflare Tunnel).

**Posso deixar o Online Detection em Auto?**
Sim — neste guia adotamos **Auto**. Use **Manual** apenas se quiser validação dupla e tiver alvos estáveis (ICMP + DNS).

**O failover está “piscando” (flapping).**
Ajuste para alvos mais estáveis, confirme DNS públicos nas WANs e evite usar o gateway da Starlink como alvo de ping.

---

## Troubleshooting rápido

* **Se optar por Manual e não ficar Online**: lembre que *DNS Lookup* precisa de **NOME** (ex.: `dns.google`), não IP. Use um IP público no campo *Ping*.
* **Não volta para a Fibra**: confirme o estado de Online Detection da WAN1 e se a regra de Link Backup está **Enable**.
* **Clientes perdem DNS no failover**: no DHCP, **Gateway/DNS = 192.168.31.2** (o ER605 resolve; não entregue DNS do modem aos clientes).

---

## Referências rápidas (menus)

* **Transmission → Load Balancing** (desabilitar)
* **Transmission → Link Backup** (Primary/Backup + Failover all primary)
* **Transmission → Online Detection** (Manual; definir Ping + DNS Lookup)
* **Network → WAN** (bandwidth e DNS públicos por WAN)
* **Network → LAN → DHCP Server** (gateway/DNS 192.168.31.2 para clientes)
* **Status → System Status / Traffic Statistics** (verificação)

---

## Assinatura

Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles/](https://github.com/jmsalles/)
