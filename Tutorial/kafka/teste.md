# Guia Definitivo — Kafka 4.x (KRaft) multinode em **um servidor** Oracle Linux

**Arquitetura:** 1 Controller + 3 Brokers • IP: **192.168.31.12** • **Java 21** • **Kafka 4.x estável**

## Sumário

* [0) PATH do Kafka (KAFKA\_HOME)](#0-path-do-kafka-kafka_home)
* [1) Pré-requisitos de SO](#1-pré-requisitos-de-so)
* [2) Instalação do Kafka 4.x](#2-instalação-do-kafka-4x)
* [3) Cluster ID (KRaft)](#3-cluster-id-kraft)
* [4) Configuração (Controller e Brokers)](#4-configuração-controller-e-brokers)
* [5) Serviços systemd](#5-serviços-systemd)
* [6) Testes e Validações](#6-testes-e-validações)
* [7) Operação diária](#7-operação-diária)
* [8) Troubleshooting (erros comuns)](#8-troubleshooting-erros-comuns)
* [9) Limpeza geral](#9-limpeza-geral)

---

## 0) PATH do Kafka (KAFKA\_HOME)

### Opção A) Para o usuário `kafka` (recomendado)

```bash
sudo -u kafka vim /home/kafka/.bashrc
```

Adicione ao final:

```bash
export KAFKA_HOME=/opt/kafka
export PATH="$PATH:$KAFKA_HOME/bin"
```

Carregue e teste:

```bash
sudo -u kafka bash -lc 'source ~/.bashrc && echo $KAFKA_HOME && which kafka-topics.sh && kafka-topics.sh --version'
```

### Opção B) Global (todos usuários)

```bash
sudo vim /etc/profile.d/kafka.sh
```

Conteúdo:

```bash
export KAFKA_HOME=/opt/kafka
export PATH="$PATH:$KAFKA_HOME/bin"
```

Ative:

```bash
sudo chmod 644 /etc/profile.d/kafka.sh
source /etc/profile.d/kafka.sh
which kafka-topics.sh && kafka-topics.sh --version
```

---

## 1) Pré-requisitos de SO

### 1.1 Java 21 e utilitários

```bash
sudo dnf install -y java-21-openjdk-headless jq lsof tar curl coreutils
java -version
```

### 1.2 Usuário e diretórios

```bash
export HOST_IP="192.168.31.12"
export SCALA="2.13"
export KAFKA_VER="4.1.0"    # ajuste para a 4.x estável disponível
export KAFKA_HOME="/opt/kafka"
export KAFKA_DATA="/data/kafka"

sudo useradd -m -r -s /bin/bash kafka || true
sudo mkdir -p "$KAFKA_HOME" "$KAFKA_DATA"/{controller-1,broker-{2,3,4}}
sudo chown -R kafka:kafka "$KAFKA_HOME" "$KAFKA_DATA"
```

### 1.3 Limites (evitar “too many open files”)

```bash
echo -e "kafka soft nofile 1000000\nkafka hard nofile 1000000\nkafka soft nproc 65535\nkafka hard nproc 65535" | sudo tee /etc/security/limits.d/kafka.conf
```

> Faça logout/login do usuário `kafka` (ou reinicie os serviços depois).

### 1.4 Firewall (acesso externo a clientes)

```bash
sudo firewall-cmd --permanent --add-port=9094/tcp --add-port=9095/tcp --add-port=9096/tcp
sudo firewall-cmd --reload
```

---

## 2) Instalação do Kafka 4.x

```bash
cd /tmp
curl -LO "https://downloads.apache.org/kafka/${KAFKA_VER}/kafka_${SCALA}-${KAFKA_VER}.tgz"
sudo tar -xzf "kafka_${SCALA}-${KAFKA_VER}.tgz" -C "$KAFKA_HOME" --strip-components=1
sudo chown -R kafka:kafka "$KAFKA_HOME"
```

---

## 3) Cluster ID (KRaft)

> Um **único** ID para **controller e todos os brokers**.

```bash
sudo -u kafka bash -lc 'kafka-storage.sh random-uuid | tee ~/.kafka-cluster-id'
sudo -u kafka bash -lc 'cat ~/.kafka-cluster-id'
```

---

## 4) Configuração (Controller e Brokers)

### 4.1 Controller (node.id=1)

```bash
sudo -u kafka vim /opt/kafka/config/controller.properties
```

Conteúdo:

```ini
process.roles=controller
node.id=1

controller.listener.names=CONTROLLER
listeners=CONTROLLER://127.0.0.1:9093
listener.security.protocol.map=CONTROLLER:PLAINTEXT

controller.quorum.voters=1@127.0.0.1:9093
log.dirs=/data/kafka/controller-1
```

**Formatar storage do controller:**

```bash
sudo -u kafka bash -lc 'kafka-storage.sh format -t $(cat ~/.kafka-cluster-id) -c /opt/kafka/config/controller.properties'
```

### 4.2 Brokers (node.id=2,3,4) — **linhas obrigatórias incluídas**

> Em **todos** os brokers:
> `controller.listener.names=CONTROLLER`
> `listener.security.protocol.map=PLAINTEXT:PLAINTEXT,INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT`

#### Broker 1 (node.id=2)

```bash
sudo -u kafka vim /opt/kafka/config/broker-2.properties
```

Conteúdo:

```ini
process.roles=broker
node.id=2

listeners=PLAINTEXT://0.0.0.0:9094,INTERNAL://127.0.0.1:19094
advertised.listeners=PLAINTEXT://192.168.31.12:9094,INTERNAL://127.0.0.1:19094
inter.broker.listener.name=INTERNAL

controller.listener.names=CONTROLLER
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT

controller.quorum.voters=1@127.0.0.1:9093
log.dirs=/data/kafka/broker-2

num.partitions=3
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
min.insync.replicas=2
```

Formatar:

```bash
sudo -u kafka bash -lc 'kafka-storage.sh format -t $(cat ~/.kafka-cluster-id) -c /opt/kafka/config/broker-2.properties'
```

#### Broker 2 (node.id=3)

```bash
sudo -u kafka vim /opt/kafka/config/broker-3.properties
```

Conteúdo:

```ini
process.roles=broker
node.id=3

listeners=PLAINTEXT://0.0.0.0:9095,INTERNAL://127.0.0.1:19095
advertised.listeners=PLAINTEXT://192.168.31.12:9095,INTERNAL://127.0.0.1:19095
inter.broker.listener.name=INTERNAL

controller.listener.names=CONTROLLER
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT

controller.quorum.voters=1@127.0.0.1:9093
log.dirs=/data/kafka/broker-3

num.partitions=3
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
min.insync.replicas=2
```

Formatar:

```bash
sudo -u kafka bash -lc 'kafka-storage.sh format -t $(cat ~/.kafka-cluster-id) -c /opt/kafka/config/broker-3.properties'
```

#### Broker 3 (node.id=4)

```bash
sudo -u kafka vim /opt/kafka/config/broker-4.properties
```

Conteúdo:

```ini
process.roles=broker
node.id=4

listeners=PLAINTEXT://0.0.0.0:9096,INTERNAL://127.0.0.1:19096
advertised.listeners=PLAINTEXT://192.168.31.12:9096,INTERNAL://127.0.0.1:19096
inter.broker.listener.name=INTERNAL

controller.listener.names=CONTROLLER
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT

controller.quorum.voters=1@127.0.0.1:9093
log.dirs=/data/kafka/broker-4

num.partitions=3
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
min.insync.replicas=2
```

Formatar:

```bash
sudo -u kafka bash -lc 'kafka-storage.sh format -t $(cat ~/.kafka-cluster-id) -c /opt/kafka/config/broker-4.properties'
```

---

## 5) Serviços systemd

### 5.1 Controller

```bash
sudo vim /etc/systemd/system/kafka-controller.service
```

Conteúdo:

```ini
[Unit]
Description=Apache Kafka Controller (KRaft)
After=network-online.target
Wants=network-online.target

[Service]
User=kafka
Group=kafka
Environment="KAFKA_HEAP_OPTS=-Xms1g -Xmx1g"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/controller.properties
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 5.2 Broker 2 (9094)

```bash
sudo vim /etc/systemd/system/kafka-broker-2.service
```

Conteúdo:

```ini
[Unit]
Description=Apache Kafka Broker 2 (KRaft)
After=kafka-controller.service
Requires=kafka-controller.service

[Service]
User=kafka
Group=kafka
Environment="KAFKA_HEAP_OPTS=-Xms2g -Xmx2g"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/broker-2.properties
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 5.3 Broker 3 (9095)

```bash
sudo vim /etc/systemd/system/kafka-broker-3.service
```

Conteúdo:

```ini
[Unit]
Description=Apache Kafka Broker 3 (KRaft)
After=kafka-controller.service
Requires=kafka-controller.service

[Service]
User=kafka
Group=kafka
Environment="KAFKA_HEAP_OPTS=-Xms2g -Xmx2g"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/broker-3.properties
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 5.4 Broker 4 (9096)

````bash
sudo vim /etc/systemd/system/kafka-broker-4.service
``]
Conteúdo:
```ini
[Unit]
Description=Apache Kafka Broker 4 (KRaft)
After=kafka-controller.service
Requires=kafka-controller.service

[Service]
User=kafka
Group=kafka
Environment="KAFKA_HEAP_OPTS=-Xms2g -Xmx2g"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/broker-4.properties
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
````

### 5.5 Habilitar/Iniciar

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now kafka-controller
sudo systemctl enable --now kafka-broker-2
sudo systemctl enable --now kafka-broker-3
sudo systemctl enable --now kafka-broker-4

systemctl --no-pager -l status kafka-controller kafka-broker-{2,3,4}
```

---

## 6) Testes e Validações

> **Observação:** os comandos `journalctl` abaixo **devem ser executados como root** (use `sudo`).

### 6.1 Saúde básica

```bash
systemctl --no-pager is-active kafka-controller kafka-broker-{2,3,4}
ss -lntp | egrep ':9093|:9094|:9095|:9096|:1909[4-6]'
sudo journalctl -u kafka-controller -n 80 --no-pager
sudo journalctl -u kafka-broker-2 -n 80 --no-pager
sudo journalctl -u kafka-broker-3 -n 80 --no-pager
sudo journalctl -u kafka-broker-4 -n 80 --no-pager
```

### 6.2 Quorum/metadata do cluster

```bash
kafka-metadata-quorum.sh --bootstrap-server ${HOST_IP}:9094 describe --status
kafka-metadata-quorum.sh --bootstrap-server ${HOST_IP}:9094 describe --replication
```

### 6.3 Criar tópico (RF=3) e conferir ISR

```bash
kafka-topics.sh --create --topic teste.validacao \
  --bootstrap-server ${HOST_IP}:9094,${HOST_IP}:9095,${HOST_IP}:9096 \
  --partitions 6 --replication-factor 3

kafka-topics.sh --describe --topic teste.validacao --bootstrap-server ${HOST_IP}:9094
```

### 6.4 Produzir/Consumir com **chaves** (distribuição por partição)

#### Opção A) Interativo

```bash
kafka-console-producer.sh --topic teste.validacao \
  --bootstrap-server ${HOST_IP}:9094 \
  --property parse.key=true --property key.separator=:
# digite linhas SEM espaços, no formato "chave:valor":
# a:msg-1
# b:msg-2
# a:msg-3
# Ctrl+C para sair
```

Consumidor (mostrando chave e partição):

```bash
kafka-console-consumer.sh --topic teste.validacao \
  --bootstrap-server ${HOST_IP}:9095 \
  --from-beginning \
  --property print.key=true --property print.partition=true
```

#### Opção B) **Sem intervenção** (scriptável)

**B.1 – Pequeno lote fixo:**

```bash
printf "a:msg-1\nb:msg-2\na:msg-3\n" | \
kafka-console-producer.sh --topic teste.validacao \
  --bootstrap-server ${HOST_IP}:9094 \
  --property parse.key=true --property key.separator=:
```

**B.2 – 100 mensagens com chaves cíclicas `k0..k9`:**

```bash
seq 1 100 | awk '{printf "k%d:msg-%d\n", ($1-1)%10, $1}' | \
kafka-console-producer.sh --topic teste.validacao \
  --bootstrap-server ${HOST_IP}:9094 \
  --property parse.key=true --property key.separator=:
```

**B.3 – Consumir, mostrar chave/partição e contar total:**

```bash
kafka-console-consumer.sh --topic teste.validacao \
  --bootstrap-server ${HOST_IP}:9095 \
  --from-beginning \
  --timeout-ms 5000 \
  --property print.key=true --property print.partition=true | \
tee /tmp/consumo.validacao.out >/dev/null

echo "TOTAL=$(wc -l </tmp/consumo.validacao.out)"
```

> Dicas: com `--property parse.key=true`, **cada linha** precisa ter o separador (por padrão `:`).
> Para **chave vazia**, use `:mensagem`.

### 6.5 Consumo em grupo (rebalance)

```bash
kafka-console-consumer.sh --topic teste.validacao \
  --bootstrap-server ${HOST_IP}:9094 \
  --group grupo.validacao --from-beginning \
  --property print.partition=true
```

Outro terminal:

```bash
kafka-console-consumer.sh --topic teste.validacao \
  --bootstrap-server ${HOST_IP}:9095 \
  --group grupo.validacao --from-beginning \
  --property print.partition=true
```

Descrever o grupo:

```bash
kafka-consumer-groups.sh --bootstrap-server ${HOST_IP}:9094 --describe --group grupo.validacao
```

### 6.6 Replicação e tamanhos por broker

```bash
kafka-log-dirs.sh --bootstrap-server ${HOST_IP}:9094 --describe --topics teste.validacao
```

### 6.7 Failover (parar um broker e recuperar)

Parar broker-4:

```bash
sudo systemctl stop kafka-broker-4
```

Checar ISR/URPs:

```bash
kafka-topics.sh --describe --topic teste.validacao --bootstrap-server ${HOST_IP}:9094
kafka-topics.sh --under-replicated-partitions --bootstrap-server ${HOST_IP}:9094
```

Religar:

```bash
sudo systemctl start kafka-broker-4
kafka-topics.sh --describe --topic teste.validacao --bootstrap-server ${HOST_IP}:9094
```

### 6.8 Eleição de líder preferido

```bash
kafka-leader-election.sh --bootstrap-server ${HOST_IP}:9094 \
  --all-topic-partitions --election-type PREFERRED
```

### 6.9 Throughput do produtor (baseline)

```bash
kafka-topics.sh --create --topic perf.test \
  --bootstrap-server ${HOST_IP}:9094,${HOST_IP}:9095,${HOST_IP}:9096 \
  --partitions 12 --replication-factor 3

kafka-producer-perf-test.sh --topic perf.test \
  --num-records 500000 --record-size 100 --throughput -1 \
  --producer-props acks=all linger.ms=5 batch.size=65536 \
                   bootstrap.servers=${HOST_IP}:9094,${HOST_IP}:9095,${HOST_IP}:9096
```

### 6.10 Retenção (comportamento de “fila”)

```bash
kafka-configs.sh --bootstrap-server ${HOST_IP}:9094 \
  --entity-type topics --entity-name teste.validacao \
  --alter --add-config retention.ms=60000

kafka-configs.sh --bootstrap-server ${HOST_IP}:9094 \
  --entity-type topics --entity-name teste.validacao --describe
```

### 6.11 Verificação de integridade de réplicas

```bash
kafka-replica-verification.sh \
  --topic-white-list teste.validacao \
  --time -1 --report-interval-ms 5000 \
  --bootstrap-server ${HOST_IP}:9094
```

### 6.12 Smoke test fim-a-fim automático

```bash
TOPIC="smoke.$(date +%s)"; \
kafka-topics.sh --create --topic "$TOPIC" \
  --bootstrap-server ${HOST_IP}:9094,${HOST_IP}:9095,${HOST_IP}:9096 \
  --partitions 3 --replication-factor 3 && \
seq 1 1000 | awk '{print "k"($1%10)":"$1}' | \
kafka-console-producer.sh --bootstrap-server ${HOST_IP}:9094 \
  --topic "$TOPIC" --property parse.key=true --property key.separator=: && \
kafka-console-consumer.sh --bootstrap-server ${HOST_IP}:9095 \
  --topic "$TOPIC" --from-beginning --timeout-ms 5000 \
  --property print.key=true --property print.partition=true | \
tee "/tmp/$TOPIC.out" >/dev/null; \
echo "TOTAL=$(wc -l </tmp/$TOPIC.out) (esperado=1000)"
```

---

## 7) Operação diária

```bash
kafka-metadata-quorum.sh --bootstrap-server ${HOST_IP}:9094 describe --status
kafka-topics.sh --list --bootstrap-server ${HOST_IP}:9094
kafka-consumer-groups.sh --bootstrap-server ${HOST_IP}:9094 --list
```

---

## 8) Troubleshooting (erros comuns)

* **No security protocol defined for listener INTERNAL**
  ➜ Adicione `listener.security.protocol.map=PLAINTEXT:PLAINTEXT,INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT` no broker.

* **controller.listener.names must contain at least one value**
  ➜ Adicione `controller.listener.names=CONTROLLER` no broker.

* **Mismatched clusterId**
  ➜ Reformatar `log.dirs` do(s) nós afetado(s) com **o mesmo** UUID do controller:

  ```bash
  sudo -u kafka bash -lc 'kafka-storage.sh format -t $(cat ~/.kafka-cluster-id) -c <arquivo.properties>'
  ```

* **Clientes não conectam**
  ➜ Corrija `advertised.listeners` para **192.168.31.12**.

* **Logs (como root)**

  ```bash
  sudo journalctl -u kafka-controller -n 200 --no-pager
  sudo journalctl -u kafka-broker-2 -n 200 --no-pager
  sudo journalctl -u kafka-broker-3 -n 200 --no-pager
  sudo journalctl -u kafka-broker-4 -n 200 --no-pager
  ```

---

## 9) Limpeza geral (remove tudo)

```bash
sudo systemctl stop kafka-broker-{2,3,4} kafka-controller
sudo systemctl disable kafka-broker-{2,3,4} kafka-controller
sudo rm -f /etc/systemd/system/kafka-*.service
sudo systemctl daemon-reload
sudo rm -rf "$KAFKA_DATA"/* "$KAFKA_HOME"
sudo userdel -r kafka
```

---

**Criado por Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
