local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("dkjson")
local socket = require("socket")
local mime = require("mime")

-- Importa classes do models.lua
-- local models = require("models")
-- local Usuario = models.Usuario
-- local Postagem = models.Postagem
-- local Mensagem = models.Mensagem

-- Configuração do RabbitMQ via API HTTP
local BROKER_URL = "http://rabbitmq:15672/api/queues/%2F/task_queue/get"
local SYNC_URL = "http://rabbitmq:15672/api/exchanges/%2F/amq.default/publish"
local AUTH = "guest:guest"
local EXCHANGE_NAME = "sync_exchange"  -- Exchange em comum para sincronização de dados
local SERVER_ID = nil
local last_sync_time = 0
local coordinator_timeout = 0
local election_in_progress = false
local queue = false -- Controla instancia de fila dinamicamente
-- Banco de dados simples em JSON (simulado)
local database = {
    usuarios = {},
    postagens = {},
    mensagens = {}
}
last_message = nil

servers = {} -- IDs dos servidores
coordinator = nil


-----------------

local servers_list = {} -- IDs conhecidos, pode ser preenchido estaticamente ou dinamicamente
local berkeley_responses = {}

-- Relógio lógico
local logical_clock = 0

local function divisao() 
    print("\n --------------------------------------------------- \n")
end


local function find_servers()
    local response_body = {}

    local res, status, headers = http.request{
        url = "http://rabbitmq:15672/api/queues",
        method = "GET",
        headers = {
            ["Authorization"] = "Basic " .. mime.b64(AUTH),
            ["Content-Type"] = "application/json"
        },
        sink = ltn12.sink.table(response_body)
    }

    if not res then
        print("Erro ao tentar acessar a API do RabbitMQ para obter filas.")
        return {}
    end

    if status == 200 then
        local response_str = table.concat(response_body)
        local data, _, err = json.decode(response_str)
        print("Obtendo filas dos servidores...")
        if not data then
            print("Erro ao decodificar JSON:", err)
            return {}
        end

        local queues = {}
        for _, queue in ipairs(data) do
            if #queue.name <= 3 then--and queue.name ~= tostring(SERVER_ID) then
                
                table.insert(queues, queue.name)
            end
        end

        return queues
    else
        print("Erro ao obter filas:", status, table.concat(response_body))
        return {}
    end
end

--                BERKELEY ELEICAO BULLYING
-- Procura os servidores e salva em um array
function update_servers_ID()
    servers = find_servers()
    servers_list = servers
end


local function send_message(operation, data, destination)
    local payload = {
        properties = {
            correlation_id = "berkeley"
        },
        routing_key = destination or "task_queue",
        payload = json.encode({
            operation = operation,
            data = data,
            sender_id = SERVER_ID,
            timestamp = os.time()                     --timestamp = socket.gettime()
        }),
        payload_encoding = "string"
    }

    local response_body = {}
    local res, status = http.request{
        url = "http://rabbitmq:15672/api/exchanges/%2F/amq.default/publish",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. mime.b64(AUTH)
        },
        source = ltn12.source.string(json.encode(payload)),
        sink = ltn12.sink.table(response_body)
    }

    if status ~= 200 then
        print("Erro ao enviar mensagem:", status, table.concat(response_body))
    end
end

local function request_coordinator()
    print("Requisitando coordenador atual...")
    coordinator_timeout = socket.gettime()
    send_message("who_is_coordinator", {}, "task_queue")
end


-- Início do algoritmo de Berkeley (somente coordenador executa)

function announce_coordinator()
    print("Anunciando como coordenador.")
    coordinator = SERVER_ID
    for _, id in ipairs(servers_list) do
        print("Enviado para os outros... ", id)
        if tonumber(id) ~= tonumber(SERVER_ID) then
            print("ID DO SERVIDOR: ", SERVER_ID)
            send_message("coordinator", { coordinator_id = SERVER_ID }, id)
        end
    end
