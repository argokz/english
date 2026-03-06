<template>
  <div class="page">
    <h1 class="page-title">🎧 IELTS Listening</h1>

    <div class="listening-layout">
      <!-- Left: Player & URL input -->
      <div class="left-panel">
        <!-- Youtube embed -->
        <div v-if="video" class="player-wrap">
          <iframe
            :src="`https://www.youtube.com/embed/${video.video_id}?autoplay=0&rel=0`"
            class="yt-player"
            frameborder="0"
            allow="accelerometer; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen
          />
        </div>
        <div v-else class="player-placeholder card">
          <div class="placeholder-icon">📺</div>
          <p>Вставьте ссылку на YouTube видео</p>
        </div>

        <!-- URL Input -->
        <div class="url-row">
          <input v-model="url" class="input" placeholder="https://youtube.com/watch?v=..." @keyup.enter="process" />
          <button class="btn btn-primary" :disabled="!url.trim() || processing" @click="process">
            <span v-if="processing" class="spinner-sm" />
            <span v-else>Обработать</span>
          </button>
        </div>

        <!-- History -->
        <div v-if="history.length" class="history-section">
          <div class="section-label">История</div>
          <div class="history-list">
            <div
              v-for="item in history"
              :key="item.id"
              class="history-item"
              :class="{ active: video?.id === item.id }"
              @click="loadFromHistory(item)"
            >
              <div class="hi-thumb">
                <img :src="`https://img.youtube.com/vi/${item.video_id}/mqdefault.jpg`" />
              </div>
              <div class="hi-info">
                <div class="hi-title">{{ item.title ?? item.video_id }}</div>
                <div class="hi-date">{{ formatDate(item.viewed_at) }}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Right: Tabs -->
      <div v-if="video" class="right-panel card">
        <div class="tab-bar">
          <button v-for="tab in tabs" :key="tab.key" class="tab-btn" :class="{ active: activeTab === tab.key }" @click="activeTab = tab.key">
            {{ tab.label }}
          </button>
        </div>

        <!-- Transcript -->
        <div v-if="activeTab === 'transcript'" class="tab-content">
          <div class="transcript-text">
            <p v-for="(para, i) in transcriptParagraphs" :key="i" class="para">
              <span class="para-num">{{ i + 1 }}.</span> {{ para }}
            </p>
          </div>
        </div>

        <!-- Translation -->
        <div v-if="activeTab === 'translation'" class="tab-content">
          <div class="transcript-text">
            <p v-for="(para, i) in translationParagraphs" :key="i" class="para">
              <span class="para-num">{{ i + 1 }}.</span> {{ para }}
            </p>
          </div>
        </div>

        <!-- Questions -->
        <div v-if="activeTab === 'questions'" class="tab-content questions-list">
          <div v-if="!video.questions?.length" class="empty-tab">Нет вопросов</div>
          <div v-for="(q, qi) in video.questions" :key="qi" class="question-card">
            <div class="q-num">Вопрос {{ qi + 1 }}</div>
            <div class="q-text">{{ q.question }}</div>
            <div v-if="q.options?.length" class="options-list">
              <button
                v-for="(opt, oi) in q.options"
                :key="oi"
                class="option-btn"
                :class="{ correct: answered[qi] === oi && oi === correctIdx(q), wrong: answered[qi] === oi && oi !== correctIdx(q) }"
                :disabled="answered[qi] !== undefined"
                @click="answer(qi, oi, q)"
              >
                {{ opt }}
              </button>
            </div>
            <div v-else>
              <input v-model="gapAnswers[qi]" class="input" placeholder="Введите ответ..." />
              <button class="btn btn-primary btn-sm" style="margin-top: 8px" @click="checkGap(qi, q)">Проверить</button>
            </div>
            <div v-if="feedback[qi]" class="feedback" :class="feedback[qi].correct ? 'correct' : 'wrong'">
              {{ feedback[qi].correct ? '✅ Верно!' : `❌ Неверно. Правильный ответ: ${q.answer}` }}
            </div>
          </div>
        </div>

        <!-- Chat -->
        <div v-if="activeTab === 'chat'" class="tab-content chat-tab">
          <div class="chat-messages" ref="chatEl">
            <div v-for="(msg, i) in chatMessages" :key="i" class="chat-msg" :class="msg.role">
              <div class="msg-bubble">{{ msg.text }}</div>
            </div>
            <div v-if="chatLoading" class="chat-msg assistant"><div class="msg-bubble loader-dots">●●●</div></div>
          </div>
          <div class="chat-input-row">
            <input v-model="chatInput" class="input" placeholder="Задайте вопрос по видео..." @keyup.enter="sendChat" />
            <button class="btn btn-primary" :disabled="!chatInput.trim() || chatLoading" @click="sendChat">➤</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { VideoResult, VideoHistoryItem, VideoQuestion } from '~/composables/useApi'
