<template>
  <div class="login-screen">
    <div class="login-card">
      <div class="login-logo">📚</div>
      <h1>English Learning</h1>
      <p class="subtitle">Desktop App</p>

      <!-- Google OAuth Button -->
      <button class="google-btn" @click="loginWithGoogle">
        <img src="https://www.svgrepo.com/show/475656/google-color.svg" width="18" height="18" />
        Войти через Google
      </button>

      <div class="divider"><span>или</span></div>

      <!-- Manual JWT paste -->
      <div class="token-section">
        <label>JWT Token (из мобильного приложения)</label>
        <textarea
          v-model="tokenInput"
          class="input token-input"
          placeholder="Вставьте токен из настроек мобильного приложения..."
          rows="4"
        />
        <button class="btn btn-primary" :disabled="!tokenInput.trim()" @click="loginWithToken">
          Войти с токеном
        </button>
      </div>

      <p v-if="error" class="error-msg">{{ error }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ layout: false })

const auth = useAuthStore()
const tokenInput = ref('')
const error = ref('')

// Manual JWT paste
const loginWithToken = () => {
  if (tokenInput.value.trim()) {
    auth.setToken(tokenInput.value.trim())
    navigateTo('/')
  }
}

// Google OAuth — open system browser, deep link returns token
const loginWithGoogle = async () => {
  try {
    const { open } = await import('@tauri-apps/plugin-shell')
    await open('http://localhost:8007/auth/google/desktop')
  } catch (e) {
    // Fallback: just open in a new window if not running in Tauri
    window.open('http://localhost:8007/auth/google/desktop', '_blank')
  }
}

onMounted(async () => {
  auth.loadFromStorage()
  if (auth.isLoggedIn) {
    navigateTo('/')
    return
  }

  // Listen for english-desktop://auth#access_token=... deep link (only in Tauri)
  try {
    const { onOpenUrl } = await import('@tauri-apps/plugin-deep-link')
    await onOpenUrl((urls: string[]) => {
      console.log('Deep link received:', urls)
      for (const url of urls) {
        if (url.includes('access_token=')) {
          const hashStr = url.includes('#') ? url.split('#')[1] : url.split('?')[1]
          const params = new URLSearchParams(hashStr)
          const token = params.get('access_token')
          if (token) {
            auth.setToken(token)
            navigateTo('/')
          }
        }
      }
    })
  } catch (err) {
    console.log('Deep link not available (not running in Tauri):', err)
  }
})
</script>

<style scoped>
.login-screen {
  width: 100vw; height: 100vh;
  background: radial-gradient(ellipse at top left, #1e1b4b 0%, #0f1117 60%);
  display: flex; align-items: center; justify-content: center;
}
.login-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 40px 48px;
  width: 440px;
  text-align: center;
  box-shadow: 0 24px 80px rgba(0,0,0,.6);
}
.login-logo { font-size: 52px; margin-bottom: 12px; }
h1 { font-family: 'Outfit', sans-serif; font-size: 26px; font-weight: 700; margin-bottom: 4px; }
.subtitle { color: var(--text-muted); margin-bottom: 32px; }
.google-btn {
  width: 100%; display: flex; align-items: center; justify-content: center; gap: 10px;
  background: white; color: #333; font-weight: 600; font-size: 14px;
  padding: 12px; border-radius: 8px; border: 1px solid #ddd;
  cursor: pointer; transition: all .2s;
}
.google-btn:hover { background: #f1f1f1; border-color: #bbb; }
.divider { color: var(--text-muted); text-align: center; margin: 20px 0; font-size: 13px; text-transform: uppercase; letter-spacing: 1px; }
.divider::before, .divider::after { content: ''; display: inline-block; width: 60px; border-top: 1px solid var(--border); vertical-align: middle; margin: 0 10px; }
.token-section { display: flex; flex-direction: column; gap: 10px; text-align: left; }
.token-section label { font-size: 13px; font-weight: 600; color: var(--text-muted); }
.token-input { resize: none; font-family: monospace; font-size: 12px; }
.hint { color: var(--text-muted); font-size: 13px; line-height: 1.6; }
.error-msg { color: var(--error); font-size: 13px; margin-top: 12px; }
</style>
