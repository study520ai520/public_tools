#!/bin/bash
sudo service docker start

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
projects["langgenius/dify-web"]=1
projects["milvusdb/milvus"]=0
projects["zilliz/attu"]=0
projects["mongo"]=1
projects["neo4j"]=1
projects["yidadaa/chatgpt-next-web"]=0

declare -A commands

commands["langgenius/dify-web"]="cd /project/pro/dify/docker && docker compose down && docker compose up -d"
commands["milvusdb/milvus"]="cd /project/pro/milvus && docker compose down && docker compose up -d"

commands["mongo"]="docker run -d --name mongodb --shm-size=${SHM_SIZE} -p ${MONGO_OUT_PORT}:27017 -e TZ=Asia/Shanghai -v /project/pro/mongodb/data:/data/db -e MONGO_INITDB_ROOT_USERNAME=${MONGO_USER} -e MONGO_INITDB_ROOT_PASSWORD=${MONGO_PASSWORD} --restart always mongo:${MONGODB_VERSION}"
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
    if [ ! -d "$1" ]; then
        echo "目录 $1 不存在，正在创建..."
        mkdir -p "$1"
        chmod 777 "$1"
    fi
}

check_container_status() {
    local container_name=$1
    local max_retries=3
    local retry_count=0

    echo "检查容器 $container_name 状态..."
    while [ $retry_count -lt $max_retries ]; do
        if docker ps | grep -q "$container_name"; then
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
    local project=$1
    local command=${commands[$project]}

    echo "启动项目 $project..."
    eval "$command"
    check_container_status "$(echo $project | awk -F'/' '{print $NF}')"
}

# === project_setup.sh ===
start_dify() {
    local DIFY_DIR="/project/pro/dify"

    if [ ! -d "$DIFY_DIR" ]; then
        echo "目录 $DIFY_DIR 不存在，正在克隆项目..."
        git clone https://github.com/langgenius/dify.git "$DIFY_DIR"
        cd "$DIFY_DIR/docker" && cp .env.example .env
    else
        echo "目录 $DIFY_DIR 已存在，跳过克隆步骤。"
    fi

    echo "启动 Dify 容器..."
    start_container "langgenius/dify-web"
}

start_milvus() {
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
    local MONGODB_DATA_DIR="/project/pro/mongodb/data"
    check_and_create_dir "$MONGODB_DATA_DIR"
    echo "启动 MongoDB 容器..."
    start_container "mongo"
}

start_neo4j() {
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

# === main.sh ===
main() {
    check_and_create_dir "/project/pro"
    check_and_create_dir "/project/pro/logs"

    # 启动各个项目
    for project in "${!projects[@]}"; do
        if [ "${projects[$project]}" -eq 1 ]; then
            case $project in
                "langgenius/dify-web") start_dify ;;
                "milvusdb/milvus") start_milvus ;;
                "mongo") start_mongodb ;;
                "neo4j") start_neo4j ;;
                *) start_container "$project" ;;
            esac
        fi
    done

    echo "部署完成，请检查日志文件：/project/pro/logs/app_init.log"
}

# 执行主逻辑
main