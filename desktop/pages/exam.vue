<template>
  <div class="page">
    <h1 class="page-title">🎓 IELTS Экзамен (Симулятор)</h1>
    <div v-if="!exam.length" class="exam-start">
      <div class="exam-intro card">
        <div class="exam-icon">🎓</div>
        <h2>Полный тест IELTS Listening</h2>
        <p>4 части, каждая часть — отрывок из реального YouTube видео + 10 вопросов. Всего 40 вопросов.</p>
        <button class="btn btn-primary" :disabled="loading" @click="startExam">
          <span v-if="loading">Загрузка ({{ loadedParts }}/4)...</span>
          <span v-else>▶ Начать экзамен</span>
        </button>
      </div>
    </div>

    <div v-else class="exam-content">
      <div class="part-tabs">
        <button
          v-for="part in exam"
          :key="part.part_number"
          class="tab-btn"
          :class="{ active: activePart === part.part_number }"
          @click="activePart = part.part_number"
        >
          Часть {{ part.part_number }}
          <span v-if="partScore(part) !== null" class="part-score">{{ partScore(part) }}/10</span>
        </button>
      </div>

      <div v-for="part in exam" v-show="activePart === part.part_number" :key="part.part_number" class="part-content">
        <div class="part-video-wrap">
          <iframe
            :src="`https://www.youtube.com/embed/${part.video_id}?rel=0`"
            class="yt-player-sm"
            frameborder="0"
            allowfullscreen
          />
        </div>
        <div class="part-questions">
          <div v-for="(q, qi) in part.questions" :key="qi" class="question-card">
            <div class="q-num">{{ (activePart - 1) * 10 + qi + 1 }}.</div>
            <div class="q-text">{{ q.question }}</div>
            <div v-if="q.options?.length" class="options-list">
              <button
                v-for="(opt, oi) in q.options"
                :key="oi"
                class="option-btn"
                :class="getClass(part.part_number, qi, oi, q)"
                :disabled="!!examAnswers[`${part.part_number}-${qi}`]"
                @click="answerExam(part.part_number, qi, oi, q)"
              >{{ opt }}</button>
            </div>
            <div v-else>
              <input v-model="gapInputs[`${part.part_number}-${qi}`]" class="input" placeholder="Ответ..." />
              <button class="btn btn-sm btn-primary" style="margin-top:6px" @click="checkExamGap(part.part_number, qi, q)">✓</button>
            </div>
            <div v-if="examFeedback[`${part.part_number}-${qi}`]" class="feedback" :class="examFeedback[`${part.part_number}-${qi}`] ? 'correct' : 'wrong'">
              {{ examFeedback[`${part.part_number}-${qi}`] ? `✅ Верно!` : `❌ Правильно: ${q.answer}` }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { ExamPart, ExamQuestion } from '~/composables/useApi'
const api = useApi()
const exam = ref<ExamPart[]>([])
const loading = ref(false)
const loadedParts = ref(0)
const activePart = ref(1)
const examAnswers = ref<Record<string, number>>({})
const gapInputs = ref<Record<string, string>>({})
const examFeedback = ref<Record<string, boolean | null>>({})

const startExam = async () => {
  loading.value = true; exam.value = []; loadedParts.value = 0
  try {
    for (let i = 1; i <= 4; i++) {
      const part = await api.generateExamPart(i)
      exam.value.push(part); loadedParts.value = i
    }
    activePart.value = 1
  } catch (e: any) { alert(e.message) }
  finally { loading.value = false }
}

const correctIdx = (q: ExamQuestion) => q.options?.indexOf(q.answer) ?? -1
const getClass = (pn: number, qi: number, oi: number, q: ExamQuestion) => {
  const key = `${pn}-${qi}`
  if (examAnswers.value[key] === undefined) return ''
  if (oi === correctIdx(q)) return 'correct'
  if (examAnswers.value[key] === oi) return 'wrong'
  return ''
}
const answerExam = (pn: number, qi: number, oi: number, q: ExamQuestion) => {
  const key = `${pn}-${qi}`
  examAnswers.value[key] = oi
  examFeedback.value[key] = oi === correctIdx(q)
}
const checkExamGap = (pn: number, qi: number, q: ExamQuestion) => {
  const key = `${pn}-${qi}`
  const ans = gapInputs.value[key]?.trim().toLowerCase() ?? ''
  examFeedback.value[key] = ans === q.answer.toLowerCase()
}
const partScore = (part: ExamPart) => {
  const answered = part.questions.filter((_, qi) => examFeedback.value[`${part.part_number}-${qi}`] !== undefined)
  if (!answered.length) return null
  return part.questions.filter((_, qi) => examFeedback.value[`${part.part_number}-${qi}`] === true).length
}
</script>

<style scoped>
.exam-start { display: flex; align-items: center; justify-content: center; height: calc(100vh - 150px); }
.exam-intro { text-align: center; padding: 48px; width: 480px; display: flex; flex-direction: column; gap: 16px; align-items: center; }
.exam-icon { font-size: 56px; }
.exam-intro h2 { font-family: 'Outfit', sans-serif; font-size: 22px; }
.exam-intro p { color: var(--text-muted); line-height: 1.6; }

.exam-content { display: flex; flex-direction: column; gap: 16px; }
.part-tabs { display: flex; gap: 8px; }
.tab-btn {
  padding: 8px 18px; border-radius: 8px; border: 1px solid var(--border);
  background: var(--surface); color: var(--text-muted); cursor: pointer;
  font-weight: 600; font-size: 13px; transition: all .15s; display: flex; align-items: center; gap: 8px;
}
.tab-btn:hover { border-color: var(--accent); color: var(--text); }
.tab-btn.active { background: var(--accent); border-color: var(--accent); color: white; }
.part-score { background: rgba(255,255,255,.25); padding: 1px 6px; border-radius: 999px; font-size: 11px; }

.part-content { display: grid; grid-template-columns: 280px 1fr; gap: 16px; max-height: calc(100vh - 220px); }
.part-video-wrap { position: sticky; top: 0; align-self: start; }
.yt-player-sm { width: 100%; aspect-ratio: 16/9; border-radius: var(--radius); }

.part-questions { overflow-y: auto; display: flex; flex-direction: column; gap: 12px; }
.question-card { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 14px; }
.q-num { font-size: 11px; font-weight: 700; color: var(--accent2); margin-bottom: 4px; }
.q-text { font-weight: 600; margin-bottom: 10px; line-height: 1.5; }
.options-list { display: flex; flex-direction: column; gap: 6px; }
.option-btn {
  padding: 8px 14px; border-radius: 8px; border: 1px solid var(--border);
  background: var(--surface2); color: var(--text); cursor: pointer; text-align: left; transition: all .15s; font-size: 13px;
}
.option-btn.correct { background: rgba(16,185,129,.2); border-color: #10b981; color: #10b981; }
.option-btn.wrong { background: rgba(239,68,68,.15); border-color: #ef4444; color: #ef4444; }
.feedback { margin-top: 8px; padding: 8px 12px; border-radius: 6px; font-size: 12px; }
.feedback.correct { background: rgba(16,185,129,.1); color: #10b981; }
.feedback.wrong { background: rgba(239,68,68,.1); color: #ef4444; }
</style>
