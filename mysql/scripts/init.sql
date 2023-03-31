-- Removendo acesso remoto do usuário ROOT
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;

-- Criando usuário `netdata` utilizado apenas na reda interna do servidor, rede DOCKER!
-- 172.16.0.0/255.240.0.0 === 172.16.0.0/12
CREATE USER 'netdata'@'172.16.0.0/255.240.0.0' IDENTIFIED BY 'Pa55w0rd';
GRANT USAGE, REPLICATION CLIENT, PROCESS ON *.* TO 'netdata'@'172.16.0.0/255.240.0.0';
FLUSH PRIVILEGES;

-- Adicionando autenticação X509 ao usuário `admin` (usuários remotos - conexão fora do servidor)
ALTER USER 'admin'@'%' REQUIRE X509;
FLUSH PRIVILEGES;

-- Criando Usuário `admin` na rede interna DOCKER
CREATE USER 'admin'@'172.16.0.0/255.240.0.0' IDENTIFIED BY 'Pa55w0rd';
GRANT ALL ON *.* TO 'admin'@'172.16.0.0/255.240.0.0';
FLUSH PRIVILEGES;

-- Criando usuário `admin` em `localhost`
CREATE USER 'admin'@'localhost' IDENTIFIED BY 'Pa55w0rd';
GRANT ALL ON *.* TO 'admin'@'localhost';
FLUSH PRIVILEGES;

SELECT user, host FROM mysql.user;
