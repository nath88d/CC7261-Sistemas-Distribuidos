import requests
import pika
from time import sleep
# Configurações
RABBITMQ_HOST = 'rabbitmq'
API_URL = f'http://{RABBITMQ_HOST}:15672/api/queues'
EXCHANGE_NAME = 'amq.fanout'
# Autenticação
AUTH = ('guest', 'guest')
def wait_for_rabbitmq(max_retries=20, delay=2):
    for i in range(max_retries):
        try:
            RABBITMQ_HOST = 'rabbitmq'
            connectionTRY = pika.BlockingConnection(pika.ConnectionParameters(RABBITMQ_HOST))
            print("Conexão com RabbitMQ estabelecida.")
            
            return connectionTRY
        except pika.exceptions.AMQPConnectionError as e:
            print(f"Tentativa {i+1}/{max_retries} falhou. RabbitMQ não está pronto ainda...")
            sleep(delay)
    raise Exception("Não foi possível conectar ao RabbitMQ após várias tentativas.")

def create_task_queue(channel):
    try:
        channel.queue_declare(queue='task_queue', durable=True)
        print("Fila 'task_queue' criada com sucesso.")
    except Exception as e:
        # print(f"Erro ao criar a fila 'task_queue': {e}")
        pass



# Função para obter as filas usando a API HTTP do RabbitMQ
def get_queues():
    try:
        # Fazendo uma requisição GET para obter as filas
        response = requests.get(API_URL, auth=AUTH)
        
        # Se a resposta for bem-sucedida, continua
        if response.status_code == 200:
            queues = [queue['name'] for queue in response.json() if queue['name'] != 'task_queue']
            return queues
        else:
            print(f"Erro ao obter filas: {response.status_code} - {response.text}")
            return []
    
    except Exception as e:
        print(f"Erro ao tentar acessar a API do RabbitMQ: {e}")
        return []

# Função para fazer o binding entre a fila e a exchange
def bind_queue_to_exchange(queue_name, channel):
    try:
        # Realiza o binding da fila para a exchange fanout
        channel.queue_bind(exchange=EXCHANGE_NAME, queue=queue_name, routing_key="")
        print(f"Binding da fila '{queue_name}' criado com sucesso!")
    except Exception as e:
        # print(f"Erro ao criar o binding para a fila '{queue_name}': {e}")
        pass

# Função principal
def main():
    print("BINDING iniciado")
    conn = wait_for_rabbitmq()
    channel = conn.channel()
    create_task_queue(channel) 
    # Obter as filas
    queues = get_queues()
    if not queues:
        print("Nenhuma fila encontrada para fazer o binding.")

    for queue_name in queues:
        bind_queue_to_exchange(queue_name, channel)
    # Fechar a conexão
    conn.close()

if __name__ == "__main__":
    main()