const api = useApi()
const url = ref('')
const video = ref<VideoResult | null>(null)
const history = ref<VideoHistoryItem[]>([])
const processing = ref(false)
const activeTab = ref('transcript')
const tabs = [
  { key: 'transcript', label: 'Транскрипция' },
  { key: 'translation', label: 'Перевод' },
  { key: 'questions', label: 'Вопросы' },
  { key: 'chat', label: '💬 Чат' },
]
const answered = ref<Record<number, number>>({})
const gapAnswers = ref<Record<number, string>>({})
const feedback = ref<Record<number, { correct: boolean }>>({})
const chatMessages = ref<{ role: string; text: string }[]>([])
const chatInput = ref('')
const chatLoading = ref(false)
const chatEl = ref<HTMLElement | null>(null)

const transcriptParagraphs = computed(() => {
  const text = video.value?.transcription ?? ''
  return text.split(/\n+/).filter(p => p.trim().length > 0)
})
const translationParagraphs = computed(() => {
  const text = video.value?.translation ?? ''
  return text.split(/\n+/).filter(p => p.trim().length > 0)
})

const process = async () => {
  processing.value = true
  try {
    video.value = await api.processVideo(url.value.trim())
    activeTab.value = 'transcript'
    loadHistory()
  } catch (e: any) { alert(e.message) }
  finally { processing.value = false }
}
const loadHistory = async () => { history.value = await api.getYoutubeHistory() }
const loadFromHistory = (item: VideoHistoryItem) => {
  video.value = { ...item }; activeTab.value = 'transcript'
  answered.value = {}; gapAnswers.value = {}; feedback.value = {}; chatMessages.value = []
}
const formatDate = (s: string) => new Date(s).toLocaleDateString('ru-RU')

const correctIdx = (q: VideoQuestion) => q.options?.indexOf(q.answer) ?? -1
const answer = (qi: number, oi: number, q: VideoQuestion) => {
  answered.value[qi] = oi
  feedback.value[qi] = { correct: oi === correctIdx(q) }
}
const checkGap = (qi: number, q: VideoQuestion) => {
  feedback.value[qi] = { correct: gapAnswers.value[qi]?.trim().toLowerCase() === q.answer.toLowerCase() }
}

const sendChat = async () => {
  if (!chatInput.value.trim() || !video.value) return
  chatMessages.value.push({ role: 'user', text: chatInput.value.trim() })
  chatInput.value = ''; chatLoading.value = true
  await nextTick(); if (chatEl.value) chatEl.value.scrollTop = chatEl.value.scrollHeight
  try {
    const resp = await api.askVideoQuestion(video.value.video_id, chatMessages.value[chatMessages.value.length - 1].text)
    chatMessages.value.push({ role: 'assistant', text: resp.answer })
  } catch (e: any) { chatMessages.value.push({ role: 'assistant', text: '❌ ' + e.message }) }
  finally { chatLoading.value = false; await nextTick(); if (chatEl.value) chatEl.value.scrollTop = chatEl.value.scrollHeight }
}

onMounted(loadHistory)
</script>

<style scoped>
.listening-layout { display: grid; grid-template-columns: 320px 1fr; gap: 16px; height: calc(100vh - 130px); }
.left-panel { display: flex; flex-direction: column; gap: 12px; overflow-y: auto; }
.right-panel { display: flex; flex-direction: column; overflow: hidden; padding: 0; }

