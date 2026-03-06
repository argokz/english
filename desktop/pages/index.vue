<template>
  <div class="page">
    <div class="page-header">
      <h1 class="page-title">Колоды</h1>
      <button class="btn btn-primary" @click="showCreateDeck = true">+ Новая колода</button>
    </div>

    <!-- Feature cards -->
    <div class="feature-grid">
      <NuxtLink to="/translator" class="feature-card">
        <div class="feature-icon">🌐</div>
        <div>
          <div class="feature-title">Переводчик</div>
          <div class="feature-sub">Русский ↔ English</div>
        </div>
      </NuxtLink>
      <NuxtLink to="/writing" class="feature-card">
        <div class="feature-icon">✍️</div>
        <div>
          <div class="feature-title">IELTS Writing</div>
          <div class="feature-sub">Таймер, оценка, ошибки</div>
        </div>
      </NuxtLink>
      <NuxtLink to="/listening" class="feature-card">
        <div class="feature-icon">🎧</div>
        <div>
          <div class="feature-title">IELTS Listening</div>
          <div class="feature-sub">YouTube + транскрипция</div>
        </div>
      </NuxtLink>
      <NuxtLink to="/exam" class="feature-card">
        <div class="feature-icon">🎓</div>
        <div>
          <div class="feature-title">IELTS Экзамен</div>
          <div class="feature-sub">4 части, симулятор</div>
        </div>
      </NuxtLink>
    </div>

    <!-- Decks list -->
    <div v-if="loading" class="center-spinner"><div class="spinner" /></div>
    <div v-else-if="error" class="error-block">{{ error }}</div>
    <div v-else class="decks-grid">
      <div v-for="deck in decks" :key="deck.id" class="deck-card card">
        <div class="deck-info">
          <div class="deck-name">{{ deck.name }}</div>
          <div class="deck-sub">
            <span class="badge-muted tag">{{ dueCounts[deck.id] ?? 0 }} на сегодня</span>
          </div>
        </div>
        <div class="deck-actions">
          <button v-if="(dueCounts[deck.id] ?? 0) > 0" class="btn btn-primary btn-sm" @click="startStudy(deck)">
            📖 Учить
          </button>
          <NuxtLink :to="`/deck/${deck.id}`" class="btn btn-secondary btn-sm">Открыть</NuxtLink>
          <button class="btn btn-danger btn-sm" @click="removeDeck(deck.id)">🗑</button>
        </div>
      </div>
      <div v-if="decks.length === 0" class="empty-state">
        <div class="empty-icon">📂</div>
        <p>У вас пока нет колод. Создайте первую!</p>
      </div>
    </div>

    <!-- Create deck modal -->
    <Teleport to="body">
      <div v-if="showCreateDeck" class="modal-overlay" @click.self="showCreateDeck = false">
        <div class="modal">
          <h2>Новая колода</h2>
          <input v-model="newDeckName" class="input" placeholder="Название колоды" autofocus @keyup.enter="createDeck" />
          <div class="modal-actions">
            <button class="btn btn-secondary" @click="showCreateDeck = false">Отмена</button>
            <button class="btn btn-primary" :disabled="!newDeckName.trim()" @click="createDeck">Создать</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
import type { Deck } from '~/composables/useApi'
const api = useApi()
const router = useRouter()

const decks = ref<Deck[]>([])
const dueCounts = ref<Record<string, number>>({})
const loading = ref(true)
const error = ref('')
const showCreateDeck = ref(false)
const newDeckName = ref('')

const load = async () => {
  loading.value = true; error.value = ''
  try {
    decks.value = await api.getDecks()
    for (const d of decks.value) {
      const due = await api.getDueCards(d.id)
      dueCounts.value[d.id] = due.length
    }
  } catch (e: any) { error.value = e.message }
  finally { loading.value = false }
}

const createDeck = async () => {
  if (!newDeckName.value.trim()) return
  await api.createDeck(newDeckName.value.trim())
  newDeckName.value = ''; showCreateDeck.value = false
  load()
}
const removeDeck = async (id: string) => {
  if (!confirm('Удалить колоду?')) return
  await api.deleteDeck(id); load()
}
const startStudy = (deck: Deck) => router.push(`/study/${deck.id}`)

onMounted(load)
</script>

<style scoped>
.feature-grid {
  display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 28px;
}
.feature-card {
  display: flex; align-items: center; gap: 12px;
  background: var(--surface); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 16px;
  text-decoration: none; color: var(--text); transition: all .15s;
}
.feature-card:hover { border-color: var(--accent); transform: translateY(-2px); box-shadow: 0 8px 24px rgba(124,58,237,.2); }
.feature-icon { font-size: 28px; flex-shrink: 0; }
.feature-title { font-weight: 600; font-size: 14px; }
.feature-sub { color: var(--text-muted); font-size: 12px; margin-top: 2px; }

.decks-grid { display: flex; flex-direction: column; gap: 10px; }
.deck-card { display: flex; align-items: center; justify-content: space-between; cursor: pointer; }
.deck-name { font-weight: 600; font-size: 15px; }
.deck-sub { margin-top: 4px; }
.deck-actions { display: flex; gap: 8px; align-items: center; }

.empty-state { text-align: center; padding: 60px 0; color: var(--text-muted); }
.empty-icon { font-size: 48px; margin-bottom: 12px; }
.error-block { color: var(--error); text-align: center; padding: 32px; }

.modal-overlay {
  position: fixed; inset: 0; background: rgba(0,0,0,.6); backdrop-filter: blur(4px);
  display: flex; align-items: center; justify-content: center; z-index: 999;
}
.modal {
  background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
  padding: 28px 32px; width: 400px; display: flex; flex-direction: column; gap: 16px;
}
.modal h2 { font-family: 'Outfit', sans-serif; font-size: 18px; }
.modal-actions { display: flex; gap: 10px; justify-content: flex-end; }
</style>
