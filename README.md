# Moon

LunaTV（MoonTV 系）自部署后端的 Android 客户端。Flutter 编写。

## 功能

- 登录：内置服务器地址，账号密码登录（自动识别 localstorage / 数据库存储模式），支持内置账号免登录
- 首页：继续观看 / 每日放送（Bangumi）/ 热门电影·剧集·综艺
- 分类浏览：电影 / 剧集 / 动漫 / 综艺，豆瓣分类 + 多层级筛选（类型/地区/年代/平台/排序），无限滚动
- 搜索：SSE 流式搜索、按源 / 聚合视图、搜索建议、搜索历史
- 播放：media_kit 播放器、选集、换源、倍速、进度云端同步、跳过片头片尾、收藏
- 直播：多直播源、分组频道、EPG 节目单
- 设置：修改密码、清空播放记录/搜索历史

## 内置配置（--dart-define）

| 变量 | 说明 | 默认 |
|---|---|---|
| `MOON_SERVER` | 服务器地址 | `https://tv.mrchevy.cn` |
| `MOON_USERNAME` | 内置账号（可选） | 空 → 显示登录页 |
| `MOON_PASSWORD` | 内置密码（可选） | 空 → 显示登录页 |

本地运行：

```bash
flutter run --dart-define=MOON_USERNAME=admin --dart-define=MOON_PASSWORD=xxx
```

## CI 构建

push 到 `main` → 自动构建 APK（Actions 产物下载）；
打 `v*` tag → 自动发布到 Release。

凭据注入（仓库 Settings → Secrets and variables → Actions）：

- Secrets：`MOON_USERNAME`、`MOON_PASSWORD`（要免登录内置账号才配）
- Variables：`MOON_SERVER`（可留空，默认 tv.mrchevy.cn）

> 注意：不要直接把密码写进源码——本仓库是公开的。凭据只在构建时注入。

## 多用户隔离

LunaTV 服务端自带多用户：用数据库存储（`NEXT_PUBLIC_STORAGE_TYPE=redis`/`kvrocks`/`upstash`）
部署后，后台 `/admin` 的"用户管理"可创建账号，每个人的播放记录、收藏、
搜索历史、跳过配置自动按用户隔离。

`localstorage` 模式只有一个全局密码，数据全站共享，无法隔离。

## 后端部署

```yaml
services:
  lunatv:
    image: ghcr.io/moontechlab/lunatv:latest
    ports:
      - "3000:3000"
    environment:
      - PASSWORD=your-strong-password      # localstorage 模式的管理密码
      - NEXT_PUBLIC_STORAGE_TYPE=redis     # 多用户隔离必须用数据库模式
      - USERNAME=admin                     # DB 模式的管理员账号
      - REDIS_URL=redis://redis:6379
      - NEXT_PUBLIC_SITE_NAME=MoonTV
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    restart: unless-stopped
```

## 致谢

接口协议与交互参考 [LunaTV](https://github.com/MoonTechLab/LunaTV) /
[Selene](https://github.com/MoonTechLab/Selene)（MoonTechLab），本仓库代码为独立实现。
