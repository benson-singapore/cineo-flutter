# Cineo Website

Cineo 官方静态官网，使用 React、Vite、Tailwind CSS 和 shadcn/ui 风格组件构建。它与根目录的 Flutter Web 工程相互独立，真实 App 截图位于 `public/screenshots/`。

## Development

```bash
npm install
npm run dev
```

## Production build

```bash
npm run build
npm run preview
```

构建产物输出到 `dist/`，可以部署到 GitHub Pages、Vercel、Cloudflare Pages 或任意静态文件服务器。

## Links to update

下载地址和项目地址集中定义在 `src/main.jsx` 顶部：

- `GITHUB_URL`
- `RELEASES_URL`

发布真实 APK 前，请将 GitHub Releases 中的构建产物上传到对应版本页面。