end
function start_election()
    print("Iniciando eleição...")

    -- Se existe um coordenador maior, tentar pingar ele
    if coordinator and tonumber(coordinator) > tonumber(SERVER_ID) then
        print("Existe um coordenador maior. Verificando se está ativo...")
        send_message("coordinator_alive?", {}, coordinator)

        -- Aguarda resposta por até 3 segundos
        local timeout = socket.gettime() + 3
        while socket.gettime() < timeout do
            if coordinator == nil or coordinator == SERVER_ID then
                break
            end
            socket.sleep(0.02)
        end

        -- Se ainda não recebeu resposta, assume que o coordenador está morto
        if coordinator and tonumber(coordinator) > tonumber(SERVER_ID) then
            print("Coordenador não respondeu. Iniciando eleição normalmente.")
            if (tonumber(coordinator) - 1) == tonumber(SERVER_ID) then
                print("Substituindo servidor antigo.")
                announce_coordinator()
            end
        else
            return  -- Coordenador ainda válido, aborta eleição
        end
    end

    -- Continua eleição se não há coordenador maior ou ele está inativo
    for _, other_id in ipairs(servers_list) do
        if tonumber(other_id) > tonumber(SERVER_ID) then
            send_message("election_response", { from = SERVER_ID }, other_id)
        end
    end
    socket.sleep(0.03)
    if not coordinator or tonumber(coordinator) < tonumber(SERVER_ID) then
        announce_coordinator()
    end
end



function start_berkeley()
    print("Coordenador iniciando sincronização de tempo (Berkeley)")
    for _, id in ipairs(servers_list) do
        if tonumber(id) ~= tonumber(SERVER_ID) then
            send_message("sync_time_request", { timestamp = os.time() }, id)
        end
    end
    -- socket.sleep(0.5)

    local total_offset = 0
    local count = 1  -- inclui o coordenador (offset = 0)
    
    for _, offset in pairs(berkeley_responses) do
        total_offset = total_offset + offset
        count = count + 1
    end

    local avg_offset = total_offset / count
    logical_clock = logical_clock + avg_offset
    print("AVG offset: ", avg_offset, " logical clock", logical_clock)
    berkeley_responses = {}

end



















-- Função para carregar o banco de dados do arquivo JSON, se existir
local function load_database_from_file()
    local name = "database-" .. tostring(SERVER_ID) .. ".json"
    print("DATABASE NAME: ", name)
    local file = io.open(name, "r")
    if file then
        local content = file:read("*a")
        local success, loaded_data = pcall(json.decode, content)
        if success then
            database = loaded_data
            print("Banco de dados carregado com sucesso do arquivo .", name)
        else
            print("Erro ao carregar banco de dados do arquivo JSON:", loaded_data)
        end
        file:close()
    else
        print("Arquivo 'database.json' não encontrado. Usando banco de dados vazio.")
    end
end

-- Função para salvar o banco de dados em um arquivo JSON
local function save_database_to_file()
    local name = "database-" .. tostring(SERVER_ID) .. ".json"
    local file = io.open(name, "w")
    if file then
        file:write(json.encode(database, { indent = true }))
        file:close()
        print("Banco de dados salvo no arquivo ", name)
    else
        print("Erro ao salvar o banco de dados.")
    end
end

local function save_log(log)
    local name = "log" .. tostring(SERVER_ID) ..".txt "
    local file = io.open(name, "a")
    if file then
        file:write(log)
        file:close()
        print("log salvo em: ", name)
    else
        print("Erro ao salvar logs.")
    end
end
-- Função para publicar atualização no RabbitMQ e salvar localmente
local function update_json_file(entry, operation)
    -- logical_clock = logical_clock + 1
    last_message = math.floor(socket.gettime())
    if entry._correlation_id then entry = entry.data end
    local payload = {
        properties = {
            delivery_mode = 2,
            correlation_id = "12345"
        },
        routing_key = "task_queue",
        payload = json.encode({
            operation = operation,
            data = entry,
            clock = logical_clock,  -- Inclui o relógio lógico
            avoid_duplicate = last_message
        }),
        payload_encoding = "string"
    }

    local payload_data = json.encode(payload)
    local rabbitmq_url = "http://rabbitmq:15672/api/exchanges/%2F/amq.fanout/publish"

    local response_body = {}
    local res, status, headers = http.request{
        url = rabbitmq_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. mime.b64("guest:guest")
        },
        source = ltn12.source.string(payload_data),
        sink = ltn12.sink.table(response_body)
    }
    
    if status == 200 then
        divisao()
        print("Publicação de atualização bem-sucedida: ", operation)
    else
        print("Erro ao publicar atualização: ", status, table.concat(response_body))
    end
    
    save_database_to_file()
end

