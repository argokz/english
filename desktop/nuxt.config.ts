// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  devtools: { enabled: false },
  devServer: { port: 3007 },
  modules: ['@pinia/nuxt', '@vueuse/nuxt'],
  ssr: false, // Required for Tauri - static SPA mode
  runtimeConfig: {
    public: {
      apiBase: 'https://itwin.kz/english-words',
    }
  },
  app: {
    head: {
      title: 'English Learning Desktop',
      meta: [
        { charset: 'utf-8' },
        { name: 'viewport', content: 'width=device-width, initial-scale=1' }
      ],
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Outfit:wght@400;600;700&display=swap' }
      ]
    }
  }
})
