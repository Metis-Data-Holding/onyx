# BytePlus ECS Onyx Lite Deployment Design

## Issues to Address

- 在已有项目运行中的 BytePlus ECS 上，快速部署当前仓库版本的 Onyx。
- 避免与现有 `AIComicDrama` 的公网端口、宿主机 Nginx、证书和目录结构冲突。
- 采用适合 `4C8G` 机器的最小可运行方案，优先保证尽快可用。
- 为后续基于 GitHub 的手工触发式 CI/CD 留出清晰演进路径。

## Important Notes

- 目标机器规格为 `4C8G`，因此使用 Onyx Lite 模式，只保留 `api_server`、`web_server`、`relational_db`、`nginx`。
- Lite 模式下不启动 `Vespa`、`Redis`、`MinIO`、`OpenSearch`、模型服务和后台 worker。
- Lite 模式保留基础聊天与 Web 使用能力，但不包含完整连接器索引和 RAG 检索链路。
- 认证方式首发使用 `basic`，避免现在引入 OIDC/OAuth/SAML 配置。
- 大模型供应商不在首发部署脚本里预置，服务启动后通过 Onyx 管理界面配置。
- 目标域名为 `onyx.metisdata.ai`。
- 现有 ECS 宿主机 Nginx 已在 80/443 提供统一入口，因此 Onyx 不应直接占用公网 80/443。
- 现有证书为通配符证书，可覆盖 `onyx.metisdata.ai`。

## Recommended Approach

采用“宿主机统一网关 + Onyx 本地回源端口”的结构：

- Cloudflare 仅负责 DNS 与 TLS 入口。
- ECS 宿主机 Nginx 继续作为公网统一入口。
- Onyx 自带容器内 `nginx` 保持官方默认路由行为，但只监听宿主机本地端口。
- 宿主机 Nginx 新增 `onyx.metisdata.ai` 的站点配置，并反向代理到 Onyx 本地端口。

这是本次推荐方案，因为它：

- 不会影响已经在线的 `AIComicDrama`
- 不需要重写 Onyx 应用层路由
- 能最大限度复用官方 `docker compose` 结构
- 后续最容易接 GitHub Actions 远程部署

## Rejected Alternatives

### 直接暴露新的公网端口

优点是初次配置更少，但公网端口会分散，后续多项目管理和证书策略更混乱。

### 把 Onyx 挂到现有主域名路径前缀下

不适合首发。Onyx 前端和 API 路由都默认按根路径工作，路径前缀模式需要更多兼容性验证，且后续升级更脆弱。

## Deployment Topology

- Cloudflare
  - `onyx.metisdata.ai` 指向 BytePlus ECS
- ECS 宿主机网关 Nginx
  - 监听 `80/443`
  - 根据 `server_name onyx.metisdata.ai` 转发到 `127.0.0.1:39000`
- Onyx Docker Compose
  - `nginx` 仅监听宿主机本地端口 `127.0.0.1:39000`
  - `api_server`、`web_server`、`relational_db` 仅在 Docker 网络内通信

## Directory Layout

建议服务器目录为：

- `/opt/metis/onyx`
  - Onyx 仓库 checkout 根目录
- `/opt/metis/onyx/deployment/docker_compose`
  - 官方 compose 文件与环境文件
- `/opt/metis/onyx/deployment/byteplus-lite`
  - 本次新增的 BytePlus 部署专用覆盖文件、说明和脚本

数据库数据仍优先使用 Docker named volumes，由 Docker 管理持久化。

## Ports

- 宿主机公网
  - `80/443` 继续只由宿主机网关 Nginx 占用
- Onyx 本地回源端口
  - `127.0.0.1:39000 -> onyx nginx:80`

不额外开放数据库或其他内部服务端口。

## Compose Strategy

基础命令使用官方 compose 文件叠加 lite overlay：

```bash
docker compose -f docker-compose.yml -f docker-compose.onyx-lite.yml up -d --build
```

但需要增加一层 BytePlus 专用覆盖，使 Onyx `nginx` 只绑定到本地端口而不是默认占用 `80` 和 `3000`。