local function responder_API(correlation_id, reply_to, data)
    local payload = {
        properties = {
            correlation_id = correlation_id,
            resposta_para_API = true
        },
        routing_key = reply_to,
        payload = json.encode(data),
        payload_encoding = "string"
    }

    local response_body = {}
    local res, status, headers = http.request{
        url = "http://rabbitmq:15672/api/exchanges/%2F/amq.default/publish",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. mime.b64("guest:guest")
        },
        source = ltn12.source.string(json.encode(payload)),
        sink = ltn12.sink.table(response_body)
    }

    if status == 200 then
        print("Resposta enviada para Python (correlation_id: " .. correlation_id .. ")")
    else
        print("Erro ao enviar resposta:", status, table.concat(response_body))
    end
end

local function request_sync()
    local payload = {
        properties = {
            correlation_id = "sync_" .. tostring(SERVER_ID),
            priority = 10
        },
        routing_key = "task_queue",
        payload = json.encode({
            operation = "sync_request",
            requester_id = SERVER_ID
        }),
        payload_encoding = "string"
    }

    local response = {}
    local res, status = http.request{
        url = "http://rabbitmq:15672/api/exchanges/%2F/amq.default/publish",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. mime.b64("guest:guest")
        },
        source = ltn12.source.string(json.encode(payload)),
        sink = ltn12.sink.table(response)
    }
    if #response == 0 then print("Nenhuma resposta retornada ao request_sync") end

    local msg = table.concat(response)
    print("Resposta: ", tostring(msg), " Resposta json: ", tostring(json.decode(msg)))

    if status == 200 then
        print("Solicitação de sincronização enviada (broadcast).")
    else
        print("Erro ao solicitar sincronização:", status)
    end
end













-- Função para manipular as mensagens recebidas
local function handle_message(message)

        if message.operation == "get_users" then
            responder_API(message._correlation_id, message._reply_to, database.usuarios)
            return
        elseif message.operation == "get_posts" then
            -- envia posts agrupados por usuário
            local agrupadas = {}
            for _, usuario in ipairs(database.usuarios or {}) do
                local usuario_posts = {}
                for _, pid in ipairs(usuario.postagens or {}) do
                    for _, post in ipairs(database.postagens or {}) do
                        if post.post_id == pid then
                            table.insert(usuario_posts, post)
                        end
                    end
                end
                table.insert(agrupadas, {
                    usuario = usuario.nome,
                    postagens = usuario_posts
                })
            end
            responder_API(message._correlation_id, message._reply_to, agrupadas)
            return

        elseif message.operation == "get_messages" then
            responder_API(message._correlation_id, message._reply_to, database.mensagens)
            return


        elseif message.operation == "election" then
            if tonumber(message.sender_id) < tonumber(SERVER_ID) then
                -- responde ao remetente indicando que existe servidor com ID maior
                send_message("election_response", {from = SERVER_ID}, message.sender_id)

                -- apenas reinicia eleição se ainda não for o coordenador
                if coordinator ~= SERVER_ID then
                    start_election()
                end
            end
            return
        
        elseif message.operation == "election_response" then
            -- Recebeu resposta de outro servidor com ID maior
            print("Recebido election_response de ", message.sender_id)
            election_in_progress = true
            return


