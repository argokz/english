<template>
  <div class="page">
    <h1 class="page-title">✍️ IELTS Writing</h1>
    <div class="writing-layout">
      <!-- Editor panel -->
      <div class="editor-panel">
        <div class="editor-toolbar">
          <select v-model="taskType" class="input" style="width:auto">
            <option value="task1">Task 1 (150–200 слов)</option>
            <option value="task2">Task 2 (250–300 слов)</option>
          </select>
          <div class="timer-badge" :class="{ warn: timerSeconds < 300 }">
            ⏱ {{ formatTimer }}
          </div>
          <button v-if="!timerRunning" class="btn btn-secondary btn-sm" @click="startTimer">▶ Старт</button>
          <button v-else class="btn btn-secondary btn-sm" @click="stopTimer">⏸ Пауза</button>
          <div class="word-count">{{ wordCount }} слов</div>
        </div>
        <textarea
          v-model="text"
          class="input writing-textarea"
          placeholder="Напишите ваш ответ на IELTS Writing..."
        />
        <div class="editor-footer">
          <button class="btn btn-primary" :disabled="wordCount < 50 || evaluating" @click="evaluate">
            <span v-if="evaluating">Оценивается...</span>
            <span v-else>🤖 Оценить</span>
          </button>
        </div>
      </div>

      <!-- Results panel -->
      <div class="results-panel card">
        <div v-if="evaluating" class="center-spinner"><div class="spinner" /></div>
        <div v-else-if="result" class="result-content">
          <div class="band-score" v-if="result.band_score">
            <span class="band-label">Band</span>
            <span class="band-num">{{ result.band_score }}</span>
          </div>
          <div class="result-section">
            <div class="result-label">Оценка</div>
            <div class="result-text">{{ result.evaluation }}</div>
          </div>
          <div v-if="result.errors?.length" class="result-section">
            <div class="result-label">Ошибки ({{ result.errors.length }})</div>
            <div v-for="(err, i) in result.errors" :key="i" class="error-item">
              <div class="err-original">❌ {{ err.original }}</div>
              <div class="err-correction">✅ {{ err.correction }}</div>
              <div class="err-explanation">{{ err.explanation }}</div>
            </div>
          </div>
          <div v-if="result.recommendations" class="result-section">
            <div class="result-label">Рекомендации</div>
            <div class="result-text">{{ result.recommendations }}</div>
          </div>
        </div>
        <div v-else class="empty-results">
          <div class="empty-icon">📊</div>
          <p>Оценка появится здесь после проверки</p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { WritingResult } from '~/composables/useApi'
const api = useApi()
const taskType = ref('task2')
const text = ref('')
const evaluating = ref(false)
const result = ref<WritingResult | null>(null)
const timerSeconds = ref(0)
const timerRunning = ref(false)
let timerInterval: ReturnType<typeof setInterval> | null = null

const wordCount = computed(() => text.value.trim().split(/\s+/).filter(Boolean).length)
const formatTimer = computed(() => {
  const m = Math.floor(timerSeconds.value / 60).toString().padStart(2, '0')
  const s = (timerSeconds.value % 60).toString().padStart(2, '0')
  return `${m}:${s}`
})
const startTimer = () => { timerRunning.value = true; timerInterval = setInterval(() => timerSeconds.value++, 1000) }
const stopTimer = () => { timerRunning.value = false; if (timerInterval) clearInterval(timerInterval) }

const evaluate = async () => {
  evaluating.value = true
  try {
    result.value = await api.evaluateWriting(text.value, taskType.value, timerSeconds.value)
  } catch (e: any) { alert(e.message) }
  finally { evaluating.value = false }
}
</script>

<style scoped>
.writing-layout { display: grid; grid-template-columns: 1fr 400px; gap: 16px; height: calc(100vh - 130px); }
.editor-panel { display: flex; flex-direction: column; gap: 10px; }
.editor-toolbar { display: flex; align-items: center; gap: 10px; }
.writing-textarea { flex: 1; resize: none; font-size: 15px; line-height: 1.8; }
.editor-footer { display: flex; justify-content: flex-end; }
.word-count { color: var(--text-muted); font-size: 13px; margin-left: auto; }
.timer-badge {
  font-family: monospace; font-size: 15px; font-weight: 700;
  background: var(--surface2); padding: 5px 12px; border-radius: 8px; color: var(--text);
}
.timer-badge.warn { color: var(--warn); }

.results-panel { overflow-y: auto; }
.result-content { display: flex; flex-direction: column; gap: 20px; }
.band-score { display: flex; align-items: baseline; gap: 8px; padding: 16px; background: var(--accent); border-radius: 10px; }
.band-label { font-size: 13px; font-weight: 700; color: rgba(255,255,255,.7); }
.band-num { font-size: 48px; font-weight: 700; font-family: 'Outfit', sans-serif; color: white; }
.result-section { display: flex; flex-direction: column; gap: 8px; }
.result-label { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; color: var(--accent2); }
.result-text { font-size: 13.5px; line-height: 1.7; color: var(--text); white-space: pre-wrap; }
.error-item { background: var(--surface2); border-radius: 8px; padding: 10px 12px; display: flex; flex-direction: column; gap: 4px; }
.err-original { color: var(--error); font-size: 13px; }
.err-correction { color: var(--success); font-size: 13px; }
.err-explanation { color: var(--text-muted); font-size: 12px; }
.empty-results { display: flex; flex-direction: column; align-items: center; justify-content: center; height: 200px; color: var(--text-muted); gap: 12px; }
.empty-icon { font-size: 42px; }
</style>
