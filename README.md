
## Ferramentas utilizadas no desenvolvimento

* **Front-end:**
  - HTML  
  - CSS  
  - JavaScript

* **API:**
  - Python (comunicação via AMQP)  
  - Biblioteca FastAPI

* **Broker:**
  - RabbitMQ

* **Back-end:**
  - Lua (comunicação via `socket.http`)

---

## Como executar o projeto

Copiar o repositório:
```bash
git clone https://github.com/nath88d/CC7261-Sistemas-Distribuidos.git
```

Mudar de diretório:
```bash
cd CC7261-Sistemas-Distribuidos/
```

Iniciar o projeto via Docker:
```bash
docker-compose up --build
```

Acessar o painel web:
```bash
localhost:8080
```

(Opcional) Acessar o painel RabbitMQ:  
Usuário padrão: `guest`  
Senha padrão: `guest`
```bash
http://localhost:15672
```

---

## Funcionamento do projeto

### Os usuários podem:
  * Publicar e visualizar publicações de outros usuários;
  * Seguir outros usuários:
    - Os usuários seguidos têm prioridade na ordenação das **Postagens Recentes**;
  * Trocar mensagens privadas entre si, com armazenamento do histórico da conversa de forma ordenada.

### API:
  * Ao iniciar, a API cria a `task_queue` (fila principal de comunicação entre API e servidores);
  * Caso detecte uma nova fila (fila privada de um servidor) sendo instanciada, realiza o binding dessa nova fila à Exchange Fanout, possibilitando o funcionamento correto do broadcast entre servidores;
  * Intermedia as solicitações entre cliente e servidores.

### Servidor:
  * Ao consumir uma mensagem da `task_queue` (solicitação de armazenamento vinda da API), o servidor compartilha essa informação com os demais, para que todos armazenem o mesmo dado;
  * Caso um dos servidores inicie após os demais já estarem em operação, ele sincroniza seu banco de dados com os demais.
  * Realiza sincronização dos relógios lógicos

#### Algoritmo de Berkeley / Coordenador via Bullying:
  * O servidor de maior número será eleito coordenador (algoritmo de bullying);
  * Caso o coordenador pare de responder (timeout), uma nova eleição é iniciada;
  * Os servidores armazenam os logs a cada envio/recebimento de mensagem.

---

## Panorama da arquitetura
![d](https://github.com/user-attachments/assets/9a83d612-518b-43d2-ad61-a733dcc62f32)

## Rede Social com Publicações e Troca de Mensagens

Desenvolver um sistema distribuído para uma rede social que permita a interação entre usuários, incluindo publicação de textos, troca de mensagens e funcionalidades de notificação, utilizando múltiplos servidores para garantir alta disponibilidade e consistência. O sistema deve utilizar algoritmos de sincronização de relógios e garantir a ordenação das mensagens por meio de relógios lógicos.

**Usuários:**
- Um usuário pode publicar textos visíveis para outros. Cada publicação é associada ao autor e registrada com um timestamp;
- Usuários podem seguir outros usuários. Ao seguir alguém, o usuário recebe notificações quando essa pessoa publica algo novo;
- Usuários podem trocar mensagens privadas entre si. As mensagens devem ser entregues de forma confiável e ordenada.

**Servidores:**
- Mensagens e postagens são replicadas em pelo menos três servidores. A adição e remoção de servidores devem ser feitas dinamicamente, sem comprometer a disponibilidade ou integridade das mensagens;
- O sistema garante que os relógios dos servidores estejam sincronizados por meio do algoritmo de Berkeley, com eleição de coordenador via bullying. O coordenador é responsável por atualizar os relógios dos servidores participantes.

**Sistema implementado:**
- Cada processo (usuário ou servidor) mantém um relógio lógico. As mensagens publicadas e interações entre usuários (como mensagens privadas) são ordenadas com base nesse relógio lógico, garantindo consistência na leitura e entrega;
- Todos os processos (usuário ou servidor) devem gerar um arquivo de log com todas as interações realizadas (postagens, mensagens, sincronizações de relógio etc.).