------------------BERKELEY---------------------------

        elseif message.operation == "coordinator_alive?" then
            if coordinator == SERVER_ID then
                print("Recebido ping de coordenador_alive?, respondendo...")
                send_message("coordinator_alive_ack", {}, message.sender_id)
            end
            return

        elseif message.operation == "coordinator_alive_ack" then
            print("Coordenador respondeu ao ping. Mantendo coordenador atual: ", coordinator)
            -- Reafirma coordenador e impede que eleição continue
            election_in_progress = true
            return


        elseif message.operation == "coordinator" then
        if message.data and message.data.coordinator_id then
            coordinator = message.data.coordinator_id
            election_in_progress = true
            print("Novo coordenador definido: ", coordinator)
        else
            print("Mensagem de coordenador recebida, mas coordinator_id está ausente!")
        end
        return
        elseif message.operation == "sync_time_request" then
            local delay = os.time() - (message.data.timestamp) -- socket.gettime() - message.timestamp
            -- print("DELAY: ", delay)
            print("Respondendo sync_time_response do coordenador")
            last_sync_time = socket.gettime()
            if tostring(SERVER_ID) > tostring(message.sender_id) then election_in_progress = false end
            send_message("sync_time_response", { offset = delay }, message.sender_id)
            if tonumber(message.sender_id) < tonumber(SERVER_ID) then
                -- responde ao remetente indicando que existe servidor com ID maior
                send_message("election_response", {from = SERVER_ID}, message.sender_id)
            end
            return

        elseif message.operation == "sync_time_response" then
            if message.sender_id and message.data and message.data.offset then
                berkeley_responses[message.sender_id] = message.data.offset
                print("RECEBENDO sync_time_response")
                return
            end
            
            
            ------------------BERKELEY---------------------------

        elseif message.operation == "who_is_coordinator" then
        if coordinator == SERVER_ID then
            print("Recebida requisição de coordenador. Sou o coordenador.")
            send_message("coordinator", { coordinator_id = SERVER_ID }, message.sender_id)
        end
        return


        elseif message.operation == "sync_request" then
            print("SYNC_REQUEST solicitado ", message.requester_id)
            if message.requester_id ~= SERVER_ID then
                print("SYNC_REQUEST processando...")
            local sync_data = {
                usuarios = database.usuarios,
                postagens = database.postagens,
                mensagens = database.mensagens
            }

            local sync_payload = {
                properties = {
                    correlation_id = "sync_response_" .. message.requester_id,
                    priority = 10
                },
                routing_key = message.requester_id,
                payload = json.encode({
                    operation = "sync_response",
                    data = sync_data
                }),
                payload_encoding = "string"
            }

            local res_body = {}
            local res, status = http.request{
                url = "http://rabbitmq:15672/api/exchanges/%2F/amq.default/publish",
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Basic " .. mime.b64("guest:guest")
                },
                source = ltn12.source.string(json.encode(sync_payload)),
                sink = ltn12.sink.table(res_body)
            }

            print("Respondendo sync_request do servidor " .. message.requester_id)
            return
    end

        end
    divisao()
    -- save_log(texto)
    print("Operacao recebida:", message.operation)
    print("Avoid-ID:", message.avoid_duplicate, "Last message: ", last_message)


    if last_message == nil or last_message ~= message.avoid_duplicate then --Evita mensagens duplicadas
        if last_message == nil or last_message ~= message.avoid_duplicate then --Evita mensagens duplicadas
            last_message = message.avoid_duplicate
            if message.operation == "create_post" or message.operation == "add_post" then
            texto = string.format("LOG: %s | Data: %s | Timestamp: %s", message.operation, tostring(json.encode(message.data, { indent = true })), os.date("%d-%m-%Y %H:%M:%S"))
                print(texto)
                if message.operation == "create_post" then update_json_file(message, "add_post") end --Envia para os outros servidores
                print("MENSAGEM ACEITA - Criar postagem")
                local post = message.data
                for _, usuario in ipairs(database.usuarios) do
                    if usuario.nome == post.usuario_id then
                usuario.postagens = usuario.postagens or {}  -- Garante que a tabela postagens exista
                print("SALVANDO POST: ", post , " em usuario: ", usuario.nome)
                table.insert(usuario.postagens, post.post_id)     -- Adiciona a postagem
                table.insert(database.postagens, post)
                save_database_to_file()
                break
            end
        end


        elseif message.operation == "create_user" or message.operation == "add_user" then
            if message.operation == "create_user" then update_json_file(message, "add_user") end --Envia para os outros servidores
            texto = string.format("LOG: %s | Data: %s | Timestamp: %s", message.operation, tostring(json.encode(message.data, { indent = true })), os.date("%d-%m-%Y %H:%M:%S"))
            print(texto)
            print("MENSAGEM ACEITA - Criar usuário")
            table.insert(database.usuarios, message.data)
            save_database_to_file()
            
        elseif message.operation == "send_message" or message.operation == "add_message" then
            if message.operation == "send_message" then update_json_file(message, "add_message") end --Envia para os outros servidores
            texto = string.format("LOG: %s | Data: %s | Timestamp: %s", message.operation, tostring(json.encode(message.data, { indent = true })), os.date("%d-%m-%Y %H:%M:%S"))
            print(texto)
            print("MENSAGEM ACEITA - Enviar mensagem")
            table.insert(database.mensagens, message.data)
            save_database_to_file()
        
            elseif message.operation == "sync_response" then
        print("SYNC_RESPONSE recebido. Sincronizando dados...")

        local data = message.data
        if data then
            database.usuarios = data.usuarios or {}
            database.postagens = data.postagens or {}
            database.mensagens = data.mensagens or {}
            save_database_to_file()
            print("Sincronização concluída com sucesso!")
            return
        else
            print("SYNC_RESPONSE inválido: dados ausentes.")
        
         end

        elseif message.operation == "follow" or message.operation == "add_follow" then
            if message.operation == "follow" then update_json_file(message, "add_follow") end --Envia para os outros servidores
            texto = string.format("LOG: %s | Data: %s => %s | Timestamp: %s", message.operation, message.data.follower, message.data.following, os.date("%d-%m-%Y %H:%M:%S"))
            print(texto)
            print("MENSAGEM ACEITA - Seguir usuário")
            local follow_data = message.data
            print("MENSAGEM RECEBIDA FOLLOW: ", follow_data.follower)
            local usuario_a = follow_data.follower
            local usuario_b = follow_data.following

            for _, usuario in ipairs(database.usuarios) do
                if usuario.nome == usuario_a then
                    usuario.seguindo = usuario.seguindo or {}
                    print("Usuário:", usuario.nome, "seguindo:", usuario_b)

                    local ja_segue = false
                    for _, seguido in ipairs(usuario.seguindo) do
                        if seguido == usuario_b then
                            ja_segue = true
                            break
                        end
                    end
                    
                    if not ja_segue then
                        table.insert(usuario.seguindo, usuario_b)
                        save_database_to_file()
                    end
                end

                if usuario.nome == usuario_b then
                    usuario.seguidores = usuario.seguidores or {}
                    print("Usuário:", usuario.nome, "ganhou seguidor:", usuario_a)

                    local ja_e_seguidor = false
                    for _, seguidor in ipairs(usuario.seguidores) do
                        if seguidor == usuario_a then
                            ja_e_seguidor = true
                            break
                        end
                    end

                    if not ja_e_seguidor then
                        table.insert(usuario.seguidores, usuario_a)
                        save_database_to_file()
                    end
                end
                -- print("Seguindo usuário:", message.data.usuario_b.nome)
            end
        
        
        


        
        else
            print("Operação desconhecida:", message.operation)
        end
    else
        print("Mensagem duplicada ignorada...")
    end