建议通过新增一个 BytePlus compose overlay 来重写 `nginx.ports`，避免直接修改官方主 compose 文件。

## Minimum Environment Configuration

首发建议最小环境变量：

```env
IMAGE_TAG=local-deploy
AUTH_TYPE=basic
WEB_DOMAIN=https://onyx.metisdata.ai

POSTGRES_USER=postgres
POSTGRES_PASSWORD=<strong-password>

USER_AUTH_SECRET=<openssl-rand-hex-32>

HOST_PORT=39000
HOST_PORT_80=39000

LOG_LEVEL=info
SESSION_EXPIRE_TIME_SECONDS=604800
```

部署专用 `.env` 中还应显式设置 Lite 所需配置，确保行为稳定：

```env
DISABLE_VECTOR_DB=true
FILE_STORE_BACKEND=postgres
CACHE_BACKEND=postgres
AUTH_BACKEND=postgres
```

## Authentication

首发使用 `basic` 认证：

- 不需要接入第三方身份系统
- 可最快验证服务是否完整可用
- 后续如需接 OIDC，再切换配置即可

## Model Provider Strategy

首发不把具体模型供应商写入部署脚本。原因：

- 先验证服务、域名、登录和基础页面可用性
- 避免把供应商密钥混入 GitHub Actions 或脚本
- 便于后续在管理界面灵活切换供应商

上线后通过 Onyx 管理后台完成模型供应商与 API Key 配置。

## ECS Gateway Nginx Changes

宿主机网关 Nginx 需要做两处变更：

1. 在 80 端口跳转块中加入 `onyx.metisdata.ai`
2. 新增 `server_name onyx.metisdata.ai` 的 443 站点，反代到 `127.0.0.1:39000`

反代配置应保留：

- `Host`
- `X-Real-IP`
- `X-Forwarded-For`
- `X-Forwarded-Proto`
- `X-Forwarded-Host`
- `X-Forwarded-Port`
- `Upgrade`
- `Connection`
- `proxy_buffering off`
- `proxy_read_timeout 86400s`

同时建议将 `client_max_body_size` 提高到 `512m`，避免较大文件上传过早被宿主机网关截断。

## Cloudflare Changes

- 新增 `onyx.metisdata.ai` DNS 记录
- 首发排障阶段可先使用 `DNS only`
- 稳定后可切回 Cloudflare 代理模式
- SSL 模式建议 `Full (strict)`

## First Release Procedure

1. 在 ECS 上准备 `/opt/metis/onyx`
2. 将当前仓库切到 `deploy` 分支
3. 准备部署专用 `.env`
4. 使用官方 compose + lite overlay + BytePlus overlay 启动服务
5. 验证本机 `127.0.0.1:39000` 已可访问
6. 修改宿主机网关 Nginx 并 reload
7. 配置 Cloudflare DNS
8. 访问 `https://onyx.metisdata.ai`
9. 登录 Onyx 并在后台配置模型供应商

## Operational Checks

首发至少验证：

- `docker compose ps`
- `curl http://127.0.0.1:39000`
- 宿主机 Nginx reload 成功
- `https://onyx.metisdata.ai` 可打开登录页
- `basic` 登录可用
- 后台模型配置保存成功

## CI/CD Evolution Path

分三阶段推进：

### Phase 1

手工部署，ECS 本机构建：

- 直接在 ECS 上拉取 `deploy` 分支
- 运行部署脚本
- `docker compose ... up -d --build`

### Phase 2

GitHub Actions 手工触发远程部署：

- `workflow_dispatch`
- SSH 到 ECS
- 更新仓库
- 执行部署脚本
- 输出 compose 状态和健康检查结果

### Phase 3

如果部署频率提高，再演进为镜像仓库式发布：

- Actions 构建镜像
- 推送镜像仓库
- ECS 只负责拉镜像和重启服务

## Why This Design

这套方案的核心目标不是一次性做完完整平台化，而是：

- 尽快在 BytePlus ECS 上稳定跑起来
- 不干扰已有项目
- 让后续 GitHub 自动部署有明确落点
- 在不提前过度设计的前提下保留演进空间
