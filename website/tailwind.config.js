/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#080909',
        panel: '#141516',
        panel2: '#1c1d1f',
        line: '#303133',
        copy: '#f8f7f4',
        muted: '#aaa7a1',
        cineo: '#ffa13a',
        'cineo-light': '#ffc467',
        'cineo-deep': '#4b2e13',
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'],
        display: ['Space Grotesk', 'Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      boxShadow: {
        glow: '0 0 60px rgba(255, 161, 58, 0.18)',
        'glow-sm': '0 0 25px rgba(255, 161, 58, 0.16)',
      },
      backgroundImage: {
        grain: "url(\"data:image/svg+xml,%3Csvg viewBox='0 0 180 180' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='.28'/%3E%3C/svg%3E\")",
      },
      keyframes: {
        drift: { '0%, 100%': { transform: 'translate3d(0, 0, 0)' }, '50%': { transform: 'translate3d(0, -14px, 0)' } },
        marquee: { from: { transform: 'translateX(0)' }, to: { transform: 'translateX(-50%)' } },
        'fade-up': { from: { opacity: '0', transform: 'translateY(18px)' }, to: { opacity: '1', transform: 'translateY(0)' } },
      },
      animation: {
        drift: 'drift 8s ease-in-out infinite',
        marquee: 'marquee 34s linear infinite',
        'fade-up': 'fade-up .7s ease-out both',
      },
    },
  },
  plugins: [],
}
