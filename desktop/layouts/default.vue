<template>
  <div class="app-shell">
    <aside class="sidebar">
      <div class="sidebar-logo">
        <span class="logo-icon">📚</span>
        <span class="logo-text">English</span>
      </div>
      <nav class="sidebar-nav">
        <NuxtLink to="/" class="nav-item" active-class="active" exact>
          <span class="nav-icon">🏠</span>
          <span>Колоды</span>
        </NuxtLink>
        <NuxtLink to="/translator" class="nav-item" active-class="active">
          <span class="nav-icon">🌐</span>
          <span>Переводчик</span>
        </NuxtLink>
        <NuxtLink to="/listening" class="nav-item" active-class="active">
          <span class="nav-icon">🎧</span>
          <span>IELTS Listening</span>
        </NuxtLink>
        <NuxtLink to="/writing" class="nav-item" active-class="active">
          <span class="nav-icon">✍️</span>
          <span>IELTS Writing</span>
        </NuxtLink>
        <NuxtLink to="/exam" class="nav-item" active-class="active">
          <span class="nav-icon">🎓</span>
          <span>IELTS Экзамен</span>
        </NuxtLink>
      </nav>
      <div class="sidebar-footer">
        <button class="logout-btn" @click="logout">
          <span>⬅️</span> Выйти
        </button>
      </div>
    </aside>
    <main class="main-content">
      <slot />
    </main>
  </div>
</template>

<script setup lang="ts">
const auth = useAuthStore()
const router = useRouter()
const logout = () => { auth.logout(); router.push('/login') }
</script>

<style>
:root {
  --bg: #0f1117;
  --surface: #1a1d2e;
  --surface2: #252840;
  --accent: #7c3aed;
  --accent2: #06b6d4;
  --text: #e2e8f0;
  --text-muted: #94a3b8;
  --border: #2d3160;
  --success: #10b981;
  --error: #ef4444;
  --warn: #f59e0b;
  --radius: 12px;
  --sidebar-w: 220px;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  background: var(--bg);
  color: var(--text);
  font-family: 'Inter', system-ui, sans-serif;
  font-size: 14px;
  overflow: hidden;
}

.app-shell {
  display: flex;
  height: 100vh;
  width: 100vw;
  overflow: hidden;
}

.sidebar {
  width: var(--sidebar-w);
  background: var(--surface);
  border-right: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  padding: 20px 0;
  flex-shrink: 0;
}

.sidebar-logo {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 20px 24px;
  border-bottom: 1px solid var(--border);
  margin-bottom: 12px;
}
.logo-icon { font-size: 24px; }
.logo-text { font-family: 'Outfit', sans-serif; font-size: 18px; font-weight: 700; color: var(--text); }

.sidebar-nav { flex: 1; display: flex; flex-direction: column; gap: 4px; padding: 0 10px; }

.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  border-radius: 8px;
  color: var(--text-muted);
  text-decoration: none;
  font-weight: 500;
  transition: all .15s;
}
.nav-item:hover { background: var(--surface2); color: var(--text); }
.nav-item.active { background: var(--accent); color: white; }
.nav-icon { font-size: 17px; width: 22px; text-align: center; }

.sidebar-footer { padding: 12px 10px 0; border-top: 1px solid var(--border); margin-top: 12px; }
.logout-btn {
  display: flex; align-items: center; gap: 8px;
  background: none; border: none; cursor: pointer;
  color: var(--text-muted); font-size: 14px; padding: 10px 12px;
  border-radius: 8px; width: 100%;
  transition: all .15s;
}
.logout-btn:hover { background: var(--surface2); color: var(--error); }

.main-content {
  flex: 1;
  overflow-y: auto;
  background: var(--bg);
}

/* ── Global utility styles ── */
.page { padding: 28px 32px; max-width: 960px; width: 100%; margin: 0 auto; }
.page-title { font-family: 'Outfit', sans-serif; font-size: 24px; font-weight: 700; margin-bottom: 20px; }
.page-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px; }

.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 16px 20px;
}
.card:hover { border-color: var(--accent); }

.btn {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 9px 18px; border-radius: 8px; border: none;
  font-size: 14px; font-weight: 600; cursor: pointer;
  transition: all .15s; text-decoration: none;
}
.btn-primary { background: var(--accent); color: white; }
.btn-primary:hover { background: #6d28d9; }
.btn-secondary { background: var(--surface2); color: var(--text); border: 1px solid var(--border); }
.btn-secondary:hover { border-color: var(--accent); }
.btn-danger { background: transparent; color: var(--error); border: 1px solid var(--error); }
.btn-danger:hover { background: var(--error); color: white; }
.btn-sm { padding: 5px 12px; font-size: 12px; }
.btn:disabled { opacity: .45; cursor: not-allowed; }

.input {
  background: var(--surface2); border: 1px solid var(--border); border-radius: 8px;
  color: var(--text); padding: 10px 14px; font-size: 14px; width: 100%;
  outline: none; font-family: 'Inter', sans-serif;
  transition: border-color .15s;
}
.input:focus { border-color: var(--accent); }
.input::placeholder { color: var(--text-muted); }

.badge {
  display: inline-flex; align-items: center; justify-content: center;
  background: var(--accent); color: white; border-radius: 999px;
  font-size: 11px; font-weight: 700; padding: 2px 8px; min-width: 22px;
}
.badge-muted { background: var(--surface2); color: var(--text-muted); }

.spinner {
  width: 36px; height: 36px; border-radius: 50%;
  border: 3px solid var(--border); border-top-color: var(--accent);
  animation: spin .7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.center-spinner { display: flex; align-items: center; justify-content: center; height: 200px; }

.tag {
  display: inline-block; padding: 3px 8px; border-radius: 6px;
  font-size: 11px; font-weight: 600;
  background: var(--surface2); color: var(--text-muted);
}
</style>
