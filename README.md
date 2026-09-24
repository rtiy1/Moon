# Moon

LunaTV（MoonTV 系）自部署后端的 Android 客户端。Flutter 编写。

## 功能

- 登录：服务器地址 + 用户名/密码（自动识别 localstorage / 数据库存储模式）
- 首页：继续观看 / 每日放送（Bangumi）/ 热门电影·剧集·综艺
- 分类浏览：电影 / 剧集 / 动漫 / 综艺，支持豆瓣分类 + 多层级筛选（类型/地区/年代/平台/排序），无限滚动
- 搜索：SSE 流式搜索、按源分组 / 聚合视图、搜索建议、搜索历史（云端同步）
- 播放：media_kit 播放器、选集、换源、倍速、进度云端同步、跳过片头片尾、收藏
- 直播：多直播源、分组频道、EPG 节目单
- 设置：修改密码、清空播放记录/搜索历史

## 构建

```
flutter pub get
flutter build apk --release --split-per-abi
```

或推送 `v*` 标签 / 手动触发 GitHub Actions，APK 自动上传到 Release。

## 后端

配合自部署的 LunaTV 使用（v100+，Next.js）。Docker 部署示例：

```yaml
services:
  lunatv:
    image: ghcr.io/moontechlab/lunatv:latest
    ports:
      - "3000:3000"
    environment:
      - PASSWORD=your-strong-password
      - NEXT_PUBLIC_STORAGE_TYPE=localstorage   # 或 redis/kvrocks/upstash（多用户同步）
      # - USERNAME=admin                        # DB 模式必填
      # - REDIS_URL=redis://redis:6379
      - NEXT_PUBLIC_SITE_NAME=MoonTV
    restart: unless-stopped
```

登录时填服务器地址（如 `https://tv.example.com`）+ 密码（DB 模式加用户名）。