.yt-player { width: 100%; aspect-ratio: 16/9; border-radius: var(--radius); }
.player-placeholder { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; aspect-ratio: 16/9; color: var(--text-muted); }
.placeholder-icon { font-size: 40px; }

.url-row { display: flex; gap: 8px; }

.history-section { flex: 1; }
.section-label { font-size: 12px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: .04em; margin-bottom: 8px; }
.history-list { display: flex; flex-direction: column; gap: 6px; }
.history-item {
  display: flex; gap: 10px; align-items: center; padding: 8px; border-radius: 8px;
  cursor: pointer; border: 1px solid transparent; transition: all .15s;
}
.history-item:hover { background: var(--surface); border-color: var(--border); }
.history-item.active { border-color: var(--accent); }
.hi-thumb img { width: 72px; height: 42px; object-fit: cover; border-radius: 4px; }
.hi-title { font-size: 12px; font-weight: 600; line-height: 1.4; }
.hi-date { font-size: 11px; color: var(--text-muted); margin-top: 2px; }

.tab-bar { display: flex; border-bottom: 1px solid var(--border); padding: 0 16px; flex-shrink: 0; }
.tab-btn {
  background: none; border: none; color: var(--text-muted); cursor: pointer;
  padding: 12px 14px; font-size: 13px; font-weight: 600; transition: all .15s;
  border-bottom: 2px solid transparent; margin-bottom: -1px;
}
.tab-btn.active { color: var(--accent); border-bottom-color: var(--accent); }
.tab-content { flex: 1; overflow-y: auto; padding: 16px; }

.transcript-text { display: flex; flex-direction: column; gap: 12px; }
.para { line-height: 1.8; font-size: 14px; }
.para-num { color: var(--accent); font-weight: 600; margin-right: 6px; }

.questions-list { display: flex; flex-direction: column; gap: 16px; }
.question-card { background: var(--surface2); border-radius: 10px; padding: 14px; }
.q-num { font-size: 11px; font-weight: 700; color: var(--accent2); text-transform: uppercase; letter-spacing: .04em; margin-bottom: 6px; }
.q-text { font-weight: 600; margin-bottom: 10px; line-height: 1.5; }
.options-list { display: flex; flex-direction: column; gap: 6px; }
.option-btn {
  padding: 8px 14px; border-radius: 8px; border: 1px solid var(--border);
  background: var(--surface); color: var(--text); cursor: pointer; text-align: left;
  transition: all .15s; font-size: 13px;
}
.option-btn:hover:not(:disabled) { border-color: var(--accent); }
.option-btn.correct { background: rgba(16,185,129,.2); border-color: var(--success); color: var(--success); }
.option-btn.wrong { background: rgba(239,68,68,.15); border-color: var(--error); color: var(--error); }
.feedback { margin-top: 8px; padding: 8px 12px; border-radius: 6px; font-size: 13px; }
.feedback.correct { background: rgba(16,185,129,.15); color: var(--success); }
.feedback.wrong { background: rgba(239,68,68,.1); color: var(--error); }

.chat-tab { display: flex; flex-direction: column; gap: 12px; padding: 16px; }
.chat-messages { flex: 1; display: flex; flex-direction: column; gap: 10px; overflow-y: auto; }
.chat-msg { display: flex; }
.chat-msg.user { justify-content: flex-end; }
.msg-bubble {
  max-width: 75%; padding: 10px 14px; border-radius: 12px; font-size: 13.5px; line-height: 1.55;
  background: var(--surface2); color: var(--text);
}
.chat-msg.user .msg-bubble { background: var(--accent); color: white; }
.loader-dots { letter-spacing: 3px; animation: pulse 1s infinite; }
@keyframes pulse { 0%,100%{opacity:.3} 50%{opacity:1} }
.chat-input-row { display: flex; gap: 8px; }
.empty-tab { color: var(--text-muted); text-align: center; padding: 40px 0; }
</style>
