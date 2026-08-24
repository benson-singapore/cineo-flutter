import { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import {
  ArrowDownRight,
  ArrowRight,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  CirclePlay,
  Database,
  Download,
  ExternalLink,
  Github,
  Layers3,
  LockKeyhole,
  Menu,
  Search,
  Server,
  Settings2,
  Sparkles,
  Tv,
  X,
  Zap,
} from 'lucide-react'
import { Badge, Button, Card, Separator } from './components/ui'
import './index.css'

const GITHUB_URL = 'https://github.com/benson-singapore/cineo-flutter'
const RELEASES_URL = `${GITHUB_URL}/releases/latest`
const asset = (name) => `./screenshots/${name}.jpg`

const screenshots = [
  ['首页 · 内容分区', '首页媒体分区界面'], ['关于 · Cineo', 'Cineo 关于页面'], ['发现 · 分类浏览', '分类浏览界面'], ['详情 · 内容信息', '影视详情界面'],
  ['播放 · 沉浸观看', '视频播放界面'], ['来源 · 多源管理', '视频来源管理界面'], ['搜索 · 快速找到', '搜索界面'],
  ['首页 · 推荐内容', '首页推荐内容界面'], ['发现 · 热门分类', '热门分类界面'], ['详情 · 剧集信息', '剧集信息界面'],
  ['播放 · 播放控制', '播放控制界面'], ['来源 · 站点选择', '站点选择界面'], ['搜索 · 结果列表', '搜索结果列表界面'],
  ['设置 · TMDB 配置', 'TMDB 配置界面'], ['设置 · 应用偏好', '应用偏好设置界面'],
].map(([label, alt], index) => ({ name: `IMG_${[3493, 3507, 3494, 3495, 3496, 3497, 3498, 3499, 3500, 3501, 3502, 3503, 3504, 3505, 3506][index]}`, label, alt: `Cineo ${alt}` }))

const features = [
  { icon: Layers3, number: '01', title: '多源聚合', text: '把分散的视频来源收进一个清晰的入口。支持 MacCMS 兼容 API、JSON 导入、启用、收藏与连通性测试。', image: 'IMG_3498' },
  { icon: Search, number: '02', title: '发现与搜索', text: '首页推荐、分类浏览和搜索串成完整的发现路径，找到想看的内容，不需要在多个站点之间来回切换。', image: 'IMG_3500' },
  { icon: CirclePlay, number: '03', title: '从详情到播放', text: '影视详情、季与剧集信息、HLS / MP4 播放和 Android 画中画，保持从选择到观看的连续体验。', image: 'IMG_3496' },
]

function App() {
  const [menuOpen, setMenuOpen] = useState(false)
  const [activeShot, setActiveShot] = useState(null)
  const [activePreview, setActivePreview] = useState(0)
  const previewRef = useRef(null)
  const previewDragRef = useRef({ active: false, startX: 0, startScroll: 0 })

  useEffect(() => {
    document.body.style.overflow = activeShot || menuOpen ? 'hidden' : ''
    return () => { document.body.style.overflow = '' }
  }, [activeShot, menuOpen])

  const closeMenu = () => setMenuOpen(false)

  const scrollToPreview = (index) => {
    const nextIndex = (index + screenshots.length) % screenshots.length
    const track = previewRef.current
    const slide = track?.querySelector(`[data-preview-index="${nextIndex}"]`)
    if (!track || !slide) return
    track.scrollTo({ left: slide.offsetLeft - track.offsetLeft, behavior: 'smooth' })
    setActivePreview(nextIndex)
  }

  const handlePreviewScroll = () => {
    const track = previewRef.current
    if (!track) return
    const slides = [...track.querySelectorAll('[data-preview-index]')]
    const center = track.scrollLeft + track.clientWidth / 2
    const closest = slides.reduce((current, slide, index) => {
      const distance = Math.abs(slide.offsetLeft + slide.offsetWidth / 2 - center)
      return distance < current.distance ? { index, distance } : current
    }, { index: activePreview, distance: Infinity })
    if (closest.index !== activePreview) setActivePreview(closest.index)
  }

  const handlePreviewPointerDown = (event) => {
    if (event.pointerType === 'mouse' && event.button !== 0) return
    const track = previewRef.current
    if (!track) return
    previewDragRef.current = { active: true, startX: event.clientX, startScroll: track.scrollLeft }
    track.setPointerCapture?.(event.pointerId)
    track.classList.add('is-dragging')
  }

  const handlePreviewPointerMove = (event) => {
    const track = previewRef.current
    const drag = previewDragRef.current
    if (!track || !drag.active) return
    track.scrollLeft = drag.startScroll - (event.clientX - drag.startX)
  }

  const handlePreviewPointerUp = (event) => {
    const track = previewRef.current
    if (!track) return
    previewDragRef.current.active = false
    track.releasePointerCapture?.(event.pointerId)
    track.classList.remove('is-dragging')
  }

  const PhoneMockup = ({ image, alt, className = '' }) => (
    <div className={`phone-shell ${className}`}>
      <span className="phone-speaker" aria-hidden="true" />
      <span className="phone-camera" aria-hidden="true" />
      <span className="phone-side-button phone-side-button-top" aria-hidden="true" />
      <span className="phone-side-button phone-side-button-bottom" aria-hidden="true" />
      <img className="phone-image" src={image} alt={alt} />
    </div>
  )

  return (
    <div className="min-h-screen overflow-hidden">
      <header className="fixed inset-x-0 top-0 z-40 border-b border-white/[.06] bg-ink/80 backdrop-blur-xl">
        <div className="container-wide flex h-[4.5rem] items-center justify-between">
          <a href="#top" className="flex items-center gap-3" onClick={closeMenu} aria-label="Cineo 首页">
            <img src="./branding/cineo_mark.png" alt="Cineo" className="h-8 w-8" />
            <span className="font-display text-lg font-bold tracking-[.16em]">CINEO</span>
          </a>
          <nav className="hidden items-center gap-8 text-sm font-semibold text-muted md:flex" aria-label="主导航">
            <a className="transition-colors hover:text-copy" href="#features">功能</a>
            <a className="transition-colors hover:text-copy" href="#preview">预览</a>
            <a className="transition-colors hover:text-copy" href="#tmdb">TMDB</a>
            <a className="transition-colors hover:text-copy" href="#install">安装</a>
            <a className="transition-colors hover:text-copy" href={GITHUB_URL} target="_blank" rel="noreferrer">GitHub</a>
          </nav>
          <div className="hidden md:block">
            <Button asChild size="sm"><a href={RELEASES_URL} target="_blank" rel="noreferrer">获取 Cineo <ArrowRight size={15} className="ml-2" /></a></Button>
          </div>
          <Button variant="ghost" size="icon" className="md:hidden" onClick={() => setMenuOpen(!menuOpen)} aria-label={menuOpen ? '关闭菜单' : '打开菜单'}>
            {menuOpen ? <X size={21} /> : <Menu size={21} />}
          </Button>
        </div>
        {menuOpen && <div className="border-t border-white/[.06] bg-ink px-5 py-5 md:hidden"><nav className="container-wide flex flex-col gap-5 text-sm font-semibold text-muted" aria-label="移动端主导航">
          {['功能', '预览', 'tmdb', '安装'].map((item) => <a key={item} href={`#${item}`} onClick={closeMenu} className="hover:text-copy">{item === 'tmdb' ? 'TMDB' : item}</a>)}
          <a href={GITHUB_URL} target="_blank" rel="noreferrer" className="hover:text-copy">GitHub <ExternalLink size={13} className="ml-1 inline" /></a>
          <Button asChild><a href={RELEASES_URL} target="_blank" rel="noreferrer">获取 Cineo <ArrowRight size={15} className="ml-2" /></a></Button>
        </nav></div>}
      </header>

      <main id="top">
        <section className="relative isolate flex min-h-[760px] items-center pt-28 pb-10 lg:min-h-[850px] lg:pt-20 lg:pb-16">
          <div className="absolute left-1/2 top-[-20rem] -z-10 h-[48rem] w-[48rem] -translate-x-1/2 rounded-full bg-cineo/10 blur-[140px]" />
          <div className="absolute inset-0 -z-10 bg-grain opacity-[.035] mix-blend-soft-light" />
          <div className="container-wide grid items-center gap-16 lg:grid-cols-[minmax(0,1.15fr)_minmax(450px,.85fr)] lg:gap-8">
            <div className="animate-fade-up">
              <Badge><Sparkles size={12} className="mr-2" /> local-first media</Badge>
              <h1 className="keep-cjk mt-7 max-w-none font-display text-[3.6rem] font-semibold leading-[.93] tracking-[-.065em] text-copy sm:text-7xl lg:text-6xl xl:text-[6.5rem]"><span className="block whitespace-normal lg:whitespace-nowrap">把你的片库，</span><span className="block whitespace-normal lg:whitespace-nowrap text-cineo">放回你手中。</span></h1>
              <p className="keep-cjk mt-8 max-w-2xl text-lg leading-8 text-muted sm:text-xl">Cineo 是一个简洁、专注、可扩展的个人影视发现与播放客户端。多源聚合，本地优先，找到内容后，专心看电影。</p>
              <div className="mt-9 flex flex-wrap items-center gap-3">
                <Button asChild size="lg" className="group"><a href={RELEASES_URL} target="_blank" rel="noreferrer"><Download size={17} className="mr-2" />下载 Android <ArrowDownRight size={17} className="button-arrow ml-2" /></a></Button>
                <Button asChild variant="outline" size="lg"><a href="#install">查看 iOS 安装 <ArrowRight size={17} className="ml-2" /></a></Button>
              </div>
              <div className="mt-10 flex flex-wrap gap-x-7 gap-y-3 text-xs font-medium text-muted">
                <span className="flex items-center gap-2"><Check size={14} className="text-cineo" />Flutter 跨平台</span>
                <span className="flex items-center gap-2"><Check size={14} className="text-cineo" />本地数据优先</span>
                <span className="flex items-center gap-2"><Check size={14} className="text-cineo" />开源项目</span>
              </div>
            </div>
            <div className="relative mx-auto h-[560px] w-full max-w-[540px] lg:h-[650px] lg:max-w-none">
              <div className="absolute right-[3%] top-[7%] h-[33rem] w-[15.25rem] rotate-[8deg] opacity-70 sm:right-[8%] sm:h-[36rem] sm:w-[16.6rem] lg:right-[11%]"><PhoneMockup image={asset('IMG_3495')} alt="Cineo 影视详情页面" /></div>
              <div className="float-slow absolute left-[4%] top-[15%] h-[37rem] w-[17.1rem] rotate-[-8deg] sm:left-[12%] sm:h-[40rem] sm:w-[18.45rem] lg:left-[15%]"><PhoneMockup image={asset('IMG_3493')} alt="Cineo 首页界面" /></div>
              <div className="float-reverse absolute bottom-[3%] right-[3%] z-10 flex items-center gap-3 rounded-2xl border border-white/10 bg-panel/90 px-4 py-3 shadow-2xl backdrop-blur-md sm:right-[7%]"><div className="flex h-9 w-9 items-center justify-center rounded-xl bg-cineo text-[#251300]"><Tv size={18} /></div><div><p className="text-xs font-bold text-copy">Cineo</p><p className="mt-0.5 text-[10px] text-muted">你的本地媒体中心</p></div></div>
              <div className="absolute left-[2%] top-[4%] z-10 hidden rounded-full border border-cineo/30 bg-cineo/10 px-3 py-2 font-mono text-[10px] uppercase tracking-[.18em] text-cineo-light sm:block">Watch what matters</div>
            </div>
          </div>
        </section>

        <div className="relative z-20 mt-8 border-y border-white/[.06] bg-panel/60 py-5"><div className="flex w-max animate-marquee gap-10 font-mono text-[11px] uppercase tracking-[.22em] text-muted"><span>DISCOVER WITHOUT DISTRACTION</span><span className="text-cineo">✦</span><span>LOCAL-FIRST BY DESIGN</span><span className="text-cineo">✦</span><span>YOUR SOURCES. YOUR LIBRARY.</span><span className="text-cineo">✦</span><span>DISCOVER WITHOUT DISTRACTION</span><span className="text-cineo">✦</span><span>LOCAL-FIRST BY DESIGN</span><span className="text-cineo">✦</span><span>YOUR SOURCES. YOUR LIBRARY.</span></div></div>

        <section id="features" className="container-wide scroll-mt-28 py-28 sm:py-36">
          <div className="grid gap-10 lg:grid-cols-[minmax(0,.95fr)_minmax(360px,1.05fr)] lg:gap-24"><div><p className="eyebrow">The Cineo approach / 01</p><h2 className="section-title mt-5 max-w-none lg:whitespace-nowrap lg:text-[3.8rem]">为观看而设计，<br /><span className="text-muted">不为打扰而设计。</span></h2></div><div className="max-w-2xl lg:pt-10"><p className="section-copy text-pretty">从多个视频源，到一部电影的播放按钮。Cineo 把复杂的配置留在幕后，把清晰、连续的观影体验留在你面前。</p><a href={GITHUB_URL} target="_blank" rel="noreferrer" className="group mt-7 inline-flex items-center text-sm font-bold text-cineo-light">在 GitHub 查看项目 <ArrowRight size={16} className="button-arrow ml-2" /></a></div></div>
          <div className="feature-grid mt-16 grid gap-5 md:grid-cols-2 lg:auto-rows-fr lg:grid-cols-3 lg:items-stretch">{features.map((feature) => <Card key={feature.number} className="group flex h-full flex-col overflow-hidden"><div className="relative aspect-[4/5] shrink-0 overflow-hidden bg-black"><img src={asset(feature.image)} alt={feature.text} className={`h-full w-full object-cover ${feature.number === '03' ? 'object-center' : 'object-top'} opacity-75 transition duration-700 group-hover:scale-[1.02] group-hover:opacity-100`} /><div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-panel via-transparent to-transparent" /><span className="absolute left-5 top-5 font-mono text-xs text-cineo">{feature.number}</span><span className="absolute right-5 top-5 flex h-9 w-9 items-center justify-center rounded-full border border-white/15 bg-ink/60 text-cineo-light backdrop-blur"><feature.icon size={16} /></span></div><div className="p-6"><h3 className="font-display text-2xl font-semibold tracking-tight">{feature.title}</h3><p className="mt-3 text-sm leading-6 text-muted">{feature.text}</p></div></Card>)}</div>
        </section>

        <section id="preview" className="scroll-mt-20 border-y border-white/[.06] bg-panel/45 py-28 sm:py-36"><div className="container-wide"><div className="flex flex-col justify-between gap-7 sm:flex-row sm:items-end"><div><p className="eyebrow">Real screens / 02</p><h2 className="section-title mt-5">真实界面，<br /><span className="text-cineo">一眼看见质感。</span></h2></div><p className="max-w-sm text-sm leading-6 text-muted sm:text-right">所有预览均来自 Cineo 当前应用界面。左右滑动或拖动浏览，点击截图查看完整细节。</p></div><div className="relative mt-14"><div ref={previewRef} onScroll={handlePreviewScroll} onPointerDown={handlePreviewPointerDown} onPointerMove={handlePreviewPointerMove} onPointerUp={handlePreviewPointerUp} onPointerCancel={handlePreviewPointerUp} className="preview-track flex snap-x snap-mandatory gap-4 overflow-x-auto overscroll-x-contain pb-5" aria-label="Cineo 应用界面轮播">{screenshots.map((shot, index) => <button key={shot.name} data-preview-index={index} className="preview-slide group w-[min(72vw,16rem)] shrink-0 snap-center text-left sm:w-[min(38vw,18rem)] lg:w-[19rem]" onClick={() => setActiveShot(shot)} aria-label={`查看${shot.label}`}><div className="image-frame relative aspect-[1290/2796] transition duration-300 group-hover:-translate-y-1 group-hover:border-cineo/50 group-hover:shadow-glow-sm"><img src={asset(shot.name)} alt={shot.alt} className="h-full w-full object-cover transition duration-500 group-hover:scale-[1.02]" /><div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-ink/95 to-transparent p-4 pt-14"><p className="text-xs font-semibold text-copy">{shot.label}</p><p className="mt-1 font-mono text-[9px] uppercase tracking-widest text-cineo">Open preview ↗</p></div></div></button>)}</div><div className="flex items-center justify-between gap-5 border-t border-white/[.08] pt-5"><div className="flex items-center gap-2" aria-label="预览页码">{screenshots.map((shot, index) => <button key={shot.name} onClick={() => scrollToPreview(index)} className={`h-2 rounded-full transition-all ${index === activePreview ? 'w-8 bg-cineo' : 'w-2 bg-white/20 hover:bg-white/50'}`} aria-label={`显示第 ${index + 1} 张预览`} aria-current={index === activePreview ? 'true' : undefined} />)}</div><div className="flex items-center gap-2"><Button variant="outline" size="icon" onClick={() => scrollToPreview(activePreview - 1)} aria-label="上一张预览"><ChevronLeft size={18} /></Button><Button variant="outline" size="icon" onClick={() => scrollToPreview(activePreview + 1)} aria-label="下一张预览"><ChevronRight size={18} /></Button></div></div></div></div></section>

        <section id="tmdb" className="container-wide scroll-mt-28 py-28 sm:py-36"><div className="relative overflow-hidden rounded-[2rem] border border-cineo/20 bg-cineo-deep/45 p-7 sm:p-12 lg:p-16"><div className="absolute -right-20 -top-28 h-80 w-80 rounded-full bg-cineo/20 blur-[100px]" /><div className="relative grid items-center gap-14 lg:grid-cols-[1fr_.8fr]"><div><p className="eyebrow">Metadata enrichment / 03</p><h2 className="mt-5 max-w-xl font-display text-4xl font-semibold leading-tight tracking-[-.04em] sm:text-6xl">让每一部电影，<br /><span className="text-cineo-light">看起来都值得。</span></h2><p className="mt-6 max-w-lg text-base leading-7 text-muted">接入 TMDB 数据增强，为你的媒体补充海报、背景图、演员、季和单集简介。基础播放不依赖 TMDB，但它会显著提升整个片库的展示质量。</p><div className="mt-8 flex flex-wrap gap-2"><Badge>海报与背景图</Badge><Badge>演员与季</Badge><Badge>本地磁盘缓存</Badge></div><a href="#install" className="group mt-9 inline-flex items-center text-sm font-bold text-cineo-light">查看配置方法 <ArrowRight size={16} className="button-arrow ml-2" /></a></div><div className="relative mx-auto w-full max-w-[330px]"><PhoneMockup image={asset('IMG_3495')} alt="Cineo 详情页展示 TMDB 丰富元数据" className="rotate-[4deg]" /><div className="absolute -bottom-5 -left-8 rounded-2xl border border-white/10 bg-panel px-4 py-3 shadow-xl"><div className="flex items-center gap-2"><Sparkles size={14} className="text-cineo" /><span className="font-mono text-[10px] uppercase tracking-wider text-muted">Enriched locally</span></div></div></div></div></div></section>

        <section id="install" className="scroll-mt-20 border-t border-white/[.06] bg-panel/45 py-28 sm:py-36"><div className="container-wide"><div className="max-w-4xl"><p className="eyebrow">Start your library / 04</p><h2 className="section-title mt-5">下载，配置，<br /><span className="text-cineo">开始观看。</span></h2><p className="section-copy mt-7 max-w-3xl">Cineo 提供 Android APK 与未签名的 iOS IPA 安装文件。Android 可以直接安装；iOS 需要使用你自己的证书完成签名后再安装。首次启动内置演示媒体库，也可以随后添加自己的合法视频源。</p></div><div className="mt-14 grid gap-5 lg:grid-cols-2"><Card className="relative overflow-hidden p-7 sm:p-9"><div className="absolute right-0 top-0 h-48 w-48 rounded-full bg-cineo/10 blur-3xl" /><div className="relative"><div className="flex items-start justify-between"><div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-cineo text-[#251300]"><Download size={22} /></div><Badge>Android</Badge></div><h3 className="keep-cjk mt-8 font-display text-3xl font-semibold">直接安装 APK</h3><p className="keep-cjk mt-3 max-w-md text-sm leading-6 text-muted">前往 GitHub Releases 下载最新 Android APK。若系统提示来源限制，请在确认文件来源后允许安装未知应用。</p><Button asChild className="mt-7"><a href={RELEASES_URL} target="_blank" rel="noreferrer">前往 Releases <ExternalLink size={15} className="ml-2" /></a></Button></div></Card><Card className="p-7 sm:p-9"><div className="flex items-start justify-between"><div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-panel2 text-cineo"><Zap size={22} /></div><Badge className="border-white/15 bg-white/5 text-muted">iOS / unsigned</Badge></div><h3 className="keep-cjk mt-8 font-display text-3xl font-semibold">未签名 IPA 安装</h3><p className="keep-cjk mt-3 text-sm leading-6 text-muted">本项目仅提供未签名的 IPA 安装文件，不提供已签名版本。下载后需要使用你自己的 Apple Developer 账号、证书或签名工具完成签名，然后安装到 iPhone 或 iPad。</p><ol className="mt-5 space-y-3 text-sm leading-6 text-muted"><li className="flex gap-3"><span className="font-mono text-cineo">01</span><span>从 GitHub Releases 下载未签名 IPA。</span></li><li className="flex gap-3"><span className="font-mono text-cineo">02</span><span>使用自己的证书和签名工具完成签名。</span></li><li className="flex gap-3"><span className="font-mono text-cineo">03</span><span>将签名后的 IPA 安装到自己的 iOS 设备。</span></li></ol><Button asChild variant="outline" className="mt-7"><a href={`${GITHUB_URL}#getting-started`} target="_blank" rel="noreferrer">查看源码说明 <Github size={15} className="ml-2" /></a></Button></Card></div><Card className="mt-5 border-cineo/20 bg-cineo/5 p-7 sm:p-9"><div className="grid gap-8 lg:grid-cols-[.75fr_1fr]"><div><div className="flex items-center gap-3"><Settings2 size={18} className="text-cineo" /><h3 className="font-display text-2xl font-semibold">TMDB 数据增强配置</h3></div><p className="mt-3 text-sm leading-6 text-muted">可选配置，不影响基础播放。Token 只保存在本机安全存储中。</p></div><div className="grid gap-3 sm:grid-cols-3"><div className="rounded-xl border border-white/10 bg-panel/60 p-4"><span className="font-mono text-xs text-cineo">01</span><p className="mt-3 text-sm font-semibold">创建 Read Access Token</p></div><div className="rounded-xl border border-white/10 bg-panel/60 p-4"><span className="font-mono text-xs text-cineo">02</span><p className="mt-3 text-sm font-semibold">打开设置中的 TMDB</p></div><div className="rounded-xl border border-white/10 bg-panel/60 p-4"><span className="font-mono text-xs text-cineo">03</span><p className="mt-3 text-sm font-semibold">粘贴并保存 Token</p></div></div></div></Card></div></section>
      </main>

      <footer className="border-t border-white/[.06] py-12"><div className="container-wide"><div className="flex flex-col justify-between gap-8 sm:flex-row sm:items-start"><div><a href="#top" className="flex items-center gap-3"><img src="./branding/cineo_mark.png" alt="Cineo" className="h-7 w-7" /><span className="font-display text-base font-bold tracking-[.16em]">CINEO</span></a><p className="mt-4 max-w-sm text-xs leading-6 text-muted">一个简洁、专注、可扩展的 Flutter 影视发现与播放客户端。</p></div><div className="flex flex-wrap gap-5 text-xs font-semibold text-muted"><a href={GITHUB_URL} target="_blank" rel="noreferrer" className="transition-colors hover:text-copy">GitHub</a><a href={RELEASES_URL} target="_blank" rel="noreferrer" className="transition-colors hover:text-copy">Releases</a><a href="#tmdb" className="transition-colors hover:text-copy">TMDB 配置</a></div></div><div className="mt-9 flex items-start gap-3 rounded-2xl border border-cineo/20 bg-cineo/5 px-5 py-4"><LockKeyhole size={18} className="mt-0.5 shrink-0 text-cineo" /><p className="text-sm leading-6 text-copy"><span className="font-semibold">本地优先，资料由你掌控。</span> 所有数据都保存在你的设备上，不会被上传到服务器；你的片库、来源和设置始终由你自己控制。</p></div><Separator className="my-9" /><div className="flex flex-col gap-4 text-[11px] leading-5 text-muted sm:flex-row sm:items-start sm:justify-between"><p>© {new Date().getFullYear()} Cineo · 由 <a href="https://benson.indevs.in/" target="_blank" rel="noreferrer" className="text-cineo-light transition-colors hover:text-cineo">Benson</a> 独立制作 · 欢迎创意引用</p><p className="max-w-2xl sm:text-right">本项目仅供个人参考与学习交流使用，由个人开发者独立维护。Cineo 不提供、不托管任何影视资源，页面中的图片与第三方服务标识归其各自权利人所有。请仅配置和访问你有权使用的内容，并遵守所在地法律法规及相关服务条款。</p></div></div></footer>

      {activeShot && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-5 backdrop-blur-sm" role="dialog" aria-modal="true" aria-label={activeShot.label} onClick={() => setActiveShot(null)}><button className="absolute right-5 top-5 flex h-11 w-11 items-center justify-center rounded-full border border-white/15 bg-panel text-copy hover:border-cineo" onClick={() => setActiveShot(null)} aria-label="关闭预览"><X size={20} /></button><div className="max-h-[90vh] max-w-[min(90vw,420px)]" onClick={(event) => event.stopPropagation()}><PhoneMockup image={asset(activeShot.name)} alt={activeShot.alt} className="phone-shell-modal" /><p className="mt-4 text-center text-sm font-semibold text-copy">{activeShot.label}</p></div></div>}
    </div>
  )
}

export default App

createRoot(document.getElementById('root')).render(<App />)