end
end


-- Re-consome a mensagem para retirá-la da fila
local function acknowledge_message()
    local response_body = {}
    local status

    _, status = http.request{
        url = BROKER_URL,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. mime.b64(AUTH)
        },
        source = ltn12.source.string(json.encode({
            count = 1,
            requeue = false,
            encoding = "auto",
            trunc = true,
            ackmode = "ack_requeue_false"
        })),
        sink = ltn12.sink.table(response_body)
    }

    if status ~= 200 then
        print("Erro ao remover mensagem da fila (ACK): ", status)
    else
        print("Mensagem confirmada e removida da fila (ACK).")
    end
end


-- Função para consumir mensagens da fila de tarefas
local function consume_messages()
    local response = {}

    local response_body, status, headers = http.request{
        url = BROKER_URL,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. mime.b64(AUTH)
        },
        source = ltn12.source.string(json.encode({
            count = 1,
            requeue = true,
            encoding = "auto",
            trunc = true,
            ackmode = "ack_requeue_true"
        })),
        sink = ltn12.sink.table(response)
    }

    if status ~= 200 then
        print("Erro ao consumir mensagem: ", status)
        return
    end

    if #response == 0 then
        print("Nenhuma mensagem na fila.")
        return
    end

    local msg = table.concat(response)

    if msg and #msg > 0 then
        local msg_json = json.decode(msg)
        if msg_json and #msg_json > 0 then
            local raw = msg_json[1]
            local payload = raw.payload
            local message = json.decode(payload)
            texto = string.format("LOG: %s | Data: %s | Timestamp: %s", message.operation, tostring(json.encode(message.data, { indent = false }) ), os.date("%d-%m-%Y %H:%M:%S") .. "\n")
            save_log(texto)
            -- Verifica se é resposta para API
            local correlation_id = raw.properties and raw.properties.correlation_id
            local reply_to = raw.properties and raw.properties.reply_to

            -- Se for uma resposta destinada a outra fila, ignora
            if raw.properties.resposta_para_API then
                print("Ignorando resposta destinada a outro servidor. reply_to: " .. tostring(reply_to))
                return
            end

            -- Se for broadcast ou destinado a este servidor, processa
            message._correlation_id = correlation_id
            message._reply_to = reply_to

            handle_message(message)
            acknowledge_message()
        else
            print("Nenhuma mensagem válida encontrada.")
        end
    else
        print("Resposta vazia recebida da fila.")
    end
