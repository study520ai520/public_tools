#!/bin/bash

# === config.sh ===
SHM_SIZE="4g"
MILVUS_VERSION="v2.4.9"
MONGODB_VERSION="8.0.3"
MONGO_USER="admin"
MONGO_PASSWORD="admin123"
MONGO_OUT_PORT="27017"

declare -A projects
projects["vinlic/qwen-free-api"]=0
projects["vinlic/kimi-free-api"]=1
projects["vinlic/deepseek-free-api"]=1
projects["vinlic/glm-free-api"]=0
projects["vinlic/metaso-free-api"]=0
projects["vinlic/step-free-api"]=0
projects["langgenius/dify-web-1"]=1
projects["milvusdb/milvus"]=0
projects["zilliz/attu"]=0
projects["mongodb"]=1
projects["neo4j"]=1
projects["yidadaa/chatgpt-next-web"]=0

declare -A commands

commands["langgenius/dify-web-1"]="cd /project/pro/dify/docker && docker compose down && docker compose up -d"
commands["milvusdb/milvus"]="cd /project/pro/milvus && docker compose down && docker compose up -d"
commands["mongodb"]="docker run -d --name mongodb --shm-size=${SHM_SIZE} -p ${MONGO_OUT_PORT}:27017 -e TZ=Asia/Shanghai -v /project/pro/mongodb/data:/data/db -e MONGO_INITDB_ROOT_USERNAME=${MONGO_USER} -e MONGO_INITDB_ROOT_PASSWORD=${MONGO_PASSWORD} --restart always mongo:${MONGODB_VERSION}"
commands["neo4j"]="docker run -d --name neo4j --shm-size=${SHM_SIZE} -p 7474:7474 -p 7687:7687 -v /project/pro/neo4j/data:/data -v /project/pro/neo4j/logs:/logs -v /project/pro/neo4j/import:/var/lib/neo4j/import -v /project/pro/neo4j/plugins:/plugins --env NEO4J_AUTH=neo4j/password neo4j"
commands["yidadaa/chatgpt-next-web"]="docker run -d --shm-size=${SHM_SIZE} -p 10001:3000 -e OPENAI_API_KEY=your_api_key -e CODE=zxc123... yidadaa/chatgpt-next-web"
commands["vinlic/qwen-free-api"]="docker run -it -d --init --name qwen-free-api --shm-size=${SHM_SIZE} -p 10002:8000 -e TZ=Asia/Shanghai vinlic/qwen-free-api"
commands["vinlic/kimi-free-api"]="docker run -it -d --init --name kimi-free-api --shm-size=${SHM_SIZE} -p 10003:8000 -e TZ=Asia/Shanghai vinlic/kimi-free-api"
commands["vinlic/deepseek-free-api"]="docker run -it -d --init --name deepseek-free-api --shm-size=${SHM_SIZE} -p 10004:8000 -e TZ=Asia/Shanghai vinlic/deepseek-free-api"
commands["vinlic/glm-free-api"]="docker run -it -d --init --name glm-free-api --shm-size=${SHM_SIZE} -p 10005:8000 -e TZ=Asia/Shanghai vinlic/glm-free-api"
commands["vinlic/metaso-free-api"]="docker run -it -d --init --name metaso-free-api --shm-size=${SHM_SIZE} -p 10006:8000 -e TZ=Asia/Shanghai vinlic/metaso-free-api:latest"
commands["vinlic/step-free-api"]="docker run -it -d --init --name step-free-api --shm-size=${SHM_SIZE} -p 10007:8000 -e TZ=Asia/Shanghai vinlic/step-free-api:latest"
commands["zilliz/attu"]="docker run -d --name attu --shm-size=${SHM_SIZE} -p 10008:3000 -e MILVUS_URL=milvus-standalone:19530 zilliz/attu"

# === docker_utils.sh ===
check_and_create_dir() {
    print_line
    if [ ! -d "$1" ]; then
        echo "目录 $1 不存在，正在创建..."
        mkdir -p "$1"
        chmod 777 "$1"
    fi
}

# 创建虚拟网络
create_network() {
    print_line
    local NETWORK_NAME="my_virtual_network"

    # 检查虚拟网络是否存在
    if ! docker network ls | grep -q "$NETWORK_NAME"; then
        echo "网络 $NETWORK_NAME 不存在，正在创建..."
        docker network create "$NETWORK_NAME"
    else
        echo "网络 $NETWORK_NAME 已存在。"
    fi

    # 将所有运行中的容器加入到该网络
    for container in $(docker ps -q); do
        if ! docker network inspect "$NETWORK_NAME" | grep -q "$container"; then
            echo "将容器 $container 加入网络 $NETWORK_NAME..."
            docker network connect "$NETWORK_NAME" "$container"
        else
            echo "容器 $container 已经连接到网络 $NETWORK_NAME。"
        fi
    done

    # 获取虚拟网络的网关 IP 地址
    network_gateway_ip=$(docker network inspect "$NETWORK_NAME" --format='{{range .IPAM.Config}}{{.Gateway}}{{end}}')
    echo "网络 $NETWORK_NAME 的网关 IP 地址为: $network_gateway_ip"
}

