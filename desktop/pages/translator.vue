<template>
  <div class="page">
    <h1 class="page-title">🌐 Переводчик</h1>
    <div class="translator-grid">
      <!-- Source -->
      <div class="trans-panel card">
        <div class="panel-header">
          <div class="lang-label">{{ direction === 'en-ru' ? 'English' : 'Русский' }}</div>
          <button class="btn btn-secondary btn-sm" @click="swap">⇄ Поменять</button>
        </div>
        <textarea v-model="inputText" class="input trans-textarea" :placeholder="`Введите текст на ${direction === 'en-ru' ? 'английском' : 'русском'}...`" @keydown.ctrl.enter="translate" />
        <div class="panel-footer">
          <span class="char-count">{{ inputText.length }} симв.</span>
          <button class="btn btn-primary" :disabled="!inputText.trim() || loading" @click="translate">
            <span v-if="loading">...</span>
            <span v-else>Перевести ↵</span>
          </button>
        </div>
      </div>
      <!-- Result -->
      <div class="trans-panel card">
        <div class="panel-header">
          <div class="lang-label">{{ direction === 'en-ru' ? 'Русский' : 'English' }}</div>
          <button v-if="result" class="btn btn-secondary btn-sm" @click="copy">📋 Копировать</button>
        </div>
        <div class="trans-result">
          <div v-if="loading" class="center-spinner"><div class="spinner" /></div>
          <div v-else-if="result" class="result-text">{{ result }}</div>
          <div v-else-if="error" class="error-text">{{ error }}</div>
          <div v-else class="placeholder-text">Перевод появится здесь...</div>
        </div>
        <div v-if="result" class="panel-footer">
          <button class="btn btn-secondary btn-sm" @click="addToCard">➕ В карточку</button>
        </div>
      </div>
    </div>

    <!-- Add to deck modal -->
    <Teleport to="body">
      <div v-if="showAddCard" class="modal-overlay" @click.self="showAddCard = false">
        <div class="modal">
          <h2>Добавить карточку</h2>
          <div class="form-row">
            <label>Слово</label>
            <input v-model="cardWord" class="input" />
          </div>
          <div class="form-row">
            <label>Перевод</label>
            <input v-model="cardTranslation" class="input" />
          </div>
          <div class="form-row">
            <label>Колода</label>
            <select v-model="selectedDeck" class="input">
              <option v-for="d in decks" :key="d.id" :value="d.id">{{ d.name }}</option>
            </select>
          </div>
          <div class="modal-actions">
            <button class="btn btn-secondary" @click="showAddCard = false">Отмена</button>
            <button class="btn btn-primary" @click="saveCard">Сохранить</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
import type { Deck } from '~/composables/useApi'
const api = useApi()
const direction = ref<'en-ru' | 'ru-en'>('en-ru')
const inputText = ref('')
const result = ref('')
const error = ref('')
const loading = ref(false)
const decks = ref<Deck[]>([])
const showAddCard = ref(false)
const cardWord = ref('')
const cardTranslation = ref('')
const selectedDeck = ref('')

onMounted(() => api.getDecks().then(d => { decks.value = d; selectedDeck.value = d[0]?.id ?? '' }))

const swap = () => { direction.value = direction.value === 'en-ru' ? 'ru-en' : 'en-ru'; result.value = '' }

const translate = async () => {
  if (!inputText.value.trim()) return
  loading.value = true; error.value = ''
  const [src, tgt] = direction.value === 'en-ru' ? ['en', 'ru'] : ['ru', 'en']
  try {
    const r = await api.translate(inputText.value.trim(), src, tgt)
    result.value = r.translation
  } catch (e: any) { error.value = e.message }
  finally { loading.value = false }
}

const copy = () => navigator.clipboard.writeText(result.value)

const addToCard = () => {
  if (direction.value === 'en-ru') { cardWord.value = inputText.value; cardTranslation.value = result.value }
  else { cardWord.value = result.value; cardTranslation.value = inputText.value }
  showAddCard.value = true
}

const saveCard = async () => {
  await api.createCard(selectedDeck.value, cardWord.value, cardTranslation.value)
  showAddCard.value = false
}
</script>

<style scoped>
.translator-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; height: calc(100vh - 160px); }
.trans-panel { display: flex; flex-direction: column; gap: 12px; height: 100%; }
.panel-header { display: flex; align-items: center; justify-content: space-between; }
.lang-label { font-weight: 700; font-size: 15px; color: var(--accent2); }
.trans-textarea {
  flex: 1; resize: none; border-radius: 8px;
  font-size: 16px; line-height: 1.6;
}
.trans-result {
  flex: 1; background: var(--surface2); border-radius: 8px; padding: 12px;
  overflow-y: auto; position: relative;
}
.result-text { font-size: 16px; line-height: 1.7; white-space: pre-wrap; color: var(--text); }
.placeholder-text { color: var(--text-muted); font-style: italic; }
.error-text { color: var(--error); }
.panel-footer { display: flex; align-items: center; justify-content: space-between; }
.char-count { color: var(--text-muted); font-size: 12px; }

.form-row { display: flex; flex-direction: column; gap: 4px; }
.form-row label { font-size: 12px; font-weight: 600; color: var(--text-muted); }
.modal { gap: 14px; }
.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,.6); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; z-index: 999; }
.modal { background: var(--surface); border: 1px solid var(--border); border-radius: 16px; padding: 28px 32px; width: 400px; display: flex; flex-direction: column; gap: 16px; }
.modal h2 { font-family: 'Outfit', sans-serif; font-size: 18px; }
.modal-actions { display: flex; gap: 10px; justify-content: flex-end; }
</style>