end

-- Variável global para o ID do servidor


-- Função para criar a fila com TTL e associá-la a uma exchange
local function create_queue_and_bind_to_exchange()
    local queue_url = "http://rabbitmq:15672/api/queues/%2F/" .. SERVER_ID
    local ttl_ms = 60000  -- TTL de (3000000 ms)

    local queue_data = {
        name = SERVER_ID,
        durable = true,
        arguments = {
            ["x-expires"] = ttl_ms,
            ["x-max-priority"] = 10 
        }
    }

    local response_body = {}
    local res, status = http.request{
        url = queue_url,
        method = "PUT",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. mime.b64("guest:guest")
        },
        source = ltn12.source.string(json.encode(queue_data)),
        sink = ltn12.sink.table(response_body)
    }

    if status == 201 or status == 204 then
        queue = true
        print("Fila criada com sucesso para o servidor " .. SERVER_ID)
    else
        print("Erro ao criar fila para o servidor " .. SERVER_ID, status, table.concat(response_body))
        return
    end
end

-- Função para consumir mensagens da fila de sincronização
local function consume_sync_data()
    local response = {}

    local response_body, status, headers = http.request{
        url = "http://rabbitmq:15672/api/queues/%2F/" .. SERVER_ID .. "/get",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. mime.b64(AUTH)
        },
        source = ltn12.source.string(json.encode({
            count = 1,
            requeue = true,
            encoding = "auto",
            trunc = true,
            ackmode = "ack_requeue_false"
        })),
        sink = ltn12.sink.table(response)
    }

    if status ~= 200 then
        print("Erro ao consumir mensagem: ", status)
        return
    end

    if #response == 0 then
        print("Nenhuma mensagem na fila.")
        return
    end

    local msg = table.concat(response)
    if msg and #msg > 0 then
        local msg_json = json.decode(msg)
        if msg_json and #msg_json > 0 then
            local payload = msg_json[1].payload
            local message = json.decode(payload)
            texto = string.format("LOG: %s | Data: %s | Timestamp: %s", message.operation, tostring(json.encode(message.data, { indent = false }) ), os.date("%d-%m-%Y %H:%M:%S") .. "\n")
            save_log(texto)
            handle_message(message)
        else
            -- print("Nenhuma mensagem válida encontrada.")
            
        end
    else
        print("Resposta vazia recebida da fila.")
    end
end


-- Função para sincronizar os dados entre servidores
local function sync_data()
    if not queue then create_queue_and_bind_to_exchange() end
    
    consume_sync_data()
end


-- Função para inicializar o servidor Lua
local function initialize_server(server_number)
    SERVER_ID = server_number
    print("Servidor " .. server_number .. " inicializado com ID: " .. SERVER_ID)
    print("Aguardando RabbitMQ inicializar")
    socket.sleep(40)
    -- synchronize_clocks()
    load_database_from_file()
    if #database.usuarios == 0 and #database.postagens == 0 and #database.mensagens == 0 then
        request_sync()
    end
    sync_data()
    request_coordinator()
    sync_data()
    socket.sleep(2)  -- Pausa antes da próxima tentativa
    while true do
        update_servers_ID()
        
        print("Coordenador: ", coordinator)
            consume_messages()
            sync_data()
            socket.sleep(0.5)  -- Pausa antes da próxima tentativa
            if not election_in_progress then
                start_election()
                election_in_progress = true
            end
            --Caso o coordenador pare de responder por timeout, uma nova eleicao se iniciada, e a fila do coordenador antigo e deletada
            if socket.gettime() - last_sync_time > 60 then 
                election_in_progress = false 
            end
            
            if coordinator == SERVER_ID then
                print("Eu SERVIDOR ", SERVER_ID, " sou coordenador!")
            else
                print("Eu SERVIDOR ", SERVER_ID, " nao sou coordenador")
            end
            if coordinator == SERVER_ID and socket.gettime() - last_sync_time > 15 then
                start_berkeley()
                last_sync_time = socket.gettime()
            end
    end
end

initialize_server(arg[1] or 1)