check_container_status() {
    print_line
    local container_name=$1
    local max_retries=3
    local retry_count=0

    echo "检查容器 $container_name 状态..."
    while [ $retry_count -lt $max_retries ]; do
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo "容器 $container_name 运行正常"
            return 0
        fi
        echo "等待容器 $container_name 启动... (${retry_count}/${max_retries})"
        sleep 10
        ((retry_count++))
    done
    echo "容器 $container_name 启动失败"
    return 1
}

start_container() {
    print_line
    local project=$1
    local command=${commands[$project]}
    local container_name=$(echo $project | awk -F'/' '{print $NF}')  # 默认提取容器名称

    echo "启动项目 $project..."
    echo "执行的命令: $command"

    # 针对 Dify 项目的特殊处理
    if [[ "$project" == "langgenius/dify-web-1" ]]; then
        eval "$command"
        # 等待一段时间让容器启动
        sleep 5
        container_name=$(docker ps --format '{{.Names}}' | grep "docker-web" || true)
        if [ -z "$container_name" ]; then
            echo "注意：Dify 项目使用 docker compose 启动，不需要检查单个容器名称"
            return 0
        fi
    else
        # 检查是否已经存在同名容器
        if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo "容器 $container_name 已存在，停止并删除..."
            docker stop "$container_name"
            docker rm "$container_name"
        fi

        eval "$command"
        check_container_status "$container_name"
    fi
}

# === project_setup.sh ===
start_dify() {
    print_line
    local DIFY_DIR="/project/pro/dify"

    if [ ! -d "$DIFY_DIR" ]; then
        echo "目录 $DIFY_DIR 不存在，正在克隆项目..."
        git clone https://github.com/langgenius/dify.git "$DIFY_DIR"
        cd "$DIFY_DIR/docker" && cp .env.example .env
    else
        echo "目录 $DIFY_DIR 已存在，跳过克隆步骤。"
    fi

    echo "启动 Dify 容器..."
    start_container "langgenius/dify-web-1"
}

start_milvus() {
    print_line
    local MILVUS_COMPOSE_URL="https://github.com/milvus-io/milvus/releases/download/${MILVUS_VERSION}/milvus-standalone-docker-compose.yml"
    local MILVUS_COMPOSE_PATH="/project/pro/milvus/docker-compose.yml"
    local MILVUS_DATA_DIR="/project/pro/milvus/data"

    check_and_create_dir "$MILVUS_DATA_DIR"

    if [ ! -f "$MILVUS_COMPOSE_PATH" ]; then
        echo "下载 Milvus 的 docker-compose.yml 文件..."
        wget "$MILVUS_COMPOSE_URL" -O "$MILVUS_COMPOSE_PATH"

        if [ $? -eq 0 ]; then
            echo "Milvus 的 docker-compose.yml 文件下载成功。"
            sed -i "s|volumes:|volumes:\n      - ${MILVUS_DATA_DIR}:/var/lib/milvus|" "$MILVUS_COMPOSE_PATH"
            sed -i '/^version:/d' "$MILVUS_COMPOSE_PATH"
        else
            echo "Milvus 的 docker-compose.yml 文件下载失败，请检查网络连接或链接的有效性。"
            return 1
        fi
    else
        echo "Milvus 的 docker-compose.yml 文件已存在，跳过下载步骤。"
        sed -i '/^version:/d' "$MILVUS_COMPOSE_PATH"
    fi

    echo "启动 Milvus 容器..."
    start_container "milvusdb/milvus"
}

start_mongodb() {
    print_line
    local MONGODB_DATA_DIR="/project/pro/mongodb/data"
    check_and_create_dir "$MONGODB_DATA_DIR"
    echo "启动 MongoDB 容器..."
    start_container "mongodb"
}

start_neo4j() {
    print_line
    local NEO4J_DATA_DIR="/project/pro/neo4j/data"
    local NEO4J_LOGS_DIR="/project/pro/neo4j/logs"
    local NEO4J_IMPORT_DIR="/project/pro/neo4j/import"
    local NEO4J_PLUGINS_DIR="/project/pro/neo4j/plugins"

    check_and_create_dir "$NEO4J_DATA_DIR"
    check_and_create_dir "$NEO4J_LOGS_DIR"
    check_and_create_dir "$NEO4J_IMPORT_DIR"
    check_and_create_dir "$NEO4J_PLUGINS_DIR"

    echo "启动 Neo4j 容器..."
    start_container "neo4j"
}

print_line() {
    echo "================================================="
}

# === main.sh ===
main() {
    print_line
    sudo service docker restart
    echo "等待 Docker 服务启动...10秒"
    sleep 10  
    echo "等待完成，继续执行脚本..."
    print_line
    check_and_create_dir "/project/pro"
    check_and_create_dir "/project/pro/logs"
    print_line
    # 启动各个项目
    for project in "${!projects[@]}"; do
        if [ "${projects[$project]}" -eq 1 ]; then
            case $project in
                "langgenius/dify-web-1") start_dify ;;
                "milvusdb/milvus") start_milvus ;;
                "mongodb") start_mongodb ;;
                "neo4j") start_neo4j ;;
                *) start_container "$project" ;;
            esac
        fi
    done
    print_line
    # 创建虚拟网络
    echo "等待 虚拟网络...10秒"
    sleep 10  
    create_network
    echo "等待完成，继续执行脚本..."
    print_line

    echo "部署完成，请检查日志文件：/project/pro/logs/app_init.log"
}

# 执行主逻辑
main